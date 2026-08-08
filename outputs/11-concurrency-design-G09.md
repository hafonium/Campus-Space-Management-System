# Concurrency Design — Concurrent Staff Approval (G09)

## 1. Conflict Identification

### 1.1. Scenario

Two facility staff members simultaneously approve two different **pending** bookings that target the **same space** with **overlapping time periods**. Under default isolation, both approvals can succeed, creating a double-booking — violating the rule that no two approved bookings may overlap on the same space at the same time.

### 1.2. Root Cause: Write Skew

The overlap check (read) and the status update (write) form a non-atomic read-modify-write cycle. Under `READ COMMITTED` (SQL Server default), each `SELECT` acquires shared locks that are released immediately after the read completes. Both transactions see the same committed state — neither has committed its own approval yet — so both conclude "no conflict exists" and proceed to update.

```
Time    Staff A (approve booking #1)        Staff B (approve booking #2)
        SPACE X, 09:00–11:00                SPACE X, 10:00–12:00
────    ─────────────────────────────────   ─────────────────────────────────
T1      BEGIN TRAN                          BEGIN TRAN
T2      SELECT overlap check                SELECT overlap check
          → reads committed rows              → reads committed rows
          → no approved row overlapping        → no approved row overlapping
          → S-locks released                   → S-locks released
T3      UPDATE booking #1 → 'approved'      UPDATE booking #2 → 'approved'
T4      COMMIT                              COMMIT

Result: TWO approved bookings overlap from 10:00 to 11:00 on SPACE X.
```

This is a classic **write-skew** anomaly: two concurrent writers each make a decision based on a predicate that the other's write invalidates, but neither sees the other's uncommitted write.

### 1.3. Affected Isolation Levels

| Isolation Level | Conflict Prevented? | Reason |
|-----------------|---------------------|--------|
| `READ UNCOMMITTED` | No | Dirty reads; no locking at all. |
| `READ COMMITTED` (default) | No | Shared locks released immediately after read. |
| `READ COMMITTED SNAPSHOT` | No | Row-versioning; each statement sees a point-in-time snapshot. |
| `REPEATABLE READ` | No | Prevents non-repeatable reads but not phantoms; two concurrent checks can still both see zero rows. |
| `SNAPSHOT` | No | Transaction-level row-versioning; both transactions see pre-commit snapshot. |
| `SERIALIZABLE` | **Yes** | Range locks prevent phantom inserts; combined with UPDLOCK, only one transaction can acquire the lock on the key range. |

---

## 2. Solution

### 2.1. Chosen Strategy: `UPDLOCK` + `SERIALIZABLE`

A stored procedure `sp_approve_booking` executes the approval workflow under `SERIALIZABLE` isolation. The overlap-check query uses explicit `WITH (UPDLOCK, SERIALIZABLE)` table hints on the `BOOKING` table.

#### Lock Mechanics

- **`UPDLOCK`**: Acquires update (U) locks on matching data rows instead of shared (S) locks. U-locks are incompatible with other U-locks on the same resource — only one transaction at a time can hold a U-lock on a given row or key range. If Transaction A holds a U-lock, Transaction B's `UPDLOCK` request blocks until A commits or rolls back.

#### Lock Compatibility (U vs U)

When Transaction A scans the overlap predicate (`space_code = 'X' AND booking_status = 'approved'`) with `UPDLOCK`:
- U-locks are placed on every existing approved booking row for that space.
- `SERIALIZABLE` range locks cover the intervening gaps, preventing phantom inserts.
- Transaction B attempting the **same** overlap check on the **same** space is **blocked** — its requested U-locks are incompatible with A's held U-locks.

When A commits and releases all locks:
- B is unblocked and re-evaluates the overlap predicate.
- B now sees A's newly committed approved booking → overlap detected → error raised → rollback.

#### Resolution Flow

```
Staff A approves #1                         Staff B approves #2
─────────────────────────                   ─────────────────────────
BEGIN TRAN (SERIALIZABLE)                   BEGIN TRAN (SERIALIZABLE)
Overlap check: scans for approved           Overlap check: scans for approved
  bookings on SPACE X                         bookings on SPACE X
  → 0 rows → U-locks + range locks            → BLOCKED (incompatible with A's
    held on (SPACE X, approved, *)              U-locks)
UPDATE #1 → 'approved'                      (still blocked)
COMMIT → locks released                     UNBLOCKED → re-scans
                                              → finds #1 now approved, overlap
                                                (09:00–11:00 ∧ 10:00–12:00)
                                              → THROW error, ROLLBACK
```

### 2.2. Why a Stored Procedure (Not Trigger-Only)

The `INSTEAD OF INSERT, UPDATE` trigger already carries `WITH (UPDLOCK, HOLDLOCK)` hints (see `10-schema-migration-G09.sql`). However, the trigger inherits the caller's transaction isolation level. If the caller operates under `READ COMMITTED`, other statements inside the trigger may not be fully protected. A dedicated stored procedure:

- Explicitly sets `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE` — unambiguous.
- Encapsulates the full approval flow (existence check → overlap check → update) in one atomic unit.
- Provides a single, testable entry point for concurrency verification.

### 2.3. Alternatives Not Chosen

| Alternative | Why Rejected |
|-------------|--------------|
| **Application-level distributed lock** | External infrastructure dependency; direct SQL can bypass. |
| **`sp_getapplock`** | Coarse-grained; one lock per space blocks all non-overlapping operations too. |
| **Optimistic concurrency (application retry)** | Requires retry logic in every client; cascading retries under contention. |
| **Trigger-only `UPDLOCK, SERIALIZABLE` hints** | Works but isolation is caller-dependent; less explicit than a stored procedure. |

---

## 3. Test Design

### Test Case 1: Conflicting Approvals

Two staff members approve two pending bookings on the **same space** with **overlapping times**. Only one should succeed.

| Parameter | Booking A | Booking B |
|-----------|-----------|-----------|
| Space | SPACE-001 | SPACE-001 |
| Time | 2026-09-01 09:00–11:00 | 2026-09-01 10:00–12:00 |
| Initial status | pending | pending |

**Expected:** One booking → `approved`; the other session → error 50000, booking stays `pending`.

### Test Case 2: Non-Conflicting Approvals

Two staff members approve two pending bookings on the **same space** with **disjoint times**. Both should succeed.

| Parameter | Booking A | Booking B |
|-----------|-----------|-----------|
| Space | SPACE-001 | SPACE-001 |
| Time | 2026-09-01 08:00–09:00 | 2026-09-01 10:00–11:00 |
| Initial status | pending | pending |

**Expected:** Both bookings → `approved`.

### Execution

Each test is run in two separate SQL Server sessions launched concurrently. Session A begins first and holds its transaction open; Session B starts while A is still open. A bash script orchestrates timing via `sqlcmd` in background processes.

---

## 4. Assumptions

1. The approval transaction is self-contained (internal `COMMIT`); callers do not wrap it in larger transactions that delay lock release.
2. Bookings on different spaces operate on disjoint key ranges and will not block each other.
3. Role validation (`facility_staff` / `facility_manager`) is performed by the application before invoking `sp_approve_booking`.
