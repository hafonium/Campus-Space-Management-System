-- ============================================================================
-- Step 15 - Indexing and Query Tuning Benchmark (G09)
-- Target: Microsoft SQL Server 2022
--
-- Prerequisites (run in this order):
--   outputs/05-db-definition-G09.sql
--   outputs/06-sample-data-G09.sql
--   outputs/10-schema-migration-G09.sql
--   outputs/12-concurrency-implementation-G09.sql
--   outputs/14-data-generator-G09/high-volume-sample-data-G09.sql
-- Step 16 is the semantic source for W2-W4, but is not an execution
-- prerequisite because the final query bodies are embedded below.
--
-- This script benchmarks exactly four Phase 2 workloads:
--   W1 - booking conflict check
--   W2 - room finder
--   W3 - approved booking hours by semester
--   W4 - approved booking count by weekday/hour
--
-- It does not retain experimental indexes. All pre-existing non-unique,
-- non-constraint performance indexes on relevant tables are disabled for BASE
-- and restored to their original enabled/disabled state at the end.
-- Do not run concurrent booking writes while this script is executing.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Set to 1 when one BASE and one INDEXED actual-plan XML per workload is
-- desired in the output. Measured runs always use the same query text and
-- parameters, but do not have STATISTICS XML enabled.
DECLARE @CaptureActualPlans BIT = 1;
DECLARE @MeasuredRuns INT = 5;

IF @MeasuredRuns < 3
    THROW 55000, 'MeasuredRuns must be at least 3.', 1;

-- ============================================================================
-- 1. Schema and dataset preflight
-- ============================================================================

IF OBJECT_ID('dbo.BOOKING', 'U') IS NULL
   OR OBJECT_ID('dbo.SPACE', 'U') IS NULL
   OR OBJECT_ID('dbo.SPACE_FACILITY', 'U') IS NULL
   OR OBJECT_ID('dbo.MAINTENANCE_RECORD', 'U') IS NULL
   OR OBJECT_ID('dbo.SEMESTER', 'U') IS NULL
BEGIN
    THROW 55001, 'Required Phase 2 tables are missing.', 1;
END;

DECLARE @BookingCount BIGINT,
        @ActiveBookingCount BIGINT,
        @MaintenanceCount BIGINT,
        @FirstBooking DATETIME2,
        @LastBooking DATETIME2,
        @BookingDaySpan INT;

SELECT @BookingCount = COUNT_BIG(*),
       @FirstBooking = MIN(requested_start_time),
       @LastBooking = MAX(requested_start_time),
       @BookingDaySpan = DATEDIFF(DAY,
                                  MIN(requested_start_time),
                                  MAX(requested_start_time))
FROM dbo.BOOKING;

SELECT @ActiveBookingCount = COUNT_BIG(*)
FROM dbo.BOOKING
WHERE booking_status IN ('approved', 'checked_in', 'completed');

SELECT @MaintenanceCount = COUNT_BIG(*)
FROM dbo.MAINTENANCE_RECORD;

IF @BookingCount < 100000
    THROW 55002, 'Benchmark requires at least 100,000 BOOKING rows.', 1;

IF @BookingDaySpan < 1094
    THROW 55003, 'Booking data covers less than three academic years.', 1;

IF @ActiveBookingCount = 0
    THROW 55004, 'No approved/active bookings are available for benchmarking.', 1;

IF @MaintenanceCount = 0
    THROW 55005, 'No maintenance data is available for room-finder benchmarking.', 1;

PRINT '=== DATASET PREFLIGHT ===';
SELECT @BookingCount AS booking_rows,
       @ActiveBookingCount AS approved_active_rows,
       @MaintenanceCount AS maintenance_rows,
       @FirstBooking AS first_booking_start,
       @LastBooking AS last_booking_start,
       @BookingDaySpan AS booking_day_span;

PRINT '=== SQL SERVER ENVIRONMENT ===';
SELECT SERVERPROPERTY('ServerName') AS server_name,
       SERVERPROPERTY('Edition') AS edition,
       SERVERPROPERTY('ProductVersion') AS product_version,
       SERVERPROPERTY('ProductLevel') AS product_level,
       d.compatibility_level,
       d.recovery_model_desc
FROM sys.databases d
WHERE d.database_id = DB_ID();

PRINT '=== SEMESTER COVERAGE ===';
SELECT s.semester_id,
       s.semester_name,
       s.start_date,
       s.end_date,
       COUNT_BIG(b.booking_id) AS approved_active_overlapping_rows
FROM dbo.SEMESTER s
LEFT JOIN dbo.BOOKING b
  ON b.booking_status IN ('approved', 'checked_in', 'completed')
 AND b.requested_end_time > CAST(s.start_date AS DATETIME2)
 AND b.requested_start_time < DATEADD(DAY, 1, CAST(s.end_date AS DATETIME2))
GROUP BY s.semester_id, s.semester_name, s.start_date, s.end_date
ORDER BY s.start_date, s.semester_id;

-- ============================================================================
-- 2. Current index inventory
-- ============================================================================

PRINT '=== CURRENT RELEVANT INDEXES (one row per index column) ===';
SELECT OBJECT_NAME(i.object_id) AS table_name,
       i.name AS index_name,
       i.type_desc,
       i.is_unique,
       i.is_primary_key,
       i.is_unique_constraint,
       i.is_disabled,
       c.name AS column_name,
       ic.key_ordinal,
       ic.is_included_column
FROM sys.indexes i
LEFT JOIN sys.index_columns ic
  ON ic.object_id = i.object_id
 AND ic.index_id = i.index_id
LEFT JOIN sys.columns c
  ON c.object_id = ic.object_id
 AND c.column_id = ic.column_id
WHERE i.object_id IN (
          OBJECT_ID('dbo.BOOKING'),
          OBJECT_ID('dbo.SPACE'),
          OBJECT_ID('dbo.SPACE_FACILITY'),
          OBJECT_ID('dbo.MAINTENANCE_RECORD'),
          OBJECT_ID('dbo.SEMESTER')
      )
  AND i.index_id > 0
ORDER BY OBJECT_NAME(i.object_id), i.index_id,
         ic.is_included_column, ic.key_ordinal, ic.index_column_id;

-- Preserve the original state of every non-unique, non-constraint
-- nonclustered performance index that could influence W1-W4.
CREATE TABLE #OriginalPerformanceIndexes (
    object_id INT NOT NULL,
    index_id INT NOT NULL,
    schema_name SYSNAME NOT NULL,
    table_name SYSNAME NOT NULL,
    index_name SYSNAME NOT NULL,
    was_disabled BIT NOT NULL,
    PRIMARY KEY (object_id, index_id)
);

INSERT INTO #OriginalPerformanceIndexes (
    object_id, index_id, schema_name, table_name, index_name, was_disabled
)
SELECT i.object_id,
       i.index_id,
       OBJECT_SCHEMA_NAME(i.object_id),
       OBJECT_NAME(i.object_id),
       i.name,
       i.is_disabled
FROM sys.indexes i
WHERE i.object_id IN (
          OBJECT_ID('dbo.BOOKING'),
          OBJECT_ID('dbo.SPACE'),
          OBJECT_ID('dbo.SPACE_FACILITY'),
          OBJECT_ID('dbo.MAINTENANCE_RECORD'),
          OBJECT_ID('dbo.SEMESTER')
      )
  AND i.type = 2                         -- NONCLUSTERED
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND i.is_unique = 0
  AND i.is_hypothetical = 0;

DECLARE @C1OriginallyExisted BIT = CASE WHEN EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.BOOKING')
      AND name = 'ix_booking_overlap_lock'
) THEN 1 ELSE 0 END;

DECLARE @C2OriginallyExisted BIT = CASE WHEN EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.BOOKING')
      AND name = 'ix_g09_booking_semester_reporting'
) THEN 1 ELSE 0 END;

DECLARE @C3OriginallyExisted BIT = CASE WHEN EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
      AND name = 'ix_g09_maintenance_room_finder'
) THEN 1 ELSE 0 END;

-- C1 is a correctness-supporting Step 12 index. Refuse to benchmark under its
-- name if the live definition is not the expected four-key definition.
IF @C1OriginallyExisted = 1
BEGIN
    DECLARE @C1IndexId INT = (
        SELECT index_id FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.BOOKING')
          AND name = 'ix_booking_overlap_lock'
    );

    IF EXISTS (
           SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID('dbo.BOOKING')
             AND index_id = @C1IndexId
             AND (type <> 2 OR is_unique <> 0
                  OR is_primary_key <> 0 OR is_unique_constraint <> 0)
       )
       OR (SELECT COUNT(*) FROM sys.index_columns
        WHERE object_id = OBJECT_ID('dbo.BOOKING')
          AND index_id = @C1IndexId
          AND key_ordinal > 0) <> 4
       OR EXISTS (
           SELECT 1 FROM sys.index_columns
           WHERE object_id = OBJECT_ID('dbo.BOOKING')
             AND index_id = @C1IndexId
             AND is_included_column = 1
       )
       OR NOT EXISTS (
           SELECT 1 FROM sys.index_columns ic
           JOIN sys.columns c ON c.object_id = ic.object_id
                             AND c.column_id = ic.column_id
           WHERE ic.object_id = OBJECT_ID('dbo.BOOKING')
             AND ic.index_id = @C1IndexId
             AND ic.key_ordinal = 1 AND c.name = 'space_code'
       )
       OR NOT EXISTS (
           SELECT 1 FROM sys.index_columns ic
           JOIN sys.columns c ON c.object_id = ic.object_id
                             AND c.column_id = ic.column_id
           WHERE ic.object_id = OBJECT_ID('dbo.BOOKING')
             AND ic.index_id = @C1IndexId
             AND ic.key_ordinal = 2 AND c.name = 'booking_status'
       )
       OR NOT EXISTS (
           SELECT 1 FROM sys.index_columns ic
           JOIN sys.columns c ON c.object_id = ic.object_id
                             AND c.column_id = ic.column_id
           WHERE ic.object_id = OBJECT_ID('dbo.BOOKING')
             AND ic.index_id = @C1IndexId
             AND ic.key_ordinal = 3 AND c.name = 'requested_start_time'
       )
       OR NOT EXISTS (
           SELECT 1 FROM sys.index_columns ic
           JOIN sys.columns c ON c.object_id = ic.object_id
                             AND c.column_id = ic.column_id
           WHERE ic.object_id = OBJECT_ID('dbo.BOOKING')
             AND ic.index_id = @C1IndexId
             AND ic.key_ordinal = 4 AND c.name = 'requested_end_time'
       )
    BEGIN
        THROW 55006, 'ix_booking_overlap_lock exists with an unexpected definition.', 1;
    END;
END;

-- Refuse to reuse C2/C3 names for a different index definition. This keeps
-- INDEXED reproducible without destroying a pre-existing index definition.
IF @C2OriginallyExisted = 1
BEGIN
    DECLARE @C2IndexId INT = (
        SELECT index_id FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.BOOKING')
          AND name = 'ix_g09_booking_semester_reporting'
    );
    DECLARE @C2Keys NVARCHAR(MAX), @C2Includes NVARCHAR(MAX);

    SELECT @C2Keys = STRING_AGG(CONVERT(NVARCHAR(MAX), c.name), N',')
                     WITHIN GROUP (ORDER BY ic.key_ordinal)
    FROM sys.index_columns ic
    JOIN sys.columns c ON c.object_id = ic.object_id
                      AND c.column_id = ic.column_id
    WHERE ic.object_id = OBJECT_ID('dbo.BOOKING')
      AND ic.index_id = @C2IndexId
      AND ic.key_ordinal > 0;

    SELECT @C2Includes = STRING_AGG(CONVERT(NVARCHAR(MAX), c.name), N',')
                         WITHIN GROUP (ORDER BY ic.index_column_id)
    FROM sys.index_columns ic
    JOIN sys.columns c ON c.object_id = ic.object_id
                      AND c.column_id = ic.column_id
    WHERE ic.object_id = OBJECT_ID('dbo.BOOKING')
      AND ic.index_id = @C2IndexId
      AND ic.is_included_column = 1;

    IF EXISTS (
           SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID('dbo.BOOKING')
             AND index_id = @C2IndexId
             AND (type <> 2 OR is_unique <> 0
                  OR is_primary_key <> 0 OR is_unique_constraint <> 0)
       )
       OR @C2Keys <> N'booking_status,requested_start_time,space_code'
       OR COALESCE(@C2Includes, N'') <> N'requested_end_time'
        THROW 55012, 'ix_g09_booking_semester_reporting has an unexpected definition.', 1;
END;

IF @C3OriginallyExisted = 1
BEGIN
    DECLARE @C3IndexId INT = (
        SELECT index_id FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
          AND name = 'ix_g09_maintenance_room_finder'
    );
    DECLARE @C3Keys NVARCHAR(MAX), @C3Includes NVARCHAR(MAX);

    SELECT @C3Keys = STRING_AGG(CONVERT(NVARCHAR(MAX), c.name), N',')
                     WITHIN GROUP (ORDER BY ic.key_ordinal)
    FROM sys.index_columns ic
    JOIN sys.columns c ON c.object_id = ic.object_id
                      AND c.column_id = ic.column_id
    WHERE ic.object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
      AND ic.index_id = @C3IndexId
      AND ic.key_ordinal > 0;

    SELECT @C3Includes = STRING_AGG(CONVERT(NVARCHAR(MAX), c.name), N',')
                         WITHIN GROUP (ORDER BY ic.index_column_id)
    FROM sys.index_columns ic
    JOIN sys.columns c ON c.object_id = ic.object_id
                      AND c.column_id = ic.column_id
    WHERE ic.object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
      AND ic.index_id = @C3IndexId
      AND ic.is_included_column = 1;

    IF EXISTS (
           SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
             AND index_id = @C3IndexId
             AND (type <> 2 OR is_unique <> 0
                  OR is_primary_key <> 0 OR is_unique_constraint <> 0)
       )
       OR @C3Keys <> N'space_code,impact_level,status,start_time'
       OR COALESCE(@C3Includes, N'') <> N'completion_time'
        THROW 55013, 'ix_g09_maintenance_room_finder has an unexpected definition.', 1;
END;

-- ============================================================================
-- 3. Deterministic benchmark parameters
-- ============================================================================

DECLARE @SemesterId INT,
        @SemesterStart DATETIME2,
        @SemesterEndExclusive DATETIME2,
        @SemesterBookingCount BIGINT;

SELECT TOP (1)
       @SemesterId = s.semester_id,
       @SemesterStart = CAST(s.start_date AS DATETIME2),
       @SemesterEndExclusive = DATEADD(DAY, 1, CAST(s.end_date AS DATETIME2)),
       @SemesterBookingCount = COUNT_BIG(b.booking_id)
FROM dbo.SEMESTER s
LEFT JOIN dbo.BOOKING b
  ON b.booking_status IN ('approved', 'checked_in', 'completed')
 AND b.requested_end_time > CAST(s.start_date AS DATETIME2)
 AND b.requested_start_time < DATEADD(DAY, 1, CAST(s.end_date AS DATETIME2))
GROUP BY s.semester_id, s.start_date, s.end_date
ORDER BY COUNT_BIG(b.booking_id) DESC, s.semester_id;

IF @SemesterId IS NULL OR @SemesterBookingCount < 1000
    THROW 55007, 'No semester contains enough approved/active bookings.', 1;

DECLARE @ConflictSpaceCode VARCHAR(50),
        @ConflictRequestedStart DATETIME2,
        @ConflictRequestedEnd DATETIME2;

SELECT TOP (1)
       @ConflictSpaceCode = b.space_code,
       @ConflictRequestedStart = b.requested_start_time,
       @ConflictRequestedEnd = b.requested_end_time
FROM dbo.BOOKING b
WHERE b.booking_status = 'approved'
--   AND b.requested_end_time > @SemesterStart
--   AND b.requested_start_time < @SemesterEndExclusive
ORDER BY b.requested_start_time, b.space_code, b.booking_id;

IF @ConflictSpaceCode IS NULL
    THROW 55008, 'No approved booking is available for W1 parameters.', 1;

CREATE TABLE #RequiredFacilities (
    facility_id INT NOT NULL PRIMARY KEY
);

DECLARE @Facility1 INT, @Facility2 INT;

SELECT TOP (1)
       @Facility1 = sf1.facility_id,
       @Facility2 = sf2.facility_id
FROM dbo.SPACE_FACILITY sf1
JOIN dbo.SPACE_FACILITY sf2
  ON sf2.space_code = sf1.space_code
 AND sf2.facility_id > sf1.facility_id
GROUP BY sf1.facility_id, sf2.facility_id
ORDER BY COUNT_BIG(*) DESC, sf1.facility_id, sf2.facility_id;

IF @Facility1 IS NOT NULL
    INSERT INTO #RequiredFacilities (facility_id)
    VALUES (@Facility1), (@Facility2);
ELSE
    INSERT INTO #RequiredFacilities (facility_id)
    SELECT TOP (1) facility_id
    FROM dbo.SPACE_FACILITY
    GROUP BY facility_id
    ORDER BY COUNT_BIG(*) DESC, facility_id;

IF NOT EXISTS (SELECT 1 FROM #RequiredFacilities)
    THROW 55009, 'No facility assignments are available for W2 parameters.', 1;

DECLARE @RoomStart DATETIME2,
        @RoomEnd DATETIME2,
        @RoomCapacity INT,
        @ParameterMaintenanceId INT;

SELECT TOP (1)
       @ParameterMaintenanceId = mr.maintenance_id,
       @RoomStart = mr.start_time,
       @RoomEnd = CASE
           WHEN mr.completion_time IS NULL
               THEN DATEADD(HOUR, 2, mr.start_time)
           ELSE mr.completion_time
       END
FROM dbo.MAINTENANCE_RECORD mr
WHERE mr.impact_level = 'out-of-service'
  AND mr.status IN ('reported', 'in_progress')
  AND (mr.completion_time IS NULL OR mr.completion_time > mr.start_time)
ORDER BY mr.maintenance_id;

IF @RoomStart IS NULL
BEGIN
    SELECT TOP (1)
           @ParameterMaintenanceId = mr.maintenance_id,
           @RoomStart = mr.start_time,
           @RoomEnd = COALESCE(mr.completion_time,
                               DATEADD(HOUR, 2, mr.start_time))
    FROM dbo.MAINTENANCE_RECORD mr
    WHERE mr.impact_level = 'out-of-service'
    ORDER BY mr.maintenance_id;
END;

IF @RoomStart IS NULL OR @RoomEnd <= @RoomStart
    THROW 55010, 'No valid out-of-service interval is available for W2.', 1;

SELECT @RoomCapacity = MIN(s.capacity)
FROM dbo.SPACE s
WHERE s.current_status NOT IN ('temporarily_closed', 'retired')
  AND NOT EXISTS (
      SELECT 1
      FROM #RequiredFacilities rf
      WHERE NOT EXISTS (
          SELECT 1 FROM dbo.SPACE_FACILITY sf
          WHERE sf.space_code = s.space_code
            AND sf.facility_id = rf.facility_id
      )
  );

IF @RoomCapacity IS NULL
    THROW 55011, 'No space satisfies the deterministic facility set.', 1;

PRINT '=== EXACT BENCHMARK PARAMETERS ===';
SELECT @SemesterId AS semester_id,
       @SemesterStart AS semester_start,
       @SemesterEndExclusive AS semester_end_exclusive,
       @SemesterBookingCount AS approved_active_rows_in_semester,
       @ConflictSpaceCode AS conflict_space_code,
       @ConflictRequestedStart AS conflict_requested_start,
       @ConflictRequestedEnd AS conflict_requested_end,
       @RoomCapacity AS room_required_capacity,
       @RoomStart AS room_start,
       @RoomEnd AS room_end,
       @ParameterMaintenanceId AS room_parameter_maintenance_id,
       @MeasuredRuns AS measured_runs;

SELECT rf.facility_id, f.facility_name
FROM #RequiredFacilities rf
JOIN dbo.FACILITY f ON f.facility_id = rf.facility_id
ORDER BY rf.facility_id;

-- Query text is declared once and reused unchanged for BASE and INDEXED.
DECLARE @W1 NVARCHAR(MAX) = N'
SELECT COUNT_BIG(*) AS conflicting_approved_bookings
FROM dbo.BOOKING b
WHERE b.space_code = @space_code
  AND b.booking_status = ''approved''
  AND b.requested_start_time < @requested_end
  AND b.requested_end_time > @requested_start;';

DECLARE @W2 NVARCHAR(MAX) = N'
SELECT s.space_code
FROM dbo.SPACE s
WHERE s.capacity >= @required_capacity
  AND s.current_status NOT IN (''temporarily_closed'', ''retired'')
  AND NOT EXISTS (
      SELECT 1
      FROM #RequiredFacilities rf
      WHERE rf.facility_id NOT IN (
          SELECT sf.facility_id
          FROM dbo.SPACE_FACILITY sf
          WHERE sf.space_code = s.space_code
      )
  )
EXCEPT
SELECT s.space_code
FROM dbo.SPACE s
JOIN dbo.BOOKING b ON b.space_code = s.space_code
WHERE b.booking_status IN (''approved'', ''checked_in'', ''completed'')
  AND b.requested_end_time > @start_time
  AND b.requested_start_time < @end_time
EXCEPT
SELECT s.space_code
FROM dbo.SPACE s
JOIN dbo.MAINTENANCE_RECORD mr ON mr.space_code = s.space_code
WHERE mr.impact_level = ''out-of-service''
  AND mr.status IN (''reported'', ''in_progress'')
  AND ISNULL(mr.completion_time, CONVERT(DATETIME2, ''9999-12-31'')) > @start_time
  AND mr.start_time < @end_time;';

DECLARE @W3 NVARCHAR(MAX) = N'
SELECT s.space_code,
       ISNULL(SUM(DATEDIFF(MINUTE,
                           b.requested_start_time,
                           b.requested_end_time) / 60.0), 0) AS total_hour
FROM dbo.SPACE s
LEFT JOIN dbo.BOOKING b
  ON b.space_code = s.space_code
 AND b.booking_status IN (''approved'', ''checked_in'', ''completed'')
 AND b.requested_end_time > @semester_start
 AND b.requested_start_time < @semester_end_exclusive
GROUP BY s.space_code;';

DECLARE @W4 NVARCHAR(MAX) = N'
SELECT DATENAME(WEEKDAY, b.requested_start_time) AS weekday,
       DATEPART(HOUR, b.requested_start_time) AS hour,
       COUNT(*) AS approved_booking
FROM dbo.BOOKING b
WHERE b.booking_status IN (''approved'', ''checked_in'', ''completed'')
  AND b.requested_end_time > @semester_start
  AND b.requested_start_time < @semester_end_exclusive
GROUP BY DATENAME(WEEKDAY, b.requested_start_time),
         DATEPART(HOUR, b.requested_start_time);';

-- Verify and print the deterministic W2 result size without changing data.
CREATE TABLE #RoomFinderParameterResult (
    space_code VARCHAR(50) NOT NULL PRIMARY KEY
);

INSERT INTO #RoomFinderParameterResult (space_code)
EXEC sys.sp_executesql @W2,
    N'@required_capacity INT, @start_time DATETIME2, @end_time DATETIME2',
    @RoomCapacity, @RoomStart, @RoomEnd;

SELECT COUNT_BIG(*) AS room_finder_result_rows
FROM #RoomFinderParameterResult;

DECLARE @PerfObjectId INT,
        @PerfIndexName SYSNAME,
        @PerfSchemaName SYSNAME,
        @PerfTableName SYSNAME,
        @Sql NVARCHAR(MAX),
        @Run INT;

BEGIN TRY
    -- ========================================================================
    -- 4. BASE - disable only non-essential performance indexes
    -- ========================================================================

    PRINT '=== PREPARING CLEAN BASE ===';
    DECLARE DisableIndexes CURSOR LOCAL FAST_FORWARD FOR
        SELECT object_id, schema_name, table_name, index_name
        FROM #OriginalPerformanceIndexes
        WHERE was_disabled = 0;

    OPEN DisableIndexes;
    FETCH NEXT FROM DisableIndexes
        INTO @PerfObjectId, @PerfSchemaName, @PerfTableName, @PerfIndexName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'ALTER INDEX ' + QUOTENAME(@PerfIndexName)
                 + N' ON ' + QUOTENAME(@PerfSchemaName) + N'.'
                 + QUOTENAME(@PerfTableName) + N' DISABLE;';
        EXEC sys.sp_executesql @Sql;

        FETCH NEXT FROM DisableIndexes
            INTO @PerfObjectId, @PerfSchemaName, @PerfTableName, @PerfIndexName;
    END;

    CLOSE DisableIndexes;
    DEALLOCATE DisableIndexes;

    PRINT '=== BASE WARM-UP (statistics off) ===';
    EXEC sys.sp_executesql @W1,
        N'@space_code VARCHAR(50), @requested_start DATETIME2, @requested_end DATETIME2',
        @ConflictSpaceCode, @ConflictRequestedStart, @ConflictRequestedEnd;
    EXEC sys.sp_executesql @W2,
        N'@required_capacity INT, @start_time DATETIME2, @end_time DATETIME2',
        @RoomCapacity, @RoomStart, @RoomEnd;
    EXEC sys.sp_executesql @W3,
        N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
        @SemesterStart, @SemesterEndExclusive;
    EXEC sys.sp_executesql @W4,
        N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
        @SemesterStart, @SemesterEndExclusive;

    IF @CaptureActualPlans = 1
    BEGIN
        PRINT '=== BASE ACTUAL PLAN CAPTURE ===';
        SET STATISTICS XML ON;
        EXEC sys.sp_executesql @W1,
            N'@space_code VARCHAR(50), @requested_start DATETIME2, @requested_end DATETIME2',
            @ConflictSpaceCode, @ConflictRequestedStart, @ConflictRequestedEnd;
        EXEC sys.sp_executesql @W2,
            N'@required_capacity INT, @start_time DATETIME2, @end_time DATETIME2',
            @RoomCapacity, @RoomStart, @RoomEnd;
        EXEC sys.sp_executesql @W3,
            N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
            @SemesterStart, @SemesterEndExclusive;
        EXEC sys.sp_executesql @W4,
            N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
            @SemesterStart, @SemesterEndExclusive;
        SET STATISTICS XML OFF;
    END;

    PRINT '=== BASE MEASURED RUNS ===';
    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;

    SET @Run = 1;
    WHILE @Run <= @MeasuredRuns
    BEGIN
        PRINT CONCAT('BASE W1 run ', @Run);
        EXEC sys.sp_executesql @W1,
            N'@space_code VARCHAR(50), @requested_start DATETIME2, @requested_end DATETIME2',
            @ConflictSpaceCode, @ConflictRequestedStart, @ConflictRequestedEnd;
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= @MeasuredRuns
    BEGIN
        PRINT CONCAT('BASE W2 run ', @Run);
        EXEC sys.sp_executesql @W2,
            N'@required_capacity INT, @start_time DATETIME2, @end_time DATETIME2',
            @RoomCapacity, @RoomStart, @RoomEnd;
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= @MeasuredRuns
    BEGIN
        PRINT CONCAT('BASE W3 run ', @Run);
        EXEC sys.sp_executesql @W3,
            N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
            @SemesterStart, @SemesterEndExclusive;
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= @MeasuredRuns
    BEGIN
        PRINT CONCAT('BASE W4 run ', @Run);
        EXEC sys.sp_executesql @W4,
            N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
            @SemesterStart, @SemesterEndExclusive;
        SET @Run += 1;
    END;

    SET STATISTICS IO OFF;
    SET STATISTICS TIME OFF;

    -- ========================================================================
    -- 5. INDEXED - enable only C1, C2 and C3
    -- ========================================================================

    PRINT '=== CREATING/ENABLING CANDIDATE INDEXES ===';

    IF EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('dbo.BOOKING')
                 AND name = 'ix_booking_overlap_lock')
        ALTER INDEX ix_booking_overlap_lock ON dbo.BOOKING REBUILD;
    ELSE
        CREATE INDEX ix_booking_overlap_lock
            ON dbo.BOOKING (
                space_code,
                booking_status,
                requested_start_time,
                requested_end_time
            );

    IF EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('dbo.BOOKING')
                 AND name = 'ix_g09_booking_semester_reporting')
        ALTER INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING REBUILD;
    ELSE
        CREATE INDEX ix_g09_booking_semester_reporting
            ON dbo.BOOKING (
                booking_status,
                requested_start_time,
                space_code
            )
            INCLUDE (requested_end_time);

    IF EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
                 AND name = 'ix_g09_maintenance_room_finder')
        ALTER INDEX ix_g09_maintenance_room_finder
            ON dbo.MAINTENANCE_RECORD REBUILD;
    ELSE
        CREATE INDEX ix_g09_maintenance_room_finder
            ON dbo.MAINTENANCE_RECORD (
                space_code,
                impact_level,
                status,
                start_time
            )
            INCLUDE (completion_time);

    PRINT '=== INDEXED WARM-UP (statistics off) ===';
    EXEC sys.sp_executesql @W1,
        N'@space_code VARCHAR(50), @requested_start DATETIME2, @requested_end DATETIME2',
        @ConflictSpaceCode, @ConflictRequestedStart, @ConflictRequestedEnd;
    EXEC sys.sp_executesql @W2,
        N'@required_capacity INT, @start_time DATETIME2, @end_time DATETIME2',
        @RoomCapacity, @RoomStart, @RoomEnd;
    EXEC sys.sp_executesql @W3,
        N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
        @SemesterStart, @SemesterEndExclusive;
    EXEC sys.sp_executesql @W4,
        N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
        @SemesterStart, @SemesterEndExclusive;

    IF @CaptureActualPlans = 1
    BEGIN
        PRINT '=== INDEXED ACTUAL PLAN CAPTURE ===';
        SET STATISTICS XML ON;
        EXEC sys.sp_executesql @W1,
            N'@space_code VARCHAR(50), @requested_start DATETIME2, @requested_end DATETIME2',
            @ConflictSpaceCode, @ConflictRequestedStart, @ConflictRequestedEnd;
        EXEC sys.sp_executesql @W2,
            N'@required_capacity INT, @start_time DATETIME2, @end_time DATETIME2',
            @RoomCapacity, @RoomStart, @RoomEnd;
        EXEC sys.sp_executesql @W3,
            N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
            @SemesterStart, @SemesterEndExclusive;
        EXEC sys.sp_executesql @W4,
            N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
            @SemesterStart, @SemesterEndExclusive;
        SET STATISTICS XML OFF;
    END;

    PRINT '=== INDEXED MEASURED RUNS ===';
    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;

    SET @Run = 1;
    WHILE @Run <= @MeasuredRuns
    BEGIN
        PRINT CONCAT('INDEXED W1 run ', @Run);
        EXEC sys.sp_executesql @W1,
            N'@space_code VARCHAR(50), @requested_start DATETIME2, @requested_end DATETIME2',
            @ConflictSpaceCode, @ConflictRequestedStart, @ConflictRequestedEnd;
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= @MeasuredRuns
    BEGIN
        PRINT CONCAT('INDEXED W2 run ', @Run);
        EXEC sys.sp_executesql @W2,
            N'@required_capacity INT, @start_time DATETIME2, @end_time DATETIME2',
            @RoomCapacity, @RoomStart, @RoomEnd;
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= @MeasuredRuns
    BEGIN
        PRINT CONCAT('INDEXED W3 run ', @Run);
        EXEC sys.sp_executesql @W3,
            N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
            @SemesterStart, @SemesterEndExclusive;
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= @MeasuredRuns
    BEGIN
        PRINT CONCAT('INDEXED W4 run ', @Run);
        EXEC sys.sp_executesql @W4,
            N'@semester_start DATETIME2, @semester_end_exclusive DATETIME2',
            @SemesterStart, @SemesterEndExclusive;
        SET @Run += 1;
    END;

    SET STATISTICS IO OFF;
    SET STATISTICS TIME OFF;

    -- ========================================================================
    -- 6. Restore original index state
    -- ========================================================================

    PRINT '=== RESTORING ORIGINAL INDEX STATE ===';

    IF @C1OriginallyExisted = 0
       AND EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID('dbo.BOOKING')
                     AND name = 'ix_booking_overlap_lock')
        DROP INDEX ix_booking_overlap_lock ON dbo.BOOKING;

    IF @C2OriginallyExisted = 0
       AND EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID('dbo.BOOKING')
                     AND name = 'ix_g09_booking_semester_reporting')
        DROP INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING;

    IF @C3OriginallyExisted = 0
       AND EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
                     AND name = 'ix_g09_maintenance_room_finder')
        DROP INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD;

    DECLARE RestoreIndexes CURSOR LOCAL FAST_FORWARD FOR
        SELECT object_id, schema_name, table_name, index_name
        FROM #OriginalPerformanceIndexes
        WHERE was_disabled = 0;

    OPEN RestoreIndexes;
    FETCH NEXT FROM RestoreIndexes
        INTO @PerfObjectId, @PerfSchemaName, @PerfTableName, @PerfIndexName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = @PerfObjectId
                     AND name = @PerfIndexName
                     AND is_disabled = 1)
        BEGIN
            SET @Sql = N'ALTER INDEX ' + QUOTENAME(@PerfIndexName)
                     + N' ON ' + QUOTENAME(@PerfSchemaName) + N'.'
                     + QUOTENAME(@PerfTableName) + N' REBUILD;';
            EXEC sys.sp_executesql @Sql;
        END;

        FETCH NEXT FROM RestoreIndexes
            INTO @PerfObjectId, @PerfSchemaName, @PerfTableName, @PerfIndexName;
    END;

    CLOSE RestoreIndexes;
    DEALLOCATE RestoreIndexes;

    -- Candidate indexes that originally existed but were originally disabled
    -- were rebuilt for INDEXED and must be disabled again.
    DECLARE RestoreDisabledIndexes CURSOR LOCAL FAST_FORWARD FOR
        SELECT object_id, schema_name, table_name, index_name
        FROM #OriginalPerformanceIndexes
        WHERE was_disabled = 1;

    OPEN RestoreDisabledIndexes;
    FETCH NEXT FROM RestoreDisabledIndexes
        INTO @PerfObjectId, @PerfSchemaName, @PerfTableName, @PerfIndexName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = @PerfObjectId
                     AND name = @PerfIndexName
                     AND is_disabled = 0)
        BEGIN
            SET @Sql = N'ALTER INDEX ' + QUOTENAME(@PerfIndexName)
                     + N' ON ' + QUOTENAME(@PerfSchemaName) + N'.'
                     + QUOTENAME(@PerfTableName) + N' DISABLE;';
            EXEC sys.sp_executesql @Sql;
        END;

        FETCH NEXT FROM RestoreDisabledIndexes
            INTO @PerfObjectId, @PerfSchemaName, @PerfTableName, @PerfIndexName;
    END;

    CLOSE RestoreDisabledIndexes;
    DEALLOCATE RestoreDisabledIndexes;

    IF EXISTS (
        SELECT 1
        FROM #OriginalPerformanceIndexes o
        LEFT JOIN sys.indexes i
          ON i.object_id = o.object_id
         AND i.name = o.index_name
        WHERE i.index_id IS NULL
           OR i.is_disabled <> o.was_disabled
    )
        THROW 55014, 'Original performance-index state was not fully restored.', 1;

    IF (@C1OriginallyExisted = 0 AND EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('dbo.BOOKING')
              AND name = 'ix_booking_overlap_lock'))
       OR (@C2OriginallyExisted = 0 AND EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('dbo.BOOKING')
              AND name = 'ix_g09_booking_semester_reporting'))
       OR (@C3OriginallyExisted = 0 AND EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
              AND name = 'ix_g09_maintenance_room_finder'))
        THROW 55015, 'An experimental candidate index remains after restoration.', 1;

    PRINT 'Benchmark complete. Copy exact parameters, STATISTICS IO/TIME output,';
    PRINT 'Original index existence and enabled/disabled state verified.';
    PRINT 'and BASE/INDEXED actual-plan operators into the Step 15 report.';
END TRY
BEGIN CATCH
    SET STATISTICS XML OFF;
    SET STATISTICS IO OFF;
    SET STATISTICS TIME OFF;

    PRINT 'Benchmark failed. Attempting to restore the original index state.';

    IF @C1OriginallyExisted = 0
       AND EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID('dbo.BOOKING')
                     AND name = 'ix_booking_overlap_lock')
        DROP INDEX ix_booking_overlap_lock ON dbo.BOOKING;

    IF @C2OriginallyExisted = 0
       AND EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID('dbo.BOOKING')
                     AND name = 'ix_g09_booking_semester_reporting')
        DROP INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING;

    IF @C3OriginallyExisted = 0
       AND EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
                     AND name = 'ix_g09_maintenance_room_finder')
        DROP INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD;

    DECLARE EmergencyRestore CURSOR LOCAL FAST_FORWARD FOR
        SELECT object_id, schema_name, table_name, index_name, was_disabled
        FROM #OriginalPerformanceIndexes;

    DECLARE @WasDisabled BIT;
    OPEN EmergencyRestore;
    FETCH NEXT FROM EmergencyRestore
        INTO @PerfObjectId, @PerfSchemaName, @PerfTableName,
             @PerfIndexName, @WasDisabled;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = @PerfObjectId
                     AND name = @PerfIndexName)
        BEGIN
            IF @WasDisabled = 0
               AND EXISTS (SELECT 1 FROM sys.indexes
                           WHERE object_id = @PerfObjectId
                             AND name = @PerfIndexName
                             AND is_disabled = 1)
            BEGIN
                SET @Sql = N'ALTER INDEX ' + QUOTENAME(@PerfIndexName)
                         + N' ON ' + QUOTENAME(@PerfSchemaName) + N'.'
                         + QUOTENAME(@PerfTableName) + N' REBUILD;';
                EXEC sys.sp_executesql @Sql;
            END;
            ELSE IF @WasDisabled = 1
                AND EXISTS (SELECT 1 FROM sys.indexes
                            WHERE object_id = @PerfObjectId
                              AND name = @PerfIndexName
                              AND is_disabled = 0)
            BEGIN
                SET @Sql = N'ALTER INDEX ' + QUOTENAME(@PerfIndexName)
                         + N' ON ' + QUOTENAME(@PerfSchemaName) + N'.'
                         + QUOTENAME(@PerfTableName) + N' DISABLE;';
                EXEC sys.sp_executesql @Sql;
            END;
        END;

        FETCH NEXT FROM EmergencyRestore
            INTO @PerfObjectId, @PerfSchemaName, @PerfTableName,
                 @PerfIndexName, @WasDisabled;
    END;

    CLOSE EmergencyRestore;
    DEALLOCATE EmergencyRestore;

    THROW;
END CATCH;
GO
