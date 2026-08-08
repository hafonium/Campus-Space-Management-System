# Step 15 — Indexing and Query Tuning Report (G09)

## 1. Objective

This report evaluates indexing for exactly four Phase 2 workloads:

1. Booking conflict check.
2. Room finder.
3. Total approved booking hours of each space for a semester.
4. Number of approved bookings by weekday and hour for a semester.

The comparison uses the real output in `step15-benchmark-output.txt`. BASE and
INDEXED use the same dataset, query text, parameters, warm-up procedure, and
five measured executions. No values from the obsolete Step 15 report are used.

## 2. Dataset and Environment

| Item | Observed value |
|---|---|
| DBMS | Microsoft SQL Server 2022 Developer Edition (64-bit) |
| Server instance | `sqlserver2022` |
| Product version/level | `16.0.4265.3`, RTM |
| Database compatibility level | 160 |
| Recovery model | FULL |
| Total `BOOKING` rows | 100,022 |
| Approved/active booking rows | 75,722 |
| `MAINTENANCE_RECORD` rows | 125 |
| First booking start | `2023-09-01 08:00:00` |
| Last booking start | `2026-09-21 14:00:00` |
| Booking day span | 1,116 days |
| Measured executions per workload/stage | 5 |

Semester coverage uses the final interval-overlap semantics from Step 16:

| Semester ID | Semester | Start | End (inclusive) | Approved/active overlapping rows |
|---:|---|---|---|---:|
| 1 | Hoc ky 1 2023-2024 | 2023-09-01 | 2024-01-15 | 12,302 |
| 4 | Hoc ky 2 2023-2024 | 2024-02-15 | 2024-06-30 | 10,500 |
| 2 | Hoc ky 1 2024-2025 | 2024-09-01 | 2025-01-15 | 9,942 |
| 5 | Hoc ky 2 2024-2025 | 2025-02-15 | 2025-06-30 | 9,729 |
| 3 | Hoc ky 1 2025-2026 | 2025-09-01 | 2026-01-15 | 6,885 |
| 6 | Hoc ky 2 2025-2026 | 2026-02-15 | 2026-06-30 | 6,779 |

The benchmark completed successfully and printed that original index
existence and enabled/disabled state had been restored.

## 3. Exact Benchmark Parameters

| Parameter | Selected value |
|---|---|
| `semester_id` | 1 |
| `@semester_start` | `2023-09-01 00:00:00` |
| `@semester_end_exclusive` | `2024-01-16 00:00:00` |
| Approved/active rows overlapping semester | 12,302 |
| W1 `@space_code` | `A101` |
| W1 `@requested_start` | `2025-09-01 08:00:00` |
| W1 `@requested_end` | `2025-09-01 10:00:00` |
| W2 `@required_capacity` | 20 |
| W2 `@start_time` | `2026-06-20 08:00:00` |
| W2 `@end_time` | `2026-06-20 10:00:00` |
| W2 parameter maintenance ID | 1 |
| W2 required facilities | ID 2 — Whiteboard; ID 6 — Air Conditioner |
| W2 result rows | 6 |

## 4. Existing Indexes Before Tuning

The initial inventory contained the following relevant indexes. Every listed
index was enabled (`is_disabled = 0`). C2 and C3 did not exist before tuning.

| Table | Index | Type | Keys | Role |
|---|---|---|---|---|
| `BOOKING` | `pk_booking` | Clustered, unique PK | `booking_id` | Integrity |
| `BOOKING` | `ix_booking_overlap_lock` | Nonclustered | `space_code, booking_status, requested_start_time, requested_end_time` | Concurrency/performance |
| `MAINTENANCE_RECORD` | `pk_maintenance_record` | Clustered, unique PK | `maintenance_id` | Integrity |
| `SEMESTER` | `pk_semester` | Clustered, unique PK | `semester_id` | Integrity |
| `SEMESTER` | `uq_semester_semester_name` | Nonclustered unique constraint | `semester_name` | Integrity |
| `SPACE` | `pk_space` | Clustered, unique PK | `space_code` | Integrity |
| `SPACE` | `uq_space_location` | Nonclustered unique | `building, floor, room_number` | Integrity |
| `SPACE_FACILITY` | `pk_space_facility` | Clustered composite PK | `space_code, facility_id` | Integrity/access path |

For a clean BASE, the benchmark temporarily disabled non-unique performance
indexes, including `ix_booking_overlap_lock`, without dropping PKs, unique
constraints, or unique integrity indexes. No concurrent booking writes were
allowed while the concurrency index was disabled.

## 5. Candidate Indexes and Rationale

### C1 — Conflict check and booking overlap

```sql
CREATE INDEX ix_booking_overlap_lock
ON dbo.BOOKING (
    space_code,
    booking_status,
    requested_start_time,
    requested_end_time
);
```

The equality predicates lead the key, followed by the temporal keys. The same
index also provides the ordered access path needed for Step 12 key-range
locking, so it serves both concurrency correctness and query performance.

### C2 — Semester reporting

```sql
CREATE INDEX ix_g09_booking_semester_reporting
ON dbo.BOOKING (
    booking_status,
    requested_start_time,
    space_code
)
INCLUDE (requested_end_time);
```

The status and start-time keys support the semester reporting predicates.
`space_code` and included `requested_end_time` cover the reporting columns and
the second overlap boundary.

### C3 — Room-finder maintenance exclusion

```sql
CREATE INDEX ix_g09_maintenance_room_finder
ON dbo.MAINTENANCE_RECORD (
    space_code,
    impact_level,
    status,
    start_time
)
INCLUDE (completion_time);
```

The key follows the space join, equality filters, and temporal boundary while
covering the nullable maintenance end time. Its value must be judged against
the very small 125-row maintenance table.

No candidate was added for `SPACE` or `SPACE_FACILITY`: `SPACE` is small and
the existing `SPACE_FACILITY` composite PK already begins with `space_code`,
which matches the correlated facility lookup.

## 6. Benchmark Methodology

The benchmark performed these operations in one SQL session:

1. Validated volume, booking range, maintenance count, active booking count,
   and semester coverage.
2. Printed the original relevant index inventory and deterministic parameters.
3. Disabled only non-unique, non-constraint performance indexes for BASE.
4. Warmed W1-W4 once, then captured one Actual Plan per workload.
5. Ran each BASE workload five times with `STATISTICS IO/TIME` enabled.
6. Created or rebuilt C1-C3, repeated the warm-up and Actual Plan capture, and
   ran five INDEXED executions with unchanged queries and parameters.
7. Restored and verified the original index state.

The reported CPU and elapsed values are medians of the five query-level timing
records. The duplicate outer `sp_executesql` timing messages are not counted.
Logical-read medians are taken from `STATISTICS IO`; physical reads were zero
in every measured run. Actual Plan capture executions are used for operator
and rows-read analysis, not for the timing medians.

## 7. W1 — Booking Conflict Check

W1 tests the approved-booking overlap predicate for `A101` from 08:00 to 10:00
on 2025-09-01.

### Five measured runs

| Stage | `BOOKING` reads | CPU ms | Elapsed ms |
|---|---|---|---|
| BASE | 2063, 2063, 2063, 2063, 2063 | 7, 7, 7, 7, 7 | 7, 7, 6, 7, 7 |
| INDEXED | 4, 4, 4, 4, 4 | 0, 0, 0, 0, 0 | 0, 0, 0, 0, 0 |

| Metric | BASE median | INDEXED median |
|---|---:|---:|
| `BOOKING` logical reads | 2,063 | 4 |
| CPU time | 7 ms | 0 ms (below timer resolution) |
| Elapsed time | 7 ms | 0 ms (below timer resolution) |
| Result rows | 1 aggregate row | 1 aggregate row |
| Main access | Clustered Index Scan | Index Seek |
| Index used | `pk_booking` | `ix_booking_overlap_lock` |
| Key Lookup | None | None |

The BASE plan read all 100,022 booking rows to find one conflict. The INDEXED
plan sought directly through C1 and read one row. This reduced logical reads by
99.81%; the zero-millisecond timing is SQL Server timer rounding, not proof of
literally zero execution cost.

**Decision: KEEP C1.** The logical-read and rows-accessed reductions are
decisive, and the same index also supports the Step 12 concurrency design and its key-range locking strategy.

## 8. W2 — Room Finder

W2 preserves the Step 16 capacity, facility, unavailable-status, booking
overlap, and active out-of-service maintenance semantics. It returned six
spaces for the parameters in Section 3.

### Five measured runs

| Stage | `BOOKING` reads | Total reads | CPU ms | Elapsed ms |
|---|---|---|---|---|
| BASE | 78394, 78394, 78394, 78394, 78394 | 78687, 78687, 78687, 78687, 78687 | 895, 890, 897, 905, 887 | 895, 890, 896, 909, 887 |
| INDEXED | 851, 851, 851, 851, 851 | 1139, 1139, 1139, 1139, 1139 | 21, 19, 21, 21, 20 | 20, 19, 20, 21, 20 |

The total is the sum of reads reported for `BOOKING`, `MAINTENANCE_RECORD`,
`SPACE`, `SPACE_FACILITY`, and `#RequiredFacilities`.

| Metric | BASE median | INDEXED median |
|---|---:|---:|
| `BOOKING` logical reads | 78,394 | 851 |
| `MAINTENANCE_RECORD` logical reads | 33 | 28 |
| `SPACE` logical reads | 93 | 93 |
| `SPACE_FACILITY` logical reads | 90 | 90 |
| `#RequiredFacilities` logical reads | 77 | 77 |
| Total query logical reads | 78,687 | 1,139 |
| CPU time | 895 ms | 21 ms |
| Elapsed time | 895 ms | 20 ms |
| Result rows | 6 | 6 |
| `BOOKING` access | Clustered Index Scan on `pk_booking` | Index Seek on `ix_booking_overlap_lock` |
| Maintenance access | Clustered Index Scan on `pk_maintenance_record` | Index Seek on `ix_g09_maintenance_room_finder` |
| Join/set strategy | Nested Loops anti-semi joins implementing `EXCEPT` | Nested Loops anti-semi joins implementing `EXCEPT` |
| Key Lookup | None | None |

The BASE plan repeatedly scanned `BOOKING` for candidate spaces, reading
3,800,836 rows in the Actual Plan and producing 78,394 logical reads. With C1,
SQL Server performed targeted seeks by space/status/time, reading 71,131 rows
and only 851 pages. `BOOKING` reads fell 98.91%, total reads fell 98.55%, and
median elapsed time fell from 895 ms to 20 ms.

C3 changed the maintenance access from a clustered scan to a seek and reduced
maintenance reads from 33 to 28. The Actual Plan read one matching maintenance
row instead of 751 rows across repeated executions, but the page reduction was
only five reads because `MAINTENANCE_RECORD` has 125 rows. C1 accounts for the
overwhelming majority of W2's improvement.

**Decisions: KEEP C1; REJECT C3 for the current dataset and defer it until
maintenance volume grows substantially.**

## 9. W3 — Approved Booking Hours by Semester

W3 reports all 40 spaces, including zero-hour spaces, using these unchanged
semester-overlap predicates:

```sql
requested_end_time > @semester_start
AND requested_start_time < @semester_end_exclusive
```

### Five measured runs

| Stage | `BOOKING` reads | CPU ms | Elapsed ms |
|---|---|---|---|
| BASE | 2063, 2063, 2063, 2063, 2063 | 18, 18, 18, 18, 18 | 30, 17, 18, 18, 18 |
| INDEXED | 583, 580, 583, 580, 583 | 7, 6, 7, 6, 7 | 7, 6, 6, 6, 6 |

| Metric | BASE median | INDEXED median |
|---|---:|---:|
| `BOOKING` logical reads | 2,063 | 583 |
| `SPACE` logical reads | 2 | 3 |
| Total query logical reads | 2,065 | 586 |
| CPU time | 18 ms | 7 ms |
| Elapsed time | 18 ms | 6 ms |
| Result rows | 40 | 40 |
| Booking access | Clustered Index Scan on `pk_booking` | Index Seek on `ix_booking_overlap_lock` |
| Join/aggregate | Hash Match left join and Hash Aggregate | Nested Loops left join and Stream Aggregate |
| Key Lookup | None | None |

The BASE Actual Plan scanned all 100,022 booking rows. The INDEXED plan used
C1, not C2, and read the 12,302 qualifying booking rows through repeated seeks
by `space_code`, status, and start-time boundary. Its plan-capture execution
used 574 `BOOKING` reads; the five timed executions produced 580 or 583 reads,
so the reported median is 583. Median `BOOKING` reads fell 71.74%.

This improvement must not be attributed to C2. W3 joins and groups by
`space_code`, which matches C1's leading key, and the optimizer selected C1 as
the cheaper access path for this workload.

**Decision for this workload: C1 is beneficial. W3 provides no direct evidence
for keeping C2; the C2 decision is instead supported by W4.**

## 10. W4 — Booking Count by Weekday/Hour

W4 returned 25 weekday/hour groups for semester 1 and uses the same
booking-semester overlap semantics as W3.

### Five measured runs

| Stage | `BOOKING` reads | CPU ms | Elapsed ms |
|---|---|---|---|
| BASE | 2063, 2063, 2063, 2063, 2063 | 14, 14, 14, 15, 14 | 14, 14, 14, 14, 14 |
| INDEXED | 83, 83, 83, 83, 83 | 3, 4, 4, 3, 4 | 3, 3, 3, 3, 3 |

| Metric | BASE median | INDEXED median |
|---|---:|---:|
| `BOOKING` logical reads | 2,063 | 83 |
| CPU time | 14 ms | 4 ms |
| Elapsed time | 14 ms | 3 ms |
| Result rows | 25 groups | 25 groups |
| Booking access | Clustered Index Scan on `pk_booking` | Index Seek on `ix_g09_booking_semester_reporting` |
| Aggregate | Hash Match Aggregate | Hash Match Aggregate |
| Explicit Sort | None | None |
| Key Lookup | None | None |

The BASE scan read all 100,022 bookings. C2 allowed three status/start-time
seek ranges and read exactly the 12,302 qualifying rows, reducing logical reads
by 95.98%. The included end time covers the remaining overlap predicate, and
no Key Lookup was required. Median elapsed time fell from 14 ms to 3 ms.

**Decision: KEEP C2.** W4 supplies direct plan and I/O evidence for the
semester-reporting index.

## 11. Before vs After Summary

Times are median elapsed times. W2 shows both `BOOKING` and total query reads;
the other workloads show `BOOKING` reads because other reported reads are zero
or separately documented above.

| Workload | Base Reads | Indexed Reads | Base Time | Indexed Time | Plan Before | Plan After | Decision |
|---|---:|---:|---:|---:|---|---|---|
| W1 — Conflict check | 2,063 | 4 | 7 ms | 0 ms* | Clustered scan, `pk_booking` | Seek, C1 | KEEP C1 |
| W2 — Room finder | 78,394 BOOKING / 78,687 total | 851 BOOKING / 1,139 total | 895 ms | 20 ms | Repeated BOOKING clustered scans; maintenance clustered scan | C1 BOOKING seeks; C3 maintenance seeks | KEEP C1; REJECT/DEFER C3 |
| W3 — Booking hours | 2,063 | 583 | 18 ms | 6 ms | Clustered scan, `pk_booking` | Seeks through C1 | C1 beneficial; no C2 attribution |
| W4 — Weekday/hour count | 2,063 | 83 | 14 ms | 3 ms | Clustered scan, `pk_booking` | Seek through C2 | KEEP C2 |

\* Recorded as 0 ms because the execution was below SQL Server's displayed
millisecond resolution.

## 12. Final Index Decisions

| Candidate | Final decision | Evidence and action |
|---|---|---|
| C1 — `ix_booking_overlap_lock` | **KEEP** | W1 reads 2,063→4; W2 BOOKING reads 78,394→851; W3 median BOOKING reads 2,063→583. It also supports Step 12 key-range locking. Retain the existing index. |
| C2 — `ix_g09_booking_semester_reporting` | **KEEP** | W4 reads 2,063→83, elapsed 14→3 ms, and the Actual Plan uses a covering C2 seek without a Key Lookup. Add it to the final deployment after documenting its write/storage cost. |
| C3 — `ix_g09_maintenance_room_finder` | **REJECT / DEFER** | Maintenance reads improve only 33→28 on a 125-row table. Do not deploy now; reconsider if maintenance volume or room-finder frequency grows substantially. |

The report distinguishes optimizer choice from candidate intent: although C2
was designed for semester reports, SQL Server selected C1 for W3. C2 is kept
because W4 directly and materially benefits from it.

## 13. Index Trade-offs

- C1 adds booking-write maintenance, but it is already required by the
  concurrency implementation and eliminates the need for a near-duplicate
  overlap index.
- C2 consumes storage and adds work to booking inserts and updates. Its 95.98%
  W4 read reduction and covering plan justify that cost for recurring semester
  reporting.
- C3 produces a seek, but an operator name alone is insufficient evidence.
  Only five maintenance-page reads are saved at the current scale, so its
  storage and write cost are not justified.
- Scans of `SPACE` and other very small tables remain reasonable. A seek is not
  inherently better; the decision depends on pages read, rows accessed,
  execution frequency, and write overhead.
- Timings at a few milliseconds are resolution- and environment-sensitive.
  Repeated logical reads and plan row counts are the primary evidence.

## 14. Reproduction Instructions

The finalized measurements came from:

- Benchmark: `outputs/15-index-tuning-benchmark-G09.sql`
- Captured output: `step15-benchmark-output.txt`

For an independent future reproduction, prepare the Phase 2 database through
Steps 05, 06, 10, 12, 14, and 16, then execute the benchmark once in a single
session with no concurrent booking writes. Set `@CaptureActualPlans = 1` to
emit one BASE and one INDEXED ShowPlan XML for each workload. Preserve the
Messages output containing all five measured runs.

Use query-level `STATISTICS TIME` entries rather than the duplicate outer
`sp_executesql` entries, calculate medians from all five runs, and report W2
per-table reads as well as the total. Finally, confirm these restoration
messages are present:

```text
Benchmark complete.
Original index existence and enabled/disabled state verified.
```
