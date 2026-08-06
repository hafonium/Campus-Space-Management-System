# Tests — Campus Space Management System

Executable test suite for the high-volume sample-data pipeline (100,000–500,000
generated bookings). All scripts target Microsoft SQL Server 2022 and use
`THROW`-based assertion failures so any violation fails the run.

## Files

| File | Purpose |
| --- | --- |
| `sample-data/assertions.sql` | Post-load validation suite. Verifies volume, academic-year coverage, status distribution minimums, referential integrity, status-specific fields, non-overlap rules, acknowledgement links, uniqueness, and constraint/trigger state. Raises `THROW` (51000–51034) on any failure and prints `PASS` at the end. |
| `sample-data/negative-tests.sql` | Nine negative tests, each inside an isolated transaction that is rolled back. An expected SQL error is a PASS; an operation that unexpectedly succeeds is a FAIL. |
| `sample-data/run-tests.sql` | Orchestrator that runs generation, the assertion and negative-test suites and reports a summary. |

## Prerequisites

- SQL Server 2022 (Developer edition is sufficient).
- `sqlcmd` on `PATH` (use `-C` to trust the server certificate in local/container setups).
- The database `CampusSpaceManagementSystem` created and migrated to the Phase 2 schema.

## Pipeline order

Scripts must run in this order; later scripts assume earlier ones succeeded:

1. `outputs/05-db-definition-G09.sql` — Phase 1 schema
2. `outputs/06-sample-data-G09.sql` — hand-written demonstration rows
3. `outputs/10-schema-migration-G09.sql` — Phase 2 migration (ROLE, ACKNOWLEDGEMENT, USAGE_POLICY, impact_level)
4. `outputs/14-data-generator-G09/high-volume-sample-data-G09.sql` — deterministic high-volume generation (seed 9009, 100,000 bookings by default)
5. `tests/sample-data/assertions.sql` — post-load validation
6. `tests/sample-data/negative-tests.sql` — rejection tests
7. `outputs/15-index-tuning-report-G09.md` — benchmark methodology and measured results (index candidate set in §1)

## Running the tests

```bash
sqlcmd -b -i outputs/05-db-definition-G09.sql
sqlcmd -b -i outputs/06-sample-data-G09.sql
sqlcmd -b -i outputs/10-schema-migration-G09.sql
sqlcmd -b -i outputs/14-data-generator-G09/high-volume-sample-data-G09.sql
sqlcmd -b -i tests/sample-data/assertions.sql
sqlcmd -b -i tests/sample-data/negative-tests.sql
```

`-b` makes sqlcmd abort on SQL errors, so a failing assertion stops the pipeline.

Expected output of a clean run:

```
PASS: all high-volume sample-data assertions succeeded.
PASS: all negative tests rejected the invalid operations.
```

## What the assertions verify

- At least 100,000 generated bookings (`gen-%@campus.example` requesters)
- At least three academic years of coverage
- All seven booking statuses present
- Minimum status distribution: cancelled ≥ 5%, no_show ≥ 2%, rejected ≥ 3%, completed ≥ 40%
- No orphan foreign keys (all tables)
- Identity columns unchanged (no manual identity assignment)
- Status-specific fields populated (rejected, checked_in, completed)
- `requested_start_time < requested_end_time` and `actual_start_time < actual_end_time`
- No overlapping approved bookings per space
- No booking overlapping out-of-service maintenance
- Every advisory-overlap booking has an acknowledgement link, and links reference only matching maintenance records
- Unique generated emails, phone numbers, and space locations
- All constraints trusted and enabled; `dbo.trg_booking_enforce_rules` enabled

## What the negative tests verify

1. Invalid requested time range (`end <= start`) is rejected
2. Rejected booking without `rejection_reason` is rejected
3. Completed booking without completion fields is rejected
4. Unauthorized decision staff member is rejected
5. Unauthorized check-in staff member is rejected
6. Overlapping approved bookings are rejected
7. Booking during out-of-service maintenance is rejected
8. Duplicate user email is rejected
9. Invalid booking status is rejected

## Status

- `assertions.sql` — verified PASS against the 100,000-row generated dataset
- `negative-tests.sql` — verified 9/9 PASS against the generated dataset
- `run-tests.sql` — orchestrator including generation, assertions and negative tests
