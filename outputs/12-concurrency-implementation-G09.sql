-- ============================================================================
-- Campus Space Management System — Concurrency Implementation (G09)
-- Target: SQL Server
-- ============================================================================
-- Prerequisite:  05-db-definition-G09.sql + 06-sample-data-G09.sql
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- ============================================================================
-- Part 1: Supporting Index
-- ============================================================================
-- Enables key-range locking at row granularity under SERIALIZABLE isolation.
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'ix_booking_overlap_lock'
                 AND object_id = OBJECT_ID('dbo.BOOKING'))
    CREATE INDEX ix_booking_overlap_lock
        ON dbo.BOOKING (space_code, booking_status, requested_start_time, requested_end_time);
GO

-- ============================================================================
-- Part 2: Modified Trigger — one-line fix (WITH UPDLOCK, SERIALIZABLE)
-- ============================================================================

ALTER TRIGGER dbo.trg_booking_enforce_rules
ON dbo.BOOKING
INSTEAD OF INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Rule 1: Unavailable space gate
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.SPACE s ON i.space_code = s.space_code
        WHERE s.current_status IN ('under_maintenance','temporarily_closed','retired')
    )
    BEGIN
        ;THROW 50000, 'Cannot create or update a booking referencing a space that is under maintenance, temporarily closed, or retired.', 1;
    END

    -- Rule 2: Overlapping approved booking prevention
    --   WITH (UPDLOCK, SERIALIZABLE): U-locks block concurrent overlap checks
    --   on matching rows; SERIALIZABLE holds locks to EOT + key-range locking
    --   prevents phantom inserts.
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.booking_status = 'approved'
          AND EXISTS (
              SELECT 1
              FROM dbo.BOOKING b WITH (UPDLOCK, SERIALIZABLE)
              WHERE b.space_code = i.space_code
                AND b.booking_status = 'approved'
                AND b.booking_id <> i.booking_id
                AND b.requested_start_time < i.requested_end_time
                AND b.requested_end_time > i.requested_start_time
          )
    )
    BEGIN
        ;THROW 50000, 'Overlapping approved booking already exists for this space during the requested time period.', 1;
    END

    -- Rule 3: Approval / Rejection role authorization
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.decision_staff_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.[USER] u
              WHERE u.user_id = i.decision_staff_id
                AND u.role IN ('facility_staff', 'facility_manager')
          )
    )
    BEGIN
        ;THROW 50000, 'Only a user with role facility_staff or facility_manager may be recorded as the decision staff on a booking.', 1;
    END

    -- Rule 4: Check-in / Completion role authorization
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE (
              i.check_in_staff_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.[USER] u
                  WHERE u.user_id = i.check_in_staff_id
                    AND u.role = 'facility_staff'
              )
          )
          OR (
              i.completion_staff_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.[USER] u
                  WHERE u.user_id = i.completion_staff_id
                    AND u.role = 'facility_staff'
              )
          )
    )
    BEGIN
        ;THROW 50000, 'Only a user with role facility_staff may be recorded as check-in or completion staff on a booking.', 1;
    END

    -- Forward valid operations
    IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        UPDATE t
        SET
            t.requester_id          = i.requester_id,
            t.space_code            = i.space_code,
            t.requested_start_time  = i.requested_start_time,
            t.requested_end_time    = i.requested_end_time,
            t.purpose               = i.purpose,
            t.expected_participants = i.expected_participants,
            t.booking_status        = i.booking_status,
            t.decision_staff_id     = i.decision_staff_id,
            t.decision_time         = i.decision_time,
            t.decision_note         = i.decision_note,
            t.rejection_reason      = i.rejection_reason,
            t.actual_start_time     = i.actual_start_time,
            t.check_in_staff_id     = i.check_in_staff_id,
            t.initial_condition     = i.initial_condition,
            t.actual_end_time       = i.actual_end_time,
            t.completion_staff_id   = i.completion_staff_id,
            t.final_condition       = i.final_condition,
            t.usage_notes           = i.usage_notes
        FROM dbo.BOOKING t
        INNER JOIN inserted i ON t.booking_id = i.booking_id;
    END
    ELSE
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
        FROM inserted;
    END
END;
GO

-- ============================================================================
-- Part 3: Safe Approval Stored Procedure
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
-- Part 4: Test 1 — Concurrent Conflicting Approvals (MUST FAIL one)
-- ============================================================================
--
-- Two bookings on CS-101 with overlapping time: 09:00-11:00 and 10:00-12:00.
-- When approved concurrently, only ONE should succeed.
--

/*
-- === STEP 1 — Setup (run once) ==============================================

INSERT INTO dbo.BOOKING (requester_id, space_code, requested_start_time,
    requested_end_time, purpose, expected_participants, booking_status)
VALUES
    (1, 'CS-101', '2026-08-10 09:00:00', '2026-08-10 11:00:00',
     'lecture', 30, 'pending'),
    (1, 'CS-101', '2026-08-10 10:00:00', '2026-08-10 12:00:00',
     'lecture', 25, 'pending');

-- Write down the two booking IDs returned:
SELECT booking_id, space_code, requested_start_time, requested_end_time
FROM dbo.BOOKING
WHERE space_code = 'CS-101' AND booking_status = 'pending'
ORDER BY requested_start_time;

-- === STEP 2 — Session A (SSMS tab 1) ========================================

BEGIN TRAN;
    EXEC dbo.sp_approve_booking
        @booking_id        = <booking_id_1>,    -- first pending booking
        @decision_staff_id = <facility_staff_id>,
        @decision_note     = 'Approved by Session A.';
COMMIT;

-- === STEP 3 — Session B (SSMS tab 2, execute simultaneously) ================

BEGIN TRAN;
    EXEC dbo.sp_approve_booking
        @booking_id        = <booking_id_2>,    -- second pending booking
        @decision_staff_id = <facility_staff_id>,
        @decision_note     = 'Approved by Session B.';
COMMIT;
-- Expected: Msg 50000 — Overlapping approved booking already exists

-- === STEP 4 — Verify =========================================================

SELECT booking_id, booking_status, requested_start_time, requested_end_time
FROM dbo.BOOKING
WHERE space_code = 'CS-101'
  AND booking_status IN ('pending', 'approved')
ORDER BY requested_start_time;
-- Expected: 1 approved, 1 still pending (or rejected after fail)
*/

-- ============================================================================
-- Part 5: Test 2 — Concurrent Non-Conflicting Approvals (BOTH succeed)
-- ============================================================================
--
-- Two bookings on CS-MEET: 08:00-09:00 and 10:00-11:00 (no overlap).
-- Both should be approved successfully.
--

/*
-- === STEP 1 — Setup ==========================================================

INSERT INTO dbo.BOOKING (requester_id, space_code, requested_start_time,
    requested_end_time, purpose, expected_participants, booking_status)
VALUES
    (1, 'CS-MEET', '2026-08-10 08:00:00', '2026-08-10 09:00:00',
     'meeting', 10, 'pending'),
    (1, 'CS-MEET', '2026-08-10 10:00:00', '2026-08-10 11:00:00',
     'meeting', 10, 'pending');

SELECT booking_id, space_code, requested_start_time, requested_end_time
FROM dbo.BOOKING
WHERE space_code = 'CS-MEET' AND booking_status = 'pending'
ORDER BY requested_start_time;

-- === STEP 2 — Session A ======================================================

BEGIN TRAN;
    EXEC dbo.sp_approve_booking @booking_id = <id_a>,
        @decision_staff_id = <facility_staff_id>,
        @decision_note = 'Morning meeting.';
COMMIT;

-- === STEP 3 — Session B (simultaneously) =====================================

BEGIN TRAN;
    EXEC dbo.sp_approve_booking @booking_id = <id_b>,
        @decision_staff_id = <facility_staff_id>,
        @decision_note = 'Late-morning meeting.';
COMMIT;

-- === STEP 4 — Verify =========================================================

SELECT booking_id, booking_status, requested_start_time, requested_end_time
FROM dbo.BOOKING
WHERE space_code = 'CS-MEET' AND booking_status = 'approved'
ORDER BY requested_start_time;
-- Expected: BOTH approved (2 rows)
*/
GO
