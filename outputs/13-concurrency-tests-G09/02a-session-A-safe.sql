-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 02a-session-A-safe.sql
-- ============================================================================
-- SAFE DEMO: Uses sp_approve_booking with SERIALIZABLE + UPDLOCK.
-- Approves the 09:00-11:00 booking. Run simultaneously with 02b.
-- Expected: succeeds.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- Re-create overlapping pending bookings (cleaned up by 01d)
DECLARE @RequesterId INT;
SELECT TOP 1 @RequesterId = user_id FROM dbo.[USER] ORDER BY user_id;

IF NOT EXISTS (SELECT 1 FROM dbo.BOOKING
               WHERE space_code = 'TEST-CONC-001'
                 AND requested_start_time = '2027-01-11 09:00:00')
BEGIN
    INSERT INTO dbo.BOOKING
        (requester_id, space_code, requested_start_time, requested_end_time,
         purpose, expected_participants, booking_status)
    VALUES
        (@RequesterId, 'TEST-CONC-001', '2027-01-11 09:00:00', '2027-01-11 11:00:00',
         'lecture', 30, 'pending'),
        (@RequesterId, 'TEST-CONC-001', '2027-01-11 10:00:00', '2027-01-11 12:00:00',
         'lecture', 25, 'pending');
END

DECLARE @TargetId INT, @StaffId INT;

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
    THROW 50010, 'Fixture not found. Run 02a alone first to create bookings.', 1;

PRINT 'Session A (SAFE) approving booking ' + CAST(@TargetId AS VARCHAR(10)) + ' ...';

EXEC dbo.sp_approve_booking
    @booking_id         = @TargetId,
    @decision_staff_id  = @StaffId,
    @decision_note      = 'SAFE approval (Session A).',
    @hold_lock_seconds  = 10;

PRINT 'Session A (SAFE): SUCCEEDED (expected).';
GO
