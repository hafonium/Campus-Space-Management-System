-- ============================================================================
-- Step 15 — Index Tuning Benchmark (G09)
-- Current Phase 2 schema and final Step 16 workloads
-- Target: Microsoft SQL Server 2022
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- This preflight is a separate batch so missing Step 16 objects produce a clear
-- error before SQL Server compiles the typed TVP and function calls below.
DECLARE @ExpectedGeneratedBookings BIGINT = 500000;
DECLARE @GeneratedBookings BIGINT;
DECLARE @FirstBooking DATETIME2;
DECLARE @LastBooking DATETIME2;

IF OBJECT_ID('dbo.BOOKING', 'U') IS NULL
   OR OBJECT_ID('dbo.SPACE', 'U') IS NULL
   OR OBJECT_ID('dbo.FACILITY', 'U') IS NULL
   OR OBJECT_ID('dbo.MAINTENANCE_RECORD', 'U') IS NULL
   OR OBJECT_ID('dbo.SEMESTER', 'U') IS NULL
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: required Phase 2 tables are missing.', 1;
END;

IF COL_LENGTH('dbo.FACILITY', 'space_code') IS NULL
   OR OBJECT_ID('dbo.SPACE_FACILITY', 'U') IS NOT NULL
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: the current SPACE 1:N FACILITY migration is not applied.', 1;
END;

IF TYPE_ID('dbo.FacilityListType') IS NULL
   OR OBJECT_ID('dbo.fn_GetAvailableSpaces', 'IF') IS NULL
   OR OBJECT_ID('dbo.fn_CountApprovedBookingHourBySemester', 'IF') IS NULL
   OR OBJECT_ID('dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester', 'IF') IS NULL
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: run outputs/16-analytical-queries-G09.sql first.', 1;
END;

IF OBJECT_ID('dbo.gen_user_marker', 'U') IS NULL
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: generator marker tables are required to verify the 500k experiment.', 1;
END;

SELECT @GeneratedBookings = COUNT_BIG(*)
FROM dbo.BOOKING AS B
JOIN dbo.gen_user_marker AS GM ON GM.user_id = B.requester_id;

IF @GeneratedBookings <> @ExpectedGeneratedBookings
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: generated BOOKING count is not exactly 500,000.', 1;
END;

SELECT @FirstBooking = MIN(requested_start_time),
       @LastBooking = MAX(requested_start_time)
FROM dbo.BOOKING;

IF @FirstBooking IS NULL
   OR DATEDIFF(DAY, @FirstBooking, @LastBooking) < 1095
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: BOOKING data does not cover at least three years.', 1;
END;

IF NOT EXISTS (
    SELECT 1 FROM dbo.BOOKING
    WHERE booking_status IN ('approved', 'checked_in', 'completed')
)
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: no approved-equivalent bookings exist.', 1;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.MAINTENANCE_RECORD)
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: MAINTENANCE_RECORD is empty.', 1;
END;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SEMESTER AS SEM
    WHERE EXISTS (
        SELECT 1
        FROM dbo.BOOKING AS B
        WHERE B.booking_status IN ('approved', 'checked_in', 'completed')
          AND B.requested_end_time > CAST(SEM.start_date AS DATETIME2)
          AND B.requested_start_time < DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2))
    )
)
BEGIN
    ;THROW 51000, 'Step 15 preflight failed: no semester overlaps approved-equivalent bookings.', 1;
END;

PRINT 'Dataset preflight passed.';

SELECT
    DB_NAME() AS database_name,
    CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) AS product_version,
    CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) AS edition,
    D.compatibility_level,
    D.recovery_model_desc
FROM sys.databases AS D
WHERE D.database_id = DB_ID();

SELECT
    COUNT_BIG(*) AS total_bookings,
    @GeneratedBookings AS generated_bookings,
    SUM(CASE WHEN booking_status = 'approved' THEN 1 ELSE 0 END) AS approved_bookings,
    SUM(CASE WHEN booking_status IN ('approved', 'checked_in', 'completed') THEN 1 ELSE 0 END)
        AS approved_equivalent_bookings,
    @FirstBooking AS first_booking,
    @LastBooking AS last_booking,
    DATEDIFF(DAY, @FirstBooking, @LastBooking) AS booking_day_span
FROM dbo.BOOKING;

SELECT
    (SELECT COUNT_BIG(*) FROM dbo.SPACE) AS spaces,
    (SELECT COUNT_BIG(*) FROM dbo.FACILITY) AS facilities,
    (SELECT COUNT_BIG(*) FROM dbo.MAINTENANCE_RECORD) AS maintenance_records,
    (SELECT COUNT_BIG(*) FROM dbo.SEMESTER) AS semesters;

SELECT T.name AS table_name,
       I.name AS index_name,
       I.type_desc,
       I.is_unique,
       I.is_disabled
FROM sys.indexes AS I
JOIN sys.tables AS T ON T.object_id = I.object_id
WHERE T.name IN ('BOOKING', 'FACILITY', 'MAINTENANCE_RECORD', 'SPACE', 'SEMESTER')
  AND I.index_id > 0
ORDER BY T.name, I.index_id;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET DATEFIRST 7;

-- Change only this gate after the validation-only run succeeds.
DECLARE @ExecuteFullBenchmark BIT = 0;

-- Candidate hypotheses derived from the current workload audit:
-- C1 BOOKING overlap/concurrency
-- C2 BOOKING semester reporting
-- C3 MAINTENANCE_RECORD room-finder exclusion
-- C4 FACILITY physical-instance lookup by space_code
DECLARE @C1Name SYSNAME = 'ix_booking_overlap_lock';
DECLARE @C2Name SYSNAME = 'ix_g09_booking_semester_reporting';
DECLARE @C3Name SYSNAME = 'ix_g09_maintenance_room_finder';
DECLARE @C4Name SYSNAME = 'ix_g09_facility_space';

DECLARE @C1Id INT = INDEXPROPERTY(OBJECT_ID('dbo.BOOKING'), @C1Name, 'IndexId');
DECLARE @C2Id INT = INDEXPROPERTY(OBJECT_ID('dbo.BOOKING'), @C2Name, 'IndexId');
DECLARE @C3Id INT = INDEXPROPERTY(OBJECT_ID('dbo.MAINTENANCE_RECORD'), @C3Name, 'IndexId');
DECLARE @C4Id INT = INDEXPROPERTY(OBJECT_ID('dbo.FACILITY'), @C4Name, 'IndexId');

-- C4 is justified only when another index does not already provide a
-- space_code-leading FACILITY access path. Do not create a duplicate under a
-- different name in a non-clean database.
IF EXISTS (
    SELECT 1
    FROM sys.indexes AS I
    JOIN sys.index_columns AS IC
      ON IC.object_id = I.object_id
     AND IC.index_id = I.index_id
     AND IC.key_ordinal = 1
    JOIN sys.columns AS C
      ON C.object_id = IC.object_id
     AND C.column_id = IC.column_id
    WHERE I.object_id = OBJECT_ID('dbo.FACILITY')
      AND I.index_id > 0
      AND I.is_hypothetical = 0
      AND C.name = 'space_code'
      AND I.name <> @C4Name
)
BEGIN
    ;THROW 51000, 'C4 is not applicable: FACILITY already has another space_code-leading index.', 1;
END;

PRINT 'FACILITY leading-key inventory passed: no other space_code-leading index; C4 will be benchmarked.';

DECLARE @C1OriginallyExisted BIT = CASE WHEN @C1Id IS NULL THEN 0 ELSE 1 END;
DECLARE @C2OriginallyExisted BIT = CASE WHEN @C2Id IS NULL THEN 0 ELSE 1 END;
DECLARE @C3OriginallyExisted BIT = CASE WHEN @C3Id IS NULL THEN 0 ELSE 1 END;
DECLARE @C4OriginallyExisted BIT = CASE WHEN @C4Id IS NULL THEN 0 ELSE 1 END;
DECLARE @C1OriginallyDisabled BIT = ISNULL((SELECT is_disabled FROM sys.indexes
                                            WHERE object_id = OBJECT_ID('dbo.BOOKING')
                                              AND index_id = @C1Id), 0);
DECLARE @C2OriginallyDisabled BIT = ISNULL((SELECT is_disabled FROM sys.indexes
                                            WHERE object_id = OBJECT_ID('dbo.BOOKING')
                                              AND index_id = @C2Id), 0);
DECLARE @C3OriginallyDisabled BIT = ISNULL((SELECT is_disabled FROM sys.indexes
                                            WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
                                              AND index_id = @C3Id), 0);
DECLARE @C4OriginallyDisabled BIT = ISNULL((SELECT is_disabled FROM sys.indexes
                                            WHERE object_id = OBJECT_ID('dbo.FACILITY')
                                              AND index_id = @C4Id), 0);

-- A known candidate name may be reused only when its definition matches.
IF @C1Id IS NOT NULL AND (
    (SELECT type FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id) <> 2
    OR (SELECT is_unique FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id) <> 0
    OR (SELECT has_filter FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id) <> 0
    OR (SELECT COUNT(*) FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id AND key_ordinal > 0) <> 4
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id AND key_ordinal = 1 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.BOOKING'), 'space_code', 'ColumnId'))
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id AND key_ordinal = 2 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.BOOKING'), 'booking_status', 'ColumnId'))
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id AND key_ordinal = 3 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.BOOKING'), 'requested_start_time', 'ColumnId'))
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id AND key_ordinal = 4 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.BOOKING'), 'requested_end_time', 'ColumnId'))
    OR EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C1Id AND is_included_column = 1)
)
BEGIN
    ;THROW 51000, 'Candidate-name conflict: C1 has an unexpected definition.', 1;
END;

IF @C2Id IS NOT NULL AND (
    (SELECT type FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id) <> 2
    OR (SELECT is_unique FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id) <> 0
    OR (SELECT has_filter FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id) <> 0
    OR (SELECT COUNT(*) FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id AND key_ordinal > 0) <> 3
    OR (SELECT COUNT(*) FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id AND is_included_column = 1) <> 1
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id AND key_ordinal = 1 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.BOOKING'), 'booking_status', 'ColumnId'))
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id AND key_ordinal = 2 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.BOOKING'), 'requested_start_time', 'ColumnId'))
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id AND key_ordinal = 3 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.BOOKING'), 'space_code', 'ColumnId'))
    OR NOT EXISTS (
        SELECT 1 FROM sys.index_columns
        WHERE object_id = OBJECT_ID('dbo.BOOKING') AND index_id = @C2Id
          AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.BOOKING'), 'requested_end_time', 'ColumnId')
          AND is_included_column = 1
    )
)
BEGIN
    ;THROW 51000, 'Candidate-name conflict: C2 has an unexpected definition.', 1;
END;

IF @C3Id IS NOT NULL AND (
    (SELECT type FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id) <> 2
    OR (SELECT is_unique FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id) <> 0
    OR (SELECT has_filter FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id) <> 0
    OR (SELECT COUNT(*) FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id AND key_ordinal > 0) <> 4
    OR (SELECT COUNT(*) FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id AND is_included_column = 1) <> 1
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id AND key_ordinal = 1 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.MAINTENANCE_RECORD'), 'space_code', 'ColumnId'))
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id AND key_ordinal = 2 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.MAINTENANCE_RECORD'), 'impact_level', 'ColumnId'))
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id AND key_ordinal = 3 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.MAINTENANCE_RECORD'), 'status', 'ColumnId'))
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id AND key_ordinal = 4 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.MAINTENANCE_RECORD'), 'start_time', 'ColumnId'))
    OR NOT EXISTS (
        SELECT 1 FROM sys.index_columns
        WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD') AND index_id = @C3Id
          AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.MAINTENANCE_RECORD'), 'completion_time', 'ColumnId')
          AND is_included_column = 1
    )
)
BEGIN
    ;THROW 51000, 'Candidate-name conflict: C3 has an unexpected definition.', 1;
END;

IF @C4Id IS NOT NULL AND (
    (SELECT type FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.FACILITY') AND index_id = @C4Id) <> 2
    OR (SELECT is_unique FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.FACILITY') AND index_id = @C4Id) <> 0
    OR (SELECT has_filter FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.FACILITY') AND index_id = @C4Id) <> 0
    OR (SELECT COUNT(*) FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.FACILITY') AND index_id = @C4Id AND key_ordinal > 0) <> 1
    OR NOT EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.FACILITY') AND index_id = @C4Id AND key_ordinal = 1 AND column_id = COLUMNPROPERTY(OBJECT_ID('dbo.FACILITY'), 'space_code', 'ColumnId'))
    OR EXISTS (SELECT 1 FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.FACILITY') AND index_id = @C4Id AND is_included_column = 1)
)
BEGIN
    ;THROW 51000, 'Candidate-name conflict: C4 has an unexpected definition.', 1;
END;

PRINT 'Candidate-name safety passed.';

SELECT candidate_name, table_name, originally_existed, originally_disabled
FROM (VALUES
    ('C1: ix_booking_overlap_lock', 'BOOKING', @C1OriginallyExisted, @C1OriginallyDisabled),
    ('C2: ix_g09_booking_semester_reporting', 'BOOKING', @C2OriginallyExisted, @C2OriginallyDisabled),
    ('C3: ix_g09_maintenance_room_finder', 'MAINTENANCE_RECORD', @C3OriginallyExisted, @C3OriginallyDisabled),
    ('C4: ix_g09_facility_space', 'FACILITY', @C4OriginallyExisted, @C4OriginallyDisabled)
) AS S(candidate_name, table_name, originally_existed, originally_disabled);

-- Deterministic W1 parameters: a real approved booking.
DECLARE @W1SpaceCode VARCHAR(50);
DECLARE @W1Start DATETIME2;
DECLARE @W1End DATETIME2;

SELECT TOP (1)
    @W1SpaceCode = B.space_code,
    @W1Start = B.requested_start_time,
    @W1End = B.requested_end_time
FROM dbo.BOOKING AS B
WHERE B.booking_status = 'approved'
ORDER BY B.booking_id;

IF @W1SpaceCode IS NULL
BEGIN
    ;THROW 51000, 'Parameter selection failed: W1 has no approved booking.', 1;
END;

-- Deterministic W2 parameters: use the current physical facility-id TVP and a
-- future interval in which the selected anchor space is viable.
DECLARE @W2Start DATETIME2;
DECLARE @W2End DATETIME2;
DECLARE @W2Capacity INT;
DECLARE @W2AnchorSpace VARCHAR(50);
DECLARE @RequiredFacilities dbo.FacilityListType;
DECLARE @W2ViableCount BIGINT;

SELECT @W2Start = DATEADD(DAY, 1, MAX(event_end))
FROM (
    SELECT MAX(requested_end_time) AS event_end FROM dbo.BOOKING
    UNION ALL
    SELECT MAX(completion_time) AS event_end FROM dbo.MAINTENANCE_RECORD
) AS H;

IF @W2Start IS NULL SET @W2Start = SYSDATETIME();
SET @W2End = DATEADD(HOUR, 2, @W2Start);

SELECT TOP (1)
    @W2AnchorSpace = S.space_code,
    @W2Capacity = S.capacity
FROM dbo.SPACE AS S
WHERE S.current_status NOT IN ('temporarily_closed', 'retired')
  AND EXISTS (SELECT 1 FROM dbo.FACILITY AS F WHERE F.space_code = S.space_code)
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.MAINTENANCE_RECORD AS MR
      WHERE MR.space_code = S.space_code
        AND MR.impact_level = 'out-of-service'
        AND MR.status IN ('reported', 'in_progress')
        AND ISNULL(MR.completion_time, CONVERT(DATETIME2, '9999-12-31')) > @W2Start
        AND MR.start_time < @W2End
  )
ORDER BY S.space_code;

IF @W2AnchorSpace IS NULL
BEGIN
    ;THROW 51000, 'Parameter selection failed: W2 has no usable facility-bearing anchor space.', 1;
END;

INSERT INTO @RequiredFacilities (facility_id)
SELECT TOP (2) F.facility_id
FROM dbo.FACILITY AS F
WHERE F.space_code = @W2AnchorSpace
ORDER BY F.facility_id;

IF NOT EXISTS (SELECT 1 FROM @RequiredFacilities)
BEGIN
    ;THROW 51000, 'Parameter selection failed: W2 facility TVP is empty.', 1;
END;

SELECT @W2ViableCount = COUNT_BIG(*)
FROM dbo.fn_GetAvailableSpaces(@W2Capacity, @W2Start, @W2End, @RequiredFacilities);

IF @W2ViableCount < 1
BEGIN
    ;THROW 51000, 'Parameter selection failed: W2 viability check returned no spaces.', 1;
END;

-- Deterministic W3/W4 parameter: the semester with the most
-- approved-equivalent overlapping bookings.
DECLARE @SemesterId INT;
DECLARE @SemesterQualifyingRows BIGINT;

SELECT TOP (1)
    @SemesterId = SEM.semester_id,
    @SemesterQualifyingRows = Q.qualifying_rows
FROM dbo.SEMESTER AS SEM
CROSS APPLY (
    SELECT COUNT_BIG(*) AS qualifying_rows
    FROM dbo.BOOKING AS B
    WHERE B.booking_status IN ('approved', 'checked_in', 'completed')
      AND B.requested_end_time > CAST(SEM.start_date AS DATETIME2)
      AND B.requested_start_time < DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2))
) AS Q
WHERE Q.qualifying_rows > 0
ORDER BY Q.qualifying_rows DESC, SEM.start_date, SEM.semester_id;

IF @SemesterId IS NULL
BEGIN
    ;THROW 51000, 'Parameter selection failed: W3/W4 has no usable semester.', 1;
END;

SELECT 'W1' AS workload,
       @W1SpaceCode AS space_code,
       @W1Start AS start_time,
       @W1End AS end_time;

SELECT 'W2' AS workload,
       @W2AnchorSpace AS anchor_space,
       @W2Capacity AS required_capacity,
       @W2Start AS start_time,
       @W2End AS end_time,
       @W2ViableCount AS viability_result_count;

SELECT facility_id AS W2_required_facility_id
FROM @RequiredFacilities
ORDER BY facility_id;

SELECT 'W3/W4' AS workload,
       @SemesterId AS semester_id,
       @SemesterQualifyingRows AS qualifying_booking_rows;

-- Compile the current production interfaces without entering the measured run.
SELECT TOP (0) *
FROM dbo.fn_GetAvailableSpaces(@W2Capacity, @W2Start, @W2End, @RequiredFacilities);

SELECT TOP (0) *
FROM dbo.fn_CountApprovedBookingHourBySemester(@SemesterId);

SELECT TOP (0) *
FROM dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@SemesterId);

PRINT 'Canonical workload compilation and deterministic parameter validation passed.';

IF @ExecuteFullBenchmark = 0
BEGIN
    PRINT 'VALIDATION ONLY COMPLETE. Set @ExecuteFullBenchmark = 1 for the controlled full run.';
    RETURN;
END;

DECLARE @Run INT;

BEGIN TRY
    -- BASE modifies only the four candidate indexes. Do not allow concurrent
    -- BOOKING writes while C1 is disabled.
    IF @C1OriginallyExisted = 1 AND @C1OriginallyDisabled = 0
        ALTER INDEX ix_booking_overlap_lock ON dbo.BOOKING DISABLE;
    IF @C2OriginallyExisted = 1 AND @C2OriginallyDisabled = 0
        ALTER INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING DISABLE;
    IF @C3OriginallyExisted = 1 AND @C3OriginallyDisabled = 0
        ALTER INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD DISABLE;
    IF @C4OriginallyExisted = 1 AND @C4OriginallyDisabled = 0
        ALTER INDEX ix_g09_facility_space ON dbo.FACILITY DISABLE;

    PRINT 'CLEAN BASE READY.';

    PRINT 'BASE WARM-UP W1';
    SELECT COUNT_BIG(*) AS overlapping_approved_bookings
    FROM dbo.BOOKING
    WHERE space_code = @W1SpaceCode
      AND booking_status = 'approved'
      AND requested_start_time < @W1End
      AND requested_end_time > @W1Start;

    PRINT 'BASE WARM-UP W2';
    SELECT * FROM dbo.fn_GetAvailableSpaces(@W2Capacity, @W2Start, @W2End, @RequiredFacilities);

    PRINT 'BASE WARM-UP W3';
    SELECT * FROM dbo.fn_CountApprovedBookingHourBySemester(@SemesterId);

    PRINT 'BASE WARM-UP W4';
    SELECT * FROM dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@SemesterId);

    PRINT 'BASE ACTUAL PLAN CAPTURE W1-W4 (not a measured run)';
    SET STATISTICS XML ON;

    SELECT COUNT_BIG(*) AS overlapping_approved_bookings
    FROM dbo.BOOKING
    WHERE space_code = @W1SpaceCode
      AND booking_status = 'approved'
      AND requested_start_time < @W1End
      AND requested_end_time > @W1Start;

    SELECT * FROM dbo.fn_GetAvailableSpaces(@W2Capacity, @W2Start, @W2End, @RequiredFacilities);
    SELECT * FROM dbo.fn_CountApprovedBookingHourBySemester(@SemesterId);
    SELECT * FROM dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@SemesterId);

    SET STATISTICS XML OFF;
    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;

    SET @Run = 1;
    WHILE @Run <= 5
    BEGIN
        RAISERROR ('BASE W1 run %d', 10, 1, @Run) WITH NOWAIT;
        SELECT COUNT_BIG(*) AS overlapping_approved_bookings
        FROM dbo.BOOKING
        WHERE space_code = @W1SpaceCode
          AND booking_status = 'approved'
          AND requested_start_time < @W1End
          AND requested_end_time > @W1Start;
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= 5
    BEGIN
        RAISERROR ('BASE W2 run %d', 10, 1, @Run) WITH NOWAIT;
        SELECT * FROM dbo.fn_GetAvailableSpaces(@W2Capacity, @W2Start, @W2End, @RequiredFacilities);
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= 5
    BEGIN
        RAISERROR ('BASE W3 run %d', 10, 1, @Run) WITH NOWAIT;
        SELECT * FROM dbo.fn_CountApprovedBookingHourBySemester(@SemesterId);
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= 5
    BEGIN
        RAISERROR ('BASE W4 run %d', 10, 1, @Run) WITH NOWAIT;
        SELECT * FROM dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@SemesterId);
        SET @Run += 1;
    END;

    SET STATISTICS TIME OFF;
    SET STATISTICS IO OFF;

    IF @C1OriginallyExisted = 1
        ALTER INDEX ix_booking_overlap_lock ON dbo.BOOKING REBUILD;
    ELSE
        CREATE NONCLUSTERED INDEX ix_booking_overlap_lock
            ON dbo.BOOKING (space_code, booking_status, requested_start_time, requested_end_time);

    IF @C2OriginallyExisted = 1
        ALTER INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING REBUILD;
    ELSE
        CREATE NONCLUSTERED INDEX ix_g09_booking_semester_reporting
            ON dbo.BOOKING (booking_status, requested_start_time, space_code)
            INCLUDE (requested_end_time);

    IF @C3OriginallyExisted = 1
        ALTER INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD REBUILD;
    ELSE
        CREATE NONCLUSTERED INDEX ix_g09_maintenance_room_finder
            ON dbo.MAINTENANCE_RECORD (space_code, impact_level, status, start_time)
            INCLUDE (completion_time);

    IF @C4OriginallyExisted = 1
        ALTER INDEX ix_g09_facility_space ON dbo.FACILITY REBUILD;
    ELSE
        CREATE NONCLUSTERED INDEX ix_g09_facility_space
            ON dbo.FACILITY (space_code);

    PRINT 'INDEXED CANDIDATE SET READY.';

    PRINT 'INDEXED WARM-UP W1';
    SELECT COUNT_BIG(*) AS overlapping_approved_bookings
    FROM dbo.BOOKING
    WHERE space_code = @W1SpaceCode
      AND booking_status = 'approved'
      AND requested_start_time < @W1End
      AND requested_end_time > @W1Start;

    PRINT 'INDEXED WARM-UP W2';
    SELECT * FROM dbo.fn_GetAvailableSpaces(@W2Capacity, @W2Start, @W2End, @RequiredFacilities);

    PRINT 'INDEXED WARM-UP W3';
    SELECT * FROM dbo.fn_CountApprovedBookingHourBySemester(@SemesterId);

    PRINT 'INDEXED WARM-UP W4';
    SELECT * FROM dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@SemesterId);

    PRINT 'INDEXED ACTUAL PLAN CAPTURE W1-W4 (not a measured run)';
    SET STATISTICS XML ON;

    SELECT COUNT_BIG(*) AS overlapping_approved_bookings
    FROM dbo.BOOKING
    WHERE space_code = @W1SpaceCode
      AND booking_status = 'approved'
      AND requested_start_time < @W1End
      AND requested_end_time > @W1Start;

    SELECT * FROM dbo.fn_GetAvailableSpaces(@W2Capacity, @W2Start, @W2End, @RequiredFacilities);
    SELECT * FROM dbo.fn_CountApprovedBookingHourBySemester(@SemesterId);
    SELECT * FROM dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@SemesterId);

    SET STATISTICS XML OFF;
    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;

    SET @Run = 1;
    WHILE @Run <= 5
    BEGIN
        RAISERROR ('INDEXED W1 run %d', 10, 1, @Run) WITH NOWAIT;
        SELECT COUNT_BIG(*) AS overlapping_approved_bookings
        FROM dbo.BOOKING
        WHERE space_code = @W1SpaceCode
          AND booking_status = 'approved'
          AND requested_start_time < @W1End
          AND requested_end_time > @W1Start;
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= 5
    BEGIN
        RAISERROR ('INDEXED W2 run %d', 10, 1, @Run) WITH NOWAIT;
        SELECT * FROM dbo.fn_GetAvailableSpaces(@W2Capacity, @W2Start, @W2End, @RequiredFacilities);
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= 5
    BEGIN
        RAISERROR ('INDEXED W3 run %d', 10, 1, @Run) WITH NOWAIT;
        SELECT * FROM dbo.fn_CountApprovedBookingHourBySemester(@SemesterId);
        SET @Run += 1;
    END;

    SET @Run = 1;
    WHILE @Run <= 5
    BEGIN
        RAISERROR ('INDEXED W4 run %d', 10, 1, @Run) WITH NOWAIT;
        SELECT * FROM dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@SemesterId);
        SET @Run += 1;
    END;

    SET STATISTICS TIME OFF;
    SET STATISTICS IO OFF;

    -- Restore the exact original candidate state.
    IF @C1OriginallyExisted = 0
        DROP INDEX IF EXISTS ix_booking_overlap_lock ON dbo.BOOKING;
    ELSE IF @C1OriginallyDisabled = 1
        ALTER INDEX ix_booking_overlap_lock ON dbo.BOOKING DISABLE;

    IF @C2OriginallyExisted = 0
        DROP INDEX IF EXISTS ix_g09_booking_semester_reporting ON dbo.BOOKING;
    ELSE IF @C2OriginallyDisabled = 1
        ALTER INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING DISABLE;

    IF @C3OriginallyExisted = 0
        DROP INDEX IF EXISTS ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD;
    ELSE IF @C3OriginallyDisabled = 1
        ALTER INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD DISABLE;

    IF @C4OriginallyExisted = 0
        DROP INDEX IF EXISTS ix_g09_facility_space ON dbo.FACILITY;
    ELSE IF @C4OriginallyDisabled = 1
        ALTER INDEX ix_g09_facility_space ON dbo.FACILITY DISABLE;

    IF (@C1OriginallyExisted = 0 AND INDEXPROPERTY(OBJECT_ID('dbo.BOOKING'), @C1Name, 'IndexId') IS NOT NULL)
       OR (@C1OriginallyExisted = 1 AND ISNULL((SELECT is_disabled FROM sys.indexes
                                               WHERE object_id = OBJECT_ID('dbo.BOOKING')
                                                 AND name = @C1Name), -1) <> @C1OriginallyDisabled)
       OR (@C2OriginallyExisted = 0 AND INDEXPROPERTY(OBJECT_ID('dbo.BOOKING'), @C2Name, 'IndexId') IS NOT NULL)
       OR (@C2OriginallyExisted = 1 AND ISNULL((SELECT is_disabled FROM sys.indexes
                                               WHERE object_id = OBJECT_ID('dbo.BOOKING')
                                                 AND name = @C2Name), -1) <> @C2OriginallyDisabled)
       OR (@C3OriginallyExisted = 0 AND INDEXPROPERTY(OBJECT_ID('dbo.MAINTENANCE_RECORD'), @C3Name, 'IndexId') IS NOT NULL)
       OR (@C3OriginallyExisted = 1 AND ISNULL((SELECT is_disabled FROM sys.indexes
                                               WHERE object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
                                                 AND name = @C3Name), -1) <> @C3OriginallyDisabled)
       OR (@C4OriginallyExisted = 0 AND INDEXPROPERTY(OBJECT_ID('dbo.FACILITY'), @C4Name, 'IndexId') IS NOT NULL)
       OR (@C4OriginallyExisted = 1 AND ISNULL((SELECT is_disabled FROM sys.indexes
                                               WHERE object_id = OBJECT_ID('dbo.FACILITY')
                                                 AND name = @C4Name), -1) <> @C4OriginallyDisabled)
    BEGIN
        ;THROW 51000, 'Restoration verification failed.', 1;
    END;

    PRINT 'Benchmark complete.';
    PRINT 'Original candidate index existence and enabled/disabled state verified.';
END TRY
BEGIN CATCH
    SET STATISTICS XML OFF;
    SET STATISTICS TIME OFF;
    SET STATISTICS IO OFF;

    BEGIN TRY
        IF @C1OriginallyExisted = 0
            DROP INDEX IF EXISTS ix_booking_overlap_lock ON dbo.BOOKING;
        ELSE IF @C1OriginallyDisabled = 1
            ALTER INDEX ix_booking_overlap_lock ON dbo.BOOKING DISABLE;
        ELSE
            ALTER INDEX ix_booking_overlap_lock ON dbo.BOOKING REBUILD;

        IF @C2OriginallyExisted = 0
            DROP INDEX IF EXISTS ix_g09_booking_semester_reporting ON dbo.BOOKING;
        ELSE IF @C2OriginallyDisabled = 1
            ALTER INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING DISABLE;
        ELSE
            ALTER INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING REBUILD;

        IF @C3OriginallyExisted = 0
            DROP INDEX IF EXISTS ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD;
        ELSE IF @C3OriginallyDisabled = 1
            ALTER INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD DISABLE;
        ELSE
            ALTER INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD REBUILD;

        IF @C4OriginallyExisted = 0
            DROP INDEX IF EXISTS ix_g09_facility_space ON dbo.FACILITY;
        ELSE IF @C4OriginallyDisabled = 1
            ALTER INDEX ix_g09_facility_space ON dbo.FACILITY DISABLE;
        ELSE
            ALTER INDEX ix_g09_facility_space ON dbo.FACILITY REBUILD;

        PRINT 'Best-effort restoration completed after benchmark failure.';
    END TRY
    BEGIN CATCH
        PRINT 'WARNING: best-effort restoration also failed; inspect candidate indexes manually.';
    END CATCH;

    THROW;
END CATCH;
