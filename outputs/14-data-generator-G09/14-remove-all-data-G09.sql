-- ============================================================================
-- Remove ALL data from the Campus Space Management System
-- File: 14-remove-all-data-G09.sql
-- Description: Deletes every row from every table (in FK-safe order) and
-- reseeds the IDENTITY columns so the database returns to the empty,
-- post-migration state. The schema itself is NOT dropped.
-- Run ONLY when you intend to wipe the whole database (sample + generated).
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

-- ----------------------------------------------------------------------------
-- 1. DELETE leaf tables first (respect FK chain)
--    child -> parent order:
--    ACKNOWLEDGEMENT -> BOOKING, MAINTENANCE_RECORD
--    ROLE_USAGE_POLICY -> ROLE, USAGE_POLICY
--    DEPARTMENT_USAGE_POLICY -> DEPARTMENT, USAGE_POLICY
--    SPACE_FACILITY -> SPACE, FACILITY
--    BOOKING -> USER, SPACE
--    MAINTENANCE_RECORD -> USER, SPACE
--    USER -> ROLE, DEPARTMENT
--    SPACE -> USAGE_POLICY
-- ----------------------------------------------------------------------------
DELETE FROM dbo.ACKNOWLEDGEMENT;
DELETE FROM dbo.ROLE_USAGE_POLICY;
IF OBJECT_ID('dbo.DEPARTMENT_USAGE_POLICY', 'U') IS NOT NULL
    EXEC ('DELETE FROM dbo.DEPARTMENT_USAGE_POLICY;');
DELETE FROM dbo.SPACE_FACILITY;
DELETE FROM dbo.BOOKING;
DELETE FROM dbo.MAINTENANCE_RECORD;
DELETE FROM dbo.[USER];
IF OBJECT_ID('dbo.gen_user_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_user_marker;
IF OBJECT_ID('dbo.gen_policy_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_policy_marker;
IF OBJECT_ID('dbo.gen_space_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_space_marker;
IF OBJECT_ID('dbo.gen_facility_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_facility_marker;
IF OBJECT_ID('dbo.gen_maintenance_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_maintenance_marker;
DELETE FROM dbo.SPACE;
DELETE FROM dbo.USAGE_POLICY;
DELETE FROM dbo.FACILITY;
DELETE FROM dbo.ROLE;
IF OBJECT_ID('dbo.DEPARTMENT', 'U') IS NOT NULL
    EXEC ('DELETE FROM dbo.DEPARTMENT;');
IF OBJECT_ID('dbo.SEMESTER', 'U') IS NOT NULL
    EXEC ('DELETE FROM dbo.SEMESTER;');

-- ----------------------------------------------------------------------------
-- 2. Reseed IDENTITY columns so the next inserts start from 1
-- ----------------------------------------------------------------------------
DBCC CHECKIDENT (ROLE, RESEED, 0);
IF OBJECT_ID('dbo.DEPARTMENT', 'U') IS NOT NULL
    DBCC CHECKIDENT ('dbo.DEPARTMENT', RESEED, 0);
IF OBJECT_ID('dbo.SEMESTER', 'U') IS NOT NULL
    DBCC CHECKIDENT ('dbo.SEMESTER', RESEED, 0);
DBCC CHECKIDENT (USAGE_POLICY, RESEED, 0);
DBCC CHECKIDENT ([USER], RESEED, 0);
DBCC CHECKIDENT (FACILITY, RESEED, 0);
DBCC CHECKIDENT (BOOKING, RESEED, 0);
DBCC CHECKIDENT (MAINTENANCE_RECORD, RESEED, 0);

COMMIT TRANSACTION;

-- ----------------------------------------------------------------------------
-- 3. Verify the wipe
-- ----------------------------------------------------------------------------
CREATE TABLE #wipe_verification (
    tbl VARCHAR(100) NOT NULL,
    rows_now BIGINT NOT NULL
);

INSERT INTO #wipe_verification (tbl, rows_now)
SELECT 'ROLE'               AS tbl, COUNT_BIG(*) AS rows_now FROM dbo.ROLE
UNION ALL SELECT 'USAGE_POLICY'    , COUNT_BIG(*) FROM dbo.USAGE_POLICY
UNION ALL SELECT 'USER'            , COUNT_BIG(*) FROM dbo.[USER]
UNION ALL SELECT 'SPACE'           , COUNT_BIG(*) FROM dbo.SPACE
UNION ALL SELECT 'FACILITY'        , COUNT_BIG(*) FROM dbo.FACILITY
UNION ALL SELECT 'BOOKING'         , COUNT_BIG(*) FROM dbo.BOOKING
UNION ALL SELECT 'MAINTENANCE_RECORD', COUNT_BIG(*) FROM dbo.MAINTENANCE_RECORD
UNION ALL SELECT 'SPACE_FACILITY'  , COUNT_BIG(*) FROM dbo.SPACE_FACILITY
UNION ALL SELECT 'ROLE_USAGE_POLICY', COUNT_BIG(*) FROM dbo.ROLE_USAGE_POLICY
UNION ALL SELECT 'ACKNOWLEDGEMENT' , COUNT_BIG(*) FROM dbo.ACKNOWLEDGEMENT;

IF OBJECT_ID('dbo.DEPARTMENT_USAGE_POLICY', 'U') IS NOT NULL
    INSERT INTO #wipe_verification
    EXEC ('SELECT ''DEPARTMENT_USAGE_POLICY'', COUNT_BIG(*) FROM dbo.DEPARTMENT_USAGE_POLICY;');

IF OBJECT_ID('dbo.DEPARTMENT', 'U') IS NOT NULL
    INSERT INTO #wipe_verification
    EXEC ('SELECT ''DEPARTMENT'', COUNT_BIG(*) FROM dbo.DEPARTMENT;');

IF OBJECT_ID('dbo.SEMESTER', 'U') IS NOT NULL
    INSERT INTO #wipe_verification
    EXEC ('SELECT ''SEMESTER'', COUNT_BIG(*) FROM dbo.SEMESTER;');

SELECT tbl, rows_now
FROM #wipe_verification
ORDER BY tbl;

DROP TABLE #wipe_verification;

PRINT 'All data removed. Database is back to the empty post-migration state.';
