# Requirement Change Analysis

## 1. Affected Entities and Attributes
To support the new Phase 2 requirements, the database schema must be updated with new attributes and entities:
*   **`USER`**
    * **Action:** Extract attribute `role` into a standalone entity and is linked via `role_id`.
*   **`BOOKING`**
    * **Action:** Does not require decision_staff_id for an auto-approval booking.
*   **`MAINTENANCE_RECORD`**: 
    *   **Action:** Add a new attribute `impact_level`.
    *   **Values:** `out-of-service` or `advisory`.
*   **`SPACE`**:
    *   **Action:** Re-evaluate the `space_type` attribute to designate which types are eligible for auto-approval.
    *   **Action:** Extract the `usage_policy` attribute and convert it into a standalone entity.
*   **`ROLE`** (New Entity):
    *   **Action:** Create this entity to store roles for users and allow `USAGE_POLICY` to have multiple `allowed_roles` 
    *   **Attributes:**
        *   `role_id`: Unique identifier for the role.
        *   `role_name`: e.g., "Staff", "Student".
*   **`ACKNOWLEDGEMENT`** (New Entity):
    *   **Action:** Create this entity to store records of users acknowledging advisory maintenance warnings during the booking process.
        *   `booking_id`: Links to the booking
        *   `maintenance_record_id`: Links to the specific 
        `MAINTENANCE_RECORD` (must be `advisory`) that was active at the time.
        *   `acknowledged_at`: Used to check 
*   **`USAGE_POLICY`** (New Entity):
    *   **Action:** Create this entity to manage dynamic rules that determine auto-approval eligibility for spaces.
    *   **Attributes:**
        *   `policy_id`: Unique identifier for the policy.
        *   `policy_name`: e.g., "Standard Auto-Approve", "Faculty Short Lecture".
        *   `max_duration_minutes` : The maximum allowed booking length to qualify for auto-approval (e.g., 120 minutes).
        *   `requires_business_hours`: If `true`, auto-approval only works during standard operating hours.
        * `department_allowed`: A space can only be auto-approved by a user from a specific department.
        *   `legacy_policy_text`: Nullable copy of the original Phase 1 `SPACE.usage_policy` text. It preserves existing policy data during migration because free-form text cannot be converted reliably into the structured auto-approval conditions. A policy containing this value is not executable until an administrator configures the structured conditions.

### 1.1. Migration Approach for Existing Usage Policies

Each distinct Phase 1 `SPACE.usage_policy` value is inserted into `USAGE_POLICY.legacy_policy_text`, and the corresponding spaces are linked to that migrated policy through `SPACE.policy_id`. The original `SPACE.usage_policy` column is dropped only after this mapping is completed. This preserves existing data while preventing unparsed legacy text from causing automatic approval.

## 2. Affected Relationships
The extraction of usage policies and the addition of acknowledgements require new structural relationships:

*   **`SPACE` (OPTIONAL) and `USAGE_POLICY` (MANDATORY)** : Introduce a Many-to-One (**N:1**) relationship. A space can have 0 or 1 usage policy, and a specific usage policy **MUST** be applied to at least one space.
*   **`BOOKING` (OPTIONAL) and `ACKNOWLEDGEMENT` (MANDATORY)** : Introduce a Many-to-Many (**M:N**) relationship. A single booking may require some acknowledgements, and an acknowledgement must belong to some bookings.

*   **`ACKNOWLEDGEMENT` (MANDATORY) and `MAINTENANCE_RECORD` (OPTIONAL)**: Introduce a Many-to-One (**N:1**) relationship. An acknowledgement belong to a maintenance record.

**`ACKNOWLEDGEMENT` (MANDATORY) and `BOOKING` (OPTIONAL)**: Introduce Many-to-One (**N:1**) relationship. An acknowledgement must be stored with a booking.

*   **`ROLE` (MANDATORY) and `USER` (MANDATORY)**: Introduce a One-to-Many (**1:N**) relationship. A user must have a role and a role must belong to at least one user.

*   **`ROLE` (OPTIONAL) and `USAGE_POLICY` (OPTIONAL)**: Introduce a Many-to-Many (**M:N**) relationship. A usage policy might only allow some specific roles or might not. A role does not have to be listed in a usage policy.

## 3. Business Rules 

### 3.1. Modified Business Rules (Updates from Phase 1)
*   **Updated Rule 2 (Maintenance Blocks):** A space that is temporarily closed, retired, or under maintenance with an `out-of-service` impact level cannot be booked for any time period that overlaps the maintenance period. However, if the maintenance has an `advisory` impact level, the space can still be booked.
*   **Updated Rule 9 (Approval Channels):** Booking requests must generally be approved or rejected by facility staff or managers. The exception is for selected space types, where requests that satisfy the usage policy may be approved automatically by the system at submission time (instant booking).
*   **Updated Rule 14 (Auto-approve):** If a new or changed pending booking satisfies every applicable usage-policy condition of its space, the system changes its status to `approved` and records the approval time in `decision_time`. Because the system made the decision, `decision_staff_id` may remain NULL.

### 3.2. New Business Rules (Additions for Phase 2)
*   **Rule 15 (Advisory Notification):** When a space with an active `advisory` maintenance is booked, the system must notify the requester of all active advisories on that space at booking time. The system must record an acknowledgement that the requester was informed and store it with the booking. 
*   **Rule 16 (Acknowledge informed):** `acknowledge_at` is null when the user has not been submitted it yet. However, when a user is informed of an acknowledge, its `acknowledged_at` must be not null. 
*   **Rule 16 (Concurrent Maintenance):** A space may have several active maintenance records at the same time, with different impact levels.
*   **Rule 17 (Impact Escalation):** The impact level of a maintenance record may be escalated (e.g., from `advisory` to `out-of-service`) or downgraded while the maintenance is still open.
*   **Rule 18 (Escalation Resolution):** If an `advisory` maintenance is escalated to `out-of-service`, the system must identify all already-approved bookings that overlap the maintenance period so that staff can contact the affected requesters.
*   **Rule 19 (Concurrency Safety):** The system must ensure that two approved bookings cannot use the same space during overlapping time periods, regardless of whether the bookings are created through instant booking or staff approval. This rule must remain valid even when multiple users or staff members perform operations simultaneously.

## 4. Concurrency Conflicts Analysis
The introduction of auto-approval and dynamic maintenance statuses creates several potential race conditions that the system must safely handle:

*   **`BOOKING` vs. `BOOKING` (Time Overlaps):**
    *   **Auto vs. Auto:** Two instant booking requests for overlapping times submitted at the exact same millisecond.
    *   **Auto vs. Staff:** A staff member manually approves a pending request at the exact moment an automated instant booking is processed for the same time slot.
    *   **Staff vs. Staff:** Two different staff members reviewing the queue manually decide (approve/reject) overlapping requests simultaneously.
    *   **Update vs. Approve/Update (Rescheduling Conflict):** A user or staff modifies the time schedule of an existing booking (e.g., extending the duration or shifting the time slot) at the exact same moment another booking request for that newly requested time is approved (either manually or automatically). Both operations check availability simultaneously, assume the slot is free, and save successfully, resulting in a double-booked space.
*   **`BOOKING` vs. `MAINTENANCE` (Status Changes):**
    *   A staff member updates a maintenance record (e.g., adding a new record, deleting one, or escalating `advisory` to `out-of-service`) at the exact same moment a booking request is being approved. This could result in an approved booking on an out-of-service room.
*   **`BOOKING` vs. `ACKNOWLEDGEMENT` (Data Integrity):**
    *   Advisory statuses changing during the checkout process, causing the user to submit acknowledgements that no longer match the database state at the time of final approval.
*   **`BOOKING` (Auto-Approve) vs. `USAGE_POLICY`:**
    *   An administrator modifies, adds, or deletes a usage policy exactly when the system is evaluating an incoming request against those policies to determine auto-approval eligibility.
*   **`BOOKING` vs. `USER` (Role/Profile Changes):**
    *   A user's profile information or authorization level changes at the same time they submit a booking, potentially causing bypass the approval conditions.
*   **`BOOKING` vs. `SPACE` (Attribute Changes):**
    *   A space's core attributes (e.g., capacity, equipment, or space type) are modified by a facility manager while the system is concurrently evaluating a booking request based on the previous attributes.
