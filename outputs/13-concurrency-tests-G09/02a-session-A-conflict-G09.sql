-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: outputs/13-concurrency-tests-G09/02a-session-A-conflict-G09.sql
-- Purpose: Session A of the conflicting-approval test. Approves the FIRST
--          pending booking of the overlap pair via dbo.sp_approve_booking.
-- Run together with 02b-session-B-conflict-G09.sql (start both ~simultaneously).
-- Expected: Session A approves; Session B fails with Msg 50000.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @TargetBookingId INT = (
    SELECT TOP 1 booking_id
    FROM dbo.BOOKING
    WHERE space_code = 'CR-DC-1302'
      AND requested_start_time = '2027-01-11 09:00:00'
      AND booking_status = 'pending'
    ORDER BY booking_id
);

DECLARE @StaffId INT = (
    SELECT TOP 1 u.user_id
    FROM dbo.[USER] u
    JOIN dbo.ROLE r ON r.role_id = u.role_id
    WHERE r.role_name = 'facility_staff' AND u.email LIKE 'gen-%@campus.example'
    ORDER BY u.user_id
);

IF @TargetBookingId IS NULL
    THROW 50010, 'Fixture not found: run 01-setup-concurrency-tests-G09.sql first.', 1;

PRINT 'Session A approving booking ' + CAST(@TargetBookingId AS VARCHAR(10)) + ' ...';

EXEC dbo.sp_approve_booking
    @booking_id        = @TargetBookingId,
    @decision_staff_id = @StaffId,
    @decision_note     = 'Concurrent approval (Session A).';

PRINT 'Session A: approval SUCCEEDED (expected).';
GO
