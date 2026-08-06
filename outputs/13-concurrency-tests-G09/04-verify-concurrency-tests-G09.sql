-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: outputs/13-concurrency-tests-G09/04-verify-concurrency-tests-G09.sql
-- Purpose: Verify the outcome of both concurrency tests and clean up the
--          fixtures. Idempotent; safe to run at any point after the sessions.
-- Expected:
--   * Conflict pair    — exactly ONE approved, one still pending
--   * Non-conflict pair — BOTH approved
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @ConflictApproved INT, @ConflictPending INT,
        @NonConflictApproved INT;

SELECT @ConflictApproved = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'CR-DC-1302'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12'
  AND booking_status = 'approved';

SELECT @ConflictPending = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'CR-DC-1302'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12'
  AND booking_status = 'pending';

SELECT @NonConflictApproved = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'CR-DC-1302'
  AND requested_start_time >= '2027-01-12'
  AND requested_start_time <  '2027-01-13'
  AND booking_status = 'approved';

PRINT '=== Concurrency test results ===';
PRINT 'Conflict pair    : approved=' + CAST(@ConflictApproved AS VARCHAR(10))
    + ' pending=' + CAST(@ConflictPending AS VARCHAR(10))
    + '  (expected 1 approved / 1 pending)';
PRINT 'Non-conflict pair: approved=' + CAST(@NonConflictApproved AS VARCHAR(10))
    + '  (expected 2 approved)';

IF @ConflictApproved <> 1 OR @ConflictPending <> 1
    THROW 50011, 'FAIL: conflict test produced the wrong result.', 1;

IF @NonConflictApproved <> 2
    THROW 50012, 'FAIL: non-conflict test produced the wrong result.', 1;

PRINT 'PASS: concurrency tests behave as designed.';

-- cleanup fixtures (test data only; the 100k generated dataset is untouched)
DELETE FROM dbo.BOOKING
WHERE space_code = 'CR-DC-1302'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-13';

PRINT 'Fixtures removed.';
GO
