-- ============================================================================
-- Phase 2 Schema Migration Script
-- File: 10-schema-migration-G09.sql
-- Description: Migrates the database from Phase 1 to Phase 2 requirements.
-- This script strictly follows the order and structure defined in 
-- 08-requirement-change-analysis-G09.md.
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;

-- ============================================================================
-- 1. AFFECTED ENTITIES AND ATTRIBUTES
-- ============================================================================
-- (Note: New entities must be created first to satisfy SQL constraint dependencies 
-- before altering existing entities like USER or SPACE).

-- ----------------------------------------------------------------------------
-- [New Entity]: ROLE
-- Action: Create this entity to store roles for users.
-- ----------------------------------------------------------------------------
CREATE TABLE dbo.ROLE (
    role_id INT IDENTITY(1,1) NOT NULL,
    role_name VARCHAR(50) NOT NULL,
    CONSTRAINT pk_role PRIMARY KEY (role_id)
);
GO

-- ----------------------------------------------------------------------------
-- [New Entity]: ACKNOWLEDGEMENT
-- Action: Create this entity to store records of users acknowledging advisory 
-- maintenance warnings during the booking process.
-- (maintenance_id will be linked in Section 2)
-- ----------------------------------------------------------------------------
CREATE TABLE dbo.ACKNOWLEDGEMENT (
    acknowledgement_id INT IDENTITY(1,1) NOT NULL,
    maintenance_id INT NOT NULL,
    CONSTRAINT pk_acknowledgement PRIMARY KEY (acknowledgement_id)
);
GO

-- ----------------------------------------------------------------------------
-- [New Entity]: USAGE_POLICY
-- Action: Create this entity to manage dynamic rules that determine auto-approval.
-- ----------------------------------------------------------------------------
CREATE TABLE dbo.USAGE_POLICY (
    policy_id INT IDENTITY(1,1) NOT NULL,
    policy_name VARCHAR(255) NOT NULL,
    max_duration_minutes INT NULL,
    requires_business_hours BIT NULL,
    department_allowed VARCHAR(255) NULL,
    CONSTRAINT pk_usage_policy PRIMARY KEY (policy_id),
    CONSTRAINT chk_usage_policy_max_duration_boundary CHECK ([max_duration_minutes] > 0)
);
GO

-- ----------------------------------------------------------------------------
-- [Existing Entity]: USER
-- Action: Extract attribute 'role' into a standalone entity.
-- ----------------------------------------------------------------------------
-- 1. Migrate distinct roles to the new ROLE table
INSERT INTO dbo.ROLE (role_name)
SELECT DISTINCT [role] FROM dbo.[USER];
GO

-- 2. Add the new role_id column
ALTER TABLE dbo.[USER] ADD role_id INT;
GO

-- 3. Update existing records with the corresponding role_id
UPDATE u
SET u.role_id = r.role_id
FROM dbo.[USER] u
JOIN dbo.ROLE r ON u.role = r.role_name;
GO

-- 4. Enforce NOT NULL and drop the old text column & constraint
ALTER TABLE dbo.[USER] ALTER COLUMN role_id INT NOT NULL;
ALTER TABLE dbo.[USER] DROP CONSTRAINT chk_user_role_domain;
ALTER TABLE dbo.[USER] DROP COLUMN [role];
GO

-- ----------------------------------------------------------------------------
-- [Existing Entity]: BOOKING
-- Action: Does not require decision_staff_id for an auto-approval booking.
-- ----------------------------------------------------------------------------
ALTER TABLE dbo.BOOKING DROP CONSTRAINT chk_booking_decision_fields;
GO
ALTER TABLE dbo.BOOKING ADD CONSTRAINT chk_booking_decision_fields
CHECK (
    ([booking_status] NOT IN ('rejected') OR ([decision_staff_id] IS NOT NULL AND [decision_time] IS NOT NULL AND [decision_note] IS NOT NULL))
);
GO

-- ----------------------------------------------------------------------------
-- [Existing Entity]: MAINTENANCE_RECORD
-- Action: Add a new attribute impact_level ('out-of-service' or 'advisory').
-- ----------------------------------------------------------------------------
ALTER TABLE dbo.MAINTENANCE_RECORD ADD impact_level VARCHAR(50);
GO
UPDATE dbo.MAINTENANCE_RECORD 
SET impact_level = 'out-of-service' 
WHERE impact_level IS NULL;
GO
ALTER TABLE dbo.MAINTENANCE_RECORD ALTER COLUMN impact_level VARCHAR(50) NOT NULL;
GO
ALTER TABLE dbo.MAINTENANCE_RECORD 
    ADD CONSTRAINT chk_maintenance_impact_level_domain 
    CHECK (impact_level IN ('out-of-service', 'advisory'));
GO

-- ----------------------------------------------------------------------------
-- [Existing Entity]: SPACE
-- Action: Extract the usage_policy attribute and convert it into a standalone entity.
-- Since in phase 1, usage_policy was a text field, we cannot directly map it to the new USAGE_POLICY entity. For this migration, we will set all existing spaces to have a NULL policy_id, and future policies can be assigned as needed.
-- ----------------------------------------------------------------------------
ALTER TABLE dbo.SPACE ADD policy_id INT;
GO
ALTER TABLE dbo.SPACE DROP COLUMN usage_policy;
GO

-- ============================================================================
-- 2. AFFECTED RELATIONSHIPS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SPACE (OPTIONAL) and USAGE_POLICY (MANDATORY) -> N:1
-- ----------------------------------------------------------------------------
ALTER TABLE dbo.SPACE 
    ADD CONSTRAINT fk_space_policy 
    FOREIGN KEY (policy_id) REFERENCES dbo.USAGE_POLICY(policy_id);
GO

-- ----------------------------------------------------------------------------
-- BOOKING (OPTIONAL) and ACKNOWLEDGEMENT (MANDATORY) -> M:N
-- ----------------------------------------------------------------------------
CREATE TABLE dbo.BOOKING_ACKNOWLEDGEMENT (
    booking_id INT NOT NULL,
    acknowledgement_id INT NOT NULL,
    CONSTRAINT pk_booking_acknowledgement PRIMARY KEY (booking_id, acknowledgement_id),
    CONSTRAINT fk_ba_booking FOREIGN KEY (booking_id) REFERENCES dbo.BOOKING(booking_id) ON DELETE CASCADE,
    CONSTRAINT fk_ba_ack FOREIGN KEY (acknowledgement_id) REFERENCES dbo.ACKNOWLEDGEMENT(acknowledgement_id) ON DELETE CASCADE
);
GO

-- ----------------------------------------------------------------------------
-- ACKNOWLEDGEMENT (MANDATORY) and MAINTENANCE_RECORD (OPTIONAL) -> 1:1
-- ----------------------------------------------------------------------------
ALTER TABLE dbo.ACKNOWLEDGEMENT 
    ADD CONSTRAINT uq_ack_maintenance UNIQUE (maintenance_id);
GO
ALTER TABLE dbo.ACKNOWLEDGEMENT 
    ADD CONSTRAINT fk_ack_maintenance 
    FOREIGN KEY (maintenance_id) REFERENCES dbo.MAINTENANCE_RECORD(maintenance_id);
GO

-- ----------------------------------------------------------------------------
-- ROLE (MANDATORY) and USER (MANDATORY) -> 1:N
-- ----------------------------------------------------------------------------
ALTER TABLE dbo.[USER] 
    ADD CONSTRAINT fk_user_role 
    FOREIGN KEY (role_id) REFERENCES dbo.ROLE(role_id);
GO

-- ----------------------------------------------------------------------------
-- ROLE (OPTIONAL) and USAGE_POLICY (OPTIONAL) -> M:N
-- ----------------------------------------------------------------------------
CREATE TABLE dbo.ROLE_USAGE_POLICY (
    role_id INT NOT NULL,
    policy_id INT NOT NULL,
    CONSTRAINT pk_role_usage_policy PRIMARY KEY (role_id, policy_id),
    CONSTRAINT fk_rup_role FOREIGN KEY (role_id) REFERENCES dbo.ROLE(role_id) ON DELETE CASCADE,
    CONSTRAINT fk_rup_policy FOREIGN KEY (policy_id) REFERENCES dbo.USAGE_POLICY(policy_id) ON DELETE CASCADE
);
GO

-- ============================================================================
-- 3. BUSINESS RULES (Procedural Enforcement Updates)
-- ============================================================================

IF OBJECT_ID('dbo.trg_booking_enforce_rules', 'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_booking_enforce_rules;
GO

CREATE TRIGGER trg_booking_enforce_rules
ON dbo.BOOKING
INSTEAD OF INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Updated Rule 2 (Maintenance Blocks): 
    -- Allows booking if maintenance is 'advisory', blocks if 'out-of-service'.
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.SPACE s ON i.space_code = s.space_code
        WHERE s.current_status IN ('temporarily_closed', 'retired')
           OR (s.current_status = 'under_maintenance' AND EXISTS (
               SELECT 1 FROM dbo.MAINTENANCE_RECORD mr
               WHERE mr.space_code = s.space_code
                 AND mr.status IN ('reported', 'in_progress')
                 AND mr.impact_level = 'out-of-service'
                 AND (i.requested_start_time < ISNULL(mr.completion_time, '9999-12-31') AND i.requested_end_time > mr.start_time)
           ))
    )
    BEGIN
        ;THROW 50000, 'Cannot book space: Space is closed, retired, or has active out-of-service maintenance during the requested period.', 1;
    END

    -- Updated Rule 19 / Phase 1 Rule 7: Overlapping approved booking prevention
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.booking_status = 'approved'
          AND EXISTS (
              SELECT 1
              FROM dbo.BOOKING b
              WHERE b.space_code = i.space_code
                AND b.booking_status = 'approved'
                AND b.booking_id <> ISNULL(i.booking_id, -1)
                AND b.requested_start_time < i.requested_end_time
                AND b.requested_end_time > i.requested_start_time
          )
    )
    BEGIN
        ;THROW 50000, 'Overlapping approved booking already exists for this space during the requested time period.', 1;
    END

    -- Updated Rule 9: Approval / Rejection role authorization (Joined with new ROLE table)
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.decision_staff_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.[USER] u
              JOIN dbo.ROLE r ON u.role_id = r.role_id
              WHERE u.user_id = i.decision_staff_id
                AND r.role_name IN ('facility_staff', 'facility_manager')
          )
    )
    BEGIN
        ;THROW 50000, 'Only a user with role facility_staff or facility_manager may be recorded as the decision staff on a booking.', 1;
    END

    -- Phase 1 Rule 11/12 Authorization update (Joined with new ROLE table)
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE (
              i.check_in_staff_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.[USER] u
                  JOIN dbo.ROLE r ON u.role_id = r.role_id
                  WHERE u.user_id = i.check_in_staff_id
                    AND r.role_name = 'facility_staff'
              )
          )
          OR (
              i.completion_staff_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.[USER] u
                  JOIN dbo.ROLE r ON u.role_id = r.role_id
                  WHERE u.user_id = i.completion_staff_id
                    AND r.role_name = 'facility_staff'
              )
          )
    )
    BEGIN
        ;THROW 50000, 'Only a user with role facility_staff may be recorded as check-in or completion staff on a booking.', 1;
    END

    -- Forward valid operations (INSERT/UPDATE logic)
    IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        UPDATE t
        SET
            t.requester_id          = i.requester_id,
            t.space_code            = i.space_code,
            t.requested_start_time  = i.requested_start_time,
            t.requested_end_time    = i.requested_end_time,
            t.purpose               = i.purpose,
            t.expected_participants = i.expected_participants,
            t.booking_status        = i.booking_status,
            t.decision_staff_id     = i.decision_staff_id,
            t.decision_time         = i.decision_time,
            t.decision_note         = i.decision_note,
            t.rejection_reason      = i.rejection_reason,
            t.actual_start_time     = i.actual_start_time,
            t.check_in_staff_id     = i.check_in_staff_id,
            t.initial_condition     = i.initial_condition,
            t.actual_end_time       = i.actual_end_time,
            t.completion_staff_id   = i.completion_staff_id,
            t.final_condition       = i.final_condition,
            t.usage_notes           = i.usage_notes
        FROM dbo.BOOKING t
        INNER JOIN inserted i ON t.booking_id = i.booking_id;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.BOOKING (
            requester_id, space_code, requested_start_time, requested_end_time,
            purpose, expected_participants, booking_status, decision_staff_id,
            decision_time, decision_note, rejection_reason, actual_start_time,
            check_in_staff_id, initial_condition, actual_end_time,
            completion_staff_id, final_condition, usage_notes
        )
        SELECT
            requester_id, space_code, requested_start_time, requested_end_time,
            purpose, expected_participants, booking_status, decision_staff_id,
            decision_time, decision_note, rejection_reason, actual_start_time,
            check_in_staff_id, initial_condition, actual_end_time,
            completion_staff_id, final_condition, usage_notes
        FROM inserted;
    END
END;
GO