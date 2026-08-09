-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 02b-session-B-safe.sql
-- ============================================================================
-- SAFE DEMO: Uses sp_approve_booking with SERIALIZABLE + UPDLOCK.
-- Approves the 10:00-12:00 booking. Run simultaneously with 02a.
-- Expected: FAILS with Msg 50000 — blocked by A's U-locks, then rescans
--           and detects the overlap that A committed.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @TargetId INT, @StaffId INT;

SELECT TOP 1 @TargetId = booking_id
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time = '2027-01-11 10:00:00'
  AND booking_status = 'pending'
ORDER BY booking_id;

SELECT TOP 1 @StaffId = u.user_id
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE r.role_name IN ('facility_staff', 'facility_manager')
ORDER BY u.user_id;

IF @TargetId IS NULL
    THROW 50010, 'Fixture not found.', 1;

PRINT 'Session B (SAFE) approving booking ' + CAST(@TargetId AS VARCHAR(10)) + ' ...';

EXEC dbo.sp_approve_booking
    @booking_id        = @TargetId,
    @decision_staff_id = @StaffId,
    @decision_note     = 'SAFE approval (Session B).';

PRINT 'Session B (SAFE): SUCCEEDED (UNEXPECTED — should have failed!).';
GO
