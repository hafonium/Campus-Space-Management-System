-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 03b-session-B-nonconflict-G09.sql
-- Approves the 10:00-11:00 booking. Run simultaneously with 03a.
-- Expected: approval succeeds (disjoint times).
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @TargetId INT, @StaffId INT;

SELECT TOP 1 @TargetId = booking_id
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time = '2027-01-12 10:00:00'
  AND booking_status = 'pending'
ORDER BY booking_id;

SELECT TOP 1 @StaffId = u.user_id
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE r.role_name IN ('facility_staff', 'facility_manager')
ORDER BY u.user_id;

IF @TargetId IS NULL
    THROW 50010, 'Fixture not found. Run 01-setup-concurrency-tests-G09.sql first.', 1;

PRINT 'Session B approving booking ' + CAST(@TargetId AS VARCHAR(10)) + ' ...';

EXEC dbo.sp_approve_booking
    @booking_id        = @TargetId,
    @decision_staff_id = @StaffId,
    @decision_note     = 'Late-morning meeting.';

PRINT 'Session B: SUCCEEDED (expected).';
GO
