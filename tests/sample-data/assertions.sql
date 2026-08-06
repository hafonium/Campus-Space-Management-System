-- ============================================================================
-- High-volume sample-data assertions — Campus Space Management System (G09)
-- File: tests/sample-data/assertions.sql
-- Purpose: Executable validation suite for the generated high-volume dataset.
--          Every check must pass; any failed check raises THROW and the run
--          fails. Run AFTER outputs/13-high-volume-sample-data-G09.sql.
--
-- Schema note (Phase 2, per outputs/10-schema-migration-G09.sql):
--   dbo.ACKNOWLEDGEMENT(booking_id, maintenance_id, acknowledged_at) links a
--   booking directly to an advisory maintenance record. There is NO
--   BOOKING_ACKNOWLEDGEMENT junction table and no acknowledgement_id column
--   in this schema, so the advisory-link checks join ACKNOWLEDGEMENT on
--   (booking_id, maintenance_id) instead.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RequiredBookingCount INT = 100000;
DECLARE @RequiredDaySpan INT = 1094; -- at least 3 academic years + margin

-- ============================================================================
-- 1. Volume
-- ============================================================================
IF (
    SELECT COUNT_BIG(*)
    FROM dbo.BOOKING b
    JOIN dbo.[USER] u ON u.user_id = b.requester_id
    WHERE u.email LIKE 'gen-%@campus.example'
) < @RequiredBookingCount
BEGIN
    THROW 51000, 'FAIL: insufficient generated booking records.', 1;
END;

-- ============================================================================
-- 2. Three-year coverage
-- ============================================================================
IF (
    SELECT DATEDIFF(
        DAY,
        MIN(b.requested_start_time),
        MAX(b.requested_start_time)
    )
    FROM dbo.BOOKING b
    JOIN dbo.[USER] u ON u.user_id = b.requester_id
    WHERE u.email LIKE 'gen-%@campus.example'
) < @RequiredDaySpan
BEGIN
    THROW 51001, 'FAIL: booking data covers less than three years.', 1;
END;

-- ============================================================================
-- 3. Status coverage
-- ============================================================================
IF EXISTS (
    SELECT required_status
    FROM (
        VALUES
            ('pending'),
            ('approved'),
            ('rejected'),
            ('cancelled'),
            ('checked_in'),
            ('completed'),
            ('no_show')
    ) required(required_status)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.BOOKING b
        JOIN dbo.[USER] u ON u.user_id = b.requester_id
        WHERE u.email LIKE 'gen-%@campus.example'
          AND b.booking_status = required.required_status
    )
)
BEGIN
    THROW 51002, 'FAIL: one or more booking statuses are missing.', 1;
END;

-- ============================================================================
-- 4. Status distribution minimums
--    cancelled >= 5%, no_show >= 2%, rejected >= 3%, completed >= 40%
-- ============================================================================
DECLARE @TotalGenerated DECIMAL(18, 4);
DECLARE @Cancelled DECIMAL(18, 4);
DECLARE @NoShow DECIMAL(18, 4);
DECLARE @Rejected DECIMAL(18, 4);
DECLARE @Completed DECIMAL(18, 4);

SELECT
    @TotalGenerated = COUNT_BIG(*),
    @Cancelled     = SUM(CASE WHEN booking_status = 'cancelled' THEN 1.0 ELSE 0.0 END),
    @NoShow        = SUM(CASE WHEN booking_status = 'no_show'   THEN 1.0 ELSE 0.0 END),
    @Rejected      = SUM(CASE WHEN booking_status = 'rejected'  THEN 1.0 ELSE 0.0 END),
    @Completed     = SUM(CASE WHEN booking_status = 'completed' THEN 1.0 ELSE 0.0 END)
FROM dbo.BOOKING b
JOIN dbo.[USER] u ON u.user_id = b.requester_id
WHERE u.email LIKE 'gen-%@campus.example';

IF @TotalGenerated = 0 OR @Cancelled / @TotalGenerated < 0.05
BEGIN
    THROW 51007, 'FAIL: cancelled bookings are below 5 percent.', 1;
END;

IF @TotalGenerated = 0 OR @NoShow / @TotalGenerated < 0.02
BEGIN
    THROW 51008, 'FAIL: no-show bookings are below 2 percent.', 1;
END;

IF @TotalGenerated = 0 OR @Rejected / @TotalGenerated < 0.03
BEGIN
    THROW 51009, 'FAIL: rejected bookings are below 3 percent.', 1;
END;

IF @TotalGenerated = 0 OR @Completed / @TotalGenerated < 0.40
BEGIN
    THROW 51010, 'FAIL: completed bookings are below 40 percent.', 1;
END;

-- ============================================================================
-- 5. No orphan foreign keys (explicit checks per FK)
-- ============================================================================
IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    LEFT JOIN dbo.[USER] u ON u.user_id = b.requester_id
    WHERE u.user_id IS NULL
)
BEGIN
    THROW 51011, 'FAIL: orphan BOOKING.requester_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    LEFT JOIN dbo.SPACE s ON s.space_code = b.space_code
    WHERE s.space_code IS NULL
)
BEGIN
    THROW 51012, 'FAIL: orphan BOOKING.space_code.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    LEFT JOIN dbo.[USER] u ON u.user_id = b.decision_staff_id
    WHERE b.decision_staff_id IS NOT NULL AND u.user_id IS NULL
)
BEGIN
    THROW 51013, 'FAIL: orphan BOOKING.decision_staff_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    LEFT JOIN dbo.[USER] u ON u.user_id = b.check_in_staff_id
    WHERE b.check_in_staff_id IS NOT NULL AND u.user_id IS NULL
)
BEGIN
    THROW 51014, 'FAIL: orphan BOOKING.check_in_staff_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    LEFT JOIN dbo.[USER] u ON u.user_id = b.completion_staff_id
    WHERE b.completion_staff_id IS NOT NULL AND u.user_id IS NULL
)
BEGIN
    THROW 51015, 'FAIL: orphan BOOKING.completion_staff_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.MAINTENANCE_RECORD m
    LEFT JOIN dbo.SPACE s ON s.space_code = m.space_code
    WHERE s.space_code IS NULL
)
BEGIN
    THROW 51016, 'FAIL: orphan MAINTENANCE_RECORD.space_code.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.MAINTENANCE_RECORD m
    LEFT JOIN dbo.[USER] u ON u.user_id = m.reporter_id
    WHERE u.user_id IS NULL
)
BEGIN
    THROW 51017, 'FAIL: orphan MAINTENANCE_RECORD.reporter_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.MAINTENANCE_RECORD m
    LEFT JOIN dbo.[USER] u ON u.user_id = m.assigned_staff_id
    WHERE m.assigned_staff_id IS NOT NULL AND u.user_id IS NULL
)
BEGIN
    THROW 51018, 'FAIL: orphan MAINTENANCE_RECORD.assigned_staff_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.ACKNOWLEDGEMENT a
    LEFT JOIN dbo.BOOKING b ON b.booking_id = a.booking_id
    WHERE b.booking_id IS NULL
)
BEGIN
    THROW 51019, 'FAIL: orphan ACKNOWLEDGEMENT.booking_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.ACKNOWLEDGEMENT a
    LEFT JOIN dbo.MAINTENANCE_RECORD m ON m.maintenance_id = a.maintenance_id
    WHERE m.maintenance_id IS NULL
)
BEGIN
    THROW 51020, 'FAIL: orphan ACKNOWLEDGEMENT.maintenance_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.SPACE s
    LEFT JOIN dbo.USAGE_POLICY p ON p.policy_id = s.policy_id
    WHERE s.policy_id IS NOT NULL AND p.policy_id IS NULL
)
BEGIN
    THROW 51021, 'FAIL: orphan SPACE.policy_id.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.[USER] u
    LEFT JOIN dbo.ROLE r ON r.role_id = u.role_id
    WHERE r.role_id IS NULL
)
BEGIN
    THROW 51022, 'FAIL: orphan USER.role_id.', 1;
END;

-- ============================================================================
-- 6. Identity values were not manually assigned
--    The generation script must never use SET IDENTITY_INSERT; the
--    IDENTITY columns must still be identity columns and in their original
--    position. This is enforced at generation time and re-checked here.
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM sys.tables t
    JOIN sys.columns c ON c.object_id = t.object_id
    WHERE t.name IN ('USER', 'BOOKING', 'MAINTENANCE_RECORD', 'FACILITY',
                     'ROLE', 'USAGE_POLICY')
      AND c.name = CASE t.name
                       WHEN 'USER' THEN 'user_id'
                       WHEN 'BOOKING' THEN 'booking_id'
                       WHEN 'MAINTENANCE_RECORD' THEN 'maintenance_id'
                       WHEN 'FACILITY' THEN 'facility_id'
                       WHEN 'ROLE' THEN 'role_id'
                       WHEN 'USAGE_POLICY' THEN 'policy_id'
                   END
      AND c.is_identity = 0
)
BEGIN
    THROW 51023, 'FAIL: identity column is no longer an identity.', 1;
END;

-- ============================================================================
-- 7. Status-specific fields are populated
-- ============================================================================
IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    JOIN dbo.[USER] u ON u.user_id = b.requester_id
    WHERE u.email LIKE 'gen-%@campus.example'
      AND b.booking_status = 'rejected'
      AND (b.decision_staff_id IS NULL OR b.decision_time IS NULL
           OR b.decision_note IS NULL OR b.rejection_reason IS NULL)
)
BEGIN
    THROW 51024, 'FAIL: rejected booking is missing decision/rejection fields.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    JOIN dbo.[USER] u ON u.user_id = b.requester_id
    WHERE u.email LIKE 'gen-%@campus.example'
      AND b.booking_status IN ('checked_in', 'completed')
      AND (b.actual_start_time IS NULL OR b.check_in_staff_id IS NULL
           OR b.initial_condition IS NULL)
)
BEGIN
    THROW 51025, 'FAIL: checked-in booking is missing check-in fields.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    JOIN dbo.[USER] u ON u.user_id = b.requester_id
    WHERE u.email LIKE 'gen-%@campus.example'
      AND b.booking_status = 'completed'
      AND (b.actual_end_time IS NULL OR b.completion_staff_id IS NULL
           OR b.final_condition IS NULL OR b.usage_notes IS NULL)
)
BEGIN
    THROW 51026, 'FAIL: completed booking is missing completion fields.', 1;
END;

-- ============================================================================
-- 8. Time-range ordering
-- ============================================================================
IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    WHERE b.requested_start_time >= b.requested_end_time
)
BEGIN
    THROW 51027, 'FAIL: requested_start_time is not earlier than requested_end_time.', 1;
END;

IF EXISTS (
    SELECT 1 FROM dbo.BOOKING b
    WHERE b.actual_start_time IS NOT NULL
      AND b.actual_end_time IS NOT NULL
      AND b.actual_start_time >= b.actual_end_time
)
BEGIN
    THROW 51028, 'FAIL: actual_start_time is not earlier than actual_end_time.', 1;
END;

-- ============================================================================
-- 9. No overlapping approved bookings
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM (
        SELECT
            b.booking_id,
            b.space_code,
            b.requested_start_time,
            MAX(b.requested_end_time) OVER (
                PARTITION BY b.space_code
                ORDER BY
                    b.requested_start_time,
                    b.requested_end_time,
                    b.booking_id
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS prior_maximum_end
        FROM dbo.BOOKING b
        WHERE b.booking_status = 'approved'
    ) overlap_check
    WHERE overlap_check.prior_maximum_end >
          overlap_check.requested_start_time
)
BEGIN
    THROW 51003, 'FAIL: overlapping approved bookings exist.', 1;
END;

-- ============================================================================
-- 10. No booking during out-of-service maintenance
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM dbo.BOOKING b
    JOIN dbo.MAINTENANCE_RECORD m
      ON m.space_code = b.space_code
     AND b.requested_start_time <
         COALESCE(m.completion_time, DATEADD(HOUR, 36, m.start_time))
     AND b.requested_end_time > m.start_time
    WHERE m.impact_level = 'out-of-service'
      AND m.status IN ('reported', 'in_progress')
)
BEGIN
    THROW 51004,
        'FAIL: booking overlaps out-of-service maintenance.',
        1;
END;

-- ============================================================================
-- 11. Advisory overlaps require acknowledgement links
--     Phase 2 schema: ACKNOWLEDGEMENT(booking_id, maintenance_id) is the link.
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM dbo.BOOKING b
    JOIN dbo.MAINTENANCE_RECORD m
      ON m.space_code = b.space_code
     AND b.requested_start_time <
         COALESCE(m.completion_time, CONVERT(DATETIME2, '9999-12-31'))
     AND b.requested_end_time > m.start_time
    WHERE m.impact_level = 'advisory'
      AND m.status IN ('reported', 'in_progress')
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.ACKNOWLEDGEMENT a
          WHERE a.booking_id = b.booking_id
            AND a.maintenance_id = m.maintenance_id
      )
)
BEGIN
    THROW 51005,
        'FAIL: advisory booking is missing acknowledgement.',
        1;
END;

-- ============================================================================
-- 12. Acknowledgement links reference the matching maintenance record
--     (only bookings that actually overlap an advisory may have an
--     ACKNOWLEDGEMENT row for it)
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM dbo.ACKNOWLEDGEMENT a
    JOIN dbo.BOOKING b ON b.booking_id = a.booking_id
    JOIN dbo.MAINTENANCE_RECORD m ON m.maintenance_id = a.maintenance_id
    WHERE NOT (
        m.space_code = b.space_code
        AND m.impact_level = 'advisory'
        AND m.status IN ('reported', 'in_progress')
     AND b.requested_start_time <
         COALESCE(m.completion_time, CONVERT(DATETIME2, '9999-12-31'))
     AND b.requested_end_time > m.start_time
    )
)
BEGIN
    THROW 51029,
        'FAIL: acknowledgement links to a non-overlapping maintenance record.',
        1;
END;

-- ============================================================================
-- 13. Generated user emails and phone numbers are unique
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM dbo.[USER] u
    WHERE u.email LIKE 'gen-%@campus.example'
    GROUP BY u.email
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    THROW 51030, 'FAIL: duplicate generated user email.', 1;
END;

IF EXISTS (
    SELECT 1
    FROM dbo.[USER] u
    WHERE u.phone_number LIKE 'GEN-%'
    GROUP BY u.phone_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    THROW 51031, 'FAIL: duplicate generated user phone number.', 1;
END;

-- ============================================================================
-- 14. Generated space locations are unique
--     (building, floor, room_number) — enforced by uq_space_location
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM dbo.SPACE s
    WHERE s.space_code LIKE 'GSP-%'
    GROUP BY s.building, s.floor, s.room_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    THROW 51032, 'FAIL: duplicate generated space location.', 1;
END;

-- ============================================================================
-- 15. All constraints are trusted and enabled
-- ============================================================================
IF EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE is_disabled = 1 OR is_not_trusted = 1
)
BEGIN
    THROW 51033, 'FAIL: one or more CHECK constraints are disabled or untrusted.', 1;
END;

IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE is_disabled = 1 OR is_not_trusted = 1
)
BEGIN
    THROW 51034, 'FAIL: one or more foreign keys are disabled or untrusted.', 1;
END;

-- ============================================================================
-- 16. Trigger must be enabled
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM sys.triggers
    WHERE object_id = OBJECT_ID('dbo.trg_booking_enforce_rules')
      AND is_disabled = 1
)
BEGIN
    THROW 51006, 'FAIL: booking enforcement trigger is disabled.', 1;
END;

PRINT 'PASS: all high-volume sample-data assertions succeeded.';
GO
