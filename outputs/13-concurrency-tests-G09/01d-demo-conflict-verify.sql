-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: 01d-demo-conflict-verify.sql
-- ============================================================================
-- UNSAFE DEMO: Verifies that BOTH bookings were approved (write-skew confirmed)
-- and that their time periods overlap. Then re-enables the trigger and
-- cleans up.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

DECLARE @ApprovedCount INT, @OverlapExists INT;

-- Count approved bookings for the conflict pair
SELECT @ApprovedCount = COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time = '2027-01-11 09:00:00'
  AND requested_end_time   = '2027-01-11 11:00:00'
  AND booking_status = 'approved';

SELECT @ApprovedCount = @ApprovedCount + COUNT(*)
FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time = '2027-01-11 10:00:00'
  AND requested_end_time   = '2027-01-11 12:00:00'
  AND booking_status = 'approved';

-- Verify the two approved bookings actually overlap
SELECT @OverlapExists = COUNT(*)
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
PRINT '========== UNSAFE DEMO RESULT ==========';

IF @ApprovedCount = 2 AND @OverlapExists >= 1
BEGIN
    PRINT 'CONFLICT CONFIRMED: Both bookings approved and overlap!';
    PRINT 'Write-skew double booking occurred — exactly as predicted.';
    PRINT '';

    -- Show the two overlapping approved bookings
    SELECT 'DOUBLE-BOOKING!' AS result,
           booking_id,
           space_code,
           requested_start_time,
           requested_end_time,
           booking_status,
           decision_note
    FROM dbo.BOOKING
    WHERE space_code = 'TEST-CONC-001'
      AND requested_start_time >= '2027-01-11'
      AND requested_start_time <  '2027-01-12'
      AND booking_status = 'approved'
    ORDER BY requested_start_time;
END
ELSE
BEGIN
    PRINT 'UNEXPECTED: approved=' + CAST(@ApprovedCount AS VARCHAR(5))
        + '  overlaps=' + CAST(@OverlapExists AS VARCHAR(5));
    PRINT '(Expected 2 approved, >=1 overlap)';
END
GO

-- ============================================================================
-- Re-enable trigger and cleanup unsafe test data
-- ============================================================================
ENABLE TRIGGER dbo.trg_booking_enforce_rules ON dbo.BOOKING;
GO

PRINT 'Trigger RE-ENABLED.';

DELETE FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001'
  AND requested_start_time >= '2027-01-11'
  AND requested_start_time <  '2027-01-12';

PRINT 'Unsafe test bookings cleaned up.';
PRINT 'Ready for SAFE demo (02a + 02b).';
GO
