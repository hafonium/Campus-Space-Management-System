-- ============================================================================
-- High-volume Sample Data Generation — Campus Space Management System (G09)
-- File: outputs/14-data-generator-G09/high-volume-sample-data-G09.sql
-- Target: Microsoft SQL Server 2022 (T-SQL), Phase 2 schema
--          (run after 05-db-definition-G09.sql, 06-sample-data-G09.sql and
--           10-schema-migration-G09.sql)
--
-- Generates a deterministic high-volume dataset:
--   - 100,000 bookings by default (range 100,000 .. 500,000)
--   - 5,000 users, at least 120 spaces, and 12 facilities
--   - four maintenance records per generated space
--   - at least three complete academic years
--   - two realistic SEMESTER rows per academic year (SEMESTER remains
--     intentionally independent of BOOKING)
--   - maintenance records (advisory and out-of-service)
--   - cancellations, no-shows, rejections, completions, check-ins
--   - advisory acknowledgements for every overlapping booking
--
-- Determinism: the same parameters produce the same logical dataset. All
-- indices are derived arithmetically from digit-based number tables (no
-- ROW_NUMBER over unordered rows), and user/staff ids are resolved through
-- explicit id maps instead of relying on IDENTITY allocation order.
--   All user-facing values follow the English Waterloo-style sample dataset:
--   English names and departments, +1-519 phone numbers, @uwaterloo.ca
--   addresses, familiar campus buildings, facilities, policies, and notes.
--   Nothing carries marker text; generated rows are tracked in persistent
--   dbo.gen_*_marker tables (PK/identity-based) so re-runs can clean up.
--   User emails use firstname.lastname####@uwaterloo.ca, where the numeric
--   suffix makes every deterministic high-volume address unique.
-- Rerunnable: cleanup deletes only previously generated rows; the
--   hand-written demonstration rows from 06-sample-data-G09.sql are kept.
--
-- NOTE: after the schema preflight, the generation body runs as a single batch
-- so that parameters declared at the top stay in scope.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

-- Fail before SQL Server compiles references in the generator body when the
-- revised Phase 2 migration has not yet been applied to this database.
IF OBJECT_ID('dbo.DEPARTMENT', 'U') IS NULL
   OR OBJECT_ID('dbo.SEMESTER', 'U') IS NULL
   OR OBJECT_ID('dbo.DEPARTMENT_USAGE_POLICY', 'U') IS NULL
   OR COL_LENGTH('dbo.USER', 'department_id') IS NULL
   OR COL_LENGTH('dbo.FACILITY', 'space_code') IS NULL
   OR COL_LENGTH('dbo.ACKNOWLEDGEMENT', 'maintenance_record_id') IS NULL
   OR OBJECT_ID('dbo.SPACE_FACILITY', 'U') IS NOT NULL
   OR COL_LENGTH('dbo.USAGE_POLICY', 'department_allowed') IS NOT NULL
BEGIN
    ;THROW 53003,
        'Schema is not current. Run outputs/10-schema-migration-G09.sql before the high-volume data generator.',
        1;
END;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET DATEFIRST 1;

-- ============================================================================
-- 0. GENERATION PARAMETERS
-- ============================================================================
DECLARE @BookingCount INT        = 100000;  -- valid range 100000 .. 500000
DECLARE @Seed INT                = 9009;    -- deterministic seed
DECLARE @FirstAcademicYear INT   = 2023;    -- academic year start (Sep 1)
DECLARE @AcademicYearCount INT   = 3;       -- minimum 3 complete academic years
DECLARE @BatchSize INT           = 25000;   -- bulk-insert batch size
DECLARE @CalendarTailDays INT    = 21;      -- schedule buffer past the last AY end
DECLARE @KeepMarkerTables BIT    = 1;       -- 1 = safely rerunnable; 0 = drop tracking tables after success

IF @BookingCount < 100000 OR @BookingCount > 500000
    THROW 53000, 'BookingCount must be between 100000 and 500000.', 1;
IF @AcademicYearCount < 3
    THROW 53001, 'AcademicYearCount must be at least 3.', 1;
IF @BatchSize < 10000
    THROW 53002, 'BatchSize must be at least 10000.', 1;

-- ============================================================================
-- 1. CLEANUP — delete only previously generated rows.
--    Realistic values cannot carry marker text, so every generated row is
--    tracked by dbo.gen_*_marker tables (persistent, driven by PK/identity).
--    Cleanup always follows child -> parent order.
-- ============================================================================
PRINT 'Step 1: cleanup of previously generated rows';

IF OBJECT_ID('dbo.gen_user_marker', 'U') IS NULL
    EXEC ('CREATE TABLE dbo.gen_user_marker (user_id INT NOT NULL PRIMARY KEY)');
IF OBJECT_ID('dbo.gen_policy_marker', 'U') IS NULL
    EXEC ('CREATE TABLE dbo.gen_policy_marker (policy_id INT NOT NULL PRIMARY KEY)');
IF OBJECT_ID('dbo.gen_space_marker', 'U') IS NULL
    EXEC ('CREATE TABLE dbo.gen_space_marker (space_code VARCHAR(50) NOT NULL PRIMARY KEY)');
IF OBJECT_ID('dbo.gen_facility_marker', 'U') IS NULL
    EXEC ('CREATE TABLE dbo.gen_facility_marker (facility_id INT NOT NULL PRIMARY KEY)');
IF OBJECT_ID('dbo.gen_maintenance_marker', 'U') IS NULL
    EXEC ('CREATE TABLE dbo.gen_maintenance_marker (maintenance_id INT NOT NULL PRIMARY KEY)');

-- 1a. ACKNOWLEDGEMENT (children of generated bookings / maintenance)
DELETE a
FROM dbo.ACKNOWLEDGEMENT a
WHERE EXISTS (SELECT 1 FROM dbo.BOOKING b
              WHERE b.booking_id = a.booking_id
                AND b.requester_id IN (SELECT user_id FROM dbo.gen_user_marker))
   OR EXISTS (SELECT 1 FROM dbo.MAINTENANCE_RECORD m
              WHERE m.maintenance_id = a.maintenance_record_id
                AND m.maintenance_id IN (SELECT maintenance_id FROM dbo.gen_maintenance_marker));

-- 1b. ROLE_USAGE_POLICY linked to generated policies
DELETE rp
FROM dbo.ROLE_USAGE_POLICY rp
WHERE rp.policy_id IN (SELECT policy_id FROM dbo.gen_policy_marker);

-- 1c. DEPARTMENT_USAGE_POLICY linked to generated policies
DELETE dp
FROM dbo.DEPARTMENT_USAGE_POLICY dp
WHERE dp.policy_id IN (SELECT policy_id FROM dbo.gen_policy_marker);

-- 1d. maintenance first, then bookings
DELETE FROM dbo.MAINTENANCE_RECORD
WHERE maintenance_id IN (SELECT maintenance_id FROM dbo.gen_maintenance_marker);

DELETE b
FROM dbo.BOOKING b
WHERE b.requester_id IN (SELECT user_id FROM dbo.gen_user_marker)
   OR b.space_code IN (SELECT space_code FROM dbo.gen_space_marker);

-- 1e. parent rows. Delete facilities before their parent spaces; the migrated
-- schema stores the relationship directly in nullable FACILITY.space_code.
DELETE FROM dbo.FACILITY WHERE facility_id IN (SELECT facility_id FROM dbo.gen_facility_marker);
DELETE FROM dbo.SPACE WHERE space_code IN (SELECT space_code FROM dbo.gen_space_marker);
DELETE FROM dbo.[USER] WHERE user_id IN (SELECT user_id FROM dbo.gen_user_marker);
DELETE FROM dbo.USAGE_POLICY WHERE policy_id IN (SELECT policy_id FROM dbo.gen_policy_marker);

-- clear the markers for the new run
DELETE FROM dbo.gen_user_marker;
DELETE FROM dbo.gen_policy_marker;
DELETE FROM dbo.gen_space_marker;
DELETE FROM dbo.gen_facility_marker;
DELETE FROM dbo.gen_maintenance_marker;

-- ============================================================================
-- 2. DETERMINISTIC SCHEDULING CALENDAR
-- ============================================================================
PRINT 'Step 2: scheduling calendar';

DECLARE @AYStart DATETIME2 = DATEFROMPARTS(@FirstAcademicYear, 9, 1);
DECLARE @AYEnd   DATETIME2 = DATEFROMPARTS(@FirstAcademicYear + @AcademicYearCount, 9, 1);
DECLARE @CalStart DATETIME2 = @AYStart;
DECLARE @CalEnd   DATETIME2 = DATEADD(DAY, @CalendarTailDays, @AYEnd);
DECLARE @TotalDays INT = DATEDIFF(DAY, @CalStart, @CalEnd);
DECLARE @WPY0 INT, @WPY1 INT, @WPY2 INT;

-- Weekday ordinal list (Mon-Fri) and Saturday ordinal list
IF OBJECT_ID('tempdb..#weekdays') IS NOT NULL DROP TABLE #weekdays;
CREATE TABLE #weekdays (wd_ord INT NOT NULL PRIMARY KEY, wd_date DATE NOT NULL);

IF OBJECT_ID('tempdb..#saturdays') IS NOT NULL DROP TABLE #saturdays;
CREATE TABLE #saturdays (sa_ord INT NOT NULL PRIMARY KEY, sa_date DATE NOT NULL);

WITH DAYS(d) AS (
    SELECT TOP (@TotalDays) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
    FROM (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
          UNION ALL SELECT 9 UNION ALL SELECT 10) d1
    CROSS JOIN (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
                UNION ALL SELECT 9 UNION ALL SELECT 10) d2
    CROSS JOIN (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
                UNION ALL SELECT 9 UNION ALL SELECT 10) d3
    CROSS JOIN (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
                UNION ALL SELECT 9 UNION ALL SELECT 10) d4
),
CAL(dt) AS (SELECT DATEADD(DAY, d, @CalStart) FROM DAYS)
INSERT INTO #weekdays (wd_ord, wd_date)
SELECT ROW_NUMBER() OVER (ORDER BY dt) - 1, dt
FROM CAL
WHERE DATEPART(WEEKDAY, dt) BETWEEN 1 AND 5;

WITH DAYS(d) AS (
    SELECT TOP (@TotalDays) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
    FROM (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
          UNION ALL SELECT 9 UNION ALL SELECT 10) d1
    CROSS JOIN (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
                UNION ALL SELECT 9 UNION ALL SELECT 10) d2
    CROSS JOIN (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
                UNION ALL SELECT 9 UNION ALL SELECT 10) d3
    CROSS JOIN (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
                UNION ALL SELECT 9 UNION ALL SELECT 10) d4
),
CAL(dt) AS (SELECT DATEADD(DAY, d, @CalStart) FROM DAYS)
INSERT INTO #saturdays (sa_ord, sa_date)
SELECT ROW_NUMBER() OVER (ORDER BY dt) - 1, dt
FROM CAL
WHERE DATEPART(WEEKDAY, dt) = 6;

SELECT @WPY0 = COUNT(*) FROM #weekdays WHERE wd_date < DATEADD(YEAR, 1, @AYStart);
SELECT @WPY1 = COUNT(*) FROM #weekdays
WHERE wd_date >= DATEADD(YEAR, 1, @AYStart) AND wd_date < DATEADD(YEAR, 2, @AYStart);
SELECT @WPY2 = COUNT(*) FROM #weekdays
WHERE wd_date >= DATEADD(YEAR, 2, @AYStart);

DECLARE @WeekdayCount INT = (SELECT COUNT(*) FROM #weekdays);
DECLARE @SaturdayCount INT = (SELECT COUNT(*) FROM #saturdays);

-- Space count: enough slots so every space spans the full calendar.
-- 6 slots per weekday (08:00-10:00 ... 18:00-20:00), non-overlapping.
DECLARE @SpaceCount INT = CASE
    WHEN @BookingCount / (@WeekdayCount * 6.0) <= 120 THEN 120
    ELSE CEILING(@BookingCount / (@WeekdayCount * 6.0))
END;
DECLARE @UserCount INT = 5000;
DECLARE @PolicyCount INT = 12;
DECLARE @FacilityCount INT = 12;
DECLARE @StaffCount INT = 60;       -- facility_staff band: user_idx 0..59
DECLARE @ManagerCount INT = 40;     -- facility_manager band: user_idx 60..99

PRINT '  Calendar: ' + CONVERT(VARCHAR(10), @CalStart) + ' .. '
    + CONVERT(VARCHAR(10), @CalEnd) + '  weekdays=' + CAST(@WeekdayCount AS VARCHAR(10))
    + '  spaces=' + CAST(@SpaceCount AS VARCHAR(10));

-- Two teaching semesters per academic year. These rows describe the academic
-- calendar but are deliberately not linked to individual bookings.
IF OBJECT_ID('tempdb..#gen_semester') IS NOT NULL DROP TABLE #gen_semester;
CREATE TABLE #gen_semester (
    semester_name VARCHAR(100) NOT NULL PRIMARY KEY,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL
);

WITH AY(n) AS (
    SELECT 0
    UNION ALL
    SELECT n + 1 FROM AY WHERE n + 1 < @AcademicYearCount
)
INSERT INTO #gen_semester (semester_name, start_date, end_date)
SELECT 'Fall ' + CAST(@FirstAcademicYear + n AS VARCHAR(4)) + '-'
       + CAST(@FirstAcademicYear + n + 1 AS VARCHAR(4)),
       DATEFROMPARTS(@FirstAcademicYear + n, 9, 1),
       DATEFROMPARTS(@FirstAcademicYear + n + 1, 1, 15)
FROM AY
UNION ALL
SELECT 'Winter ' + CAST(@FirstAcademicYear + n + 1 AS VARCHAR(4)) + '-'
       + CAST(@FirstAcademicYear + n + 1 AS VARCHAR(4)),
       DATEFROMPARTS(@FirstAcademicYear + n + 1, 2, 15),
       DATEFROMPARTS(@FirstAcademicYear + n + 1, 6, 30)
FROM AY
OPTION (MAXRECURSION 0);

UPDATE s
SET s.start_date = g.start_date,
    s.end_date = g.end_date
FROM dbo.SEMESTER s
JOIN #gen_semester g ON g.semester_name = s.semester_name;

INSERT INTO dbo.SEMESTER (semester_name, start_date, end_date)
SELECT g.semester_name, g.start_date, g.end_date
FROM #gen_semester g
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SEMESTER s WHERE s.semester_name = g.semester_name
);

DECLARE @GeneratedSemesterCount INT;
SELECT @GeneratedSemesterCount = COUNT(*) FROM #gen_semester;
PRINT '  semesters ensured: ' + CAST(@GeneratedSemesterCount AS VARCHAR(10));

-- ============================================================================
-- 3. PARENT TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 USAGE_POLICY
-- ----------------------------------------------------------------------------
PRINT 'Step 3.1: usage policies';

IF OBJECT_ID('dbo.stg_gen_policy', 'U') IS NOT NULL DROP TABLE dbo.stg_gen_policy;
CREATE TABLE dbo.stg_gen_policy (
    policy_idx INT NOT NULL,
    policy_name VARCHAR(255) NOT NULL,
    max_duration_minutes INT NULL,
    requires_business_hours BIT NULL,
    legacy_policy_text VARCHAR(MAX) NULL
);

WITH NUMS(n) AS (
    SELECT d1.v*1000 + d2.v*100 + d3.v*10 + d4.v
    FROM (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
          UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
          UNION ALL SELECT 8 UNION ALL SELECT 9) d1
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d2
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d3
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d4
)
INSERT INTO dbo.stg_gen_policy
SELECT n,
       CASE n % 12
           WHEN 0 THEN 'Standard Room Booking Policy'
           WHEN 1 THEN 'Business Hours Access Policy'
           WHEN 2 THEN 'After-Hours Access Policy'
           WHEN 3 THEN 'Weekend Space Use Policy'
           WHEN 4 THEN 'Lecture Hall Use Policy'
           WHEN 5 THEN 'Computer Lab Use Policy'
           WHEN 6 THEN 'Project Lab Safety Policy'
           WHEN 7 THEN 'Meeting Room Use Policy'
           WHEN 8 THEN 'Seminar and Event Policy'
           WHEN 9 THEN 'Student Activity Policy'
           WHEN 10 THEN 'Group Study Policy'
           ELSE 'Examination Room Policy' END,
       120 + ((n * 47) % 180),
       CASE WHEN n % 2 = 0 THEN 1 ELSE 0 END,
       NULL
FROM NUMS
WHERE n < @PolicyCount;

INSERT INTO dbo.USAGE_POLICY (policy_name, max_duration_minutes,
                              requires_business_hours, legacy_policy_text)
SELECT policy_name, max_duration_minutes, requires_business_hours,
       legacy_policy_text
FROM dbo.stg_gen_policy;

-- Track the generated policies for the next cleanup run.
INSERT INTO dbo.gen_policy_marker (policy_id)
SELECT pol.policy_id
FROM dbo.USAGE_POLICY pol
JOIN dbo.stg_gen_policy s ON s.policy_name = pol.policy_name;

-- ----------------------------------------------------------------------------
-- 3.2 ROLE_USAGE_POLICY (deterministic links)
-- ----------------------------------------------------------------------------
PRINT 'Step 3.2: role-usage-policy links';

-- Ensure the six standard roles exist (idempotent; they are normally
-- back-filled from dbo.[USER] by 10-schema-migration-G09.sql, but the
-- generator must not depend on that having run).
INSERT INTO dbo.ROLE (role_name)
SELECT v.role_name
FROM (VALUES ('student'), ('lecturer'), ('teaching_assistant'),
             ('department_administrator'), ('facility_staff'),
             ('facility_manager')) v(role_name)
WHERE NOT EXISTS (SELECT 1 FROM dbo.ROLE r WHERE r.role_name = v.role_name);

DECLARE @RoleStudent INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'student');
DECLARE @RoleLecturer INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'lecturer');
DECLARE @RoleTA INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'teaching_assistant');
DECLARE @RoleAdmin INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'department_administrator');
DECLARE @RoleStaff INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'facility_staff');
DECLARE @RoleManager INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'facility_manager');

INSERT INTO dbo.ROLE_USAGE_POLICY (role_id, policy_id)
SELECT CASE p.policy_idx % 3
           WHEN 0 THEN @RoleStudent
           WHEN 1 THEN @RoleLecturer
           ELSE @RoleTA END,
       pol.policy_id
FROM dbo.stg_gen_policy p
JOIN dbo.USAGE_POLICY pol ON pol.policy_name = p.policy_name
WHERE p.policy_idx % 2 = 1;

-- ----------------------------------------------------------------------------
-- 3.3 SPACE
-- ----------------------------------------------------------------------------
PRINT 'Step 3.3: spaces';

IF OBJECT_ID('dbo.stg_gen_space', 'U') IS NOT NULL DROP TABLE dbo.stg_gen_space;
CREATE TABLE dbo.stg_gen_space (
    space_idx INT NOT NULL,
    space_code VARCHAR(50) NOT NULL,
    space_name VARCHAR(255) NOT NULL,
    space_type VARCHAR(50) NOT NULL,
    building VARCHAR(255) NOT NULL,
    floor INT NOT NULL,
    room_number VARCHAR(20) NOT NULL,
    capacity INT NOT NULL,
    current_status VARCHAR(50) NOT NULL,
    policy_id INT NOT NULL
);

WITH NUMS(n) AS (
    SELECT d1.v*1000 + d2.v*100 + d3.v*10 + d4.v
    FROM (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
          UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
          UNION ALL SELECT 8 UNION ALL SELECT 9) d1
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d2
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d3
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d4
)
INSERT INTO dbo.stg_gen_space
SELECT n,
       -- Waterloo-style room code, e.g. 'MC-101'
       CASE n % 6 WHEN 0 THEN 'MC-' WHEN 1 THEN 'DC-' WHEN 2 THEN 'M3-'
            WHEN 3 THEN 'STC-' WHEN 4 THEN 'E5-' ELSE 'EV3-' END
         + CAST((n / 4) % 3 + 1 AS VARCHAR(2))
         + RIGHT('00' + CAST((n / 12) + 1 AS VARCHAR(3)), 2) AS space_code,
       -- Descriptive English room name, consistent with the reference sample.
       CASE n % 6
           WHEN 0 THEN 'Lecture Hall' WHEN 1 THEN 'Classroom' WHEN 2 THEN 'Computing Lab'
           WHEN 3 THEN 'Project Lab' WHEN 4 THEN 'Meeting Room' ELSE 'Collaborative Workspace' END
         + ' ' + CASE n % 6 WHEN 0 THEN 'MC-' WHEN 1 THEN 'DC-' WHEN 2 THEN 'M3-'
              WHEN 3 THEN 'STC-' WHEN 4 THEN 'E5-' ELSE 'EV3-' END
         + CAST((n / 4) % 3 + 1 AS VARCHAR(2))
         + RIGHT('00' + CAST((n / 12) + 1 AS VARCHAR(3)), 2) AS space_name,
       CASE n % 6
           WHEN 0 THEN 'auditorium' WHEN 1 THEN 'classroom' WHEN 2 THEN 'computer_lab'
           WHEN 3 THEN 'project_lab' WHEN 4 THEN 'meeting_room' ELSE 'student_workspace' END,
       CASE n % 6 WHEN 0 THEN 'MC' WHEN 1 THEN 'DC' WHEN 2 THEN 'M3'
            WHEN 3 THEN 'STC' WHEN 4 THEN 'E5' ELSE 'EV3' END AS building,
       (n / 4) % 3 + 1 AS floor,
       CAST((n / 12) + 1 AS VARCHAR(10)) AS room_number,
       20 + ((n * 37) % 180),
       CASE WHEN n % 7 = 0 THEN 'in_use' ELSE 'available' END,
       (SELECT TOP 1 policy_id FROM dbo.USAGE_POLICY p
        JOIN dbo.stg_gen_policy s ON s.policy_name = p.policy_name
        WHERE s.policy_idx = n % @PolicyCount)
FROM NUMS
WHERE n < @SpaceCount;

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor,
                       room_number, capacity, current_status, policy_id)
SELECT space_code, space_name, space_type, building, floor, room_number,
       capacity, current_status, policy_id
FROM dbo.stg_gen_space;

-- Track the generated spaces for the next cleanup run.
INSERT INTO dbo.gen_space_marker (space_code)
SELECT space_code FROM dbo.stg_gen_space;

-- ----------------------------------------------------------------------------
-- 3.4 FACILITY (each row optionally belongs to one SPACE)
-- ----------------------------------------------------------------------------
PRINT 'Step 3.4: facilities';

-- A facility is a unique physical instance in Phase 2. Create twelve distinct
-- rows and assign each to one generated space. OUTPUT tracks only rows created
-- by this run, so similarly named demonstration facilities are never adopted.
INSERT INTO dbo.FACILITY (facility_name, space_code)
OUTPUT INSERTED.facility_id INTO dbo.gen_facility_marker (facility_id)
SELECT v.facility_name, s.space_code
FROM (VALUES
          (0, 'Document Camera'),
          (1, 'Ceiling Projector'),
          (2, 'Wireless Microphone'),
          (3, 'Climate Control'),
          (4, 'Interactive Whiteboard'),
          (5, 'Hybrid Meeting Camera'),
          (6, 'Desktop Workstation'),
          (7, 'Lecture Capture System'),
          (8, 'Assistive Listening System'),
          (9, 'Charging Station'),
          (10, 'Adjustable Lectern'),
          (11, 'Digital Display')
     ) v(facility_idx, facility_name)
JOIN dbo.stg_gen_space s ON s.space_idx = v.facility_idx;

-- ----------------------------------------------------------------------------
-- 3.5 USER (staff first for deterministic id band)
-- ----------------------------------------------------------------------------
PRINT 'Step 3.5: users';

IF OBJECT_ID('dbo.stg_gen_user', 'U') IS NOT NULL DROP TABLE dbo.stg_gen_user;
CREATE TABLE dbo.stg_gen_user (
    user_idx INT NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    email_local VARCHAR(255) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    role_id INT NOT NULL,
    department_id INT NOT NULL,
    account_status VARCHAR(50) NOT NULL
);

-- ----------------------------------------------------------------------------
-- English name/reference lists. Combining 20 first names, 10 middle initials,
-- and 24 surnames provides enough natural-looking variation for 2,000 users.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#vn_surname') IS NOT NULL DROP TABLE #vn_surname;
CREATE TABLE #vn_surname (vn_id INT NOT NULL PRIMARY KEY, vn_name VARCHAR(60) NOT NULL);
INSERT INTO #vn_surname (vn_id, vn_name) VALUES
 (1,'Anderson'),(2,'Brown'),(3,'Campbell'),(4,'Chen'),(5,'Davis'),(6,'Evans'),
 (7,'Garcia'),(8,'Hassan'),(9,'Johnson'),(10,'Kim'),(11,'Lee'),(12,'Martin'),
 (13,'Martinez'),(14,'Miller'),(15,'Nguyen'),(16,'O''Brien'),(17,'Okafor'),(18,'Patel'),
 (19,'Robinson'),(20,'Santos'),(21,'Smith'),(22,'Taylor'),(23,'Wilson'),(24,'Wong');

IF OBJECT_ID('tempdb..#vn_middle') IS NOT NULL DROP TABLE #vn_middle;
CREATE TABLE #vn_middle (vn_id INT NOT NULL PRIMARY KEY, vn_name VARCHAR(60) NOT NULL);
INSERT INTO #vn_middle (vn_id, vn_name) VALUES
(1,'A.'),(2,'B.'),(3,'C.'),(4,'D.'),(5,'E.'),(6,'J.'),
(7,'L.'),(8,'M.'),(9,'R.'),(10,'S.');

IF OBJECT_ID('tempdb..#vn_given') IS NOT NULL DROP TABLE #vn_given;
CREATE TABLE #vn_given (vn_id INT NOT NULL PRIMARY KEY, vn_name VARCHAR(60) NOT NULL);
INSERT INTO #vn_given (vn_id, vn_name) VALUES
(1,'Alice'),(2,'Amelia'),(3,'Benjamin'),(4,'Chloe'),(5,'Daniel'),
(6,'Emily'),(7,'Ethan'),(8,'Fatima'),(9,'Grace'),(10,'Hannah'),
(11,'Isabella'),(12,'James'),(13,'Liam'),(14,'Lucas'),(15,'Maria'),
(16,'Michael'),(17,'Noah'),(18,'Olivia'),(19,'Sarah'),(20,'Thomas');

-- University of Waterloo academic and service departments.
IF OBJECT_ID('tempdb..#vn_dept') IS NOT NULL DROP TABLE #vn_dept;
CREATE TABLE #vn_dept (vn_id INT NOT NULL PRIMARY KEY, vn_name VARCHAR(120) NOT NULL);
INSERT INTO #vn_dept (vn_id, vn_name) VALUES
(1,'Computer Science'),
(2,'Mathematics'),
(3,'Electrical and Computer Engineering'),
(4,'Mechanical and Mechatronics Engineering'),
(5,'Civil and Environmental Engineering'),
(6,'Physics and Astronomy'),
(7,'Chemistry'),
(8,'Biology'),
(9,'Psychology'),
(10,'Facilities Management');

-- Ensure normalized department reference rows exist. Existing migrated
-- departments are reused by name; only missing departments are inserted.
INSERT INTO dbo.DEPARTMENT (department_name)
SELECT d.vn_name
FROM #vn_dept d
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.DEPARTMENT x WHERE x.department_name = d.vn_name
);

-- Give half of the generated policies explicit department restrictions.
-- The other half receive no rows and therefore remain unrestricted.
INSERT INTO dbo.DEPARTMENT_USAGE_POLICY (department_id, policy_id)
SELECT d.department_id, p.policy_id
FROM dbo.stg_gen_policy sp
JOIN dbo.USAGE_POLICY p ON p.policy_name = sp.policy_name
JOIN #vn_dept vd ON vd.vn_id = (sp.policy_idx % 10) + 1
JOIN dbo.DEPARTMENT d ON d.department_name = vd.vn_name
WHERE sp.policy_idx % 2 = 1
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.DEPARTMENT_USAGE_POLICY existing_link
      WHERE existing_link.department_id = d.department_id
        AND existing_link.policy_id = p.policy_id
  );

WITH NUMS(n) AS (
    SELECT d1.v*1000 + d2.v*100 + d3.v*10 + d4.v
    FROM (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
          UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
          UNION ALL SELECT 8 UNION ALL SELECT 9) d1
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d2
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d3
    CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                UNION ALL SELECT 8 UNION ALL SELECT 9) d4
)
INSERT INTO dbo.stg_gen_user (user_idx, full_name, email, email_local,
                              phone_number, role_id, department_id, account_status)
SELECT
    n,
    g.vn_name + ' ' + m.vn_name + ' ' + s.vn_name AS full_name,
    LOWER(g.vn_name + '.' + REPLACE(s.vn_name, '''', ''))
        + RIGHT('0000' + CAST(n + 1 AS VARCHAR(10)), 4) + '@uwaterloo.ca' AS email,
    LOWER(g.vn_name + '.' + REPLACE(s.vn_name, '''', '')) AS email_local,
    -- 1000..2999 is disjoint from the hand-written 0101..0112 range.
    '+1-519-555-' + RIGHT('0000' + CAST(n + 1000 AS VARCHAR(10)), 4),
    CASE WHEN n < 60 THEN @RoleStaff
         WHEN n < 100 THEN @RoleManager
         WHEN n < 210 THEN @RoleAdmin
         WHEN n < 310 THEN @RoleLecturer
         WHEN n < 400 THEN @RoleTA
         ELSE @RoleStudent END,
    dep.department_id,
    CASE WHEN n % 97 = 0 THEN 'suspended' ELSE 'active' END
FROM NUMS
JOIN #vn_surname s ON s.vn_id = (n % 24) + 1
JOIN #vn_middle m ON m.vn_id = ((n / 4) % 10) + 1
JOIN #vn_given g ON g.vn_id = ((n / 40) % 20) + 1
JOIN #vn_dept d ON d.vn_id = (n % 10) + 1
JOIN dbo.DEPARTMENT dep ON dep.department_name = d.vn_name
WHERE n < @UserCount;

-- USER.email and USER.phone_number are both protected by UNIQUE constraints.
-- Validate the complete staged set, including collisions with retained sample
-- rows, before attempting either insert statement.
IF EXISTS (
    SELECT email
    FROM dbo.stg_gen_user
    GROUP BY email
    HAVING COUNT(*) > 1
)
    THROW 53004, 'Generated user emails are not unique within the staged set.', 1;

IF EXISTS (
    SELECT phone_number
    FROM dbo.stg_gen_user
    GROUP BY phone_number
    HAVING COUNT(*) > 1
)
    THROW 53005, 'Generated user phone numbers are not unique within the staged set.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.stg_gen_user s
    JOIN dbo.[USER] u ON u.email = s.email
)
    THROW 53006, 'A generated user email conflicts with an existing user.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.stg_gen_user s
    JOIN dbo.[USER] u ON u.phone_number = s.phone_number
)
    THROW 53007, 'A generated user phone number conflicts with an existing user.', 1;

-- facility_staff (0..59) and facility_manager (60..99) inserted first so the
-- staff user ids form a contiguous band for deterministic staff mapping.
INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
SELECT full_name, email, phone_number, role_id, department_id, account_status
FROM dbo.stg_gen_user
WHERE user_idx < 100
ORDER BY user_idx;

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
SELECT full_name, email, phone_number, role_id, department_id, account_status
FROM dbo.stg_gen_user
WHERE user_idx >= 100
ORDER BY user_idx;

-- Track generated users by joining their unique, realistic email addresses.
INSERT INTO dbo.gen_user_marker (user_id)
SELECT u.user_id FROM dbo.[USER] u
JOIN dbo.stg_gen_user s ON s.email = u.email;

IF (SELECT COUNT(*) FROM dbo.stg_gen_policy) <> @PolicyCount
    THROW 53008, 'Generated policy count does not match PolicyCount.', 1;
IF (SELECT COUNT(*) FROM dbo.stg_gen_space) <> @SpaceCount
    THROW 53009, 'Generated space count does not match SpaceCount.', 1;
IF (SELECT COUNT(*) FROM dbo.gen_facility_marker) <> @FacilityCount
    THROW 53022, 'Generated facility count does not match FacilityCount.', 1;
IF (SELECT COUNT(*) FROM dbo.gen_user_marker) <> @UserCount
    THROW 53023, 'Generated user count does not match UserCount.', 1;

-- Deterministic id maps (do not rely on IDENTITY allocation order)
IF OBJECT_ID('tempdb..#user_map') IS NOT NULL DROP TABLE #user_map;
SELECT u.user_id, s.user_idx
INTO #user_map
FROM dbo.[USER] u
JOIN dbo.stg_gen_user s ON s.email = u.email;
CREATE UNIQUE CLUSTERED INDEX ix_user_map_user_idx ON #user_map(user_idx);

IF OBJECT_ID('tempdb..#decision_staff') IS NOT NULL DROP TABLE #decision_staff;
SELECT ROW_NUMBER() OVER (ORDER BY user_id) - 1 AS staff_ord, user_id
INTO #decision_staff
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE u.user_id IN (SELECT user_id FROM dbo.gen_user_marker)
  AND r.role_name IN ('facility_staff', 'facility_manager');
CREATE UNIQUE CLUSTERED INDEX ix_decision_staff_ord ON #decision_staff(staff_ord);

IF OBJECT_ID('tempdb..#checkin_staff') IS NOT NULL DROP TABLE #checkin_staff;
SELECT ROW_NUMBER() OVER (ORDER BY user_id) - 1 AS staff_ord, user_id
INTO #checkin_staff
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE u.user_id IN (SELECT user_id FROM dbo.gen_user_marker)
  AND r.role_name = 'facility_staff';
CREATE UNIQUE CLUSTERED INDEX ix_checkin_staff_ord ON #checkin_staff(staff_ord);

-- ============================================================================
-- 4. MAINTENANCE_RECORD (advisory + out-of-service)
-- ============================================================================
PRINT 'Step 4: maintenance records';

IF OBJECT_ID('dbo.stg_gen_maintenance', 'U') IS NOT NULL DROP TABLE dbo.stg_gen_maintenance;
CREATE TABLE dbo.stg_gen_maintenance (
    space_code VARCHAR(50) NOT NULL,
    reporter_id INT NOT NULL,
    assigned_staff_id INT NULL,
    problem_description VARCHAR(MAX) NOT NULL,
    start_time DATETIME2 NOT NULL,
    completion_time DATETIME2 NULL,
    status VARCHAR(50) NOT NULL,
    result_note VARCHAR(MAX) NULL,
    impact_level VARCHAR(50) NOT NULL
);

-- Advisory windows: weekday mornings, open (reported/in_progress), overlapping
-- generated bookings -> acknowledgement links are created in step 8.
INSERT INTO dbo.stg_gen_maintenance (
    space_code, reporter_id, assigned_staff_id, problem_description,
    start_time, completion_time, status, result_note, impact_level
)
SELECT s.space_code,
       (SELECT user_id FROM #user_map WHERE user_idx = (s.space_idx * 37) % @UserCount),
       (SELECT user_id FROM #decision_staff WHERE staff_ord = (s.space_idx * 13) % 100),
       'Routine inspection of lighting and electrical outlets in ' + s.space_code,
       CAST(DATEADD(HOUR, 8, CAST(w.wd_date AS DATETIME2)) AS DATETIME2),
       NULL,
       'in_progress',
       NULL,
       'advisory'
FROM dbo.stg_gen_space s
JOIN #weekdays w ON w.wd_ord = ((s.space_idx * 7 + 3) % @WeekdayCount)
UNION ALL
SELECT s.space_code,
       (SELECT user_id FROM #user_map WHERE user_idx = (s.space_idx * 37 + 11) % @UserCount),
       (SELECT user_id FROM #decision_staff WHERE staff_ord = (s.space_idx * 13 + 7) % 100),
       'Routine inspection of ventilation and climate controls in ' + s.space_code,
       CAST(DATEADD(HOUR, 8, CAST(w.wd_date AS DATETIME2)) AS DATETIME2),
       NULL,
       'reported',
       NULL,
       'advisory'
FROM dbo.stg_gen_space s
JOIN #weekdays w ON w.wd_ord = ((s.space_idx * 11 + 5) % @WeekdayCount);

-- Out-of-service windows: weekends only (no bookings), Saturday 08:00 to
-- Sunday 20:00. One open (in_progress), one completed.
INSERT INTO dbo.stg_gen_maintenance (
    space_code, reporter_id, assigned_staff_id, problem_description,
    start_time, completion_time, status, result_note, impact_level
)
SELECT s.space_code,
       (SELECT user_id FROM #user_map WHERE user_idx = (s.space_idx * 41 + 3) % @UserCount),
       (SELECT user_id FROM #decision_staff WHERE staff_ord = (s.space_idx * 17) % 100),
       'Deep cleaning and equipment inspection for ' + s.space_code,
       CAST(DATEADD(HOUR, 8, CAST(w.sa_date AS DATETIME2)) AS DATETIME2),
       CAST(DATEADD(HOUR, 20, CAST(DATEADD(DAY, 1, w.sa_date) AS DATETIME2)) AS DATETIME2),
       'in_progress',
       NULL,
       'out-of-service'
FROM dbo.stg_gen_space s
JOIN #saturdays w ON w.sa_ord = (s.space_idx % @SaturdayCount)
UNION ALL
SELECT s.space_code,
       (SELECT user_id FROM #user_map WHERE user_idx = (s.space_idx * 41 + 5) % @UserCount),
       (SELECT user_id FROM #decision_staff WHERE staff_ord = (s.space_idx * 17 + 9) % 100),
       'Electrical and classroom equipment maintenance for ' + s.space_code,
       CAST(DATEADD(HOUR, 8, CAST(w.sa_date AS DATETIME2)) AS DATETIME2),
       CAST(DATEADD(HOUR, 20, CAST(DATEADD(DAY, 1, w.sa_date) AS DATETIME2)) AS DATETIME2),
       'completed',
       'Maintenance completed; room inspected and returned to service.',
       'out-of-service'
FROM dbo.stg_gen_space s
JOIN #saturdays w ON w.sa_ord = ((s.space_idx + 13) % @SaturdayCount);

-- Capture the identity values of every row we just inserted so the next
-- cleanup run can find them again (no marker text in the data).
DECLARE @gen_maint_ids TABLE (maintenance_id INT NOT NULL);
INSERT INTO dbo.MAINTENANCE_RECORD (
    space_code, reporter_id, assigned_staff_id, problem_description,
    start_time, completion_time, status, result_note, impact_level
)
OUTPUT INSERTED.maintenance_id INTO @gen_maint_ids
SELECT space_code, reporter_id, assigned_staff_id, problem_description,
       start_time, completion_time, status, result_note, impact_level
FROM dbo.stg_gen_maintenance;

INSERT INTO dbo.gen_maintenance_marker (maintenance_id)
SELECT maintenance_id FROM @gen_maint_ids;

IF (SELECT COUNT(*) FROM dbo.gen_maintenance_marker) <> @SpaceCount * 4
    THROW 53024, 'Generated maintenance count must equal four records per space.', 1;

-- ============================================================================
-- 5. BOOKING STAGING
-- ============================================================================
PRINT 'Step 5: booking staging (set-based)';

IF OBJECT_ID('dbo.stg_gen_booking', 'U') IS NOT NULL DROP TABLE dbo.stg_gen_booking;
CREATE TABLE dbo.stg_gen_booking (
    n BIGINT NOT NULL CONSTRAINT pk_stg_gen_booking PRIMARY KEY CLUSTERED,
    requester_id INT NOT NULL,
    space_code VARCHAR(50) NOT NULL,
    requested_start_time DATETIME2 NOT NULL,
    requested_end_time DATETIME2 NOT NULL,
    purpose VARCHAR(50) NOT NULL,
    expected_participants INT NOT NULL,
    booking_status VARCHAR(50) NOT NULL,
    decision_staff_id INT NULL,
    decision_time DATETIME2 NULL,
    decision_note VARCHAR(MAX) NULL,
    rejection_reason VARCHAR(255) NULL,
    actual_start_time DATETIME2 NULL,
    check_in_staff_id INT NULL,
    initial_condition VARCHAR(MAX) NULL,
    actual_end_time DATETIME2 NULL,
    completion_staff_id INT NULL,
    final_condition VARCHAR(MAX) NULL,
    usage_notes VARCHAR(MAX) NULL
);

INSERT INTO dbo.stg_gen_booking (
    n, requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note, rejection_reason,
    actual_start_time, check_in_staff_id, initial_condition,
    actual_end_time, completion_staff_id, final_condition, usage_notes
)
SELECT
    src.n,
    src.requester_id,
    src.space_code,
    src.req_start,
    src.req_end,
    sv.purpose,
    sv.participants,
    sv.status,
    CASE WHEN sv.status IN ('approved', 'rejected') THEN ds.user_id END AS decision_staff_id,
    CASE WHEN sv.status IN ('approved', 'rejected')
         THEN DATEADD(HOUR, -3, src.req_start) END AS decision_time,
    CASE WHEN sv.status IN ('approved', 'rejected')
         THEN CASE WHEN sv.status = 'approved' THEN 'Approved after space and schedule review.'
                   ELSE 'Request declined after space and schedule review.' END END AS decision_note,
    CASE WHEN sv.status = 'rejected'
         THEN CASE src.h_cancel % 5
                  WHEN 0 THEN 'The room is already reserved for this time.'
                  WHEN 1 THEN 'The requested time falls outside permitted hours.'
                  WHEN 2 THEN 'The activity is not suitable for this room type.'
                  WHEN 3 THEN 'The booking request is missing required details.'
                  ELSE 'Expected attendance exceeds room capacity.' END END AS rejection_reason,
    CASE WHEN sv.status IN ('checked_in', 'completed')
         THEN DATEADD(MINUTE, 5 + (src.h_minutes % 10), src.req_start) END AS actual_start_time,
    CASE WHEN sv.status IN ('checked_in', 'completed') THEN cs.user_id END AS check_in_staff_id,
    CASE WHEN sv.status IN ('checked_in', 'completed') THEN 'Room clean; lighting, furniture, and presentation equipment checked.' END AS initial_condition,
    CASE WHEN sv.status = 'completed'
         THEN DATEADD(MINUTE, 5 + (src.h_minutes % 10), src.req_end) END AS actual_end_time,
    CASE WHEN sv.status = 'completed' THEN cs.user_id END AS completion_staff_id,
    CASE WHEN sv.status = 'completed' THEN 'Room returned in good condition; equipment powered down.' END AS final_condition,
    CASE WHEN sv.status = 'completed' THEN 'Space used for the approved purpose with no incidents reported.' END AS usage_notes
FROM (
    SELECT
        n,
        um.user_id AS requester_id,
        spc.space_code,
        spc.capacity,
        ((n / @SpaceCount) % @WeekdayCount) AS day_ord,
        ((n / @SpaceCount) / @WeekdayCount) % 6 AS slot_of_day,
        CASE WHEN (n / @SpaceCount) % @WeekdayCount < @WPY0 THEN 0
             WHEN (n / @SpaceCount) % @WeekdayCount < @WPY0 + @WPY1 THEN 1
             ELSE 2 END AS year_zone,
        CAST(DATEADD(HOUR, 8 + (((n / @SpaceCount) / @WeekdayCount) % 6) * 2, CAST(w.wd_date AS DATETIME2)) AS DATETIME2) AS req_start,
        CAST(DATEADD(HOUR, 10 + (((n / @SpaceCount) / @WeekdayCount) % 6) * 2, CAST(w.wd_date AS DATETIME2)) AS DATETIME2) AS req_end,
        CAST(ABS(CAST(CHECKSUM(CAST(@Seed AS BIGINT) * 1000003 + CAST(n AS BIGINT) * 40503) AS BIGINT)) % 1000 AS INT) AS h_status,
        CAST(ABS(CAST(CHECKSUM(CAST(@Seed AS BIGINT) * 1000003 + CAST(n AS BIGINT) * 104729 + 17) AS BIGINT)) % 7 AS INT) AS h_purpose,
        CAST(ABS(CAST(CHECKSUM(CAST(@Seed AS BIGINT) * 1000003 + CAST(n AS BIGINT) * 2087 + 41) AS BIGINT)) % 100 AS INT) AS h_staff,
        CAST(ABS(CAST(CHECKSUM(CAST(@Seed AS BIGINT) * 1000003 + CAST(n AS BIGINT) * 509 + 3) AS BIGINT)) % 10 AS INT) AS h_minutes,
        CAST(ABS(CAST(CHECKSUM(CAST(@Seed AS BIGINT) * 1000003 + CAST(n AS BIGINT) * 1299721 + 97) AS BIGINT)) % 1000 AS INT) AS h_cancel
    FROM (
        SELECT d1.v*100000 + d2.v*10000 + d3.v*1000 + d4.v*100 + d5.v*10 + d6.v AS n
        FROM (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
              UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
              UNION ALL SELECT 8 UNION ALL SELECT 9) d1
        CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                    UNION ALL SELECT 8 UNION ALL SELECT 9) d2
        CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                    UNION ALL SELECT 8 UNION ALL SELECT 9) d3
        CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                    UNION ALL SELECT 8 UNION ALL SELECT 9) d4
        CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                    UNION ALL SELECT 8 UNION ALL SELECT 9) d5
        CROSS JOIN (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                    UNION ALL SELECT 8 UNION ALL SELECT 9) d6
    ) NUMS
    JOIN dbo.stg_gen_space spc ON spc.space_idx = (n % @SpaceCount)
    JOIN #weekdays w ON w.wd_ord = ((n / @SpaceCount) % @WeekdayCount)
    JOIN #user_map um ON um.user_idx = (n % @UserCount)
    WHERE n < @BookingCount
) src
LEFT JOIN #decision_staff ds ON ds.staff_ord = src.h_staff % 100
LEFT JOIN #checkin_staff cs ON cs.staff_ord = src.h_staff % 60
CROSS APPLY (
    SELECT
        CASE src.h_purpose
            WHEN 0 THEN 'lecture' WHEN 1 THEN 'examination' WHEN 2 THEN 'seminar'
            WHEN 3 THEN 'workshop' WHEN 4 THEN 'meeting' WHEN 5 THEN 'student_activity'
            ELSE 'administrative_event' END AS purpose,
        (src.h_cancel % src.capacity) + 1 AS participants,
        CASE src.year_zone
            WHEN 2 THEN
                CASE WHEN src.h_status < 440 THEN 'approved'
                     WHEN src.h_status < 780 THEN 'pending'
                     WHEN src.h_status < 890 THEN 'completed'
                     WHEN src.h_status < 920 THEN 'checked_in'
                     WHEN src.h_status < 950 THEN 'no_show'
                     WHEN src.h_status < 980 THEN 'cancelled'
                     ELSE 'rejected' END
            ELSE
                CASE WHEN src.h_status < 45 THEN 'rejected'
                     WHEN src.h_status < 75 THEN 'no_show'
                     WHEN src.h_status < 155 THEN 'cancelled'
                     WHEN src.h_status < 800 THEN 'completed'
                     ELSE 'checked_in' END
        END AS status
) s
CROSS APPLY (
    SELECT s.purpose AS purpose, s.participants AS participants, s.status AS status
) sv;

DECLARE @StagedBookings BIGINT = (SELECT COUNT_BIG(*) FROM dbo.stg_gen_booking);
PRINT '  staged bookings: ' + CAST(@StagedBookings AS VARCHAR(20));

CREATE NONCLUSTERED INDEX ix_stg_gen_booking_space_time
    ON dbo.stg_gen_booking (space_code, requested_start_time, requested_end_time)
    INCLUDE (booking_status);

-- ============================================================================
-- 6. PRE-LOAD VALIDATION (staged rows)
-- ============================================================================
PRINT 'Step 6: pre-load validation';

DECLARE @StagedCount BIGINT = (SELECT COUNT_BIG(*) FROM dbo.stg_gen_booking);

IF @StagedCount <> @BookingCount
    THROW 53010, 'Staged booking count does not match BookingCount.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking WHERE requested_start_time >= requested_end_time)
    THROW 53011, 'Staged booking has invalid requested time range.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking b
           LEFT JOIN dbo.[USER] u ON u.user_id = b.requester_id
           LEFT JOIN dbo.SPACE s ON s.space_code = b.space_code
           WHERE u.user_id IS NULL OR s.space_code IS NULL)
    THROW 53012, 'Staged booking references unknown user or space.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking WHERE booking_status NOT IN
           ('pending','approved','rejected','cancelled','checked_in','completed','no_show'))
    THROW 53013, 'Staged booking has invalid status.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking WHERE expected_participants <= 0)
    THROW 53014, 'Staged booking has non-positive participants.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking
           WHERE booking_status = 'rejected'
             AND (decision_staff_id IS NULL OR decision_time IS NULL
                  OR decision_note IS NULL OR rejection_reason IS NULL))
    THROW 53015, 'Staged rejected booking is missing decision/rejection fields.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking
           WHERE booking_status = 'approved' AND decision_time IS NULL)
    THROW 53016, 'Staged approved booking is missing decision_time.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking
           WHERE booking_status IN ('checked_in','completed')
             AND (actual_start_time IS NULL OR check_in_staff_id IS NULL
                  OR initial_condition IS NULL))
    THROW 53017, 'Staged checked-in booking is missing check-in fields.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking
           WHERE booking_status = 'completed'
             AND (actual_end_time IS NULL OR completion_staff_id IS NULL
                  OR final_condition IS NULL OR usage_notes IS NULL))
    THROW 53018, 'Staged completed booking is missing completion fields.', 1;

IF EXISTS (SELECT 1 FROM dbo.stg_gen_booking
           GROUP BY space_code, requested_start_time
           HAVING COUNT_BIG(*) > 1)
    THROW 53019, 'Staged bookings contain a duplicate space/time slot.', 1;

-- A window check is linear after ordering and avoids the very expensive
-- inequality self-join that previously made a 100,000-row run appear stalled.
IF EXISTS (
    SELECT 1
    FROM (
        SELECT requested_start_time,
               MAX(requested_end_time) OVER (
                   PARTITION BY space_code ORDER BY requested_start_time
                   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
               ) AS previous_end_time
        FROM dbo.stg_gen_booking
        WHERE booking_status = 'approved'
    ) approved_schedule
    WHERE previous_end_time > requested_start_time
)
    THROW 53020, 'Staged approved bookings overlap within a space.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.stg_gen_booking b
    JOIN dbo.MAINTENANCE_RECORD m
      ON m.space_code = b.space_code
     AND m.impact_level = 'out-of-service'
     AND m.status IN ('reported','in_progress')
     AND b.requested_start_time < COALESCE(m.completion_time, DATEADD(HOUR, 36, m.start_time))
     AND b.requested_end_time > m.start_time
)
    THROW 53021, 'Staged booking overlaps out-of-service maintenance.', 1;

PRINT '  staged validation: PASS';

-- ============================================================================
-- 7. BULK LOAD (trigger temporarily disabled, always re-enabled)
-- ============================================================================
PRINT 'Step 7: bulk loading bookings in batches of ' + CAST(@BatchSize AS VARCHAR(10));

DECLARE @Offset BIGINT = 0;
DECLARE @RowsInserted INT;

BEGIN TRY
    ALTER TABLE dbo.BOOKING DISABLE TRIGGER trg_booking_enforce_rules;
    PRINT '  dbo.trg_booking_enforce_rules DISABLED for bulk load';

    WHILE @Offset < @BookingCount
    BEGIN
        INSERT INTO dbo.BOOKING (
            requester_id, space_code, requested_start_time, requested_end_time,
            purpose, expected_participants, booking_status,
            decision_staff_id, decision_time, decision_note, rejection_reason,
            actual_start_time, check_in_staff_id, initial_condition,
            actual_end_time, completion_staff_id, final_condition, usage_notes
        )
        SELECT
            requester_id, space_code, requested_start_time, requested_end_time,
            purpose, expected_participants, booking_status,
            decision_staff_id, decision_time, decision_note, rejection_reason,
            actual_start_time, check_in_staff_id, initial_condition,
            actual_end_time, completion_staff_id, final_condition, usage_notes
        FROM dbo.stg_gen_booking
        ORDER BY n
        OFFSET @Offset ROWS
        FETCH NEXT @BatchSize ROWS ONLY;

        SET @RowsInserted = @@ROWCOUNT;
        IF @RowsInserted = 0
            THROW 53025, 'Bulk booking load stopped before reaching BookingCount.', 1;

        SET @Offset = @Offset + @RowsInserted;
        RAISERROR ('    loaded %I64d of %d bookings', 10, 1, @Offset, @BookingCount) WITH NOWAIT;
    END;

    ALTER TABLE dbo.BOOKING ENABLE TRIGGER trg_booking_enforce_rules;
    PRINT '  dbo.trg_booking_enforce_rules ENABLED';
END TRY
BEGIN CATCH
    -- The trigger must always be re-enabled, even on failure.
    ALTER TABLE dbo.BOOKING ENABLE TRIGGER trg_booking_enforce_rules;
    PRINT '  dbo.trg_booking_enforce_rules ENABLED after failure';
    THROW;
END CATCH;

-- ============================================================================
-- 8. ADVISORY ACKNOWLEDGEMENTS
--    The bulk load bypassed the trigger's acknowledgement auto-sync, so the
--    links are created here for every booking overlapping an open advisory
--    maintenance record. ACKNOWLEDGEMENT(booking_id, maintenance_record_id,
--    acknowledged_at) is the Phase 2 link model.
-- ============================================================================
PRINT 'Step 8: advisory acknowledgement links';

INSERT INTO dbo.ACKNOWLEDGEMENT (booking_id, maintenance_record_id, acknowledged_at)
SELECT b.booking_id, m.maintenance_id, b.requested_start_time
FROM dbo.BOOKING b
JOIN dbo.MAINTENANCE_RECORD m
  ON m.space_code = b.space_code
 AND m.impact_level = 'advisory'
 AND m.status IN ('reported', 'in_progress')
 AND b.requested_start_time < COALESCE(m.completion_time, CONVERT(DATETIME2, '9999-12-31'))
 AND b.requested_end_time > m.start_time
WHERE b.requester_id IN (SELECT user_id FROM dbo.gen_user_marker)
  AND NOT EXISTS (SELECT 1 FROM dbo.ACKNOWLEDGEMENT a
                  WHERE a.booking_id = b.booking_id
                    AND a.maintenance_record_id = m.maintenance_id);

DECLARE @AckLinks BIGINT = (SELECT COUNT_BIG(*) FROM dbo.ACKNOWLEDGEMENT);
PRINT '  acknowledgement links: ' + CAST(@AckLinks AS VARCHAR(20));

-- ============================================================================
-- 9. POST-LOAD QUICK VALIDATION + SUMMARY
-- ============================================================================
PRINT 'Step 9: post-load validation';

IF EXISTS (SELECT 1 FROM sys.triggers
           WHERE object_id = OBJECT_ID('dbo.trg_booking_enforce_rules') AND is_disabled = 1)
    THROW 53030, 'trg_booking_enforce_rules is disabled after generation.', 1;

IF EXISTS (SELECT 1 FROM dbo.BOOKING b
           LEFT JOIN dbo.[USER] u ON u.user_id = b.requester_id
           LEFT JOIN dbo.SPACE s ON s.space_code = b.space_code
           WHERE b.requester_id IN (SELECT user_id FROM dbo.gen_user_marker)
             AND (u.user_id IS NULL OR s.space_code IS NULL))
    THROW 53031, 'Generated booking has an orphan reference.', 1;

DECLARE @LoadedBookingCount BIGINT = (
    SELECT COUNT_BIG(*)
    FROM dbo.BOOKING b
    WHERE b.requester_id IN (SELECT user_id FROM dbo.gen_user_marker)
);

IF @LoadedBookingCount <> @BookingCount
    THROW 53035, 'Loaded generated booking count does not match BookingCount.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.[USER] u
    JOIN dbo.gen_user_marker gm ON gm.user_id = u.user_id
    LEFT JOIN dbo.DEPARTMENT d ON d.department_id = u.department_id
    WHERE d.department_id IS NULL
)
    THROW 53032, 'Generated user has an orphan department reference.', 1;

IF (SELECT COUNT(*)
    FROM #gen_semester g
    JOIN dbo.SEMESTER s
      ON s.semester_name = g.semester_name
     AND s.start_date = g.start_date
     AND s.end_date = g.end_date) <> @AcademicYearCount * 2
    THROW 53033, 'Semester generation did not produce two valid semesters per academic year.', 1;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.DEPARTMENT_USAGE_POLICY dp
    WHERE dp.policy_id IN (SELECT policy_id FROM dbo.gen_policy_marker)
)
    THROW 53034, 'Generated policies have no department restrictions.', 1;

-- Exact generated-entity counts. Counts exclude retained demonstration rows.
SELECT entity_name, generated_count, expected_count
FROM (VALUES
    ('USER', CAST((SELECT COUNT_BIG(*) FROM dbo.gen_user_marker) AS BIGINT), CAST(@UserCount AS BIGINT)),
    ('SPACE', CAST((SELECT COUNT_BIG(*) FROM dbo.gen_space_marker) AS BIGINT), CAST(@SpaceCount AS BIGINT)),
    ('FACILITY', CAST((SELECT COUNT_BIG(*) FROM dbo.gen_facility_marker) AS BIGINT), CAST(@FacilityCount AS BIGINT)),
    ('USAGE_POLICY', CAST((SELECT COUNT_BIG(*) FROM dbo.gen_policy_marker) AS BIGINT), CAST(@PolicyCount AS BIGINT)),
    ('SEMESTER', CAST(@GeneratedSemesterCount AS BIGINT), CAST(@AcademicYearCount * 2 AS BIGINT)),
    ('MAINTENANCE_RECORD', CAST((SELECT COUNT_BIG(*) FROM dbo.gen_maintenance_marker) AS BIGINT), CAST(@SpaceCount * 4 AS BIGINT)),
    ('BOOKING', @LoadedBookingCount, CAST(@BookingCount AS BIGINT))
) summary(entity_name, generated_count, expected_count)
ORDER BY entity_name;

SELECT booking_status, COUNT_BIG(*) AS cnt,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS DECIMAL(5,2)) AS pct
FROM dbo.BOOKING b
JOIN dbo.[USER] u ON u.user_id = b.requester_id
WHERE u.user_id IN (SELECT user_id FROM dbo.gen_user_marker)
GROUP BY booking_status
ORDER BY booking_status;

SELECT MIN(requested_start_time) AS first_booking,
       MAX(requested_start_time) AS last_booking,
       DATEDIFF(DAY, MIN(requested_start_time), MAX(requested_start_time)) AS day_span
FROM dbo.BOOKING b
JOIN dbo.[USER] u ON u.user_id = b.requester_id
WHERE u.user_id IN (SELECT user_id FROM dbo.gen_user_marker);

SELECT m.impact_level, m.status, COUNT_BIG(*) AS cnt
FROM dbo.MAINTENANCE_RECORD m
JOIN dbo.gen_maintenance_marker g ON g.maintenance_id = m.maintenance_id
GROUP BY m.impact_level, m.status
ORDER BY m.impact_level, m.status;

SELECT s.semester_name, s.start_date, s.end_date
FROM dbo.SEMESTER s
JOIN #gen_semester g ON g.semester_name = s.semester_name
ORDER BY s.start_date;

SELECT p.policy_name, COUNT(dp.department_id) AS allowed_department_count
FROM dbo.USAGE_POLICY p
JOIN dbo.gen_policy_marker gm ON gm.policy_id = p.policy_id
LEFT JOIN dbo.DEPARTMENT_USAGE_POLICY dp ON dp.policy_id = p.policy_id
GROUP BY p.policy_id, p.policy_name
ORDER BY p.policy_name;

PRINT 'High-volume generation complete.';

-- ============================================================================
-- cleanup of staging tables
-- ============================================================================
DROP TABLE dbo.stg_gen_policy;
DROP TABLE dbo.stg_gen_space;
DROP TABLE dbo.stg_gen_user;
DROP TABLE dbo.stg_gen_maintenance;
DROP TABLE dbo.stg_gen_booking;

-- Marker tables make a future run able to remove only rows created by this
-- generator. Drop them only after every generation and validation step has
-- completed successfully and only when rerun support is intentionally disabled.
IF @KeepMarkerTables = 0
BEGIN
    DROP TABLE IF EXISTS dbo.gen_maintenance_marker;
    DROP TABLE IF EXISTS dbo.gen_facility_marker;
    DROP TABLE IF EXISTS dbo.gen_space_marker;
    DROP TABLE IF EXISTS dbo.gen_policy_marker;
    DROP TABLE IF EXISTS dbo.gen_user_marker;

    PRINT 'Generated-row marker tables dropped; selective cleanup on a future run is unavailable.';
END
ELSE
    PRINT 'Generated-row marker tables retained for safe reruns.';
