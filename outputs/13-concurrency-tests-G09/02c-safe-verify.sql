-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 02c-safe-verify.sql
-- ============================================================================
-- SAFE DEMO: Verifies that only ONE of the overlapping bookings was approved
-- (the other failed with Msg 50000). Cleans up.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @ApprovedCount INT, @PendingCount INT, @OverlapApproved INT;

SELECT @ApprovedCount = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12'
  AND booking_status = 'approved';

SELECT @PendingCount = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12'
  AND booking_status = 'pending';

-- Verify no two approved bookings overlap
SELECT @OverlapApproved = COUNT(*)
FROM dbo.BOOKING a
JOIN dbo.BOOKING b
  ON a.space_code = b.space_code
 AND a.booking_id < b.booking_id
WHERE a.space_code = 'TEST-CONC-001'
  AND a.booking_status = 'approved'
  AND b.booking_status = 'approved'
  AND a.requested_start_time < b.requested_end_time
  AND a.requested_end_time   > b.requested_start_time;

PRINT '';
PRINT '========== SAFE DEMO RESULT (conflict) ==========';
PRINT 'Approved: ' + CAST(@ApprovedCount AS VARCHAR(5))
    + '  Pending: ' + CAST(@PendingCount AS VARCHAR(5))
    + '  (expected 1 approved / 1 pending)';

IF @ApprovedCount = 1 AND @OverlapApproved = 0
BEGIN
    PRINT 'PREVENTION WORKS: Serialized by SERIALIZABLE + UPDLOCK — only one approved.';
    PRINT '';

    SELECT 'PREVENTED' AS result,
           booking_id,
           requested_start_time,
           requested_end_time,
           booking_status
    FROM dbo.BOOKING
    WHERE space_code = 'TEST-CONC-001'
      AND requested_start_time >= '2027-01-11'
      AND requested_start_time <  '2027-01-12'
    ORDER BY requested_start_time;
END
ELSE IF @OverlapApproved > 0
    PRINT 'FAIL: Approved bookings still overlap!';
ELSE
    PRINT 'UNEXPECTED: approved=' + CAST(@ApprovedCount AS VARCHAR(5));

-- Cleanup conflict pair
DELETE FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12';

PRINT 'Safe test bookings cleaned up.';
GO
