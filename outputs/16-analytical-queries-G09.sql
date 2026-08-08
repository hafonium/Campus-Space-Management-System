USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- Semester is identified by semester_id. The functions join SEMESTER to get
-- semester_start and semester_end.

-- ----------------------------------------------------------------------------
-- Total approved booking hours of each space for a given semester
-- Assumption: approved status includes 'approved', 'checked_in' and 'completed'
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS fn_CountApprovedBookingHourBySemester;
GO

CREATE FUNCTION fn_CountApprovedBookingHourBySemester(
    @semester_id INT
)
RETURNS TABLE
AS
RETURN (
    SELECT
        S.space_code,
        ISNULL(SUM(DATEDIFF(MINUTE, B.requested_start_time, B.requested_end_time) / 60.0), 0) AS total_hour
    FROM dbo.SPACE S
    LEFT JOIN dbo.BOOKING B
        ON S.space_code = B.space_code
        AND B.booking_status IN ('approved', 'checked_in', 'completed')
        AND B.requested_end_time > (
            SELECT CAST(SEM.start_date AS DATETIME2)
            FROM dbo.SEMESTER SEM
            WHERE SEM.semester_id = @semester_id
        )
        AND B.requested_start_time < (
            SELECT DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2))
            FROM dbo.SEMESTER SEM
            WHERE SEM.semester_id = @semester_id
        )
    WHERE EXISTS (
        SELECT 1
        FROM dbo.SEMESTER SEM
        WHERE SEM.semester_id = @semester_id
    )
    GROUP BY S.space_code
);
GO


-- ----------------------------------------------------------------------------
-- Number of approved bookings by weekday and hour for a given semester.
-- Assumption: approved bookings are grouped by requested_start_time
-- Assumption: approved status includes 'approved', 'checked_in' and 'completed'
-- ----------------------------------------------------------------------------

-- Remove the temporary renamed function from the previous revision.
DROP FUNCTION IF EXISTS dbo.fn_CountApprovedBookingsByWeekdayHourBySemester;
DROP FUNCTION IF EXISTS fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester;
GO

CREATE FUNCTION fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(
    @semester_id INT
)
RETURNS TABLE
AS
RETURN (
    SELECT
        DATENAME(WEEKDAY, B.requested_start_time) AS weekday,
        DATEPART(HOUR, B.requested_start_time) AS hour,
        COUNT(*) AS approved_booking
    FROM dbo.BOOKING B
    JOIN dbo.SEMESTER SEM ON SEM.semester_id = @semester_id
    WHERE B.booking_status IN ('approved', 'checked_in', 'completed')
        AND B.requested_end_time > CAST(SEM.start_date AS DATETIME2)
        AND B.requested_start_time < DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2))
    GROUP BY
        DATENAME(WEEKDAY, B.requested_start_time),
        DATEPART(HOUR, B.requested_start_time)
);
GO

-- ----------------------------------------------------------------------------
-- Available spaces that satisfy a required capacity and a required facility list within a given time period.
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS fn_GetAvailableSpaces;
GO

IF TYPE_ID('dbo.FacilityListType') IS NULL
    EXEC ('CREATE TYPE dbo.FacilityListType AS TABLE (
        facility_id INT NOT NULL PRIMARY KEY
    );');
GO

CREATE FUNCTION fn_GetAvailableSpaces (
    @required_capacity INT,
    @start_time DATETIME2,
    @end_time DATETIME2,
    @required_facilities dbo.FacilityListType READONLY
)
RETURNS TABLE
AS
RETURN (
    SELECT S.space_code
    FROM dbo.SPACE S
    WHERE capacity >= @required_capacity
        AND S.current_status NOT IN ('temporarily_closed', 'retired')
        AND NOT EXISTS (
            SELECT 1
            FROM @required_facilities RF
            WHERE RF.facility_id NOT IN (
                SELECT SF.facility_id
                FROM dbo.SPACE_FACILITY SF
                WHERE SF.space_code = S.space_code
            )
        )

    EXCEPT

    SELECT S.space_code
    FROM dbo.SPACE S
    JOIN dbo.BOOKING B ON B.space_code = S.space_code
    WHERE B.booking_status IN ('approved', 'checked_in', 'completed')
        AND B.requested_end_time > @start_time
        AND B.requested_start_time < @end_time

    EXCEPT

    SELECT S.space_code
    FROM dbo.SPACE S
    JOIN dbo.MAINTENANCE_RECORD MR ON MR.space_code = S.space_code
    WHERE MR.impact_level = 'out-of-service'
        AND MR.status IN ('reported', 'in_progress')
        AND ISNULL(MR.completion_time, CONVERT(DATETIME2, '9999-12-31')) > @start_time
        AND MR.start_time < @end_time
);
GO

-- ----------------------------------------------------------------------------
-- Approved bookings affected when a maintenance record is escalated to out-of-service.
-- Assumption: Users will pass maintenance_id to the function
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS fn_GetAffectedApprovedBookings;
GO

CREATE FUNCTION fn_GetAffectedApprovedBookings(
    @maintenance_id INT
)
RETURNS TABLE
AS
RETURN (
    SELECT B.booking_id
    FROM dbo.BOOKING B
    JOIN dbo.MAINTENANCE_RECORD MR ON MR.space_code = B.space_code
    WHERE MR.maintenance_id = @maintenance_id
        AND MR.impact_level = 'out-of-service'
        AND B.booking_status IN ('approved', 'checked_in', 'completed')
        AND B.requested_end_time > MR.start_time
        AND B.requested_start_time < ISNULL(
            MR.completion_time, CONVERT(DATETIME2, '9999-12-31')
        )
);
GO

-- ----------------------------------------------------------------------------
-- Test calls using IDs and dates selected from the current generated data.
-- ----------------------------------------------------------------------------

DECLARE @semester_id INT;

SELECT TOP (1) @semester_id = SEM.semester_id
FROM dbo.SEMESTER SEM
ORDER BY CASE WHEN EXISTS (
    SELECT 1
    FROM dbo.BOOKING B
    WHERE B.requested_end_time > CAST(SEM.start_date AS DATETIME2)
      AND B.requested_start_time < DATEADD(DAY, 1, CAST(SEM.end_date AS DATETIME2))
) THEN 0 ELSE 1 END,
SEM.start_date;

SELECT *
FROM dbo.fn_CountApprovedBookingHourBySemester(@semester_id)
ORDER BY total_hour DESC, space_code;

SELECT *
FROM dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@semester_id)
ORDER BY weekday, hour;

DECLARE @required_facilities dbo.FacilityListType;
DECLARE @start_time DATETIME2;
DECLARE @end_time DATETIME2;
DECLARE @required_capacity INT;
DECLARE @test_space_code VARCHAR(50);

-- Test a period after the generated booking and completed-maintenance history.
-- Then choose a usable space without open out-of-service maintenance and use
-- facilities that the selected space actually contains.
SELECT @start_time = DATEADD(DAY, 1, MAX(event_end))
FROM (
    SELECT MAX(requested_end_time) AS event_end FROM dbo.BOOKING
    UNION ALL
    SELECT MAX(completion_time) AS event_end FROM dbo.MAINTENANCE_RECORD
) history;

IF @start_time IS NULL
    SET @start_time = SYSDATETIME();

SET @end_time = DATEADD(HOUR, 2, @start_time);

SELECT TOP (1)
    @test_space_code = S.space_code,
    @required_capacity = S.capacity
FROM dbo.SPACE S
WHERE S.current_status NOT IN ('temporarily_closed', 'retired')
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.MAINTENANCE_RECORD MR
      WHERE MR.space_code = S.space_code
        AND MR.impact_level = 'out-of-service'
        AND MR.status IN ('reported', 'in_progress')
        AND MR.start_time < @end_time
        AND ISNULL(MR.completion_time, CONVERT(DATETIME2, '9999-12-31')) > @start_time
  )
ORDER BY S.space_code;

INSERT INTO @required_facilities (facility_id)
SELECT TOP (2) SF.facility_id
FROM dbo.SPACE_FACILITY SF
WHERE SF.space_code = @test_space_code
ORDER BY SF.facility_id;

SELECT *
FROM dbo.fn_GetAvailableSpaces(
    @required_capacity, @start_time, @end_time, @required_facilities
)
ORDER BY space_code;

DECLARE @maintenance_id INT;
DECLARE @temporary_maintenance BIT = 0;

SELECT TOP (1) @maintenance_id = MR.maintenance_id
FROM dbo.MAINTENANCE_RECORD MR
JOIN dbo.BOOKING B ON B.space_code = MR.space_code
WHERE MR.impact_level = 'out-of-service'
  AND B.booking_status IN ('approved', 'checked_in', 'completed')
  AND B.requested_end_time > MR.start_time
  AND B.requested_start_time < ISNULL(
      MR.completion_time, CONVERT(DATETIME2, '9999-12-31')
  )
ORDER BY MR.maintenance_id;

-- Normal generated data may correctly contain no approved booking that overlaps
-- out-of-service maintenance. In that case, create an isolated escalation test
-- inside a transaction and roll it back after displaying the function result.
IF @maintenance_id IS NULL
BEGIN
    DECLARE @test_booking_id INT;
    DECLARE @test_space_code_for_maintenance VARCHAR(50);
    DECLARE @test_reporter_id INT;
    DECLARE @test_maintenance_start DATETIME2;
    DECLARE @test_maintenance_end DATETIME2;

    SELECT TOP (1)
        @test_booking_id = B.booking_id,
        @test_space_code_for_maintenance = B.space_code,
        @test_reporter_id = B.requester_id,
        @test_maintenance_start = B.requested_start_time,
        @test_maintenance_end = B.requested_end_time
    FROM dbo.BOOKING B
    WHERE B.booking_status IN ('approved', 'checked_in', 'completed')
    ORDER BY B.booking_id;

    IF @test_booking_id IS NOT NULL
    BEGIN
        BEGIN TRANSACTION;
        SET @temporary_maintenance = 1;

        INSERT INTO dbo.MAINTENANCE_RECORD (
            space_code, reporter_id, assigned_staff_id,
            problem_description, start_time, completion_time,
            status, result_note, impact_level
        )
        VALUES (
            @test_space_code_for_maintenance, @test_reporter_id, NULL,
            'Temporary analytical-query escalation test',
            @test_maintenance_start, @test_maintenance_end,
            'in_progress', NULL, 'advisory'
        );

        SET @maintenance_id = SCOPE_IDENTITY();

        -- Simulate the required advisory-to-out-of-service escalation.
        UPDATE dbo.MAINTENANCE_RECORD
        SET impact_level = 'out-of-service'
        WHERE maintenance_id = @maintenance_id;
    END;
END;

SELECT *
FROM dbo.fn_GetAffectedApprovedBookings(@maintenance_id)
ORDER BY booking_id;

IF @temporary_maintenance = 1
    ROLLBACK TRANSACTION;
GO
