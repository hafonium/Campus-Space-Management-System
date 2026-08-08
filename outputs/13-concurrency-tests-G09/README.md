# Concurrency Tests (G09) — `13-concurrency-tests-G09/`

Tests the concurrency control described in `11-concurrency-design-G09.md` and
implemented in `12-concurrency-implementation-G09.sql`.

## Conflict tested

Two staff members simultaneously approve two pending bookings on the **same
space**. Under default `READ COMMITTED`, both overlap checks see no conflict and
both commit — a write-skew double booking. The solution (`sp_approve_booking`
with `SERIALIZABLE + UPDLOCK`) serializes the two transactions: the second is
blocked by the first, then rescans and fails on the now-committed overlap.

## Fixtures (self-contained)

The setup script creates a dedicated space `TEST-CONC-001` with a
non-auto-approving policy `CONCURRENCY_TEST`, plus four pending bookings:

| Test | Bookings | Expected |
|------|----------|----------|
| **Conflict** | 2027-01-11 09:00–11:00 and 10:00–12:00 (overlap) | one approved, one fails — **Msg 50000** |
| **Non-conflict** | 2027-01-12 08:00–09:00 and 10:00–11:00 (disjoint) | **both approved** |

## Files

| File | Purpose |
|---|---|
| `01-setup-concurrency-tests-G09.sql` | Creates policy, space, and four pending bookings |
| `02a-session-A-conflict-G09.sql` | Approves 09:00–11:00 booking |
| `02b-session-B-conflict-G09.sql` | Approves 10:00–12:00 booking (expected fail) |
| `03a-session-A-nonconflict-G09.sql` | Approves 08:00–09:00 booking |
| `03b-session-B-nonconflict-G09.sql` | Approves 10:00–11:00 booking |
| `04-verify-and-cleanup-G09.sql` | Asserts outcomes and removes all test fixtures |
| `run-concurrency-tests-G09.sh` | End-to-end bash runner |

## Prerequisites

```
sqlcmd -b -i outputs/05-db-definition-G09.sql
sqlcmd -b -i outputs/10-schema-migration-G09.sql
sqlcmd -b -i outputs/14-data-generator-G09/high-volume-sample-data-G09.sql
sqlcmd -b -i outputs/12-concurrency-implementation-G09.sql
```

## Run

```bash
# All tests in one command
bash outputs/13-concurrency-tests-G09/run-concurrency-tests-G09.sh

# Or manually (two terminals, simultaneously)
sqlcmd -b -i outputs/13-concurrency-tests-G09/01-setup-concurrency-tests-G09.sql
sqlcmd -b -i outputs/13-concurrency-tests-G09/02a-session-A-conflict-G09.sql  # terminal 1
sqlcmd -b -i outputs/13-concurrency-tests-G09/02b-session-B-conflict-G09.sql  # terminal 2
sqlcmd -b -i outputs/13-concurrency-tests-G09/04-verify-and-cleanup-G09.sql
```
