# Conceptual Database Design (ERD)
## 1. Conceptual Entity-Relationship Diagram
### Diagram 
Copy the code below and paste it into a live editor like Mermaid Live to view the diagram. The diagram has been updated to include the new entities and relationships required for Phase 2.

```mermaid
erDiagram
    %% Existing Phase 1 Relationships
    USER ||--o{ BOOKING : "submits"
    USER |o--o{ BOOKING : "decides_on"
    USER |o--o{ BOOKING : "checks_in"
    USER |o--o{ BOOKING : "completes"
    SPACE ||--o{ BOOKING : "hosts"
    USER ||--o{ MAINTENANCE_RECORD : "reports"
    USER |o--o{ MAINTENANCE_RECORD : "assigned_to"
    SPACE ||--o{ MAINTENANCE_RECORD : "undergoes"
    SPACE |o--o{ FACILITY : "contains"
    
    %% Updated Phase 2 Relationships
    ROLE ||--|{ USER : "assigned_to"
    USAGE_POLICY |o--|{ SPACE : "applied_to"
    ROLE }o--o{ USAGE_POLICY : "permitted_by"
    BOOKING }|--o{ ACKNOWLEDGEMENT : "requires"
    MAINTENANCE_RECORD ||--o| ACKNOWLEDGEMENT : "referenced_in"

    ROLE {
        int role_id PK
        string role_name
    }

    USER {
        int user_id PK
        string full_name
        string email
        string phone_number
        string department
        string account_status
    }

    SPACE {
        string space_code PK
        string space_name
        string space_type
        string building
        int floor
        string room_number
        int capacity
        string current_status
    }

    FACILITY {
        int facility_id PK
        string facility_name
    }

    BOOKING {
        int booking_id PK
        datetime requested_start_time
        datetime requested_end_time
        string purpose
        int expected_participants
        string booking_status
        datetime decision_time
        string decision_note
        string rejection_reason
        datetime actual_start_time
        string initial_condition
        datetime actual_end_time
        string final_condition
        string usage_notes
    }

    MAINTENANCE_RECORD {
        int maintenance_id PK
        string problem_description
        datetime start_time
        datetime completion_time
        string status
        string result_note
        string impact_level
    }
    
    USAGE_POLICY {
        int policy_id PK
        string policy_name
        int max_duration_minutes
        boolean requires_business_hours
        string department_allowed
    }
    
    ACKNOWLEDGEMENT {
        int acknowledgement_id PK
    }
```

### Conceptual Data Dictionary

#### Entities and Attributes

*   **ROLE**
    *   `role_id` (PK) — int
    *   `role_name` — string
*   **USER**
    *   `user_id` (PK) — int
    *   `full_name` — string
    *   `email` — string
    *   `phone_number` — string
    *   `department` — string
    *   `account_status` — string
*   **SPACE**
    *   `space_code` (PK) — string
    *   `space_name` — string
    *   `space_type` — string
    *   `building` — string
    *   `floor` — int
    *   `room_number` — string
    *   `capacity` — int
    *   `current_status` — string
*   **FACILITY**
    *   `facility_id` (PK) — int
    *   `facility_name` — string
*   **BOOKING**
    *   `booking_id` (PK) — int
    *   `requested_start_time` — datetime
    *   `requested_end_time` — datetime
    *   `purpose` — string
    *   `expected_participants` — int
    *   `booking_status` — string
    *   `decision_time` — datetime
    *   `decision_note` — string
    *   `rejection_reason` — string
    *   `actual_start_time` — datetime
    *   `initial_condition` — string
    *   `actual_end_time` — datetime
    *   `final_condition` — string
    *   `usage_notes` — string
*   **MAINTENANCE_RECORD**
    *   `maintenance_id` (PK) — int
    *   `problem_description` — string
    *   `start_time` — datetime
    *   `completion_time` — datetime
    *   `status` — string
    *   `result_note` — string
    *   `impact_level` — string
*   **USAGE_POLICY**
    *   `policy_id` (PK) — int
    *   `policy_name` — string
    *   `max_duration_minutes` — int
    *   `requires_business_hours` — boolean
    *   `department_allowed` — string
*   **ACKNOWLEDGEMENT**
    *   `acknowledgement_id` (PK) — int

#### Relationship Summary

| Entity (Left) | Cardinality | Entity (Right) | Verb Phrase | Participation | Description |
|---|---|---|---|---|---|
| ROLE | 1 : N | USER | assigned_to | Role mandatory; User mandatory | A user must have exactly one role and a role must belong to at least one user. |
| USER | 1 : N | BOOKING | submits | User optional; Booking mandatory | Each booking must be submitted by exactly one requester; each user may submit zero or many bookings. |
| USER | 1 : N | BOOKING | decides_on | User optional; Booking optional | Each booking may be decided on by at most one staff member; each staff member may decide on zero or many bookings. |
| USER | 1 : N | BOOKING | checks_in | User optional; Booking optional | Each booking may be checked in by at most one staff member; each staff member may check in zero or many bookings. |
| USER | 1 : N | BOOKING | completes | User optional; Booking optional | Each booking may be completed by at most one staff member; each staff member may complete zero or many bookings. |
| SPACE | 1 : N | BOOKING | hosts | Space optional; Booking mandatory | Each booking must reserve exactly one space; each space may host zero or many bookings over time. |
| USER | 1 : N | MAINTENANCE_RECORD | reports | User optional; MR mandatory | Each maintenance record must have exactly one reporter; each user may report zero or many records. |
| USER | 1 : N | MAINTENANCE_RECORD | assigned_to | User optional; MR optional | Each maintenance record may be assigned to at most one staff member; each staff member may be assigned zero or many records. |
| SPACE | 1 : N | MAINTENANCE_RECORD | undergoes | Space optional; MR mandatory | Each maintenance record must concern exactly one space; each space may undergo zero or many maintenance records. |
| SPACE | 1 : N | FACILITY | contains | Space optional; Facility optional | Each space may contain zero or many facilities; each facility may exist in at most one space. |
| USAGE_POLICY | 1 : N | SPACE | applied_to | Policy optional; Space mandatory | A space can have 0 or 1 usage policy, and a specific usage policy must be applied to at least one space. |
| ROLE | M : N | USAGE_POLICY | permitted_by | Role optional; Policy optional | A usage policy might only allow some specific roles or might not, and a role does not have to be listed in a usage policy. |
| BOOKING | M : N | ACKNOWLEDGEMENT | requires | Booking mandatory; Ack optional | A single booking may require zero or multiple acknowledgements, and an acknowledgement must belong to at least one booking. |
| MAINTENANCE_RECORD | 1 : 1 | ACKNOWLEDGEMENT | referenced_in | MR mandatory; Ack optional | An acknowledgement belongs to exactly one maintenance record, and a maintenance record can be referenced in zero or one acknowledgement. |

---

## 2. Logical Database Design (Relational Schema)
### Diagram
Copy the code below and paste it into [dbdiagram.io](https://dbdiagram.io/)  to view the updated schema.
```dbml
// --- Tables ---

Table ROLE {
  role_id integer [pk, increment]
  role_name varchar(50) [not null]
}

Table USER {
  user_id integer [pk, increment]
  full_name varchar(255) [not null]
  email varchar(255) [not null, unique]
  phone_number varchar(20) [not null, unique]
  role_id integer [not null]
  department varchar(255) [not null]
  account_status varchar(50) [not null, default: 'active']
}

Table USAGE_POLICY {
  policy_id integer [pk, increment]
  policy_name varchar(255) [not null]
  max_duration_minutes integer
  requires_business_hours boolean
  department_allowed varchar(255)
}

Table ROLE_USAGE_POLICY {
  role_id integer [not null]
  policy_id integer [not null]
  
  Indexes {
    (role_id, policy_id) [pk, name: 'pk_role_usage_policy']
  }
}

Table SPACE {
  space_code varchar(50) [pk]
  space_name varchar(255) [not null]
  space_type varchar(50) [not null]
  building varchar(255) [not null]
  floor integer [not null]
  room_number varchar(50) [not null]
  capacity integer [not null]
  current_status varchar(50) [not null, default: 'available']
  policy_id integer 

  Indexes {
    (building, floor, room_number) [unique, name: 'uq_space_location']
  }
}

Table FACILITY {
  facility_id integer [pk, increment]
  facility_name varchar(255) [not null]
  space_code varchar(50)
}

Table BOOKING {
  booking_id integer [pk, increment]
  requester_id integer [not null]
  space_code varchar(50) [not null]
  requested_start_time datetime [not null]
  requested_end_time datetime [not null]
  purpose varchar(50) [not null]
  expected_participants integer [not null]
  booking_status varchar(50) [not null, default: 'pending']
  decision_staff_id integer
  decision_time datetime
  decision_note text
  rejection_reason text
  check_in_staff_id integer
  actual_start_time datetime
  initial_condition text
  completion_staff_id integer
  actual_end_time datetime
  final_condition text
  usage_notes text
}

Table MAINTENANCE_RECORD {
  maintenance_id integer [pk, increment]
  space_code varchar(50) [not null]
  reporter_id integer [not null]
  assigned_staff_id integer
  problem_description text [not null]
  start_time datetime [not null]
  completion_time datetime
  status varchar(50) [not null, default: 'reported']
  result_note text
  impact_level varchar(50)
}

Table ACKNOWLEDGEMENT {
  acknowledgement_id integer [pk, increment]
  maintenance_id integer [not null, unique]
}

Table BOOKING_ACKNOWLEDGEMENT {
  booking_id integer [not null]
  acknowledgement_id integer [not null]
  
  Indexes {
    (booking_id, acknowledgement_id) [pk, name: 'pk_booking_acknowledgement']
  }
}

// --- Relationships ---

// USER referencing ROLE
Ref: USER.role_id > ROLE.role_id

// SPACE referencing USAGE_POLICY
Ref: SPACE.policy_id > USAGE_POLICY.policy_id

// ROLE_USAGE_POLICY junction table (M:N between ROLE and USAGE_POLICY)
Ref: ROLE_USAGE_POLICY.role_id > ROLE.role_id [delete: cascade]
Ref: ROLE_USAGE_POLICY.policy_id > USAGE_POLICY.policy_id [delete: cascade]

// FACILITY referencing SPACE (1:N containment)
Ref: FACILITY.space_code > SPACE.space_code [delete: cascade]

// BOOKING referencing SPACE
Ref: BOOKING.space_code > SPACE.space_code

// BOOKING referencing USER (multi-role)
Ref: BOOKING.requester_id > USER.user_id
Ref: BOOKING.decision_staff_id > USER.user_id
Ref: BOOKING.check_in_staff_id > USER.user_id
Ref: BOOKING.completion_staff_id > USER.user_id

// MAINTENANCE_RECORD referencing SPACE
Ref: MAINTENANCE_RECORD.space_code > SPACE.space_code

// MAINTENANCE_RECORD referencing USER (multi-role)
Ref: MAINTENANCE_RECORD.reporter_id > USER.user_id
Ref: MAINTENANCE_RECORD.assigned_staff_id > USER.user_id

// ACKNOWLEDGEMENT referencing MAINTENANCE_RECORD (1:1 relation)
Ref: ACKNOWLEDGEMENT.maintenance_id - MAINTENANCE_RECORD.maintenance_id

// BOOKING_ACKNOWLEDGEMENT junction table (M:N between BOOKING and ACKNOWLEDGEMENT)
Ref: BOOKING_ACKNOWLEDGEMENT.booking_id > BOOKING.booking_id [delete: cascade]
Ref: BOOKING_ACKNOWLEDGEMENT.acknowledgement_id > ACKNOWLEDGEMENT.acknowledgement_id [delete: cascade]
```

### Business Integrity Constraints (T-SQL Domain CHECKs)
*Note: As Microsoft SQL Server (T-SQL) does not natively support the `ENUM` data type, categorical domains and scalar boundaries are explicitly enforced via single-row table `CHECK` constraints.*

**USER Domain Checks:**
* **`chk_user_role_domain`**: `CHECK ([role] IN ('student', 'lecturer', 'teaching_assistant', 'facility_staff', 'department_administrator', 'facility_manager'))`
* **`chk_user_account_status_domain`**: `CHECK ([account_status] IN ('active', 'suspended', 'deactivated'))`

**SPACE Domain Checks:**
* **`chk_space_type_domain`**: `CHECK ([space_type] IN ('auditorium', 'classroom', 'computer_lab', 'project_lab', 'meeting_room', 'student_workspace'))`
* **`chk_space_capacity_boundary`**: `CHECK ([capacity] > 0)`
* **`chk_space_current_status_domain`**: `CHECK ([current_status] IN ('available', 'in_use', 'under_maintenance', 'temporarily_closed', 'retired'))`

**BOOKING Domain Checks:**
* **`chk_booking_purpose_domain`**: `CHECK ([purpose] IN ('lecture', 'examination', 'seminar', 'workshop', 'meeting', 'student_activity', 'administrative_event'))`
* **`chk_booking_expected_participants_boundary`**: `CHECK ([expected_participants] > 0)`
* **`chk_booking_status_domain`**: `CHECK ([booking_status] IN ('pending', 'approved', 'rejected', 'cancelled', 'checked_in', 'completed', 'no_show'))`
* **`chk_booking_time_order`**: `CHECK ([requested_start_time] < [requested_end_time])`
* **`chk_booking_actual_time_order`**: `CHECK ([actual_start_time] IS NULL OR [actual_end_time] IS NULL OR [actual_start_time] < [actual_end_time])`
* **`chk_booking_decision_fields`**: `CHECK ([booking_status] NOT IN ('approved', 'rejected') OR ([decision_staff_id] IS NOT NULL AND [decision_time] IS NOT NULL AND [decision_note] IS NOT NULL))`
* **`chk_booking_rejection_reason`**: `CHECK ([booking_status] <> 'rejected' OR [rejection_reason] IS NOT NULL)`
* **`chk_booking_checkin_fields`**: `CHECK ([booking_status] NOT IN ('checked_in', 'completed') OR ([check_in_staff_id] IS NOT NULL AND [actual_start_time] IS NOT NULL AND [initial_condition] IS NOT NULL))`
* **`chk_booking_completion_fields`**: `CHECK ([booking_status] <> 'completed' OR ([completion_staff_id] IS NOT NULL AND [actual_end_time] IS NOT NULL AND [final_condition] IS NOT NULL AND [usage_notes] IS NOT NULL))`

**MAINTENANCE_RECORD Domain Checks:**
* **`chk_maintenance_status_domain`**: `CHECK ([status] IN ('reported', 'in_progress', 'completed'))`
* **`chk_maintenance_time_order`**: `CHECK ([completion_time] IS NULL OR [start_time] < [completion_time])`