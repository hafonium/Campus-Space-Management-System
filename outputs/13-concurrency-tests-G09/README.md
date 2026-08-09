# Concurrency Tests (G09) — `13-concurrency-tests-G09/`

## Three scenarios

| # | Demo | Cơ chế | Kết quả |
|---|------|--------|---------|
| **1** | **Unsafe** | Trigger DISABLED, raw UPDATE không lock | CẢ 2 approved → write-skew **CONFIRMED** |
| **2** | **Safe (conflict)** | Trigger ENABLED, `sp_approve_booking` (SERIALIZABLE + UPDLOCK) | 1 approved, 1 fail 50000 → **PREVENTED** |
| **3** | **Safe (non-conflict)** | Trigger ENABLED, disjoint times | CẢ 2 approved → **no false blocking** |

## Files

| File | Scenario | Purpose |
|------|----------|---------|
| `01a-demo-conflict-setup.sql` | Unsafe | DISABLE trigger, create test space & 2 overlapping bookings |
| `01b-session-A-unsafe.sql` | Unsafe | Approve 09:00-11:00 (raw UPDATE, no lock) |
| `01c-session-B-unsafe.sql` | Unsafe | Approve 10:00-12:00 (raw UPDATE, no lock) |
| `01d-demo-conflict-verify.sql` | Unsafe | Assert double booking → ENABLE trigger → cleanup |
| `02a-session-A-safe.sql` | Safe | `sp_approve_booking` 09:00-11:00 |
| `02b-session-B-safe.sql` | Safe | `sp_approve_booking` 10:00-12:00 → expected FAIL |
| `02c-safe-verify.sql` | Safe | Assert 1 approved + 1 pending → cleanup |
| `03a-session-A-safe-nonconflict.sql` | Safe | `sp_approve_booking` 08:00-09:00 |
| `03b-session-B-safe-nonconflict.sql` | Safe | `sp_approve_booking` 10:00-11:00 |
| `03c-safe-nonconflict-verify.sql` | Safe | Assert 2 approved → final cleanup |
| `run-concurrency-tests-G09.sh` | All | Bash orchestrator |

## Prerequisites

```bash
sqlcmd -b -i outputs/05-db-definition-G09.sql
sqlcmd -b -i outputs/10-schema-migration-G09.sql
sqlcmd -b -i outputs/14-data-generator-G09/high-volume-sample-data-G09.sql
sqlcmd -b -i outputs/12-concurrency-implementation-G09.sql
```

## Run (automated)

```bash
# All 3 scenarios in one command (requires sqlcmd)
bash outputs/13-concurrency-tests-G09/run-concurrency-tests-G09.sh
```

## Run (manual — SSMS / Azure Data Studio)

Session A uses `WAITFOR DELAY` to hold locks for several seconds.
Run Session A first, then **immediately** switch tabs and run Session B.

### Unsafe Demo (watch the write-skew happen)

```
Tab A: 01a-demo-conflict-setup.sql                   → F5 (1 lần)
Tab A: 01b-session-A-unsafe.sql                      → F5
       → In ra: "Run Session B NOW (within 10 seconds)"
Tab B: 01c-session-B-unsafe.sql                      → F5 (trong vòng 10s)
       → A & B đều SUCCEEDED
Tab A: 01d-demo-conflict-verify.sql                  → F5
       → CONFLICT CONFIRMED: Both bookings approved!
```

### Safe Demo — Conflict (prevention works)

```
Tab A: 02a-session-A-safe.sql                        → F5
       → In ra: "Run Session B NOW (within 10 seconds)"
Tab B: 02b-session-B-safe.sql                        → F5 (trong vòng 10s)
       → B bị block, sau đó fail — Msg 50000
Tab A: 02c-safe-verify.sql                           → F5
       → PREVENTION WORKS: 1 approved + 1 pending
```

### Safe Demo — Non-Conflict (no false blocking)

```
Tab A: 03a-session-A-safe-nonconflict.sql            → F5
       → In ra: "Run Session B NOW (within 5 seconds)"
Tab B: 03b-session-B-safe-nonconflict.sql            → F5 (trong vòng 5s)
       → Cả 2 SUCCEEDED (disjoint times, no blocking)
Tab A: 03c-safe-nonconflict-verify.sql               → F5
       → NO FALSE BLOCKING: Both approved
```

## Expected output (automated)

```
[1/5] UNSAFE DEMO — conflict without locks
    Session A exit=0   Session B exit=0
    CONFLICT CONFIRMED: Both bookings approved and overlap!

[2/5] SAFE DEMO — prevention (conflict)
    Session A exit=0   Session B exit=1
    PREVENTION WORKS: Serialized by SERIALIZABLE + UPDLOCK

[3/5] SAFE DEMO — non-conflict
    Session A exit=0   Session B exit=0
    NO FALSE BLOCKING: Disjoint bookings both approved

ALL TESTS PASSED
```
