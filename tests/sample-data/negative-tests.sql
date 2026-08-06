-- ============================================================================
-- High-volume sample-data negative tests — Campus Space Management System (G09)
-- File: tests/sample-data/negative-tests.sql
-- Purpose: Confirm that the database rejects invalid operations. Every test
--          runs inside its own transaction that is rolled back. An expected
--          SQL error is a PASS; an operation that unexpectedly succeeds is a
--          FAIL. Run AFTER outputs/13-high-volume-sample-data-G09.sql has
--          populated the generated dataset.
--
-- Skeleton: the agent must finalize each value so the tests are runnable
-- against the actual generated dataset before these tests are marked done.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ============================================================================
-- Test harness
-- ============================================================================
DECLARE @Passed INT = 0;
DECLARE @Failed INT = 0;
DECLARE @SuiteName VARCHAR(100);
DECLARE @ErrMessage NVARCHAR(2048);

DECLARE @TestSpaceCode VARCHAR(50);
DECLARE @RequesterId INT;
DECLARE @StudentId INT;            -- role NOT allowed to decide or check in
DECLARE @FacilityStaffId INT;      -- role allowed to decide / check in
DECLARE @ExistingApprovedBookingId INT;
DECLARE @ApprovedSpaceCode VARCHAR(50);
DECLARE @ApprovedStart DATETIME2;
DECLARE @ApprovedEnd DATETIME2;
DECLARE @OutageSpaceCode VARCHAR(50);
DECLARE @OutageStart DATETIME2;
DECLARE @OutageEnd DATETIME2;
DECLARE @ExistingGeneratedEmail VARCHAR(255);
DECLARE @ExistingGeneratedPhone VARCHAR(20);
DECLARE @FutureStart DATETIME2;

-- Resolve reusable IDs from the generated dataset. The agent must verify
-- these resolvers select the intended rows for the actual generated data.
SELECT TOP 1 @RequesterId = user_id
FROM dbo.[USER]
WHERE email LIKE 'gen-%@campus.example'
  AND account_status = 'active'
ORDER BY user_id;

SELECT TOP 1 @StudentId = u.user_id
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE u.email LIKE 'gen-%@campus.example'
  AND r.role_name NOT IN ('facility_staff', 'facility_manager')
ORDER BY u.user_id;

SELECT TOP 1 @FacilityStaffId = u.user_id
FROM dbo.[USER] u
JOIN dbo.ROLE r ON r.role_id = u.role_id
WHERE r.role_name = 'facility_staff'
ORDER BY u.user_id;

SELECT TOP 1 @TestSpaceCode = space_code
FROM dbo.SPACE
WHERE space_code LIKE 'GSP-%'
  AND current_status IN ('available', 'in_use')
ORDER BY space_code;

-- A truly allocated approved slot for the overlap test.
SELECT TOP 1
    @ExistingApprovedBookingId = booking_id,
    @ApprovedSpaceCode = space_code,
    @ApprovedStart = requested_start_time,
    @ApprovedEnd = requested_end_time
FROM dbo.BOOKING
WHERE booking_status = 'approved'
  AND space_code LIKE 'GSP-%'
ORDER BY booking_id;

-- An active out-of-service maintenance window for the conflict test.
SELECT TOP 1
    @OutageSpaceCode = mr.space_code,
    @OutageStart = mr.start_time,
    @OutageEnd = ISNULL(mr.completion_time, CONVERT(DATETIME2, '9999-12-31'))
FROM dbo.MAINTENANCE_RECORD mr
WHERE mr.impact_level = 'out-of-service'
  AND mr.status IN ('reported', 'in_progress')
  AND mr.space_code LIKE 'GSP-%'
ORDER BY mr.maintenance_id;

SELECT TOP 1
    @ExistingGeneratedEmail = email,
    @ExistingGeneratedPhone = phone_number
FROM dbo.[USER]
WHERE email LIKE 'gen-%@campus.example'
ORDER BY user_id;

SET @FutureStart = DATEADD(DAY, 30, SYSDATETIME());

IF @RequesterId IS NULL OR @StudentId IS NULL OR @FacilityStaffId IS NULL
   OR @TestSpaceCode IS NULL
BEGIN
    THROW 52000, 'Negative-test setup failed: generated reference rows not found.', 1;
END;

-- ============================================================================
-- Test 1: invalid requested time range is rejected
-- ============================================================================
SET @SuiteName = 'negative: invalid requested time range (end <= start)';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.BOOKING (
        requester_id, space_code, requested_start_time, requested_end_time,
        purpose, expected_participants, booking_status
    )
    VALUES (
        @RequesterId, @TestSpaceCode, @FutureStart, @FutureStart,
        'meeting', 4, 'pending'
    );
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Test 2: rejected booking without a rejection reason is rejected
-- ============================================================================
SET @SuiteName = 'negative: rejected booking without rejection reason';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.BOOKING (
        requester_id, space_code, requested_start_time, requested_end_time,
        purpose, expected_participants, booking_status,
        decision_staff_id, decision_time, decision_note
    )
    VALUES (
        @RequesterId, @TestSpaceCode,
        @FutureStart, DATEADD(MINUTE, 30, @FutureStart),
        'meeting', 4, 'rejected',
        @FacilityStaffId, SYSDATETIME(), 'denied'
    );
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Test 3: completed booking without completion fields is rejected
-- ============================================================================
SET @SuiteName = 'negative: completed booking without completion fields';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.BOOKING (
        requester_id, space_code, requested_start_time, requested_end_time,
        purpose, expected_participants, booking_status
    )
    VALUES (
        @RequesterId, @TestSpaceCode,
        @FutureStart, DATEADD(MINUTE, 30, @FutureStart),
        'meeting', 4, 'completed'
    );
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Test 4: unauthorized decision staff is rejected
-- ============================================================================
SET @SuiteName = 'negative: unauthorized decision staff member';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.BOOKING (
        requester_id, space_code, requested_start_time, requested_end_time,
        purpose, expected_participants, booking_status,
        decision_staff_id, decision_time, decision_note, rejection_reason
    )
    VALUES (
        @RequesterId, @TestSpaceCode,
        @FutureStart, DATEADD(MINUTE, 30, @FutureStart),
        'meeting', 4, 'rejected',
        @StudentId, SYSDATETIME(), 'denied', 'not authorised'
    );
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Test 5: unauthorized check-in staff is rejected
-- ============================================================================
SET @SuiteName = 'negative: unauthorized check-in staff member';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.BOOKING (
        requester_id, space_code, requested_start_time, requested_end_time,
        purpose, expected_participants, booking_status,
        actual_start_time, check_in_staff_id, initial_condition
    )
    VALUES (
        @RequesterId, @TestSpaceCode,
        @FutureStart, DATEADD(MINUTE, 30, @FutureStart),
        'meeting', 4, 'checked_in',
        @FutureStart, @StudentId, 'clean'
    );
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Test 6: overlapping approved bookings are rejected
-- ============================================================================
SET @SuiteName = 'negative: overlapping approved bookings for one space';
BEGIN TRY
    IF @ExistingApprovedBookingId IS NULL
        THROW 52001, 'setup: no approved booking found for overlap test', 1;
    BEGIN TRAN;
    INSERT INTO dbo.BOOKING (
        requester_id, space_code, requested_start_time, requested_end_time,
        purpose, expected_participants, booking_status,
        decision_staff_id, decision_time, decision_note
    )
    VALUES (
        @RequesterId, @ApprovedSpaceCode,
        DATEADD(MINUTE, 5, @ApprovedStart), @ApprovedEnd,
        'meeting', 4, 'approved',
        @FacilityStaffId, SYSDATETIME(), 'approved'
    );
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Test 7: booking during out-of-service maintenance is rejected
-- ============================================================================
SET @SuiteName = 'negative: booking during out-of-service maintenance';
BEGIN TRY
    IF @OutageSpaceCode IS NULL
        THROW 52002, 'setup: no out-of-service maintenance found', 1;
    BEGIN TRAN;
    INSERT INTO dbo.BOOKING (
        requester_id, space_code, requested_start_time, requested_end_time,
        purpose, expected_participants, booking_status
    )
    VALUES (
        @RequesterId, @OutageSpaceCode,
        DATEADD(MINUTE, 5, @OutageStart),
        CASE WHEN @OutageEnd > DATEADD(MINUTE, 30, @OutageStart)
             THEN DATEADD(MINUTE, 30, @OutageStart)
             ELSE @OutageEnd END,
        'meeting', 4, 'pending'
    );
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Test 8: duplicate user email is rejected
-- ============================================================================
SET @SuiteName = 'negative: duplicate user email';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.[USER] (
        full_name, email, phone_number, department, account_status, role_id
    )
    SELECT
        'Negative Test User',
        x.ExistingEmail,
        'GEN-NEG-PHONE-1',
        'Campus Services',
        'active',
        r.role_id
    FROM (SELECT @ExistingGeneratedEmail AS ExistingEmail) x
    CROSS JOIN dbo.ROLE r
    WHERE r.role_name = 'student';
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Test 9: invalid booking status is rejected
-- ============================================================================
SET @SuiteName = 'negative: invalid booking status';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.BOOKING (
        requester_id, space_code, requested_start_time, requested_end_time,
        purpose, expected_participants, booking_status
    )
    VALUES (
        @RequesterId, @TestSpaceCode,
        @FutureStart, DATEADD(MINUTE, 30, @FutureStart),
        'meeting', 4, 'bogus_status'
    );
    ROLLBACK TRAN;
    PRINT 'FAIL: ' + @SuiteName + ' — insert unexpectedly succeeded.';
    SET @Failed = @Failed + 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'PASS: ' + @SuiteName + ' — ' + ERROR_MESSAGE();
    SET @Passed = @Passed + 1;
END CATCH;

-- ============================================================================
-- Summary
-- ============================================================================
PRINT '============================================================';
PRINT 'Negative-test summary: ';

IF @Failed = 0
    PRINT 'PASS: all negative tests rejected the invalid operations.';
ELSE
BEGIN
    PRINT 'FAIL: ' + CONVERT(VARCHAR(10), @Failed)
        + ' negative test(s) did not reject the invalid operation.';
    THROW 52999, 'FAIL: one or more negative tests did not reject invalid operations.', 1;
END;

PRINT 'Passed=' + CONVERT(VARCHAR(10), @Passed)
    + ' Failed=' + CONVERT(VARCHAR(10), @Failed);
GO