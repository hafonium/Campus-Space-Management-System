-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 04-verify-and-cleanup-G09.sql
-- Verifies both concurrency test outcomes and cleans up all test fixtures.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @ConflictApproved  INT, @ConflictPending  INT,
        @NonConflictApproved INT;

-- Conflict pair: 2027-01-11
SELECT @ConflictApproved = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12'
  AND booking_status = 'approved';

SELECT @ConflictPending = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12'
  AND booking_status = 'pending';

-- Non-conflict pair: 2027-01-12
SELECT @NonConflictApproved = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-12'
  AND requested_start_time <  '2027-01-13'
  AND booking_status = 'approved';

PRINT '========== Concurrency Test Results ==========';
PRINT 'Conflict pair    : approved=' + CAST(@ConflictApproved AS VARCHAR(10))
    + '  pending=' + CAST(@ConflictPending AS VARCHAR(10))
    + '  (expected 1 approved / 1 pending)';
PRINT 'Non-conflict pair: approved=' + CAST(@NonConflictApproved AS VARCHAR(10))
    + '          (expected 2 approved)';

IF @ConflictApproved <> 1 OR @ConflictPending <> 1
BEGIN
    PRINT 'FAIL: conflict test — wrong result.';
    THROW 50011, 'FAIL: conflict test — wrong result.', 1;
END

IF @NonConflictApproved <> 2
BEGIN
    PRINT 'FAIL: non-conflict test — wrong result.';
    THROW 50012, 'FAIL: non-conflict test — wrong result.', 1;
END

PRINT 'PASS: concurrency tests behave as designed.';

-- ============================================================================
-- Cleanup: remove test bookings, space, and policy
-- ============================================================================
DELETE FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-13';

DELETE FROM dbo.SPACE
WHERE space_code = 'TEST-CONC-001';

DELETE FROM dbo.USAGE_POLICY
WHERE policy_name = 'CONCURRENCY_TEST';

PRINT 'Test fixtures cleaned up.';
GO
