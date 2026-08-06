-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: outputs/13-concurrency-tests-G09/01-setup-concurrency-tests-G09.sql
-- Purpose: Prepare the fixtures used by the concurrency test scripts.
--          Creates the supporting index and approval stored procedure, then
--          inserts two pairs of pending bookings:
--            * conflict pair    — GSP-1, overlapping windows
--            * non-conflict pair — GSP-1, disjoint windows
-- Prerequisite: outputs/05-db-definition-G09.sql + 06-sample-data-G09.sql +
--               outputs/10-schema-migration-G09.sql (Phase 2 schema)
-- Usage:       sqlcmd -b -i outputs/13-concurrency-tests-G09/01-setup-concurrency-tests-G09.sql
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- ============================================================================
-- Part A: supporting index for key-range locking (idempotent)
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'ix_booking_overlap_lock'
                 AND object_id = OBJECT_ID('dbo.BOOKING'))
    CREATE INDEX ix_booking_overlap_lock
        ON dbo.BOOKING (space_code, booking_status, requested_start_time, requested_end_time);
GO

-- ============================================================================
-- Part B: safe approval stored procedure (idempotent)
-- Uses SERIALIZABLE + UPDLOCK so concurrent approvals of overlapping bookings
-- on the same space cannot both succeed (see 11-concurrency-design-G09.md).
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_approve_booking
    @booking_id         INT,
    @decision_staff_id  INT,
    @decision_note      VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.BOOKING WITH (UPDLOCK, SERIALIZABLE)
                       WHERE booking_id = @booking_id AND booking_status = 'pending')
        BEGIN
            ;THROW 50001, 'Booking not found, already processed, or not pending.', 1;
        END

        UPDATE dbo.BOOKING
        SET booking_status    = 'approved',
            decision_staff_id = @decision_staff_id,
            decision_time     = SYSDATETIME(),
            decision_note     = @decision_note
        WHERE booking_id = @booking_id;

        COMMIT TRANSACTION;
        SELECT @booking_id AS approved_booking_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- Part C: fixtures (pending bookings)
-- Uses demo space CR-DC-1302 whose usage policy is a migrated Phase 1 policy
-- (legacy_policy_text IS NOT NULL), so pending bookings stay PENDING instead
-- of being auto-approved by the trigger — this keeps the staff-approval race
-- exercisable via dbo.sp_approve_booking. A generated facility_staff user acts
-- as decision maker. Windows are placed far in the future so no existing
-- approved booking interferes.
-- ============================================================================

DECLARE @StaffId INT = (
    SELECT TOP 1 u.user_id
    FROM dbo.[USER] u
    JOIN dbo.ROLE r ON r.role_id = u.role_id
    WHERE r.role_name = 'facility_staff' AND u.email LIKE 'gen-%@campus.example'
    ORDER BY u.user_id
);

DECLARE @SpaceCode VARCHAR(50) = 'CR-DC-1302';

-- conflict pair: 2027-01-11 09:00-11:00 and 10:00-12:00 (overlap 10:00-11:00)
INSERT INTO dbo.BOOKING (requester_id, space_code, requested_start_time,
    requested_end_time, purpose, expected_participants, booking_status)
VALUES
    (1, @SpaceCode, '2027-01-11 09:00:00', '2027-01-11 11:00:00',
     'lecture', 30, 'pending');

INSERT INTO dbo.BOOKING (requester_id, space_code, requested_start_time,
    requested_end_time, purpose, expected_participants, booking_status)
VALUES
    (1, @SpaceCode, '2027-01-11 10:00:00', '2027-01-11 12:00:00',
     'lecture', 25, 'pending');

-- non-conflict pair: 2027-01-12 08:00-09:00 and 10:00-11:00 (disjoint)
INSERT INTO dbo.BOOKING (requester_id, space_code, requested_start_time,
    requested_end_time, purpose, expected_participants, booking_status)
VALUES
    (1, @SpaceCode, '2027-01-12 08:00:00', '2027-01-12 09:00:00',
     'meeting', 10, 'pending');

INSERT INTO dbo.BOOKING (requester_id, space_code, requested_start_time,
    requested_end_time, purpose, expected_participants, booking_status)
VALUES
    (1, @SpaceCode, '2027-01-12 10:00:00', '2027-01-12 11:00:00',
     'meeting', 10, 'pending');

-- Show the generated fixture ids for use in the two-session test scripts.
SELECT booking_id, requested_start_time, requested_end_time, booking_status
FROM dbo.BOOKING
WHERE space_code = @SpaceCode
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-13'
ORDER BY requested_start_time;

PRINT 'Concurrency test fixtures ready (staff id = ' + CAST(@StaffId AS VARCHAR(10)) + ').';
PRINT 'Expected fixture ids: 2 overlapping pairs on ' + @SpaceCode + '.';
GO
