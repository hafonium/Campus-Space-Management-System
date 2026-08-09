-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 03c-safe-nonconflict-verify.sql
-- ============================================================================
-- SAFE DEMO: Verifies BOTH non-overlapping bookings were approved.
-- Cleans up all test fixtures (space, policy, bookings).
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @ApprovedCount INT;

SELECT @ApprovedCount = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-12'
  AND requested_start_time <  '2027-01-13'
  AND booking_status = 'approved';

PRINT '';
PRINT '========== SAFE DEMO RESULT (non-conflict) ==========';
PRINT 'Approved: ' + CAST(@ApprovedCount AS VARCHAR(5))
    + '  (expected 2 approved)';

IF @ApprovedCount = 2
BEGIN
    PRINT 'NO FALSE BLOCKING: Disjoint bookings both approved — locking does not block unrelated operations.';
    PRINT '';

    SELECT 'APPROVED' AS result,
           booking_id,
           requested_start_time,
           requested_end_time,
           booking_status
    FROM dbo.BOOKING
    WHERE space_code = 'TEST-CONC-001'
      AND booking_status = 'approved'
      AND requested_start_time >= '2027-01-12'
      AND requested_start_time <  '2027-01-13'
    ORDER BY requested_start_time;
END
ELSE
    PRINT 'UNEXPECTED: approved=' + CAST(@ApprovedCount AS VARCHAR(5));

-- ============================================================================
-- Final cleanup: remove all test bookings, space, and policy
-- ============================================================================
DELETE FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001';

DELETE FROM dbo.SPACE
WHERE space_code = 'TEST-CONC-001';

DELETE FROM dbo.USAGE_POLICY
WHERE policy_name = 'CONCURRENCY_TEST';

PRINT '';
PRINT 'All test fixtures removed.';
GO
