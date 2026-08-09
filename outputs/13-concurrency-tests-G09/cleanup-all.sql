-- ============================================================================
-- Campus Space Management System (G09) — Concurrency Tests
-- File: cleanup-all.sql
-- ============================================================================
-- Removes ALL concurrency test fixtures regardless of current state.
-- Safe to run at any time. Does not affect non-test data.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

PRINT 'Cleaning up concurrency test data...';

DELETE FROM dbo.ACKNOWLEDGEMENT
WHERE booking_id IN (
    SELECT booking_id FROM dbo.BOOKING WHERE space_code = 'TEST-CONC-001'
);

DELETE FROM dbo.BOOKING
WHERE space_code = 'TEST-CONC-001';

DELETE FROM dbo.SPACE
WHERE space_code = 'TEST-CONC-001';

DELETE FROM dbo.USAGE_POLICY
WHERE policy_name = 'CONCURRENCY_TEST';

-- Re-enable trigger if previously disabled
IF EXISTS (
    SELECT 1 FROM sys.triggers
    WHERE name = 'trg_booking_enforce_rules'
      AND is_disabled = 1
)
BEGIN
    ENABLE TRIGGER dbo.trg_booking_enforce_rules ON dbo.BOOKING;
    PRINT 'Trigger trg_booking_enforce_rules RE-ENABLED.';
END

PRINT 'All concurrency test fixtures removed.';
GO
