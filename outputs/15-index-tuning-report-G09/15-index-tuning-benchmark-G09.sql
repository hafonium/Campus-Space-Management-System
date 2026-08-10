/*
Step 15 clean-room index-tuning benchmark (G09)
Target: Microsoft SQL Server

SAFETY DEFAULT
--------------
@execute_full_benchmark is deliberately 0. In that mode this script performs
preflight, metadata inspection, workload compilation, deterministic parameter
selection, and W2 viability validation, then stops before changing any index.

Set @execute_full_benchmark = 1 only for a controlled benchmark window with no
concurrent booking or maintenance writes. The full run takes exclusive table
locks inside one transaction, restores the original index existence/enabled
state, verifies restoration, and commits only after successful verification.

Capture the Results and Messages output. SET STATISTICS XML emits representative
BASE and INDEXED actual plans; the plan-capture executions are not measured runs.
*/

USE CampusSpaceManagementSystem;

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
SET STATISTICS XML OFF;

DECLARE @execute_full_benchmark BIT = 0; -- Change to 1 only at the human execution gate.

PRINT 'STEP 15 INDEX-TUNING BENCHMARK G09';
PRINT CONCAT('Mode: ', CASE WHEN @execute_full_benchmark = 1
    THEN 'FULL BASE/INDEXED BENCHMARK' ELSE 'VALIDATION ONLY' END);

/* -------------------------------------------------------------------------
   1. Dataset preflight
   ------------------------------------------------------------------------- */

IF OBJECT_ID(N'dbo.BOOKING', N'U') IS NULL
    THROW 51000, 'Preflight failed: dbo.BOOKING does not exist.', 1;
IF OBJECT_ID(N'dbo.SPACE', N'U') IS NULL
    THROW 51000, 'Preflight failed: dbo.SPACE does not exist.', 1;
IF OBJECT_ID(N'dbo.FACILITY', N'U') IS NULL
    THROW 51000, 'Preflight failed: dbo.FACILITY does not exist.', 1;
IF COL_LENGTH(N'dbo.FACILITY', N'space_code') IS NULL
    THROW 51000, 'Preflight failed: dbo.FACILITY.space_code does not exist.', 1;
IF OBJECT_ID(N'dbo.SPACE_FACILITY', N'U') IS NOT NULL
    THROW 51000, 'Preflight failed: obsolete dbo.SPACE_FACILITY still exists.', 1;
IF OBJECT_ID(N'dbo.MAINTENANCE_RECORD', N'U') IS NULL
    THROW 51000, 'Preflight failed: dbo.MAINTENANCE_RECORD does not exist.', 1;
IF OBJECT_ID(N'dbo.SEMESTER', N'U') IS NULL
    THROW 51000, 'Preflight failed: dbo.SEMESTER does not exist.', 1;

DECLARE @booking_count BIGINT;
DECLARE @strict_approved_count BIGINT;
DECLARE @active_or_approved_count BIGINT;
DECLARE @maintenance_count BIGINT;
DECLARE @first_booking_start DATETIME2;
DECLARE @last_booking_end DATETIME2;
DECLARE @booking_span_days INT;
DECLARE @semester_count BIGINT;
DECLARE @covered_semester_count BIGINT;
DECLARE @first_semester_start DATE;
DECLARE @last_semester_end DATE;

SELECT
    @booking_count = COUNT_BIG(*),
    @strict_approved_count = SUM(CASE WHEN booking_status = 'approved' THEN CONVERT(BIGINT, 1) ELSE 0 END),
    @active_or_approved_count = SUM(CASE
        WHEN booking_status IN ('approved', 'checked_in', 'completed')
        THEN CONVERT(BIGINT, 1) ELSE 0 END),
    @first_booking_start = MIN(requested_start_time),
    @last_booking_end = MAX(requested_end_time)
FROM dbo.BOOKING;

SELECT @maintenance_count = COUNT_BIG(*)
FROM dbo.MAINTENANCE_RECORD;

SELECT
    @semester_count = COUNT_BIG(*),
    @first_semester_start = MIN(start_date),
    @last_semester_end = MAX(end_date)
FROM dbo.SEMESTER;

SELECT @covered_semester_count = COUNT_BIG(*)
FROM dbo.SEMESTER AS SEM
WHERE EXISTS (
    SELECT 1
    FROM dbo.BOOKING AS B
    WHERE B.requested_end_time > CAST(SEM.start_date AS DATETIME2)
      AND B.requested_start_time < DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2))
);

SET @booking_span_days = DATEDIFF(DAY, @first_booking_start, @last_booking_end);

SELECT
    @booking_count AS total_bookings,
    @strict_approved_count AS approved_bookings,
    @active_or_approved_count AS approved_checked_in_completed_bookings,
    @maintenance_count AS maintenance_records,
    @first_booking_start AS first_booking_start,
    @last_booking_end AS last_booking_end,
    @booking_span_days AS booking_date_span_days,
    @semester_count AS semester_count,
    @covered_semester_count AS semesters_overlapping_booking_data,
    @first_semester_start AS first_semester_start,
    @last_semester_end AS last_semester_end;

IF @booking_count < 100000
    THROW 51000, 'Preflight failed: BOOKING must contain at least 100000 rows.', 1;
IF @booking_span_days < 1095
    THROW 51000, 'Preflight failed: booking data must span at least three years (1095 days).', 1;
IF @strict_approved_count = 0 OR @active_or_approved_count = 0
    THROW 51000, 'Preflight failed: active/approved booking data is required.', 1;
IF @maintenance_count = 0
    THROW 51000, 'Preflight failed: maintenance data is required.', 1;
IF @semester_count = 0 OR @covered_semester_count = 0
    THROW 51000, 'Preflight failed: semester coverage over booking data is required.', 1;

PRINT 'Dataset preflight passed.';

/* -------------------------------------------------------------------------
   2. SQL Server environment
   ------------------------------------------------------------------------- */

SELECT
    CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) AS product_version,
    CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)) AS product_level,
    CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) AS edition,
    D.compatibility_level,
    D.recovery_model_desc AS recovery_model,
    @@LANGUAGE AS session_language,
    @@DATEFIRST AS session_datefirst
FROM sys.databases AS D
WHERE D.name = DB_NAME();

/* -------------------------------------------------------------------------
   3. Current index inventory
   ------------------------------------------------------------------------- */

SELECT
    SC.name AS schema_name,
    T.name AS table_name,
    I.name AS index_name,
    I.type_desc,
    I.is_unique,
    I.is_primary_key,
    I.is_unique_constraint,
    I.is_disabled,
    I.has_filter,
    I.filter_definition,
    K.key_columns,
    INC.included_columns
FROM sys.tables AS T
JOIN sys.schemas AS SC
    ON SC.schema_id = T.schema_id
JOIN sys.indexes AS I
    ON I.object_id = T.object_id
   AND I.index_id > 0
OUTER APPLY (
    SELECT STRING_AGG(
        CAST(QUOTENAME(C.name) + CASE WHEN IC.is_descending_key = 1
            THEN ' DESC' ELSE ' ASC' END AS NVARCHAR(MAX)), ', '
    ) WITHIN GROUP (ORDER BY IC.key_ordinal) AS key_columns
    FROM sys.index_columns AS IC
    JOIN sys.columns AS C
        ON C.object_id = IC.object_id
       AND C.column_id = IC.column_id
    WHERE IC.object_id = I.object_id
      AND IC.index_id = I.index_id
      AND IC.key_ordinal > 0
      AND IC.is_included_column = 0
) AS K
OUTER APPLY (
    SELECT STRING_AGG(
        CAST(QUOTENAME(C.name) AS NVARCHAR(MAX)), ', '
    ) WITHIN GROUP (ORDER BY IC.index_column_id) AS included_columns
    FROM sys.index_columns AS IC
    JOIN sys.columns AS C
        ON C.object_id = IC.object_id
       AND C.column_id = IC.column_id
    WHERE IC.object_id = I.object_id
      AND IC.index_id = I.index_id
      AND IC.is_included_column = 1
) AS INC
WHERE SC.name = N'dbo'
  AND T.name IN (
      N'BOOKING', N'SPACE', N'FACILITY',
      N'MAINTENANCE_RECORD', N'SEMESTER'
  )
ORDER BY T.name, I.index_id;

/* -------------------------------------------------------------------------
   4. Candidate-name and exact-definition safety
   ------------------------------------------------------------------------- */

CREATE TABLE #ExpectedCandidateColumns (
    object_id INT NOT NULL,
    index_name SYSNAME NOT NULL,
    column_name SYSNAME NOT NULL,
    key_ordinal TINYINT NOT NULL,
    is_included_column BIT NOT NULL,
    CONSTRAINT pk_expected_candidate_columns
        PRIMARY KEY (object_id, index_name, column_name)
);

INSERT INTO #ExpectedCandidateColumns (
    object_id, index_name, column_name, key_ordinal, is_included_column
)
VALUES
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_booking_overlap_lock', N'space_code', 1, 0),
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_booking_overlap_lock', N'booking_status', 2, 0),
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_booking_overlap_lock', N'requested_start_time', 3, 0),
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_booking_overlap_lock', N'requested_end_time', 4, 0),
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_g09_booking_semester_reporting', N'booking_status', 1, 0),
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_g09_booking_semester_reporting', N'requested_start_time', 2, 0),
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_g09_booking_semester_reporting', N'space_code', 3, 0),
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_g09_booking_semester_reporting', N'requested_end_time', 0, 1),
    (OBJECT_ID(N'dbo.MAINTENANCE_RECORD'), N'ix_g09_maintenance_room_finder', N'space_code', 1, 0),
    (OBJECT_ID(N'dbo.MAINTENANCE_RECORD'), N'ix_g09_maintenance_room_finder', N'impact_level', 2, 0),
    (OBJECT_ID(N'dbo.MAINTENANCE_RECORD'), N'ix_g09_maintenance_room_finder', N'status', 3, 0),
    (OBJECT_ID(N'dbo.MAINTENANCE_RECORD'), N'ix_g09_maintenance_room_finder', N'start_time', 4, 0),
    (OBJECT_ID(N'dbo.MAINTENANCE_RECORD'), N'ix_g09_maintenance_room_finder', N'completion_time', 0, 1);

CREATE TABLE #ExpectedCandidates (
    object_id INT NOT NULL,
    index_name SYSNAME NOT NULL,
    CONSTRAINT pk_expected_candidates PRIMARY KEY (object_id, index_name)
);

INSERT INTO #ExpectedCandidates (object_id, index_name)
VALUES
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_booking_overlap_lock'),
    (OBJECT_ID(N'dbo.BOOKING'), N'ix_g09_booking_semester_reporting'),
    (OBJECT_ID(N'dbo.MAINTENANCE_RECORD'), N'ix_g09_maintenance_room_finder');

IF EXISTS (
    SELECT 1
    FROM #ExpectedCandidates AS E
    JOIN sys.indexes AS I
      ON I.object_id = E.object_id
     AND I.name = E.index_name
    WHERE I.type <> 2
       OR I.is_unique = 1
       OR I.is_primary_key = 1
       OR I.is_unique_constraint = 1
       OR I.has_filter = 1
       OR EXISTS (
            SELECT 1
            FROM sys.index_columns AS IC
            WHERE IC.object_id = I.object_id
              AND IC.index_id = I.index_id
              AND IC.key_ordinal > 0
              AND IC.is_descending_key = 1
       )
       OR EXISTS (
            SELECT 1
            FROM sys.index_columns AS IC
            JOIN sys.columns AS C
              ON C.object_id = IC.object_id
             AND C.column_id = IC.column_id
            WHERE IC.object_id = I.object_id
              AND IC.index_id = I.index_id
              AND (IC.key_ordinal > 0 OR IC.is_included_column = 1)
              AND NOT EXISTS (
                  SELECT 1
                  FROM #ExpectedCandidateColumns AS EC
                  WHERE EC.object_id = I.object_id
                    AND EC.index_name = I.name
                    AND EC.column_name = C.name
                    AND EC.key_ordinal = IC.key_ordinal
                    AND EC.is_included_column = IC.is_included_column
              )
       )
       OR EXISTS (
            SELECT 1
            FROM #ExpectedCandidateColumns AS EC
            WHERE EC.object_id = I.object_id
              AND EC.index_name = I.name
              AND NOT EXISTS (
                  SELECT 1
                  FROM sys.index_columns AS IC
                  JOIN sys.columns AS C
                    ON C.object_id = IC.object_id
                   AND C.column_id = IC.column_id
                  WHERE IC.object_id = I.object_id
                    AND IC.index_id = I.index_id
                    AND C.name = EC.column_name
                    AND IC.key_ordinal = EC.key_ordinal
                    AND IC.is_included_column = EC.is_included_column
              )
       )
)
    THROW 51000, 'Candidate-name safety failed: an existing candidate name has a different definition.', 1;

PRINT 'Candidate-name safety passed.';

/* Snapshot every non-unique rowstore performance index that the clean BASE may
   disable on the candidate target tables, plus absent candidate names. */
CREATE TABLE #OriginalIndexState (
    object_id INT NOT NULL,
    schema_name SYSNAME NOT NULL,
    table_name SYSNAME NOT NULL,
    index_name SYSNAME NOT NULL,
    originally_exists BIT NOT NULL,
    originally_disabled BIT NULL,
    is_candidate BIT NOT NULL,
    CONSTRAINT pk_original_index_state PRIMARY KEY (object_id, index_name)
);

INSERT INTO #OriginalIndexState (
    object_id, schema_name, table_name, index_name,
    originally_exists, originally_disabled, is_candidate
)
SELECT
    I.object_id,
    SC.name,
    T.name,
    I.name,
    1,
    I.is_disabled,
    CASE WHEN E.index_name IS NULL THEN 0 ELSE 1 END
FROM sys.indexes AS I
JOIN sys.tables AS T
  ON T.object_id = I.object_id
JOIN sys.schemas AS SC
  ON SC.schema_id = T.schema_id
LEFT JOIN #ExpectedCandidates AS E
  ON E.object_id = I.object_id
 AND E.index_name = I.name
WHERE I.object_id IN (
        OBJECT_ID(N'dbo.BOOKING'),
        OBJECT_ID(N'dbo.MAINTENANCE_RECORD')
      )
  AND I.index_id > 0
  AND I.type = 2
  AND I.is_unique = 0
  AND I.is_primary_key = 0
  AND I.is_unique_constraint = 0;

INSERT INTO #OriginalIndexState (
    object_id, schema_name, table_name, index_name,
    originally_exists, originally_disabled, is_candidate
)
SELECT
    E.object_id,
    N'dbo',
    OBJECT_NAME(E.object_id),
    E.index_name,
    0,
    NULL,
    1
FROM #ExpectedCandidates AS E
WHERE NOT EXISTS (
    SELECT 1
    FROM #OriginalIndexState AS O
    WHERE O.object_id = E.object_id
      AND O.index_name = E.index_name
);

SELECT
    schema_name,
    table_name,
    index_name,
    originally_exists,
    originally_disabled,
    is_candidate
FROM #OriginalIndexState
ORDER BY table_name, index_name;

/* -------------------------------------------------------------------------
   5. Frozen canonical workload bodies: define each exactly once
   ------------------------------------------------------------------------- */

DECLARE @W1_SQL NVARCHAR(MAX) = N'
SELECT COUNT_BIG(*) AS overlapping_approved_bookings
FROM dbo.BOOKING
WHERE space_code = @p_space_code
  AND booking_status = ''approved''
  AND requested_start_time < @p_probe_end
  AND requested_end_time > @p_probe_start;';

DECLARE @W1_PARAMS NVARCHAR(MAX) = N'
    @p_space_code VARCHAR(50),
    @p_probe_end DATETIME2,
    @p_probe_start DATETIME2';

DECLARE @W2_SQL NVARCHAR(MAX) = N'
SELECT S.space_code
FROM dbo.SPACE S
WHERE S.capacity >= @p_capacity
  AND S.current_status NOT IN (''temporarily_closed'', ''retired'')
  AND NOT EXISTS (
      SELECT 1
      FROM (VALUES (@p_facility_1), (@p_facility_2)) AS RF(facility_id)
      WHERE RF.facility_id NOT IN (
          SELECT F.facility_id
          FROM dbo.FACILITY F
          WHERE F.space_code = S.space_code
      )
  )

EXCEPT

SELECT S.space_code
FROM dbo.SPACE S
JOIN dbo.BOOKING B
    ON B.space_code = S.space_code
WHERE B.booking_status IN (''approved'', ''checked_in'', ''completed'')
  AND B.requested_end_time > @p_start_time
  AND B.requested_start_time < @p_end_time

EXCEPT

SELECT S.space_code
FROM dbo.SPACE S
JOIN dbo.MAINTENANCE_RECORD MR
    ON MR.space_code = S.space_code
WHERE MR.impact_level = ''out-of-service''
  AND MR.status IN (''reported'', ''in_progress'')
  AND MR.start_time < @p_end_time
  AND ISNULL(
        MR.completion_time,
        CONVERT(DATETIME2, ''9999-12-31'')
      ) > @p_start_time;';

DECLARE @W2_PARAMS NVARCHAR(MAX) = N'
    @p_capacity INT,
    @p_facility_1 INT,
    @p_facility_2 INT,
    @p_start_time DATETIME2,
    @p_end_time DATETIME2';

/* W3 is the final Step 16 LEFT JOIN/aggregation body. Only the semester-id
   parameter name differs from the table-valued function definition. */
DECLARE @W3_SQL NVARCHAR(MAX) = N'
SELECT
    S.space_code,
    ISNULL(SUM(DATEDIFF(MINUTE, B.requested_start_time, B.requested_end_time) / 60.0), 0) AS total_hour
FROM dbo.SPACE S
LEFT JOIN dbo.BOOKING B
    ON S.space_code = B.space_code
    AND B.booking_status IN (''approved'', ''checked_in'', ''completed'')
    AND B.requested_end_time > (
        SELECT CAST(SEM.start_date AS DATETIME2)
        FROM dbo.SEMESTER SEM
        WHERE SEM.semester_id = @p_semester_id
    )
    AND B.requested_start_time < (
        SELECT DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2))
        FROM dbo.SEMESTER SEM
        WHERE SEM.semester_id = @p_semester_id
    )
WHERE EXISTS (
    SELECT 1
    FROM dbo.SEMESTER SEM
    WHERE SEM.semester_id = @p_semester_id
)
GROUP BY S.space_code;';

DECLARE @W3_PARAMS NVARCHAR(MAX) = N'@p_semester_id INT';

/* W4 is the final Step 16 filtering/grouping body. Only the semester-id
   parameter name differs from the table-valued function definition. */
DECLARE @W4_SQL NVARCHAR(MAX) = N'
SELECT
    DATENAME(WEEKDAY, B.requested_start_time) AS weekday,
    DATEPART(HOUR, B.requested_start_time) AS hour,
    COUNT(*) AS approved_booking
FROM dbo.BOOKING B
JOIN dbo.SEMESTER SEM ON SEM.semester_id = @p_semester_id
WHERE B.booking_status IN (''approved'', ''checked_in'', ''completed'')
    AND B.requested_end_time > CAST(SEM.start_date AS DATETIME2)
    AND B.requested_start_time < DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2))
GROUP BY
    DATENAME(WEEKDAY, B.requested_start_time),
    DATEPART(HOUR, B.requested_start_time);';

DECLARE @W4_PARAMS NVARCHAR(MAX) = N'@p_semester_id INT';

/* Compile and bind all four canonical dynamic batches without executing them.
   The DMF returns one row per result column; aggregation consumes those rows so
   validation output stays compact while any compile/binding error still fails. */
PRINT 'Compiling W1-W4 with sys.dm_exec_describe_first_result_set.';
DECLARE @compile_error_number INT;
DECLARE @compile_error_message NVARCHAR(4000);

SELECT
    @compile_error_number = error_number,
    @compile_error_message = error_message
FROM sys.dm_exec_describe_first_result_set(@W1_SQL, @W1_PARAMS, 0)
WHERE error_number IS NOT NULL;
IF @compile_error_number IS NOT NULL
    THROW 51000, @compile_error_message, 1;

SET @compile_error_number = NULL;
SET @compile_error_message = NULL;
SELECT
    @compile_error_number = error_number,
    @compile_error_message = error_message
FROM sys.dm_exec_describe_first_result_set(@W2_SQL, @W2_PARAMS, 0)
WHERE error_number IS NOT NULL;
IF @compile_error_number IS NOT NULL
    THROW 51000, @compile_error_message, 1;

SET @compile_error_number = NULL;
SET @compile_error_message = NULL;
SELECT
    @compile_error_number = error_number,
    @compile_error_message = error_message
FROM sys.dm_exec_describe_first_result_set(@W3_SQL, @W3_PARAMS, 0)
WHERE error_number IS NOT NULL;
IF @compile_error_number IS NOT NULL
    THROW 51000, @compile_error_message, 1;

SET @compile_error_number = NULL;
SET @compile_error_message = NULL;
SELECT
    @compile_error_number = error_number,
    @compile_error_message = error_message
FROM sys.dm_exec_describe_first_result_set(@W4_SQL, @W4_PARAMS, 0)
WHERE error_number IS NOT NULL;
IF @compile_error_number IS NOT NULL
    THROW 51000, @compile_error_message, 1;
PRINT 'Canonical workload compilation passed.';

/* -------------------------------------------------------------------------
   6. Deterministic parameters from real data
   ------------------------------------------------------------------------- */

DECLARE @semester_id INT;
DECLARE @semester_start DATETIME2;
DECLARE @semester_end_exclusive DATETIME2;
DECLARE @semester_qualifying_rows BIGINT;

SELECT TOP (1)
    @semester_id = SEM.semester_id,
    @semester_start = CAST(SEM.start_date AS DATETIME2),
    @semester_end_exclusive = DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2)),
    @semester_qualifying_rows = Q.qualifying_rows
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

DECLARE @w1_space_code VARCHAR(50);
DECLARE @w1_probe_start DATETIME2;
DECLARE @w1_probe_end DATETIME2;
DECLARE @w1_booking_id INT;

SELECT TOP (1)
    @w1_booking_id = B.booking_id,
    @w1_space_code = B.space_code,
    @w1_probe_start = B.requested_start_time,
    @w1_probe_end = B.requested_end_time
FROM dbo.BOOKING AS B
WHERE B.booking_status = 'approved'
ORDER BY B.booking_id;

DECLARE @w2_start_time DATETIME2;
DECLARE @w2_end_time DATETIME2;
DECLARE @w2_interval_source VARCHAR(40);
DECLARE @w2_anchor_space_code VARCHAR(50);
DECLARE @w2_capacity INT;
DECLARE @w2_facility_1 INT;
DECLARE @w2_facility_2 INT;
DECLARE @w2_facility_2_effective INT;
DECLARE @w2_facility_count INT;
DECLARE @last_event_end DATETIME2;

SELECT TOP (1)
    @w2_start_time = MR.start_time,
    @w2_end_time = CASE
        WHEN MR.completion_time > MR.start_time THEN MR.completion_time
        ELSE DATEADD(HOUR, 2, MR.start_time)
    END,
    @w2_interval_source = 'active out-of-service maintenance'
FROM dbo.MAINTENANCE_RECORD AS MR
WHERE MR.impact_level = 'out-of-service'
  AND MR.status IN ('reported', 'in_progress')
ORDER BY MR.start_time, MR.maintenance_id;

/* Choose an anchor that makes capacity/facilities satisfiable and leaves at
   least one valid W2 result for the preferred interval. */
SELECT TOP (1)
    @w2_anchor_space_code = S.space_code,
    @w2_capacity = S.capacity
FROM dbo.SPACE AS S
WHERE @w2_start_time IS NOT NULL
  AND S.current_status NOT IN ('temporarily_closed', 'retired')
  AND EXISTS (
      SELECT 1 FROM dbo.FACILITY AS F
      WHERE F.space_code = S.space_code
  )
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.BOOKING AS B
      WHERE B.space_code = S.space_code
        AND B.booking_status IN ('approved', 'checked_in', 'completed')
        AND B.requested_end_time > @w2_start_time
        AND B.requested_start_time < @w2_end_time
  )
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.MAINTENANCE_RECORD AS MR
      WHERE MR.space_code = S.space_code
        AND MR.impact_level = 'out-of-service'
        AND MR.status IN ('reported', 'in_progress')
        AND MR.start_time < @w2_end_time
        AND ISNULL(MR.completion_time, CONVERT(DATETIME2, '9999-12-31')) > @w2_start_time
  )
ORDER BY
    (SELECT COUNT_BIG(*) FROM dbo.FACILITY AS F
     WHERE F.space_code = S.space_code) DESC,
    S.space_code;

/* Deterministic fallback: a two-hour interval after all recorded activity. */
IF @w2_anchor_space_code IS NULL
BEGIN
    SELECT @last_event_end = MAX(E.event_end)
    FROM (
        SELECT MAX(B.requested_end_time) AS event_end
        FROM dbo.BOOKING AS B
        UNION ALL
        SELECT MAX(COALESCE(MR.completion_time, MR.start_time)) AS event_end
        FROM dbo.MAINTENANCE_RECORD AS MR
    ) AS E;

    SET @w2_start_time = DATEADD(DAY, 1, COALESCE(@last_event_end, SYSDATETIME()));
    SET @w2_end_time = DATEADD(HOUR, 2, @w2_start_time);
    SET @w2_interval_source = 'post-history deterministic fallback';

    SELECT TOP (1)
        @w2_anchor_space_code = S.space_code,
        @w2_capacity = S.capacity
    FROM dbo.SPACE AS S
    WHERE S.current_status NOT IN ('temporarily_closed', 'retired')
      AND EXISTS (
          SELECT 1 FROM dbo.FACILITY AS F
          WHERE F.space_code = S.space_code
      )
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.MAINTENANCE_RECORD AS MR
          WHERE MR.space_code = S.space_code
            AND MR.impact_level = 'out-of-service'
            AND MR.status IN ('reported', 'in_progress')
            AND MR.start_time < @w2_end_time
            AND ISNULL(MR.completion_time, CONVERT(DATETIME2, '9999-12-31')) > @w2_start_time
      )
    ORDER BY
        (SELECT COUNT_BIG(*) FROM dbo.FACILITY AS F
         WHERE F.space_code = S.space_code) DESC,
        S.space_code;
END;

SELECT
    @w2_facility_count = COUNT(*),
    @w2_facility_1 = MIN(F.facility_id)
FROM dbo.FACILITY AS F
WHERE F.space_code = @w2_anchor_space_code;

SELECT @w2_facility_2 = MIN(F.facility_id)
FROM dbo.FACILITY AS F
WHERE F.space_code = @w2_anchor_space_code
  AND F.facility_id > @w2_facility_1;

SET @w2_facility_2_effective = COALESCE(@w2_facility_2, @w2_facility_1);

IF @semester_id IS NULL
   OR @semester_start IS NULL
   OR @semester_end_exclusive IS NULL
   OR @semester_qualifying_rows IS NULL
   OR @semester_qualifying_rows = 0
    THROW 51000, 'Parameter validation failed: no viable semester for W3/W4.', 1;

IF @w1_booking_id IS NULL
   OR @w1_space_code IS NULL
   OR @w1_probe_start IS NULL
   OR @w1_probe_end IS NULL
    THROW 51000, 'Parameter validation failed: no complete approved booking for W1.', 1;

IF @w2_anchor_space_code IS NULL
   OR @w2_capacity IS NULL
   OR @w2_facility_1 IS NULL
   OR @w2_facility_2_effective IS NULL
   OR @w2_start_time IS NULL
   OR @w2_end_time IS NULL
   OR @w2_start_time >= @w2_end_time
    THROW 51000, 'Parameter validation failed: no viable W2 capacity/facility/time parameter set.', 1;

SELECT
    @semester_id AS semester_id,
    @semester_start AS semester_start,
    @semester_end_exclusive AS semester_end_exclusive,
    @semester_qualifying_rows AS qualifying_booking_rows;

SELECT
    @w1_booking_id AS source_approved_booking_id,
    @w1_space_code AS space_code,
    @w1_probe_start AS probe_start,
    @w1_probe_end AS probe_end;

SELECT
    @w2_interval_source AS interval_source,
    @w2_anchor_space_code AS satisfiable_anchor_space,
    @w2_capacity AS required_capacity,
    @w2_facility_1 AS facility_1,
    @w2_facility_2 AS facility_2_if_distinct,
    @w2_facility_2_effective AS facility_2_effective,
    @w2_facility_count AS facilities_on_anchor_space,
    @w2_start_time AS start_time,
    @w2_end_time AS end_time;

/* Execute the exact W2 body once and count its result rows. This is a viability
   check, not a measured BASE or INDEXED run. */
CREATE TABLE #W2Viability (
    space_code VARCHAR(50) NOT NULL PRIMARY KEY
);

INSERT INTO #W2Viability (space_code)
EXEC sys.sp_executesql
    @stmt = @W2_SQL,
    @params = @W2_PARAMS,
    @p_capacity = @w2_capacity,
    @p_facility_1 = @w2_facility_1,
    @p_facility_2 = @w2_facility_2_effective,
    @p_start_time = @w2_start_time,
    @p_end_time = @w2_end_time;

DECLARE @w2_result_count BIGINT;
SELECT @w2_result_count = COUNT_BIG(*) FROM #W2Viability;
SELECT @w2_result_count AS w2_viability_result_count;

IF @w2_result_count = 0
    THROW 51000, 'Parameter validation failed: W2 returned no spaces.', 1;

PRINT 'Deterministic parameter and W2 viability validation passed.';

IF @execute_full_benchmark <> 1
BEGIN
    PRINT 'VALIDATION ONLY COMPLETE. No index state was changed.';
    PRINT 'Set @execute_full_benchmark = 1 only when ready for the controlled full run.';
    RETURN;
END;

/* -------------------------------------------------------------------------
   7. Controlled BASE/INDEXED experiment and restoration
   ------------------------------------------------------------------------- */

DECLARE @ddl NVARCHAR(MAX);
DECLARE @lock_probe BIGINT;
DECLARE @run INT;
DECLARE @original_error_number INT;
DECLARE @original_error_message NVARCHAR(4000);

BEGIN TRY
    SET LOCK_TIMEOUT 30000;
    BEGIN TRANSACTION;

    /* Hold exclusive locks for the whole experiment. If another session is
       active, fail rather than benchmark amid concurrent writes. */
    SELECT @lock_probe = COUNT_BIG(*)
    FROM dbo.BOOKING WITH (TABLOCKX, HOLDLOCK);

    SELECT @lock_probe = COUNT_BIG(*)
    FROM dbo.MAINTENANCE_RECORD WITH (TABLOCKX, HOLDLOCK);

    PRINT 'Exclusive benchmark locks acquired; concurrent writes are blocked.';

    /* CLEAN BASE: disable only non-unique, non-constraint rowstore performance
       indexes on BOOKING and MAINTENANCE_RECORD. Integrity indexes are absent
       from #OriginalIndexState by construction and cannot be disabled here. */
    SET @ddl = N'';
    SELECT @ddl = @ddl
        + N'ALTER INDEX ' + QUOTENAME(O.index_name)
        + N' ON ' + QUOTENAME(O.schema_name) + N'.' + QUOTENAME(O.table_name)
        + N' DISABLE;' + CHAR(10)
    FROM #OriginalIndexState AS O
    WHERE O.originally_exists = 1
      AND O.originally_disabled = 0
    ORDER BY O.table_name, O.index_name;

    IF @ddl <> N''
        EXEC sys.sp_executesql @stmt = @ddl;

    IF EXISTS (
        SELECT 1
        FROM #OriginalIndexState AS O
        JOIN sys.indexes AS I
          ON I.object_id = O.object_id
         AND I.name = O.index_name
        WHERE O.originally_exists = 1
          AND I.is_disabled = 0
    )
        THROW 51000, 'Clean BASE failed: a snapshotted performance index remains enabled.', 1;

    PRINT 'CLEAN BASE READY';

    /* BASE warm-up: statistics and plan XML remain off. */
    PRINT 'BASE WARM-UP W1';
    EXEC sys.sp_executesql @W1_SQL, @W1_PARAMS,
        @p_space_code = @w1_space_code,
        @p_probe_end = @w1_probe_end,
        @p_probe_start = @w1_probe_start;
    PRINT 'BASE WARM-UP W2';
    EXEC sys.sp_executesql @W2_SQL, @W2_PARAMS,
        @p_capacity = @w2_capacity,
        @p_facility_1 = @w2_facility_1,
        @p_facility_2 = @w2_facility_2_effective,
        @p_start_time = @w2_start_time,
        @p_end_time = @w2_end_time;
    PRINT 'BASE WARM-UP W3';
    EXEC sys.sp_executesql @W3_SQL, @W3_PARAMS,
        @p_semester_id = @semester_id;
    PRINT 'BASE WARM-UP W4';
    EXEC sys.sp_executesql @W4_SQL, @W4_PARAMS,
        @p_semester_id = @semester_id;

    /* Representative BASE actual plans; excluded from five-run medians. */
    PRINT 'BASE ACTUAL PLAN CAPTURE W1-W4 (not a measured run)';
    SET STATISTICS XML ON;
    EXEC sys.sp_executesql @W1_SQL, @W1_PARAMS,
        @p_space_code = @w1_space_code,
        @p_probe_end = @w1_probe_end,
        @p_probe_start = @w1_probe_start;
    EXEC sys.sp_executesql @W2_SQL, @W2_PARAMS,
        @p_capacity = @w2_capacity,
        @p_facility_1 = @w2_facility_1,
        @p_facility_2 = @w2_facility_2_effective,
        @p_start_time = @w2_start_time,
        @p_end_time = @w2_end_time;
    EXEC sys.sp_executesql @W3_SQL, @W3_PARAMS,
        @p_semester_id = @semester_id;
    EXEC sys.sp_executesql @W4_SQL, @W4_PARAMS,
        @p_semester_id = @semester_id;
    SET STATISTICS XML OFF;

    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;

    SET @run = 1;
    WHILE @run <= 5
    BEGIN
        PRINT CONCAT('BASE W1 run ', @run);
        EXEC sys.sp_executesql @W1_SQL, @W1_PARAMS,
            @p_space_code = @w1_space_code,
            @p_probe_end = @w1_probe_end,
            @p_probe_start = @w1_probe_start;
        SET @run += 1;
    END;

    SET @run = 1;
    WHILE @run <= 5
    BEGIN
        PRINT CONCAT('BASE W2 run ', @run);
        EXEC sys.sp_executesql @W2_SQL, @W2_PARAMS,
            @p_capacity = @w2_capacity,
            @p_facility_1 = @w2_facility_1,
            @p_facility_2 = @w2_facility_2_effective,
            @p_start_time = @w2_start_time,
            @p_end_time = @w2_end_time;
        SET @run += 1;
    END;

    SET @run = 1;
    WHILE @run <= 5
    BEGIN
        PRINT CONCAT('BASE W3 run ', @run);
        EXEC sys.sp_executesql @W3_SQL, @W3_PARAMS,
            @p_semester_id = @semester_id;
        SET @run += 1;
    END;

    SET @run = 1;
    WHILE @run <= 5
    BEGIN
        PRINT CONCAT('BASE W4 run ', @run);
        EXEC sys.sp_executesql @W4_SQL, @W4_PARAMS,
            @p_semester_id = @semester_id;
        SET @run += 1;
    END;

    SET STATISTICS IO OFF;
    SET STATISTICS TIME OFF;

    /* Build/rebuild the exact candidate set. */
    IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.BOOKING')
          AND name = N'ix_booking_overlap_lock'
    )
        ALTER INDEX ix_booking_overlap_lock ON dbo.BOOKING REBUILD;
    ELSE
        CREATE INDEX ix_booking_overlap_lock
            ON dbo.BOOKING (
                space_code, booking_status,
                requested_start_time, requested_end_time
            );

    IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.BOOKING')
          AND name = N'ix_g09_booking_semester_reporting'
    )
        ALTER INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING REBUILD;
    ELSE
        CREATE INDEX ix_g09_booking_semester_reporting
            ON dbo.BOOKING (
                booking_status, requested_start_time, space_code
            )
            INCLUDE (requested_end_time);

    IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.MAINTENANCE_RECORD')
          AND name = N'ix_g09_maintenance_room_finder'
    )
        ALTER INDEX ix_g09_maintenance_room_finder
            ON dbo.MAINTENANCE_RECORD REBUILD;
    ELSE
        CREATE INDEX ix_g09_maintenance_room_finder
            ON dbo.MAINTENANCE_RECORD (
                space_code, impact_level, status, start_time
            )
            INCLUDE (completion_time);

    PRINT 'INDEXED CANDIDATE SET READY';

    /* INDEXED warm-up: same query variables and parameters. */
    PRINT 'INDEXED WARM-UP W1';
    EXEC sys.sp_executesql @W1_SQL, @W1_PARAMS,
        @p_space_code = @w1_space_code,
        @p_probe_end = @w1_probe_end,
        @p_probe_start = @w1_probe_start;
    PRINT 'INDEXED WARM-UP W2';
    EXEC sys.sp_executesql @W2_SQL, @W2_PARAMS,
        @p_capacity = @w2_capacity,
        @p_facility_1 = @w2_facility_1,
        @p_facility_2 = @w2_facility_2_effective,
        @p_start_time = @w2_start_time,
        @p_end_time = @w2_end_time;
    PRINT 'INDEXED WARM-UP W3';
    EXEC sys.sp_executesql @W3_SQL, @W3_PARAMS,
        @p_semester_id = @semester_id;
    PRINT 'INDEXED WARM-UP W4';
    EXEC sys.sp_executesql @W4_SQL, @W4_PARAMS,
        @p_semester_id = @semester_id;

    /* Representative INDEXED actual plans; excluded from five-run medians. */
    PRINT 'INDEXED ACTUAL PLAN CAPTURE W1-W4 (not a measured run)';
    SET STATISTICS XML ON;
    EXEC sys.sp_executesql @W1_SQL, @W1_PARAMS,
        @p_space_code = @w1_space_code,
        @p_probe_end = @w1_probe_end,
        @p_probe_start = @w1_probe_start;
    EXEC sys.sp_executesql @W2_SQL, @W2_PARAMS,
        @p_capacity = @w2_capacity,
        @p_facility_1 = @w2_facility_1,
        @p_facility_2 = @w2_facility_2_effective,
        @p_start_time = @w2_start_time,
        @p_end_time = @w2_end_time;
    EXEC sys.sp_executesql @W3_SQL, @W3_PARAMS,
        @p_semester_id = @semester_id;
    EXEC sys.sp_executesql @W4_SQL, @W4_PARAMS,
        @p_semester_id = @semester_id;
    SET STATISTICS XML OFF;

    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;

    SET @run = 1;
    WHILE @run <= 5
    BEGIN
        PRINT CONCAT('INDEXED W1 run ', @run);
        EXEC sys.sp_executesql @W1_SQL, @W1_PARAMS,
            @p_space_code = @w1_space_code,
            @p_probe_end = @w1_probe_end,
            @p_probe_start = @w1_probe_start;
        SET @run += 1;
    END;

    SET @run = 1;
    WHILE @run <= 5
    BEGIN
        PRINT CONCAT('INDEXED W2 run ', @run);
        EXEC sys.sp_executesql @W2_SQL, @W2_PARAMS,
            @p_capacity = @w2_capacity,
            @p_facility_1 = @w2_facility_1,
            @p_facility_2 = @w2_facility_2_effective,
            @p_start_time = @w2_start_time,
            @p_end_time = @w2_end_time;
        SET @run += 1;
    END;

    SET @run = 1;
    WHILE @run <= 5
    BEGIN
        PRINT CONCAT('INDEXED W3 run ', @run);
        EXEC sys.sp_executesql @W3_SQL, @W3_PARAMS,
            @p_semester_id = @semester_id;
        SET @run += 1;
    END;

    SET @run = 1;
    WHILE @run <= 5
    BEGIN
        PRINT CONCAT('INDEXED W4 run ', @run);
        EXEC sys.sp_executesql @W4_SQL, @W4_PARAMS,
            @p_semester_id = @semester_id;
        SET @run += 1;
    END;

    SET STATISTICS IO OFF;
    SET STATISTICS TIME OFF;

    /* Restore original candidate existence. */
    IF EXISTS (
        SELECT 1 FROM #OriginalIndexState
        WHERE object_id = OBJECT_ID(N'dbo.BOOKING')
          AND index_name = N'ix_booking_overlap_lock'
          AND originally_exists = 0
    )
        DROP INDEX ix_booking_overlap_lock ON dbo.BOOKING;

    IF EXISTS (
        SELECT 1 FROM #OriginalIndexState
        WHERE object_id = OBJECT_ID(N'dbo.BOOKING')
          AND index_name = N'ix_g09_booking_semester_reporting'
          AND originally_exists = 0
    )
        DROP INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING;

    IF EXISTS (
        SELECT 1 FROM #OriginalIndexState
        WHERE object_id = OBJECT_ID(N'dbo.MAINTENANCE_RECORD')
          AND index_name = N'ix_g09_maintenance_room_finder'
          AND originally_exists = 0
    )
        DROP INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD;

    /* Restore every originally existing performance index to its original
       enabled/disabled state. REBUILD re-enables a disabled index. */
    SET @ddl = N'';
    SELECT @ddl = @ddl
        + CASE WHEN O.originally_disabled = 1
            THEN N'ALTER INDEX ' + QUOTENAME(O.index_name)
                + N' ON ' + QUOTENAME(O.schema_name) + N'.' + QUOTENAME(O.table_name)
                + N' DISABLE;'
            ELSE N'ALTER INDEX ' + QUOTENAME(O.index_name)
                + N' ON ' + QUOTENAME(O.schema_name) + N'.' + QUOTENAME(O.table_name)
                + N' REBUILD;'
          END
        + CHAR(10)
    FROM #OriginalIndexState AS O
    WHERE O.originally_exists = 1
    ORDER BY O.table_name, O.index_name;

    IF @ddl <> N''
        EXEC sys.sp_executesql @stmt = @ddl;

    IF EXISTS (
        SELECT 1
        FROM #OriginalIndexState AS O
        LEFT JOIN sys.indexes AS I
          ON I.object_id = O.object_id
         AND I.name = O.index_name
        WHERE (O.originally_exists = 0 AND I.index_id IS NOT NULL)
           OR (O.originally_exists = 1 AND I.index_id IS NULL)
           OR (O.originally_exists = 1 AND I.is_disabled <> O.originally_disabled)
    )
        THROW 51000, 'Restoration verification failed before commit.', 1;

    COMMIT TRANSACTION;
    SET LOCK_TIMEOUT -1;

    /* Verify again after the restoration transaction commits. */
    IF EXISTS (
        SELECT 1
        FROM #OriginalIndexState AS O
        LEFT JOIN sys.indexes AS I
          ON I.object_id = O.object_id
         AND I.name = O.index_name
        WHERE (O.originally_exists = 0 AND I.index_id IS NOT NULL)
           OR (O.originally_exists = 1 AND I.index_id IS NULL)
           OR (O.originally_exists = 1 AND I.is_disabled <> O.originally_disabled)
    )
        THROW 51000, 'Restoration verification failed after commit.', 1;

    PRINT 'Benchmark complete.';
    PRINT 'Original index existence and enabled/disabled state verified.';
END TRY
BEGIN CATCH
    SET @original_error_number = ERROR_NUMBER();
    SET @original_error_message = ERROR_MESSAGE();

    SET STATISTICS XML OFF;
    SET STATISTICS IO OFF;
    SET STATISTICS TIME OFF;

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    SET LOCK_TIMEOUT -1;

    /* Rollback is the primary restoration mechanism. These idempotent actions
       are a second recovery pass and use the pre-transaction snapshot. */
    BEGIN TRY
        IF EXISTS (
            SELECT 1 FROM #OriginalIndexState
            WHERE object_id = OBJECT_ID(N'dbo.BOOKING')
              AND index_name = N'ix_booking_overlap_lock'
              AND originally_exists = 0
        )
        AND EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.BOOKING')
              AND name = N'ix_booking_overlap_lock'
        )
            DROP INDEX ix_booking_overlap_lock ON dbo.BOOKING;

        IF EXISTS (
            SELECT 1 FROM #OriginalIndexState
            WHERE object_id = OBJECT_ID(N'dbo.BOOKING')
              AND index_name = N'ix_g09_booking_semester_reporting'
              AND originally_exists = 0
        )
        AND EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.BOOKING')
              AND name = N'ix_g09_booking_semester_reporting'
        )
            DROP INDEX ix_g09_booking_semester_reporting ON dbo.BOOKING;

        IF EXISTS (
            SELECT 1 FROM #OriginalIndexState
            WHERE object_id = OBJECT_ID(N'dbo.MAINTENANCE_RECORD')
              AND index_name = N'ix_g09_maintenance_room_finder'
              AND originally_exists = 0
        )
        AND EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.MAINTENANCE_RECORD')
              AND name = N'ix_g09_maintenance_room_finder'
        )
            DROP INDEX ix_g09_maintenance_room_finder ON dbo.MAINTENANCE_RECORD;

        SET @ddl = N'';
        SELECT @ddl = @ddl
            + CASE WHEN O.originally_disabled = 1
                THEN N'IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = '
                    + CONVERT(NVARCHAR(20), O.object_id)
                    + N' AND name = N''' + REPLACE(O.index_name, '''', '''''')
                    + N''' AND is_disabled = 0) ALTER INDEX '
                    + QUOTENAME(O.index_name) + N' ON '
                    + QUOTENAME(O.schema_name) + N'.' + QUOTENAME(O.table_name)
                    + N' DISABLE;'
                ELSE N'IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = '
                    + CONVERT(NVARCHAR(20), O.object_id)
                    + N' AND name = N''' + REPLACE(O.index_name, '''', '''''')
                    + N''' AND is_disabled = 1) ALTER INDEX '
                    + QUOTENAME(O.index_name) + N' ON '
                    + QUOTENAME(O.schema_name) + N'.' + QUOTENAME(O.table_name)
                    + N' REBUILD;'
              END
            + CHAR(10)
        FROM #OriginalIndexState AS O
        WHERE O.originally_exists = 1
        ORDER BY O.table_name, O.index_name;

        IF @ddl <> N''
            EXEC sys.sp_executesql @stmt = @ddl;

        IF EXISTS (
            SELECT 1
            FROM #OriginalIndexState AS O
            LEFT JOIN sys.indexes AS I
              ON I.object_id = O.object_id
             AND I.name = O.index_name
            WHERE (O.originally_exists = 0 AND I.index_id IS NOT NULL)
               OR (O.originally_exists = 1 AND I.index_id IS NULL)
               OR (O.originally_exists = 1 AND I.is_disabled <> O.originally_disabled)
        )
            PRINT 'WARNING: failure-path restoration could not be fully verified.';
        ELSE
            PRINT 'Failure-path restoration verified.';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('WARNING: secondary restoration error: ', ERROR_MESSAGE());
    END CATCH;

    PRINT CONCAT('Benchmark failed with SQL Server error ', @original_error_number,
                 ': ', @original_error_message);
    THROW;
END CATCH;
