-- ============================================================================
-- Campus Space Management System — Concurrency Implementation (G09)
-- Target: Microsoft SQL Server
-- Prerequisite: 10-schema-migration-G09.sql (Phase 2 schema)
-- ============================================================================
-- This script implements the concurrency design described in
-- 11-concurrency-design-G09.md: a stored procedure that prevents write-skew
-- when two staff members approve overlapping bookings on the same space
-- simultaneously.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- ============================================================================
-- sp_approve_booking
-- ============================================================================
-- Serializes concurrent approval of overlapping bookings for the same space.
--
-- Locking strategy:
--   UPDLOCK         – acquires update locks on scanned rows, blocking any other
--                     concurrent UPDLOCK request on the same resource.
--   SERIALIZABLE    – extends all locks to end-of-transaction; key-range locks
--                     prevent phantom inserts into the scanned predicate range.
--
-- Two staff members approving bookings #A and #B that overlap on the same space:
--   Session A  →  U-locks acquired on the key range  →  Session B blocked
--   Session A  →  COMMIT  →  locks released
--   Session B  →  unblocked, rescans  →  overlap found  →  THROW 50000
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

        -- Verify the booking exists and is still pending
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.BOOKING WITH (UPDLOCK, SERIALIZABLE)
            WHERE booking_id = @booking_id
              AND booking_status = 'pending'
        )
        BEGIN
            ;THROW 50001,
                'Booking not found, already processed, or not in pending status.', 1;
        END

        -- Overlap check: scan approved bookings on the same space for time conflicts
        IF EXISTS (
            SELECT 1
            FROM dbo.BOOKING target WITH (UPDLOCK, SERIALIZABLE)
            WHERE target.booking_id = @booking_id
              AND EXISTS (
                  SELECT 1
                  FROM dbo.BOOKING existing WITH (UPDLOCK, SERIALIZABLE)
                  WHERE existing.space_code = target.space_code
                    AND existing.booking_status = 'approved'
                    AND existing.booking_id <> target.booking_id
                    AND existing.requested_start_time < target.requested_end_time
                    AND existing.requested_end_time > target.requested_start_time
              )
        )
        BEGIN
            ;THROW 50000,
                'Overlapping approved booking already exists for this space during the requested time period.', 1;
        END

        -- Approve the booking
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
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- Test Case 1 — Conflicting Approvals
-- ============================================================================
-- Two bookings on the same space with overlapping times (09:00–11:00 and
-- 10:00–12:00). When approved concurrently, only one should succeed.

/*
-- ===== STEP 1 — Setup (run once) ============================================

-- Use two existing pending bookings or create new ones.
-- Replace <staff_id> with a user_id that has role facility_staff or facility_manager.

INSERT INTO dbo.BOOKING
    (requester_id, space_code, requested_start_time, requested_end_time,
     purpose, expected_participants, booking_status)
VALUES
    (1, 'SPACE-001', '2026-09-01 09:00:00', '2026-09-01 11:00:00',
     'meeting', 10, 'pending'),
    (1, 'SPACE-001', '2026-09-01 10:00:00', '2026-09-01 12:00:00',
     'meeting', 10, 'pending');

-- Capture the two booking IDs
SELECT booking_id, space_code, requested_start_time, requested_end_time
FROM dbo.BOOKING
WHERE space_code = 'SPACE-001'
  AND booking_status = 'pending'
ORDER BY requested_start_time;

-- ===== STEP 2 — Session A (run in SSMS tab 1) ================================

BEGIN TRAN;
    EXEC dbo.sp_approve_booking
        @booking_id        = <booking_id_of_09:00_11:00>,
        @decision_staff_id = <staff_id>,
        @decision_note     = 'Approved by Session A.';
COMMIT;

-- ===== STEP 3 — Session B (run in SSMS tab 2, simultaneously with Step 2) ====

BEGIN TRAN;
    EXEC dbo.sp_approve_booking
        @booking_id        = <booking_id_of_10:00_12:00>,
        @decision_staff_id = <staff_id>,
        @decision_note     = 'Approved by Session B.';
COMMIT;
-- Expected: Msg 50000 — Overlapping approved booking already exists

-- ===== STEP 4 — Verify =======================================================

SELECT booking_id, booking_status, requested_start_time, requested_end_time,
       decision_staff_id
FROM dbo.BOOKING
WHERE space_code = 'SPACE-001'
  AND booking_status IN ('pending', 'approved')
ORDER BY requested_start_time;

-- Expected result: 1 row approved, 1 row still pending
*/

-- ============================================================================
-- Test Case 2 — Non-Conflicting Approvals
-- ============================================================================
-- Two bookings on the same space with disjoint times (08:00–09:00 and
-- 10:00–11:00). Both should be approved successfully.

/*
-- ===== STEP 1 — Setup ========================================================

INSERT INTO dbo.BOOKING
    (requester_id, space_code, requested_start_time, requested_end_time,
     purpose, expected_participants, booking_status)
VALUES
    (1, 'SPACE-001', '2026-09-01 08:00:00', '2026-09-01 09:00:00',
     'meeting', 10, 'pending'),
    (1, 'SPACE-001', '2026-09-01 10:00:00', '2026-09-01 11:00:00',
     'meeting', 10, 'pending');

SELECT booking_id, space_code, requested_start_time, requested_end_time
FROM dbo.BOOKING
WHERE space_code = 'SPACE-001'
  AND booking_status = 'pending'
ORDER BY requested_start_time;

-- ===== STEP 2 — Session A =====================================================

BEGIN TRAN;
    EXEC dbo.sp_approve_booking
        @booking_id        = <booking_id_of_08:00_09:00>,
        @decision_staff_id = <staff_id>,
        @decision_note     = 'Morning meeting.';
COMMIT;

-- ===== STEP 3 — Session B (simultaneously) ====================================

BEGIN TRAN;
    EXEC dbo.sp_approve_booking
        @booking_id        = <booking_id_of_10:00_11:00>,
        @decision_staff_id = <staff_id>,
        @decision_note     = 'Late-morning meeting.';
COMMIT;

-- ===== STEP 4 — Verify =======================================================

SELECT booking_id, booking_status, requested_start_time, requested_end_time,
       decision_staff_id
FROM dbo.BOOKING
WHERE space_code = 'SPACE-001'
  AND booking_status = 'approved'
ORDER BY requested_start_time;

-- Expected result: BOTH bookings approved (2 rows)
*/
GO

-- ============================================================================
-- Cleanup (optional — resets test bookings)
-- ============================================================================

/*
DELETE FROM dbo.BOOKING
WHERE space_code = 'SPACE-001'
  AND booking_status IN ('pending', 'approved')
  AND requested_start_time >= '2026-09-01'
  AND requested_end_time <= '2026-09-01 12:00:00'
  AND decision_note LIKE '%Approved by Session%';

DELETE FROM dbo.BOOKING
WHERE space_code = 'SPACE-001'
  AND booking_status IN ('pending', 'approved')
  AND requested_start_time >= '2026-09-01'
  AND requested_end_time <= '2026-09-01 12:00:00';
*/
GO
