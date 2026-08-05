# Concurrency Design — Auto-Approval Race Condition

## 1. Problem

When two `pending` bookings for the **same space + overlapping time** are approved concurrently, the trigger's overlap check reads `BOOKING` under shared locks — released immediately after the `SELECT`. Both transactions see "no conflict" and both commit, creating a double-booking that violates BR-7.

| Time | Session A | Session B |
|------|-----------|-----------|
| T1 | BEGIN TRAN | BEGIN TRAN |
| T2 | Check: CS-101 10:00–12:00 → **no conflict** | Check: CS-101 11:00–13:00 → **no conflict** |
| T3 | UPDATE → approved | UPDATE → approved |
| T4 | COMMIT | COMMIT |

**Result:** Both bookings overlap by 1 hour on CS-101.

**Root cause**: write skew — the gap between read (T2) and write (T3) is unprotected under READ COMMITTED.

---

## 2. Solution

Add `WITH (UPDLOCK, SERIALIZABLE)` to the overlap subquery inside `trg_booking_enforce_rules`:

- **UPDLOCK**: takes update locks (incompatible with each other), so two concurrent overlap checks on the same space block one another.
- **SERIALIZABLE**: holds locks until transaction end + enables key-range locking on `ix_booking_overlap_lock`, preventing phantom inserts into the scanned range.

A supporting index is required for fine-grained key-range locks:

```sql
CREATE INDEX ix_booking_overlap_lock
    ON dbo.BOOKING (space_code, booking_status, requested_start_time, requested_end_time);
```

A stored procedure `sp_approve_booking` explicitly sets `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE` as additional defense.

---

## 3. Test Cases

| Test | Input | Expected |
|------|-------|----------|
| **Conflicting** | 2 pending bookings on CS-101, 09:00–11:00 and 10:00–12:00, approved concurrently | Only 1 succeeds; the other gets error 50000 |
| **Non-conflicting** | 2 pending bookings on CS-MEET, 08:00–09:00 and 10:00–11:00, approved concurrently | Both succeed |
