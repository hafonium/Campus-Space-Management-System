-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 01a-demo-conflict-setup.sql
-- ============================================================================
-- DEMO: Write-skew without protection.
-- Disables the overlap-check trigger, creates two overlapping pending
-- bookings. The following sessions (01b + 01c) use raw UPDATE with no
-- locking — both will succeed, proving the write-skew exists.
-- ============================================================================
-- Prerequisites: 05 → 10 → folder 14 → 12
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- Disable the INSTEAD-OF trigger so raw UPDATE bypasses all checks
DISABLE TRIGGER dbo.trg_booking_enforce_rules ON dbo.BOOKING;
GO

-- ============================================================================
-- 1. Create test space with non-auto-approving policy
-- ============================================================================
DECLARE @PolicyId INT;

IF NOT EXISTS (SELECT 1 FROM dbo.USAGE_POLICY WHERE policy_name = 'CONCURRENCY_TEST')
    INSERT INTO dbo.USAGE_POLICY (policy_name, legacy_policy_text)
    VALUES ('CONCURRENCY_TEST', 'Test policy — staff approval required.');

SELECT @PolicyId = policy_id FROM dbo.USAGE_POLICY WHERE policy_name = 'CONCURRENCY_TEST';

IF NOT EXISTS (SELECT 1 FROM dbo.SPACE WHERE space_code = 'TEST-CONC-001')
    INSERT INTO dbo.SPACE
        (space_code, space_name, space_type, building, floor, room_number,
         capacity, current_status, policy_id)
    VALUES ('TEST-CONC-001', 'Concurrency Test Room', 'classroom',
            'TEST', 1, 'CONC-001', 50, 'available', @PolicyId);

-- ============================================================================
-- 2. Insert two overlapping pending bookings
-- ============================================================================
DECLARE @RequesterId INT;
SELECT TOP 1 @RequesterId = user_id FROM dbo.[USER] ORDER BY user_id;

INSERT INTO dbo.BOOKING
    (requester_id, space_code, requested_start_time, requested_end_time,
     purpose, expected_participants, booking_status)
VALUES
    (@RequesterId, 'TEST-CONC-001', '2027-01-11 09:00:00', '2027-01-11 11:00:00',
     'lecture', 30, 'pending'),
    (@RequesterId, 'TEST-CONC-001', '2027-01-11 10:00:00', '2027-01-11 12:00:00',
     'lecture', 25, 'pending');

-- ============================================================================
-- 3. Show fixture IDs
-- ============================================================================
SELECT booking_id, space_code, requested_start_time, requested_end_time,
       booking_status
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12'
ORDER BY requested_start_time;

PRINT 'UNSAFE DEMO: trigger DISABLED. Overlapping pending bookings ready.';
PRINT 'Run 01b + 01c simultaneously — both will succeed without locks.';
GO
