-- ============================================================================
-- Index benchmark queries — Campus Space Management System (G09)
-- File: outputs/14-index-benchmark-G09.sql
-- Purpose: Measure the analytical queries from
--          outputs/16-analytical-queries-G09.sql against the high-volume
--          dataset (outputs/13-high-volume-sample-data-G09.sql) BEFORE and
--          AFTER candidate index creation. Logs logical reads, elapsed time
--          and caching state to outputs/stats.
-- Usage:   sqlcmd -b -i outputs/14-index-benchmark-G09.sql
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

-- Stage control: run with `sqlcmd -b -i outputs/14-index-benchmark-G09.sql
-- -v IndexStage=INDEXED` to create the candidate indexes first and benchmark
-- the indexed schema. Without the variable the benchmark runs on the
-- base (unindexed) schema.
-- Usage:
--   BASE:    sqlcmd -b -i outputs/14-index-benchmark-G09.sql
--   INDEXED: sqlcmd -b -i outputs/14-index-benchmark-G09.sql -v IndexStage=INDEXED

SET NOCOUNT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

IF '$(IndexStage)' = 'BASE'
BEGIN
    PRINT 'Dropping candidate indexes for BASE stage...';
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_booking_space_time')
        DROP INDEX ix_booking_space_time ON dbo.BOOKING;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_booking_status_start')
        DROP INDEX ix_booking_status_start ON dbo.BOOKING;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_booking_requester')
        DROP INDEX ix_booking_requester ON dbo.BOOKING;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_maintenance_space_status')
        DROP INDEX ix_maintenance_space_status ON dbo.MAINTENANCE_RECORD;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_acknowledgement_maintenance')
        DROP INDEX ix_acknowledgement_maintenance ON dbo.ACKNOWLEDGEMENT;
END;

IF '$(IndexStage)' = 'INDEXED'
BEGIN
    PRINT 'Creating candidate indexes for INDEXED stage...';

    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE name = 'ix_booking_space_time')
        CREATE INDEX ix_booking_space_time
        ON dbo.BOOKING (space_code, requested_start_time, requested_end_time)
        INCLUDE (booking_status);

    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE name = 'ix_booking_status_start')
        CREATE INDEX ix_booking_status_start
        ON dbo.BOOKING (booking_status, requested_start_time)
        INCLUDE (actual_start_time, actual_end_time, requested_end_time);

    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE name = 'ix_booking_requester')
        CREATE INDEX ix_booking_requester
        ON dbo.BOOKING (requester_id)
        INCLUDE (booking_id, booking_status);

    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE name = 'ix_maintenance_space_status')
        CREATE INDEX ix_maintenance_space_status
        ON dbo.MAINTENANCE_RECORD (space_code, status, impact_level)
        INCLUDE (start_time, completion_time);

    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE name = 'ix_acknowledgement_maintenance')
        CREATE INDEX ix_acknowledgement_maintenance
        ON dbo.ACKNOWLEDGEMENT (maintenance_id)
        INCLUDE (booking_id);
END;
GO

DECLARE @Stage VARCHAR(50) = '$(IndexStage)';
DECLARE @RunId INT;
IF OBJECT_ID('dbo.bench_run') IS NULL
BEGIN
    CREATE TABLE dbo.bench_run (
        run_id INT IDENTITY(1,1) PRIMARY KEY,
        stage VARCHAR(50) NOT NULL,
        started_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );

    CREATE TABLE dbo.bench_metric (
        run_id INT NOT NULL REFERENCES dbo.bench_run(run_id),
        q_number INT NOT NULL,
        logical_reads_big BIGINT NOT NULL,
        elapsed_ms INT NOT NULL,
        PRIMARY KEY (run_id, q_number)
    );

    CREATE TABLE dbo.bench_detail (
        run_id INT NOT NULL REFERENCES dbo.bench_run(run_id),
        seq INT NOT NULL,
        msg VARCHAR(4000) NOT NULL,
        PRIMARY KEY (run_id, seq)
    );
END;
GO

DECLARE @RunId INT;
DECLARE @Stage VARCHAR(50) = CASE WHEN '$(IndexStage)' = '' THEN 'BASE' ELSE '$(IndexStage)' END;
INSERT INTO dbo.bench_run (stage) VALUES (@Stage);
SET @RunId = SCOPE_IDENTITY();
PRINT 'benchmark stage=' + @Stage + ' run_id=' + CAST(@RunId AS VARCHAR(10));
GO

DECLARE @RunId INT = (SELECT MAX(run_id) FROM dbo.bench_run);
DECLARE @q INT, @ms BIGINT, @reads BIGINT, @seq INT = 0;

CREATE TABLE #queries (q_number INT, sql_text NVARCHAR(MAX));
INSERT INTO #queries (q_number, sql_text) VALUES
-- Q1: bookings per building per year
(1, N'
SELECT s.building, YEAR(b.requested_start_time) AS yr, COUNT_BIG(*) AS booking_count
FROM dbo.BOOKING b
JOIN dbo.SPACE s ON s.space_code = b.space_code
GROUP BY s.building, YEAR(b.requested_start_time);
--BENCHMARK_Q1'),
-- Q2: space utilisation ratio (actual duration vs requested)
(2, N'
SELECT b.space_code,
       SUM(DATEDIFF(MINUTE, b.requested_start_time, b.requested_end_time)) AS requested_min,
       SUM(CASE WHEN b.actual_end_time IS NOT NULL AND b.actual_start_time IS NOT NULL
                THEN DATEDIFF(MINUTE, b.actual_start_time, b.actual_end_time) ELSE 0 END) AS actual_min
FROM dbo.BOOKING b
WHERE b.booking_status IN (''completed'',''checked_in'',''no_show'')
GROUP BY b.space_code;
--BENCHMARK_Q2'),
-- Q3: pending approvals older than 3 days (staff dashboard)
(3, N'
SELECT b.booking_id, b.space_code, b.requested_start_time, b.requested_end_time,
       u.full_name AS requester
FROM dbo.BOOKING b
JOIN dbo.[USER] u ON u.user_id = b.requester_id
WHERE b.booking_status = ''pending''
  AND b.requested_start_time < DATEADD(DAY, 3, SYSDATETIME());
--BENCHMARK_Q3'),
-- Q4: top-10 most heavily used spaces
(4, N'
SELECT TOP 10 b.space_code, s.building, s.room_number, COUNT_BIG(*) AS usage_count
FROM dbo.BOOKING b
JOIN dbo.SPACE s ON s.space_code = b.space_code
GROUP BY b.space_code, s.building, s.room_number
ORDER BY usage_count DESC;
--BENCHMARK_Q4'),
-- Q5: maintenance impact summary by impact level / status
(5, N'
SELECT m.impact_level, m.status, COUNT_BIG(*) AS maintenance_count
FROM dbo.MAINTENANCE_RECORD m
GROUP BY m.impact_level, m.status;
--BENCHMARK_Q5'),
-- Q6: users with booking history (join on generated users)
(6, N'
SELECT u.user_id, u.full_name, COUNT_BIG(b.booking_id) AS booking_total
FROM dbo.[USER] u
LEFT JOIN dbo.BOOKING b ON b.requester_id = u.user_id
WHERE u.email LIKE ''gen-%@campus.example''
GROUP BY u.user_id, u.full_name
ORDER BY booking_total DESC;
--BENCHMARK_Q6'),
-- Q7: advisory maintenance with their acknowledgement counts
(7, N'
SELECT m.maintenance_id, m.space_code, COUNT_BIG(a.booking_id) AS ack_count
FROM dbo.MAINTENANCE_RECORD m
LEFT JOIN dbo.ACKNOWLEDGEMENT a ON a.maintenance_id = m.maintenance_id
WHERE m.impact_level = ''advisory''
GROUP BY m.maintenance_id, m.space_code;
--BENCHMARK_Q7');

DECLARE @sql NVARCHAR(MAX);

DECLARE qc CURSOR FOR
SELECT q_number AS q, sql_text FROM #queries ORDER BY q_number;

OPEN qc;
FETCH NEXT FROM qc INTO @q, @sql;
SET @seq = 0;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET STATISTICS IO OFF;
        -- warm-up execution (ensures the plan is compiled and cached)
        EXEC sys.sp_executesql @stmt = @sql;

        -- capture the plan handle for this query text (newest plan)
        DECLARE @ph VARBINARY(64);
        SELECT TOP 1 @ph = qs.plan_handle
            FROM sys.dm_exec_query_stats qs
            CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) t
            WHERE t.text LIKE '%BENCHMARK_Q' + CAST(@q AS VARCHAR(10)) + '%'
            ORDER BY qs.last_execution_time DESC;

        DECLARE @reads_before BIGINT = ISNULL((SELECT total_logical_reads
            FROM sys.dm_exec_query_stats WHERE plan_handle = @ph), 0);

        DECLARE @tm1 DATETIME2 = SYSDATETIME();
        EXEC sys.sp_executesql @stmt = @sql;
        DECLARE @tm2 DATETIME2 = SYSDATETIME();
        SET @ms = DATEDIFF(MILLISECOND, @tm1, @tm2);

        -- delta of the same plan's cumulative counter
        SET @reads = ISNULL((SELECT total_logical_reads
            FROM sys.dm_exec_query_stats WHERE plan_handle = @ph), 0) - @reads_before;

        INSERT INTO dbo.bench_metric (run_id, q_number, logical_reads_big, elapsed_ms)
        VALUES (@RunId, @q, ISNULL(@reads, 0), @ms);

        SET @seq = @seq + 1;
        INSERT INTO dbo.bench_detail (run_id, seq, msg)
        VALUES (@RunId, @seq, 'Q' + CAST(@q AS VARCHAR(3)) + ' done');
    END TRY
    BEGIN CATCH
        SET STATISTICS IO OFF;
        INSERT INTO dbo.bench_detail (run_id, seq, msg)
        VALUES (@RunId, @seq, 'ERROR: ' + ERROR_MESSAGE());
    END CATCH;

    SET NOCOUNT ON; -- restore if a query toggled it
    FETCH NEXT FROM qc INTO @q, @sql;
END;

CLOSE qc;
DEALLOCATE qc;
GO