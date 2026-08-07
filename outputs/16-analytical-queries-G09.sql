USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
GO

-- Semester is presented as semester_start and semester_end

-- ----------------------------------------------------------------------------
-- Total approved booking hours of each space for a given semester
-- Assumption: approved status includes 'approved', 'checked-in' and 'completed'
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS fn_CountApprovedBookingHourBySemester;
GO

CREATE FUNCTION fn_CountApprovedBookingHourBySemester(
    @semester_start DATE, 
    @semester_end DATE
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
        AND B.booking_status IN ('approved', 'checked-in', 'completed')
        AND B.requested_end_time > CAST(@semester_start AS DATETIME2)
        AND B.requested_start_time < DATEADD(DAY, 1, CAST(@semester_end AS DATETIME2))
    GROUP BY S.space_code
);
GO


-- ----------------------------------------------------------------------------
-- Number of approved bookings by weekday and hour for a given semester.
-- Assumption: approved bookings are grouped by requested_start_time
-- Assumption: approved status includes 'approved', 'checked-in' and 'completed'
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester;
GO

CREATE FUNCTION  fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(
    @semester_start DATE, 
    @semester_end DATE
)
RETURNS TABLE
AS
RETURN (
    SELECT 
        DATENAME(WEEKDAY, B.requested_start_time) AS weekday,
        DATEPART(HOUR, B.requested_start_time) AS hour,
        COUNT(*) AS approved_booking
    FROM dbo.BOOKING B
    WHERE B.booking_status IN ('approved', 'checked-in', 'completed')
        AND B.requested_end_time > CAST(@semester_start AS DATETIME2)
        AND B.requested_start_time < DATEADD(DAY, 1, CAST(@semester_end AS DATETIME2))
    GROUP BY 
        DATENAME(WEEKDAY, B.requested_start_time), 
        DATEPART(HOUR, B.requested_start_time)
)
GO

-- ----------------------------------------------------------------------------
-- Available spaces that satisfy a required capacity and a required facility list within a given time period. 
-- ----------------------------------------------------------------------------

CREATE TYPE dbo.FacilityListType AS TABLE (
    facility_id INT NOT NULL PRIMARY KEY
);
GO

DROP FUNCTION IF EXISTS fn_GetAvailableSpaces;
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
    WHERE B.booking_status IN ('approved', 'checked-in', 'completed')
        AND B.requested_end_time > @start_time
        AND B.requested_start_time < @end_time 
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
    WHERE B.space_code = (
        SELECT MR.space_code 
        FROM dbo.MAINTENANCE_RECORD MR
        WHERE MR.maintenance_id = @maintenance_id
    ) 
    AND B.booking_status IN ('approved', 'checked-in')
);
GO
