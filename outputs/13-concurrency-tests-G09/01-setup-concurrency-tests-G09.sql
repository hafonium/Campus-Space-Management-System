-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 01-setup-concurrency-tests-G09.sql
-- ============================================================================
-- Creates a self-contained test fixture: a space with a non-auto-approving
-- policy and four pending bookings (two conflict overlap + two non-conflict).
-- ============================================================================
-- Prerequisites:
--   05-db-definition-G09.sql    (Phase 1 DDL)
--   10-schema-migration-G09.sql (Phase 2 migration)
--   folder 14 data generator    (users, roles, spaces)
--   12-concurrency-implementation-G09.sql (sp_approve_booking)
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- ============================================================================
-- 1. Create a non-auto-approving policy for the test space
-- ============================================================================
DECLARE @PolicyId INT;

IF NOT EXISTS (SELECT 1 FROM dbo.USAGE_POLICY WHERE policy_name = 'CONCURRENCY_TEST')
BEGIN
    INSERT INTO dbo.USAGE_POLICY (policy_name, legacy_policy_text)
    VALUES ('CONCURRENCY_TEST', 'Phase 1 policy — staff approval required for concurrency tests.');
END

SELECT @PolicyId = policy_id
FROM dbo.USAGE_POLICY
WHERE policy_name = 'CONCURRENCY_TEST';

-- ============================================================================
-- 2. Create a dedicated test space
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM dbo.SPACE WHERE space_code = 'TEST-CONC-001')
BEGIN
    INSERT INTO dbo.SPACE
        (space_code, space_name, space_type, building, floor, room_number,
         capacity, current_status, policy_id)
    VALUES
        ('TEST-CONC-001', 'Concurrency Test Room', 'classroom',
         'TEST', 1, 'CONC-001', 50, 'available', @PolicyId);
END

-- ============================================================================
-- 3. Identify a facility_staff user to act as decision maker
-- ============================================================================
DECLARE @StaffId INT;

SELECT TOP 1 @StaffId = u.user_id
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE r.role_name IN ('facility_staff', 'facility_manager')
ORDER BY u.user_id;

IF @StaffId IS NULL
    THROW 50010, 'No facility_staff / facility_manager user found. Run folder 14 data generator first.', 1;

-- ============================================================================
-- 4. Conflict pair: 09:00-11:00 and 10:00-12:00 (overlap 10:00-11:00)
-- ============================================================================
DECLARE @RequesterId INT;
SELECT TOP 1 @RequesterId = user_id FROM dbo.[USER] ORDER BY user_id;

INSERT INTO dbo.BOOKING
    (requester_id, space_code, requested_start_time, requested_end_time,
     purpose, expected_participants, booking_status)
VALUES
    (@RequesterId, 'TEST-CONC-001', '2027-01-11 09:00:00', '2027-01-11 11:00:00',
     'lecture', 30, 'pending');

INSERT INTO dbo.BOOKING
    (requester_id, space_code, requested_start_time, requested_end_time,
     purpose, expected_participants, booking_status)
VALUES
    (@RequesterId, 'TEST-CONC-001', '2027-01-11 10:00:00', '2027-01-11 12:00:00',
     'lecture', 25, 'pending');

-- ============================================================================
-- 5. Non-conflict pair: 08:00-09:00 and 10:00-11:00 (disjoint)
-- ============================================================================
INSERT INTO dbo.BOOKING
    (requester_id, space_code, requested_start_time, requested_end_time,
     purpose, expected_participants, booking_status)
VALUES
    (@RequesterId, 'TEST-CONC-001', '2027-01-12 08:00:00', '2027-01-12 09:00:00',
     'meeting', 10, 'pending');

INSERT INTO dbo.BOOKING
    (requester_id, space_code, requested_start_time, requested_end_time,
     purpose, expected_participants, booking_status)
VALUES
    (@RequesterId, 'TEST-CONC-001', '2027-01-12 10:00:00', '2027-01-12 11:00:00',
     'meeting', 10, 'pending');

-- ============================================================================
-- 6. Output fixture IDs
-- ============================================================================
SELECT booking_id, space_code, requested_start_time, requested_end_time,
       booking_status
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-13'
ORDER BY requested_start_time;

PRINT 'Staff ID for approvals: ' + CAST(@StaffId AS VARCHAR(10));
PRINT 'Concurrency test fixtures ready on TEST-CONC-001.';
PRINT 'Run 02a + 02b simultaneously for conflict test.';
PRINT 'Run 03a + 03b simultaneously for non-conflict test.';
GO
