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
IF OBJECT_ID('dbo.ROLE', 'U') IS NULL
CREATE TABLE dbo.ROLE (
    role_id INT IDENTITY(1,1) NOT NULL,
    role_name VARCHAR(50) NOT NULL,
    CONSTRAINT pk_role PRIMARY KEY (role_id),
    CONSTRAINT uq_role_role_name UNIQUE (role_name)
);
GO

-- ----------------------------------------------------------------------------
-- [New Entity]: DEPARTMENT
-- Action: Normalize the department names currently stored on USER. The same
-- entity is also used by usage policies through an M:N relationship.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.DEPARTMENT', 'U') IS NULL
CREATE TABLE dbo.DEPARTMENT (
    department_id INT IDENTITY(1,1) NOT NULL,
    department_name VARCHAR(255) NOT NULL,
    CONSTRAINT pk_department PRIMARY KEY (department_id),
    CONSTRAINT uq_department_department_name UNIQUE (department_name)
);
GO

-- ----------------------------------------------------------------------------
-- [New Entity]: SEMESTER
-- Action: Store academic-period definitions. SEMESTER is intentionally not
-- related to BOOKING in this design.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.SEMESTER', 'U') IS NULL
CREATE TABLE dbo.SEMESTER (
    semester_id INT IDENTITY(1,1) NOT NULL,
    semester_name VARCHAR(100) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    CONSTRAINT pk_semester PRIMARY KEY (semester_id),
    CONSTRAINT uq_semester_semester_name UNIQUE (semester_name),
    CONSTRAINT chk_semester_date_range CHECK (start_date <= end_date)
);
GO

-- ----------------------------------------------------------------------------
-- [New Entity]: ACKNOWLEDGEMENT
-- Action: Create this entity to store records of users acknowledging advisory 
-- maintenance warnings during the booking process.
-- (maintenance_record_id will be linked in Section 2)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ACKNOWLEDGEMENT', 'U') IS NULL
CREATE TABLE dbo.ACKNOWLEDGEMENT (
    booking_id INT NOT NULL,
    maintenance_record_id INT NOT NULL,
    acknowledged_at DATETIME2 NULL,
    CONSTRAINT pk_acknowledgement PRIMARY KEY (booking_id, maintenance_record_id)
);
GO

-- Upgrade databases created by an earlier Phase 2 script that used the shorter
-- maintenance_id name. SQL Server updates dependent key metadata during rename.
IF COL_LENGTH('dbo.ACKNOWLEDGEMENT', 'maintenance_id') IS NOT NULL
   AND COL_LENGTH('dbo.ACKNOWLEDGEMENT', 'maintenance_record_id') IS NULL
    EXEC sys.sp_rename
        'dbo.ACKNOWLEDGEMENT.maintenance_id',
        'maintenance_record_id',
        'COLUMN';
GO

-- ----------------------------------------------------------------------------
-- [New Entity]: USAGE_POLICY
-- Action: Create this entity to manage dynamic rules that determine auto-approval.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.USAGE_POLICY', 'U') IS NULL
CREATE TABLE dbo.USAGE_POLICY (
    policy_id INT IDENTITY(1,1) NOT NULL,
    policy_name VARCHAR(255) NOT NULL,
    max_duration_minutes INT NULL,
    requires_business_hours BIT NULL,
    legacy_policy_text VARCHAR(MAX) NULL,
    CONSTRAINT pk_usage_policy PRIMARY KEY (policy_id),
    CONSTRAINT uq_usage_policy_policy_name UNIQUE (policy_name),
    CONSTRAINT chk_usage_policy_max_duration_boundary CHECK ([max_duration_minutes] > 0)
);
GO

-- Upgrade databases created by an earlier Phase 2 script where policy_name
-- was not yet enforced as a candidate key.
IF NOT EXISTS (
    SELECT 1
    FROM sys.key_constraints
    WHERE [type] = 'UQ'
      AND [name] = 'uq_usage_policy_policy_name'
      AND parent_object_id = OBJECT_ID('dbo.USAGE_POLICY')
)
    ALTER TABLE dbo.USAGE_POLICY
        ADD CONSTRAINT uq_usage_policy_policy_name UNIQUE (policy_name);
GO

-- ----------------------------------------------------------------------------
-- [Existing Entity]: USER
-- Action: Extract 'role' and 'department' into normalized entities.
-- ----------------------------------------------------------------------------
-- 1. Migrate distinct roles to the new ROLE table
IF COL_LENGTH('dbo.USER', 'role') IS NOT NULL
    EXEC ('INSERT INTO dbo.ROLE (role_name)
           SELECT DISTINCT u.[role]
           FROM dbo.[USER] u
           WHERE u.[role] IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM dbo.ROLE r WHERE r.role_name = u.[role]);');
GO

IF COL_LENGTH('dbo.USER', 'department') IS NOT NULL
    EXEC ('INSERT INTO dbo.DEPARTMENT (department_name)
           SELECT DISTINCT u.department
           FROM dbo.[USER] u
           WHERE u.department IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM dbo.DEPARTMENT d
                             WHERE d.department_name = u.department);');
GO

-- 2. Add the new foreign-key columns
IF COL_LENGTH('dbo.USER', 'role_id') IS NULL
    ALTER TABLE dbo.[USER] ADD role_id INT NULL;
IF COL_LENGTH('dbo.USER', 'department_id') IS NULL
    ALTER TABLE dbo.[USER] ADD department_id INT NULL;
GO

-- 3. Update existing records with the corresponding identifiers
IF COL_LENGTH('dbo.USER', 'role') IS NOT NULL
    EXEC ('UPDATE u SET u.role_id = r.role_id
           FROM dbo.[USER] u JOIN dbo.ROLE r ON u.[role] = r.role_name
           WHERE u.role_id IS NULL;');
GO

IF COL_LENGTH('dbo.USER', 'department') IS NOT NULL
    EXEC ('UPDATE u SET u.department_id = d.department_id
           FROM dbo.[USER] u JOIN dbo.DEPARTMENT d
             ON u.department = d.department_name
           WHERE u.department_id IS NULL;');
GO

-- 4. Enforce NOT NULL and drop the old text columns and role constraint
ALTER TABLE dbo.[USER] ALTER COLUMN role_id INT NOT NULL;
ALTER TABLE dbo.[USER] ALTER COLUMN department_id INT NOT NULL;
IF OBJECT_ID('dbo.chk_user_role_domain', 'C') IS NOT NULL
    ALTER TABLE dbo.[USER] DROP CONSTRAINT chk_user_role_domain;
IF COL_LENGTH('dbo.USER', 'role') IS NOT NULL
    ALTER TABLE dbo.[USER] DROP COLUMN [role];
IF COL_LENGTH('dbo.USER', 'department') IS NOT NULL
    ALTER TABLE dbo.[USER] DROP COLUMN department;
GO

-- ----------------------------------------------------------------------------
-- [Existing Entity]: BOOKING
-- Action: Does not require decision_staff_id for an auto-approval booking.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.chk_booking_decision_fields', 'C') IS NOT NULL
    ALTER TABLE dbo.BOOKING DROP CONSTRAINT chk_booking_decision_fields;
GO
IF OBJECT_ID('dbo.chk_booking_decision_fields', 'C') IS NULL
ALTER TABLE dbo.BOOKING ADD CONSTRAINT chk_booking_decision_fields
CHECK (
    ([booking_status] <> 'rejected'
     OR ([decision_staff_id] IS NOT NULL AND [decision_time] IS NOT NULL
         AND [decision_note] IS NOT NULL))
    AND
    ([booking_status] <> 'approved' OR [decision_time] IS NOT NULL)
);
GO

-- ----------------------------------------------------------------------------
-- [Existing Entity]: MAINTENANCE_RECORD
-- Action: Add a new attribute impact_level ('out-of-service' or 'advisory').
-- ----------------------------------------------------------------------------
IF COL_LENGTH('dbo.MAINTENANCE_RECORD', 'impact_level') IS NULL
    ALTER TABLE dbo.MAINTENANCE_RECORD ADD impact_level VARCHAR(50) NULL;
GO
UPDATE dbo.MAINTENANCE_RECORD 
SET impact_level = 'out-of-service' 
WHERE impact_level IS NULL;
GO
ALTER TABLE dbo.MAINTENANCE_RECORD ALTER COLUMN impact_level VARCHAR(50) NOT NULL;
GO
IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    JOIN sys.columns c
      ON c.object_id = dc.parent_object_id
     AND c.column_id = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.MAINTENANCE_RECORD')
      AND c.name = 'impact_level'
)
    ALTER TABLE dbo.MAINTENANCE_RECORD
        ADD CONSTRAINT df_maintenance_impact_level
        DEFAULT ('out-of-service') FOR impact_level;
GO
IF OBJECT_ID('dbo.chk_maintenance_impact_level_domain', 'C') IS NULL
ALTER TABLE dbo.MAINTENANCE_RECORD 
    ADD CONSTRAINT chk_maintenance_impact_level_domain 
    CHECK (impact_level IN ('out-of-service', 'advisory'));
GO

-- ----------------------------------------------------------------------------
-- [Existing Entity]: SPACE
-- Action: Extract the usage_policy attribute and convert it into a standalone entity.
-- Phase 1 policy text cannot be decomposed safely into executable criteria. Preserve
-- every distinct value as legacy_policy_text, attach it to its original spaces, and
-- leave the executable criteria NULL. Administrators can normalize those criteria
-- later without losing the original data. A migrated legacy policy is therefore an
-- attached policy, but it will not auto-approve until at least one criterion is set.
-- ----------------------------------------------------------------------------
IF COL_LENGTH('dbo.SPACE', 'policy_id') IS NULL
    ALTER TABLE dbo.SPACE ADD policy_id INT NULL;
GO

IF COL_LENGTH('dbo.SPACE', 'usage_policy') IS NOT NULL
    EXEC ('INSERT INTO dbo.USAGE_POLICY (policy_name, legacy_policy_text)
           SELECT CONCAT(''Migrated Phase 1 policy '',
                         ROW_NUMBER() OVER (ORDER BY p.usage_policy)),
                  p.usage_policy
           FROM (SELECT DISTINCT usage_policy
                 FROM dbo.SPACE
                 WHERE usage_policy IS NOT NULL) p
           WHERE NOT EXISTS (SELECT 1 FROM dbo.USAGE_POLICY x
                             WHERE x.legacy_policy_text = p.usage_policy);');
GO

IF COL_LENGTH('dbo.SPACE', 'usage_policy') IS NOT NULL
    EXEC ('UPDATE s SET s.policy_id = p.policy_id
           FROM dbo.SPACE s JOIN dbo.USAGE_POLICY p
             ON p.legacy_policy_text = s.usage_policy
           WHERE s.policy_id IS NULL;');
GO

IF COL_LENGTH('dbo.SPACE', 'usage_policy') IS NOT NULL
    ALTER TABLE dbo.SPACE DROP COLUMN usage_policy;
GO

-- ============================================================================
-- 2. AFFECTED RELATIONSHIPS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SPACE (OPTIONAL) and FACILITY (OPTIONAL) -> 1:N
-- Preserve every Phase 1 SPACE_FACILITY association. For a facility previously
-- shared by several spaces, retain its original row for the first space and create
-- a distinct facility row for every additional space, as required by Phase 2.
-- Facilities with no Phase 1 association remain unassigned (space_code IS NULL).
-- ----------------------------------------------------------------------------
IF COL_LENGTH('dbo.FACILITY', 'space_code') IS NULL
    ALTER TABLE dbo.FACILITY ADD space_code VARCHAR(50) NULL;
GO

-- facility_name is no longer a candidate key because separate physical facility
-- instances in different spaces may have the same descriptive name.
IF OBJECT_ID('dbo.uq_facility_facility_name', 'UQ') IS NOT NULL
    ALTER TABLE dbo.FACILITY DROP CONSTRAINT uq_facility_facility_name;
GO

IF OBJECT_ID('dbo.SPACE_FACILITY', 'U') IS NOT NULL
BEGIN
    ;WITH ranked_association AS (
        SELECT sf.facility_id,
               sf.space_code,
               ROW_NUMBER() OVER (
                   PARTITION BY sf.facility_id ORDER BY sf.space_code
               ) AS association_number
        FROM dbo.SPACE_FACILITY sf
    )
    UPDATE f
       SET f.space_code = ra.space_code
    FROM dbo.FACILITY f
    JOIN ranked_association ra
      ON ra.facility_id = f.facility_id
     AND ra.association_number = 1
    WHERE f.space_code IS NULL;

    ;WITH ranked_association AS (
        SELECT sf.facility_id,
               sf.space_code,
               ROW_NUMBER() OVER (
                   PARTITION BY sf.facility_id ORDER BY sf.space_code
               ) AS association_number
        FROM dbo.SPACE_FACILITY sf
    )
    INSERT INTO dbo.FACILITY (facility_name, space_code)
    SELECT f.facility_name, ra.space_code
    FROM ranked_association ra
    JOIN dbo.FACILITY f ON f.facility_id = ra.facility_id
    WHERE ra.association_number > 1;

    DROP TABLE dbo.SPACE_FACILITY;
END;
GO

IF OBJECT_ID('dbo.fk_facility_space', 'F') IS NULL
ALTER TABLE dbo.FACILITY
    ADD CONSTRAINT fk_facility_space
    FOREIGN KEY (space_code) REFERENCES dbo.SPACE(space_code) ON DELETE CASCADE;
GO

-- ----------------------------------------------------------------------------
-- SPACE (OPTIONAL) and USAGE_POLICY (OPTIONAL) -> N:1
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.fk_space_policy', 'F') IS NULL
ALTER TABLE dbo.SPACE 
    ADD CONSTRAINT fk_space_policy 
    FOREIGN KEY (policy_id) REFERENCES dbo.USAGE_POLICY(policy_id);
GO

-- ----------------------------------------------------------------------------
-- BOOKING (OPTIONAL) and ACKNOWLEDGEMENT (MANDATORY) -> 1:N
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.fk_ack_booking', 'F') IS NULL
ALTER TABLE dbo.ACKNOWLEDGEMENT
    ADD CONSTRAINT fk_ack_booking
    FOREIGN KEY (booking_id) REFERENCES dbo.BOOKING(booking_id) ON DELETE CASCADE;
GO

-- ----------------------------------------------------------------------------
-- ACKNOWLEDGEMENT (MANDATORY) and MAINTENANCE_RECORD (OPTIONAL) -> N:1
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.fk_ack_maintenance', 'F') IS NULL
ALTER TABLE dbo.ACKNOWLEDGEMENT 
    ADD CONSTRAINT fk_ack_maintenance 
    FOREIGN KEY (maintenance_record_id) REFERENCES dbo.MAINTENANCE_RECORD(maintenance_id)
    ON DELETE CASCADE;
GO

-- ----------------------------------------------------------------------------
-- ROLE (MANDATORY) and USER (MANDATORY) -> 1:N
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.fk_user_role', 'F') IS NULL
ALTER TABLE dbo.[USER] 
    ADD CONSTRAINT fk_user_role 
    FOREIGN KEY (role_id) REFERENCES dbo.ROLE(role_id);
GO

-- ----------------------------------------------------------------------------
-- DEPARTMENT (OPTIONAL) and USER (MANDATORY) -> 1:N
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.fk_user_department', 'F') IS NULL
ALTER TABLE dbo.[USER]
    ADD CONSTRAINT fk_user_department
    FOREIGN KEY (department_id) REFERENCES dbo.DEPARTMENT(department_id);
GO

-- ----------------------------------------------------------------------------
-- ROLE (OPTIONAL) and USAGE_POLICY (OPTIONAL) -> M:N
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ROLE_USAGE_POLICY', 'U') IS NULL
CREATE TABLE dbo.ROLE_USAGE_POLICY (
    role_id INT NOT NULL,
    policy_id INT NOT NULL,
    CONSTRAINT pk_role_usage_policy PRIMARY KEY (role_id, policy_id),
    CONSTRAINT fk_rup_role FOREIGN KEY (role_id) REFERENCES dbo.ROLE(role_id) ON DELETE CASCADE,
    CONSTRAINT fk_rup_policy FOREIGN KEY (policy_id) REFERENCES dbo.USAGE_POLICY(policy_id) ON DELETE CASCADE
);
GO

-- ----------------------------------------------------------------------------
-- DEPARTMENT (OPTIONAL) and USAGE_POLICY (OPTIONAL) -> M:N
-- An empty set of departments for a policy means no department restriction.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.DEPARTMENT_USAGE_POLICY', 'U') IS NULL
CREATE TABLE dbo.DEPARTMENT_USAGE_POLICY (
    department_id INT NOT NULL,
    policy_id INT NOT NULL,
    CONSTRAINT pk_department_usage_policy PRIMARY KEY (department_id, policy_id),
    CONSTRAINT fk_dup_department FOREIGN KEY (department_id)
        REFERENCES dbo.DEPARTMENT(department_id) ON DELETE CASCADE,
    CONSTRAINT fk_dup_policy FOREIGN KEY (policy_id)
        REFERENCES dbo.USAGE_POLICY(policy_id) ON DELETE CASCADE
);
GO

-- Upgrade databases created by an earlier Phase 2 script that stored one
-- allowed department as USAGE_POLICY.department_allowed. Preserve those
-- values as normalized departments and junction rows before dropping the
-- obsolete text column.
IF COL_LENGTH('dbo.USAGE_POLICY', 'department_allowed') IS NOT NULL
BEGIN
    EXEC ('INSERT INTO dbo.DEPARTMENT (department_name)
           SELECT DISTINCT p.department_allowed
           FROM dbo.USAGE_POLICY p
           WHERE p.department_allowed IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM dbo.DEPARTMENT d
                             WHERE d.department_name = p.department_allowed);');

    EXEC ('INSERT INTO dbo.DEPARTMENT_USAGE_POLICY (department_id, policy_id)
           SELECT d.department_id, p.policy_id
           FROM dbo.USAGE_POLICY p
           JOIN dbo.DEPARTMENT d
             ON d.department_name = p.department_allowed
           WHERE p.department_allowed IS NOT NULL
             AND NOT EXISTS (
                 SELECT 1 FROM dbo.DEPARTMENT_USAGE_POLICY dp
                 WHERE dp.department_id = d.department_id
                   AND dp.policy_id = p.policy_id
             );');

    EXEC ('ALTER TABLE dbo.USAGE_POLICY DROP COLUMN department_allowed;');
END;
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

    DECLARE @approval_time DATETIME2 = SYSDATETIME();

    -- Work with the submitted rows first; qualifying pending bookings are changed to
    -- approved by the single policy check below. Business hours are defined for this
    -- migration as Monday-Friday, 08:00 through 17:00.
    DECLARE @effective TABLE (
        effective_row_id INT IDENTITY(1,1) NOT NULL,
        booking_id INT NULL,
        requester_id INT NOT NULL,
        space_code VARCHAR(50) NOT NULL,
        requested_start_time DATETIME2 NOT NULL,
        requested_end_time DATETIME2 NOT NULL,
        purpose VARCHAR(50) NOT NULL,
        expected_participants INT NOT NULL,
        booking_status VARCHAR(50) NOT NULL,
        decision_staff_id INT NULL,
        decision_time DATETIME2 NULL,
        decision_note VARCHAR(MAX) NULL,
        rejection_reason VARCHAR(255) NULL,
        actual_start_time DATETIME2 NULL,
        check_in_staff_id INT NULL,
        initial_condition VARCHAR(MAX) NULL,
        actual_end_time DATETIME2 NULL,
        completion_staff_id INT NULL,
        final_condition VARCHAR(MAX) NULL,
        usage_notes VARCHAR(MAX) NULL
    );

    INSERT INTO @effective
    SELECT i.booking_id, i.requester_id, i.space_code,
           i.requested_start_time, i.requested_end_time, i.purpose,
           i.expected_participants, i.booking_status, i.decision_staff_id,
           i.decision_time, i.decision_note,
           i.rejection_reason, i.actual_start_time, i.check_in_staff_id,
           i.initial_condition, i.actual_end_time, i.completion_staff_id,
           i.final_condition, i.usage_notes
    FROM inserted i;

    -- Only the policy-evaluation path below may create an approval without a
    -- decision staff member. Callers must submit new candidates as pending.
    -- Existing system-approved rows may still be edited without inventing a
    -- staff decision.
    IF EXISTS (
        SELECT 1
        FROM @effective e
        WHERE e.booking_status = 'approved'
          AND e.decision_staff_id IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM deleted d
              WHERE d.booking_id = e.booking_id
                AND d.booking_status = 'approved'
                AND d.decision_staff_id IS NULL
          )
    )
    BEGIN
        ;THROW 50000, 'An approval without decision staff must be produced automatically from a pending booking.', 1;
    END

    -- A pending booking is auto-approved when it passes every applicable condition
    -- of the policy attached to its space. NULL criteria mean "no restriction".
    UPDATE e
    SET e.booking_status    = 'approved',
        e.decision_staff_id = NULL,
        e.decision_time     = @approval_time,
        e.decision_note     = 'Automatically approved: all usage-policy criteria satisfied.'
    FROM @effective e
    JOIN dbo.SPACE s ON s.space_code = e.space_code
    JOIN dbo.USAGE_POLICY p ON p.policy_id = s.policy_id
    JOIN dbo.[USER] u ON u.user_id = e.requester_id
    WHERE e.booking_status = 'pending'
      -- Preserved Phase 1 free text is not executable until administrators convert it.
      AND p.legacy_policy_text IS NULL
      AND (p.max_duration_minutes IS NULL
           OR DATEDIFF(MINUTE, e.requested_start_time,
                               e.requested_end_time) <= p.max_duration_minutes)
      AND (ISNULL(p.requires_business_hours, 0) = 0
           OR (DATEDIFF(DAY, '19000101', CAST(e.requested_start_time AS DATE)) % 7 BETWEEN 0 AND 4
               AND CAST(e.requested_start_time AS TIME) >= '08:00:00'
               AND CAST(e.requested_end_time AS TIME) <= '17:00:00'
               AND CAST(e.requested_start_time AS DATE) = CAST(e.requested_end_time AS DATE)))
      AND (NOT EXISTS (
               SELECT 1
               FROM dbo.DEPARTMENT_USAGE_POLICY dp
               WHERE dp.policy_id = p.policy_id
           )
           OR EXISTS (
               SELECT 1
               FROM dbo.DEPARTMENT_USAGE_POLICY dp
               WHERE dp.policy_id = p.policy_id
                 AND dp.department_id = u.department_id
           ))
      AND (NOT EXISTS (
               SELECT 1 FROM dbo.ROLE_USAGE_POLICY rp
               WHERE rp.policy_id = p.policy_id
           )
           OR EXISTS (
               SELECT 1 FROM dbo.ROLE_USAGE_POLICY rp
               WHERE rp.policy_id = p.policy_id
                 AND rp.role_id = u.role_id
           ));

    -- Updated Rule 2 (Maintenance Blocks): 
    -- Allows booking if maintenance is 'advisory', blocks if 'out-of-service'.
    IF EXISTS (
        SELECT 1
        FROM @effective i
        INNER JOIN dbo.SPACE s ON i.space_code = s.space_code
        WHERE s.current_status IN ('temporarily_closed', 'retired')
           OR EXISTS (
               SELECT 1 FROM dbo.MAINTENANCE_RECORD mr
               WHERE mr.space_code = s.space_code
                 AND mr.status IN ('reported', 'in_progress')
                 AND mr.impact_level = 'out-of-service'
                 AND (i.requested_start_time < ISNULL(mr.completion_time, '9999-12-31') AND i.requested_end_time > mr.start_time)
           )
    )
    BEGIN
        ;THROW 50000, 'Cannot book space: Space is closed, retired, or has active out-of-service maintenance during the requested period.', 1;
    END

    -- Updated Rule 20 / Phase 1 Rule 7: Overlapping approved booking prevention
    IF EXISTS (
        SELECT 1
        FROM @effective i
        WHERE i.booking_status = 'approved'
          AND EXISTS (
              SELECT 1
              FROM dbo.BOOKING b WITH (UPDLOCK, HOLDLOCK)
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

    -- Also reject conflicts contained in a single multi-row statement.
    IF EXISTS (
        SELECT 1
        FROM @effective a
        JOIN @effective b
          ON a.booking_status = 'approved'
         AND b.booking_status = 'approved'
         AND a.effective_row_id < b.effective_row_id
         AND a.space_code = b.space_code
         AND a.requested_start_time < b.requested_end_time
         AND a.requested_end_time > b.requested_start_time
    )
    BEGIN
        ;THROW 50000, 'The same statement contains overlapping approved bookings for one space.', 1;
    END

    -- Updated Rule 9: Approval / Rejection role authorization (Joined with new ROLE table)
    IF EXISTS (
        SELECT 1
        FROM @effective i
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
        FROM @effective i
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

    -- Forward valid operations (INSERT/UPDATE logic). Capture the persisted IDs so
    -- advisory acknowledgements can be synchronized after either operation.
    DECLARE @affected_booking TABLE (booking_id INT PRIMARY KEY);

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
        INNER JOIN @effective i ON t.booking_id = i.booking_id;

        INSERT INTO @affected_booking (booking_id)
        SELECT booking_id FROM @effective;
    END
    ELSE
    BEGIN
        MERGE dbo.BOOKING AS target
        USING @effective AS source
           ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (
                requester_id, space_code, requested_start_time, requested_end_time,
                purpose, expected_participants, booking_status, decision_staff_id,
                decision_time, decision_note, rejection_reason, actual_start_time,
                check_in_staff_id, initial_condition, actual_end_time,
                completion_staff_id, final_condition, usage_notes
            )
            VALUES (
                source.requester_id, source.space_code, source.requested_start_time,
                source.requested_end_time, source.purpose, source.expected_participants,
                source.booking_status, source.decision_staff_id, source.decision_time,
                source.decision_note, source.rejection_reason, source.actual_start_time,
                source.check_in_staff_id, source.initial_condition, source.actual_end_time,
                source.completion_staff_id, source.final_condition, source.usage_notes
            )
        OUTPUT inserted.booking_id INTO @affected_booking (booking_id);
    END


    -- Remove acknowledgements that no longer correspond to an active overlapping
    -- advisory (for example after rescheduling), then record all advisories shown at
    -- booking time. acknowledged_at remains NULL until the requester submits the
    -- acknowledgement; the application sets the timestamp upon submission.
    DELETE a
    FROM dbo.ACKNOWLEDGEMENT a
    JOIN @affected_booking ab ON ab.booking_id = a.booking_id
    JOIN dbo.BOOKING b ON b.booking_id = ab.booking_id
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.MAINTENANCE_RECORD mr
        WHERE mr.maintenance_id = a.maintenance_record_id
          AND mr.space_code = b.space_code
          AND mr.status IN ('reported', 'in_progress')
          AND mr.impact_level = 'advisory'
          AND b.requested_start_time < ISNULL(mr.completion_time, '9999-12-31')
          AND b.requested_end_time > mr.start_time
    );

    INSERT INTO dbo.ACKNOWLEDGEMENT (booking_id, maintenance_record_id, acknowledged_at)
    SELECT b.booking_id, mr.maintenance_id, NULL
    FROM @affected_booking ab
    JOIN dbo.BOOKING b ON b.booking_id = ab.booking_id
    JOIN dbo.MAINTENANCE_RECORD mr
      ON mr.space_code = b.space_code
     AND mr.status IN ('reported', 'in_progress')
     AND mr.impact_level = 'advisory'
     AND b.requested_start_time < ISNULL(mr.completion_time, '9999-12-31')
     AND b.requested_end_time > mr.start_time
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.ACKNOWLEDGEMENT a
        WHERE a.booking_id = b.booking_id
          AND a.maintenance_record_id = mr.maintenance_id
    );
END;
GO

-- Keep advisory acknowledgements synchronized when an open maintenance record's
-- impact changes. Downgrading to advisory creates one acknowledgement for every
-- overlapping booking; escalating to out-of-service removes those advisory-only
-- acknowledgements. The timestamp records when the requester is considered informed.
CREATE OR ALTER TRIGGER dbo.trg_maintenance_sync_acknowledgements
ON dbo.MAINTENANCE_RECORD
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Impact can be escalated or downgraded only while maintenance is open.
    -- THROW in this AFTER trigger rolls the originating update back.
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.maintenance_id = i.maintenance_id
        WHERE i.impact_level <> d.impact_level
          AND i.status NOT IN ('reported', 'in_progress')
    )
    BEGIN
        ;THROW 50000, 'Maintenance impact level can change only while the record is open.', 1;
    END

    DELETE a
    FROM dbo.ACKNOWLEDGEMENT a
    JOIN inserted i ON i.maintenance_id = a.maintenance_record_id
    JOIN deleted d ON d.maintenance_id = i.maintenance_id
    WHERE d.impact_level = 'advisory'
      AND i.impact_level <> 'advisory';

    INSERT INTO dbo.ACKNOWLEDGEMENT (booking_id, maintenance_record_id, acknowledged_at)
    SELECT b.booking_id, i.maintenance_id, NULL
    FROM inserted i
    JOIN deleted d ON d.maintenance_id = i.maintenance_id
    JOIN dbo.BOOKING b
      ON b.space_code = i.space_code
     AND b.requested_start_time < ISNULL(i.completion_time, '9999-12-31')
     AND b.requested_end_time > i.start_time
    WHERE i.impact_level = 'advisory'
      AND d.impact_level <> 'advisory'
      AND i.status IN ('reported', 'in_progress')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.ACKNOWLEDGEMENT a
          WHERE a.booking_id = b.booking_id
            AND a.maintenance_record_id = i.maintenance_id
      );
END;
GO

-- Rule 19: staff can query approved bookings affected by an active
-- out-of-service maintenance record after escalation.
CREATE OR ALTER VIEW dbo.vw_approved_bookings_affected_by_outage
AS
SELECT mr.maintenance_id,
       b.booking_id,
       b.requester_id,
       b.space_code,
       b.requested_start_time,
       b.requested_end_time
FROM dbo.MAINTENANCE_RECORD mr
JOIN dbo.BOOKING b
  ON b.space_code = mr.space_code
 AND b.booking_status = 'approved'
 AND b.requested_start_time < ISNULL(mr.completion_time,
                                     CONVERT(DATETIME2, '9999-12-31'))
 AND b.requested_end_time > mr.start_time
WHERE mr.impact_level = 'out-of-service'
  AND mr.status IN ('reported', 'in_progress');
GO
