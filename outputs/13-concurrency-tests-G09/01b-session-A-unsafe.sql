-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 01b-session-A-unsafe.sql
-- ============================================================================
-- UNSAFE DEMO: Raw UPDATE with no locking, no trigger (trigger is DISABLED).
-- Approves the 09:00-11:00 booking. Run simultaneously with 01c.
-- Expected: succeeds (write-skew will happen because no protection).
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @RequesterId INT, @TargetId INT, @StaffId INT;

-- Auto-create bookings if fixture missing (idempotent)
SELECT TOP 1 @RequesterId = user_id FROM dbo.[USER] ORDER BY user_id;

IF NOT EXISTS (SELECT 1 FROM dbo.BOOKING
               WHERE space_code = 'TEST-CONC-001'
                 AND requested_start_time = '2027-01-11 09:00:00')
BEGIN
    PRINT 'Creating fixtures...';
    INSERT INTO dbo.BOOKING
        (requester_id, space_code, requested_start_time, requested_end_time,
         purpose, expected_participants, booking_status)
    VALUES
        (@RequesterId, 'TEST-CONC-001', '2027-01-11 09:00:00', '2027-01-11 11:00:00',
         'lecture', 30, 'pending'),
        (@RequesterId, 'TEST-CONC-001', '2027-01-11 10:00:00', '2027-01-11 12:00:00',
         'lecture', 25, 'pending');
END

SELECT TOP 1 @TargetId = booking_id
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time = '2027-01-11 09:00:00'
  AND booking_status = 'pending'
ORDER BY booking_id;

SELECT TOP 1 @StaffId = u.user_id
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE r.role_name IN ('facility_staff', 'facility_manager')
ORDER BY u.user_id;

IF @TargetId IS NULL
    THROW 50010, 'Fixture not found. Run 01a-demo-conflict-setup.sql first.', 1;

PRINT 'Session A (UNSAFE) approving booking ' + CAST(@TargetId AS VARCHAR(10)) + ' ...';

BEGIN TRANSACTION;

-- Raw UPDATE — no UPDLOCK, no SERIALIZABLE, no trigger check
UPDATE dbo.BOOKING
SET booking_status    = 'approved',
    decision_staff_id = @StaffId,
    decision_time     = SYSDATETIME(),
    decision_note     = 'UNSAFE approval (Session A).'
WHERE booking_id = @TargetId;

PRINT '--- SESSION A: Lock held. Run Session B NOW (within 10 seconds). ---';
WAITFOR DELAY '00:00:10';

COMMIT TRANSACTION;

PRINT 'Session A (UNSAFE): SUCCEEDED.';
GO
