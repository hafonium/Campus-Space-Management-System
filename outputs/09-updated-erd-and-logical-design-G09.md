# Conceptual Database Design (ERD)
## 1. Conceptual Entity-Relationship Diagram
Copy the code below and paste it into a live editor like Mermaid Live to view the diagram. The diagram has been updated to include the new entities and relationships required for Phase 2.

```mermaid
erDiagram
    USER ||--o{ BOOKING : "submits"
    USER |o--o{ BOOKING : "decides_on"
    USER |o--o{ BOOKING : "checks_in"
    USER |o--o{ BOOKING : "completes"
    SPACE ||--o{ BOOKING : "hosts"
    USER ||--o{ MAINTENANCE_RECORD : "reports"
    USER |o--o{ MAINTENANCE_RECORD : "assigned_to"
    SPACE ||--o{ MAINTENANCE_RECORD : "undergoes"
    SPACE }o--o{ FACILITY : "contains"
    SPACE }o--|{ USAGE_POLICY : "governed_by"
    BOOKING ||--o{ ACKNOWLEDGEMENT : "requires"
    MAINTENANCE_RECORD |o--|| ACKNOWLEDGEMENT : "referenced_in"

    USER {
        int user_id PK
        string full_name
        string email
        string phone_number
        string role
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
        string allowed_roles
        boolean requires_business_hours
        string department_allowed
    }
    
    ACKNOWLEDGEMENT {
        int acknowledgement_id PK
    }
```

