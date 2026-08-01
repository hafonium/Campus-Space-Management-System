# Business Requirement Analysis

## 1. Business purpose

The School of Computer Science needs this system to replace its current manual and fragmented approach for coordinating shared campus space usage. The existing process, which relies on email, phone calls, and manually maintained spreadsheets, causes operational problems such as double-booking, unclear approval workflows, poor visibility into room maintenance status, and difficulty preventing bookings on unavailable spaces. The system supports fair space allocation among users, improves operational efficiency for facility staff, and provides historical tracking for planning, oversight, and accountability.

**(Gate check passed:** explains the organizational need, identifies clear operational problems (double-booking, unclear approvals, poor maintenance visibility), states intended outcomes (fair allocation, operational efficiency, historical tracking), and is written as a business summary rather than a feature list.)

---

## 2. System scope

- User account management and role-based access
- Shared space inventory with facility listings
- Booking request submission, editing, and status tracking
- Approval and rejection workflow for booking requests
- Check-in and session completion recording
- Maintenance issue reporting, assignment, and resolution tracking
- Conflict prevention (overlapping bookings, unavailable spaces)
- Historical record keeping for bookings and maintenance activities
- Monitoring views: upcoming bookings, maintenance status, no-show bookings, booking history

---

## 3. Actors

- **Student**: a university student who may submit booking requests for student activities, workshops, or project work.
- **Lecturer**: a faculty member who may submit booking requests for lectures, examinations, and seminars.
- **Teaching Assistant**: an assistant who may submit booking requests for tutorials, lab sessions, or workshops.
- **Facility Staff**: a staff member responsible for reviewing bookings, checking in and completing sessions, reporting maintenance issues, and updating space status.
- **Department Administrator**: a departmental staff member who oversees booking activity and monitors space utilization.
- **Facility Manager**: a manager who approves or rejects booking requests, assigns maintenance tasks, and enforces usage policies.

**Note:** All of the above are roles of the User entity. A single user may potentially hold multiple roles.

---

## 4. Candidate entities

- **User**: a person who interacts with the system. Must be stored because every action (booking, approval, check-in, maintenance reporting) is attributable to a specific user, and the system stores account-level information. *(Requirement: "Each user must have a university account. The system stores basic user information...")*

- **Space**: a bookable physical room managed by the School. Must be stored because it is the central object of the booking and maintenance processes, with identity (space code), capacity, status, and policies that affect eligibility. *(Requirement: "The School manages many bookable spaces. For each space, the system stores a unique space code...")*

- **Facility**: a type of equipment or amenity available in spaces (e.g., projector, whiteboard, air conditioner). Must be stored because spaces possess a list of facilities and users need to know what equipment a room provides. *(Requirement: "Each space may have several facilities... The system should store the list of facilities available in each space.")*

- **SpaceFacility**: an associative entity capturing which facilities are available in which spaces. Required because a space can have many facilities and a facility type can appear in many spaces (many-to-many). *(Assumption: modeled as an associative entity to resolve the many-to-many relationship.)*

- **Booking**: a transactional record of a user's request to reserve a space for a specific time and purpose. Captures the core business process from submission through approval, check-in, and completion. *(Requirement: "Users can submit booking requests by selecting a space, requested start time, requested end time, purpose of use, and expected number of participants.")*

- **MaintenanceRecord**: a transactional record of a reported problem affecting a space. Must be stored because maintenance affects space availability and the system must preserve maintenance history. *(Requirement: "A space may have maintenance records... Each maintenance record stores the related space, reporter, assigned staff member, problem description...")*

---

## 5. Candidate attributes

- **User**: `user_id` (unique account identifier, likely PK), `full_name`, `email`, `phone_number`, `role` (student / lecturer / teaching assistant / facility staff / department administrator / facility manager), `department`, `account_status` (active / suspended / deactivated).

- **Space**: `space_code` (unique identifier, PK candidate), `space_name`, `space_type` (auditorium / classroom / computer_lab / project_lab / meeting_room / student_workspace), `building`, `floor`, `room_number`, `capacity`, `current_status` (available / in_use / under_maintenance / temporarily_closed / retired), `usage_policy`.

- **Facility**: `facility_id` (unique identifier, PK candidate), `facility_name` (e.g., projector, whiteboard, microphone, computer, livestreaming equipment, air conditioner).

- **SpaceFacility**: `space_code` (FK to Space), `facility_id` (FK to Facility). *(Assumption: a composite PK on (space_code, facility_id).)*

- **Booking**: `booking_id` (unique transaction identifier, PK candidate), `requested_start_time`, `requested_end_time`, `purpose` (lecture / examination / seminar / workshop / meeting / student_activity / administrative_event), `expected_participants`, `booking_status` (pending / approved / rejected / cancelled / checked_in / completed / no_show), `requester_id` (FK to User), `space_code` (FK to Space), `decision_staff_id` (FK to User — the staff who approved or rejected), `decision_time`, `decision_note`, `rejection_reason`, `actual_start_time` (set at check-in), `check_in_staff_id` (FK to User), `initial_condition`, `actual_end_time` (set at completion), `final_condition`, `usage_notes`.

- **MaintenanceRecord**: `maintenance_id` (unique identifier, PK candidate), `space_code` (FK to Space), `reporter_id` (FK to User), `assigned_staff_id` (FK to User), `problem_description`, `start_time` (when the problem was reported or maintenance began), `completion_time`, `status` (values not fully enumerated in requirement; likely includes reported, in_progress, completed), `result_note`.

---

## 6. Relationships

- **User — submits — Booking**: a user acts as the requester for a booking request. *(Requirement: "Users can submit booking requests...")*

- **Booking — reserves — Space**: each booking targets exactly one space for the requested time. *(Requirement: "Users can submit booking requests by selecting a space...")*

- **Staff (User) — decides on — Booking**: a facility staff member or facility manager approves or rejects a booking. *(Requirement: "A booking request may require approval from a facility staff member or manager.")*

- **Staff (User) — checks in — Booking**: facility staff records the actual start of a session. *(Requirement: "When the requester arrives, facility staff can check in the booking.")*

- **Staff (User) — completes — Booking**: facility staff records the actual end of a session. *(Requirement: "When the session ends, facility staff can complete the booking...")*

- **Space — contains — SpaceFacility**: a space's facilities are recorded through the associative entity. *(Assumption: the Space–Facility relationship is resolved through SpaceFacility.)*

- **Facility — referenced by — SpaceFacility**: a facility type is linked to spaces through the associative entity.

- **User — reports — MaintenanceRecord**: a user reports a maintenance problem. *(Requirement: "Each maintenance record stores the related space, reporter, assigned staff member...")*

- **Staff (User) — assigned to — MaintenanceRecord**: a staff member is designated to handle a maintenance issue. *(Requirement: "...assigned staff member...")*

- **MaintenanceRecord — concerns — Space**: each maintenance record is linked to the affected space. *(Requirement: "A space may have maintenance records...")*

---

## 7. Cardinalities and participation

- **User submits Booking**: one user may submit many bookings, but each booking must be submitted by exactly one user. Participation is mandatory on the Booking side (every booking has a requester) and optional on the User side (some users may never submit a booking). *(Requirement: "Users can submit booking requests" — "Users" is plural, implying many bookings per user; each booking is an individual submission.)*

- **Booking reserves Space**: each booking must reserve exactly one space. One space may appear in many bookings over time. Participation is mandatory on the Booking side (every booking is for a space) and optional on the Space side (a space may never be booked). *(Requirement: "Users can submit booking requests by selecting a space" — singular "a space".)*

- **Staff decides on Booking**: one staff member may decide on many bookings. Each booking may be decided by at most one staff member. Participation is optional on both sides: a staff member may never approve or reject a booking, and a booking may remain pending without a decision. *(Requirement: "A booking request may require approval from a facility staff member or manager" — "may" implies optionality.)*

- **Staff checks in Booking**: one staff member may check in many bookings. Each booking may be checked in by at most one staff member. Participation is optional on the Booking side (a booking may be cancelled, rejected, or result in no-show before check-in ever occurs). *(Requirement: "Facility staff can check in the booking" — "can" implies optionality.)*

- **Staff completes Booking**: one staff member may complete many bookings. Each booking may be completed by at most one staff member. Participation is optional on the Booking side (a booking may never reach the completion stage). *(Requirement: "Facility staff can complete the booking" — "can" implies optionality.)*

- **Space contains SpaceFacility**: one space may be linked to many SpaceFacility entries. Each SpaceFacility entry must belong to exactly one space. Participation is optional on the Space side (a space may have no recorded facilities). *(Assumption: derived from "Each space may have several facilities" — "may" indicates optionality.)*

- **Facility referenced by SpaceFacility**: one facility type may appear in many SpaceFacility entries. Each SpaceFacility entry refers to exactly one facility. *(Assumption: the many-to-many nature of spaces and facilities.)*

- **User reports MaintenanceRecord**: one user may report many maintenance records, but each maintenance record must have exactly one reporter. Participation is mandatory on MaintenanceRecord and optional on User. *(Requirement: "...reporter..." is listed as a stored field, implying each record has one reporter.)*

- **Staff assigned to MaintenanceRecord**: one staff member may be assigned to many maintenance records. Each maintenance record may be assigned to at most one staff member. Participation is optional on both sides (a staff member may have no assignments; a maintenance record may be unassigned initially). *(Assumption: the requirement mentions "assigned staff member" but does not mandate immediate assignment upon reporting.)*

- **MaintenanceRecord concerns Space**: each maintenance record concerns exactly one space. One space may have many maintenance records over time. Participation is mandatory on MaintenanceRecord and optional on Space. *(Requirement: "A space may have maintenance records" — the singular "a space" for each record.)*

---

## 8. Business rules

1. Each user must have a valid university account to interact with the system.

2. A space that is under maintenance, temporarily closed, or retired cannot be booked.

3. The same space must not have two approved bookings whose time periods overlap.

4. A booking must have a requested start time that is before its requested end time. *(Assumption: implied by the concept of a valid time period.)*

5. When a booking is approved or rejected, the system must record the deciding staff member, the decision time, and a decision note.

6. When a booking is rejected, a rejection reason must be stored.

7. When a booking is checked in, the system must record the actual start time, the staff member who performed the check-in, and the initial condition of the space.

8. When a booking session is completed, the system must record the actual end time, the final condition of the space, and any usage notes.

9. Only facility staff or facility managers may approve or reject a booking request.

10. Only facility staff may perform check-in and session completion.

11. Historical records of bookings and maintenance activities must be retained and must be viewable by staff.

12. Each space must have a unique space code.

13. Only active accounts can book spaces.

14. When a user change booking's time, its status shoule be pending again.

---

## 9. Assumptions and ambiguities

- **Multiple roles for one user**: the requirement lists six possible roles (student, lecturer, teaching assistant, facility staff, department administrator, facility manager) but does not clarify whether a single user can hold more than one role simultaneously. Assumed possible until constrained otherwise.

- **Booking resubmission after rejection**: the requirement does not specify whether a rejected booking can be resubmitted or modified. This should be confirmed.

- **Cancellation policy**: the requirement mentions "cancelled" as a booking status but does not specify who may cancel a booking or under what conditions (e.g., time limits before start).

- **No-show handling**: the requirement mentions "no-show" as a booking status but does not define the business process for handling no-shows (e.g., automatic transition after elapsed time, manual marking by staff).

- **Maintenance status values**: the requirement references a "status" field on MaintenanceRecord but does not enumerate the possible values. Assumed common values such as "reported", "in progress", and "completed".

- **Recurring bookings**: the requirement does not mention recurring or repeating bookings. Assumed the system handles only individual booking requests.

- **Facility maintenance**: the requirement does not specify whether facilities themselves (as distinct from spaces) can have independent maintenance tracking. Assumed facilities are only tracked as attributes of spaces.

- **Check-in and completion by different staff**: the requirement does not require the same staff member to perform both check-in and completion. Assumed different staff members may handle each action.

- **Usage policy enforcement**: the requirement mentions that spaces have a "usage policy" field but does not specify how this policy is enforced (e.g., automated eligibility checks or manual review). This should be clarified before schema design.

- **Confirmation of check-in/completion**: the requirement uses "can" when describing check-in and completion by facility staff, suggesting optionality. It is assumed that not all bookings will be checked in or completed (e.g., cancellations, no-shows).

- **Purpose values**: the requirement enumerates seven purpose types (lecture, examination, seminar, workshop, meeting, student activity, administrative event). Assumed this list is exhaustive for the scope of the system.

- **User account status transitions**: the requirement mentions "account status" but does not specify the rules for when an account changes status (e.g., automatic deactivation after graduation). This should be confirmed.
