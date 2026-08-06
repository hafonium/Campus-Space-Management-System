# Concurrency Tests (G09) — `13-concurrency-tests-G09/`

Tests the concurrency control implemented in Phase 2 for the **booking
conflict rule**: two approved bookings may never use the same space during
overlapping time periods, even when users and staff perform booking and
approval operations simultaneously.

Design rationale and the identified race condition are documented in
`outputs/11-concurrency-design-G09.md`; the trigger fix and the safe approval
procedure are in `outputs/12-concurrency-implementation-G09.sql`.

## Conflict scenario tested

Two `pending` bookings on the same space with overlapping windows are approved
concurrently. Under READ COMMITTED the overlap check reads no conflict in both
sessions and both commit — a write-skew double booking. The Phase 2 trigger
(`trg_booking_enforce_rules`, `INSTEAD OF INSERT, UPDATE`) re-checks overlaps
with `WITH (UPDLOCK, SERIALIZABLE)` plus `dbo.sp_approve_booking` running at
`SERIALIZABLE`, so the second approver blocks on the first and then fails.

| Test | Fixture (space `CR-DC-1302`) | Expected |
|---|---|---|
| **Conflict** | 2027-01-11 09:00–11:00 and 10:00–12:00 (overlap 10:00–11:00) | exactly **one** approval succeeds; the other fails with **Msg 50000** |
| **Non-conflict** | 2027-01-12 08:00–09:00 and 10:00–11:00 (disjoint) | **both** approvals succeed |

`CR-DC-1302` carries a migrated Phase 1 usage policy
(`legacy_policy_text IS NOT NULL`), so inserted bookings stay `pending`
instead of being auto-approved — the staff-approval path stays exercisable.

## Files

| File | Purpose |
|---|---|
| `01-setup-concurrency-tests-G09.sql` | idempotent fixtures: index, `sp_approve_booking`, 4 pending bookings |
| `02a/02b-session-…-conflict-G09.sql` | two sessions approving the overlapping pair |
| `03a/03b-session-…-nonconflict-G09.sql` | two sessions approving the disjoint pair |
| `04-verify-concurrency-tests-G09.sql` | asserts outcomes, cleans up fixtures |
| `run-concurrency-tests-G09.sh` | end-to-end runner (launches sessions concurrently) |

## Run

```bash
sqlcmd -b -i outputs/13-concurrency-tests-G09/01-setup-concurrency-tests-G09.sql

# two terminals, roughly simultaneously:
sqlcmd -b -i outputs/13-concurrency-tests-G09/02a-session-A-conflict-G09.sql
sqlcmd -b -i outputs/13-concurrency-tests-G09/02b-session-B-conflict-G09.sql

# or the whole thing:
bash outputs/13-concurrency-tests-G09/run-concurrency-tests-G09.sh
```

## Result (verified 2026-08-06, SQL Server 2022)

```
CONFLICT pair:
  Session A approving booking 200027 ... approved_booking_id = 200027
  Session B approving booking 200028 ...
  Msg 50000 — Overlapping approved booking already exists for this space
  during the requested time period.

NON-CONFLICT pair:
  Session A approved (200029); Session B approved (200030).

Verification:
  Conflict pair    : approved=1 pending=1  (expected 1 approved / 1 pending)
  Non-conflict pair: approved=2            (expected 2 approved)
  PASS: concurrency tests behave as designed.
```
