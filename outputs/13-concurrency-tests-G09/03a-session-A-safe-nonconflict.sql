-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 03a-session-A-safe-nonconflict.sql
-- ============================================================================
-- SAFE DEMO: Disjoint times — no overlap, no blocking.
-- Approves the 08:00-09:00 booking. Run simultaneously with 03b.
-- Expected: succeeds (no conflict, no false blocking).
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- Create non-overlapping pending bookings if needed
DECLARE @RequesterId INT;
SELECT TOP 1 @RequesterId = user_id FROM dbo.[USER] ORDER BY user_id;

IF NOT EXISTS (SELECT 1 FROM dbo.BOOKING
               WHERE space_code = 'TEST-CONC-001'
                 AND requested_start_time = '2027-01-12 08:00:00')
BEGIN
    INSERT INTO dbo.BOOKING
        (requester_id, space_code, requested_start_time, requested_end_time,
         purpose, expected_participants, booking_status)
    VALUES
        (@RequesterId, 'TEST-CONC-001', '2027-01-12 08:00:00', '2027-01-12 09:00:00',
         'meeting', 10, 'pending'),
        (@RequesterId, 'TEST-CONC-001', '2027-01-12 10:00:00', '2027-01-12 11:00:00',
         'meeting', 10, 'pending');
END

DECLARE @TargetId INT, @StaffId INT;

SELECT TOP 1 @TargetId = booking_id
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time = '2027-01-12 08:00:00'
  AND booking_status = 'pending'
ORDER BY booking_id;

SELECT TOP 1 @StaffId = u.user_id
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE r.role_name IN ('facility_staff', 'facility_manager')
ORDER BY u.user_id;

IF @TargetId IS NULL
    THROW 50010, 'Fixture not found.', 1;

PRINT 'Session A (non-conflict) approving booking ' + CAST(@TargetId AS VARCHAR(10)) + ' ...';

EXEC dbo.sp_approve_booking
    @booking_id         = @TargetId,
    @decision_staff_id  = @StaffId,
    @decision_note      = 'Morning meeting.',
    @hold_lock_seconds  = 5;

PRINT 'Session A (non-conflict): SUCCEEDED (expected).';
GO
