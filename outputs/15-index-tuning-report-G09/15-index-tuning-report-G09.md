# Step 15 — Index Tuning Report (G09)

## 1. Objective

This report evaluates three candidate indexes for the four fixed Campus Space Management System workloads. It follows the required sequence:

`workload -> access pattern -> candidate hypothesis -> controlled benchmark -> actual evidence -> decision`

All measurements and Actual Execution Plan evidence in this report come only from the completed run captured in `step15-codex-output.txt`, using `outputs/test-15-index-tuning-benchmark-G09.sql`. No earlier Step 15 measurement or artifact was used. Warm-up executions and representative plan-capture executions are excluded from the measured-run medians.

The final decisions are:

- C1 `ix_booking_overlap_lock`: **KEEP**
- C2 `ix_g09_booking_semester_reporting`: **KEEP**
- C3 `ix_g09_maintenance_room_finder`: **REJECT** for the current dataset/workload

## 2. Dataset and Environment

| Item | Observed value |
|---|---:|
| SQL Server | 2022 Developer Edition (64-bit) |
| Product version | 16.0.4265.3 |
| Compatibility level | 160 |
| Recovery model | FULL |
| Session language / `DATEFIRST` | `us_english` / 7 |
| BOOKING rows | 100,022 |
| Strictly `approved` bookings | 14,573 |
| `approved` / `checked_in` / `completed` bookings | 75,722 |
| MAINTENANCE_RECORD rows | 125 |
| Booking date span | 1,116 days, from 2023-09-01 08:00 to 2026-09-21 16:00 |
| Semesters | 6; all 6 overlap booking data |

The benchmark preflight passed before any index state changed.

## 3. Exact Benchmark Parameters

| Workload | Parameter | Value |
|---|---|---|
| W1 | Source approved booking | `booking_id = 3` |
| W1 | Space | `CR-M3-1006` |
| W1 | Probe start | `2026-07-10 10:00:00` |
| W1 | Probe end | `2026-07-10 12:00:00` |
| W2 | Interval source | Active out-of-service maintenance |
| W2 | Satisfiable anchor space | `AUD-MC-1000` |
| W2 | Required capacity | 500 |
| W2 | Facilities | 1 and 3 |
| W2 | Start | `2023-09-02 08:00:00` |
| W2 | End | `2023-09-03 20:00:00` |
| W2 | Viability result count | 1 space |
| W3/W4 | Semester | `semester_id = 1` |
| W3/W4 | Semester start | `2023-09-01 00:00:00` |
| W3/W4 | Exclusive semester end | `2024-01-16 00:00:00` |
| W3/W4 | Qualifying bookings | 12,302 |

W1 was selected from a real approved booking across the whole dataset and was not constrained to the reporting semester. W2 used two facilities that co-occur on a real space and returned a non-empty result. W3/W4 used the semester with the greatest qualifying overlap count under the benchmark's deterministic ordering.

## 4. Existing Indexes Before Tuning

The relevant initial inventory was:

| Table | Index | Type / role | Initial state |
|---|---|---|---|
| BOOKING | `pk_booking(booking_id)` | Clustered primary key | Enabled |
| BOOKING | `ix_booking_overlap_lock(space_code, booking_status, requested_start_time, requested_end_time)` | Nonclustered performance/concurrency index; C1 | Enabled |
| MAINTENANCE_RECORD | `pk_maintenance_record(maintenance_id)` | Clustered primary key | Enabled |
| SPACE | `pk_space(space_code)` | Clustered primary key | Enabled |
| SPACE | `uq_space_location(building, floor, room_number)` | Unique nonclustered index | Enabled |
| SPACE_FACILITY | `pk_space_facility(space_code, facility_id)` | Clustered primary key | Enabled |
| SEMESTER | `pk_semester(semester_id)` | Clustered primary key | Enabled |
| SEMESTER | `uq_semester_semester_name(semester_name)` | Unique constraint index | Enabled |

C2 and C3 did not exist initially. Candidate-name safety confirmed that the existing C1 definition exactly matched the approved candidate. Integrity indexes were not part of the mutable baseline.

## 5. Candidate Indexes and Rationale

### C1 — `ix_booking_overlap_lock`

```sql
CREATE INDEX ix_booking_overlap_lock
ON dbo.BOOKING (
    space_code,
    booking_status,
    requested_start_time,
    requested_end_time
);
```

Why chosen: W1 has equality predicates on `space_code` and `booking_status`, followed by an upper range on `requested_start_time`; `requested_end_time` supplies the second overlap condition, normally as a residual boundary in a conventional B-tree. The same structure is relevant to W2's booking exclusion. It is also the established Step 12 key-range-locking access path.

### C2 — `ix_g09_booking_semester_reporting`

```sql
CREATE INDEX ix_g09_booking_semester_reporting
ON dbo.BOOKING (
    booking_status,
    requested_start_time,
    space_code
)
INCLUDE (requested_end_time);
```

Why chosen: the three reporting statuses form the first search dimension and `requested_start_time` supplies the usable semester boundary. `space_code` supports W3's join/grouping needs, while included `requested_end_time` covers the second overlap condition. W4 derives its grouping expressions from `requested_start_time`.

### C3 — `ix_g09_maintenance_room_finder`

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

Why chosen: W2 joins on `space_code`, filters by `impact_level` and `status`, and tests a range on `start_time`. Included `completion_time` covers the remaining interval-overlap condition.

These definitions were hypotheses before the run; their final status is based on the evidence below.

## 6. Benchmark Methodology

The script compiled and bound the four frozen canonical query bodies, selected deterministic real-data parameters, and validated W2 before the measured phases. The same query variables and parameter values were used in BASE and INDEXED.

For a clean BASE, the benchmark acquired exclusive transaction-held locks on BOOKING and MAINTENANCE_RECORD, then disabled only snapshotted non-unique, non-constraint nonclustered performance indexes on those candidate tables. Primary key, UNIQUE, and other integrity indexes stayed enabled.

Each phase used this order:

1. one warm-up execution of W1–W4 with statistics off;
2. one representative Actual Execution Plan capture of W1–W4;
3. five measured runs per workload with `STATISTICS IO` and `STATISTICS TIME` enabled.

The INDEXED phase rebuilt/created C1–C3 and repeated the identical query and parameter protocol. Medians below use only the five explicitly marked measured runs. For timing, the query-level record immediately following each run's `STATISTICS IO` output was used; the duplicate outer `sp_executesql` timing record was excluded.

## 7. W1 — Booking Conflict Check

### Five measured runs

| Run | BASE reads | BASE CPU ms | BASE elapsed ms | INDEXED reads | INDEXED CPU ms | INDEXED elapsed ms |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2,062 | 9 | 8 | 3 | 0 | 0 |
| 2 | 2,062 | 8 | 8 | 3 | 0 | 0 |
| 3 | 2,062 | 9 | 8 | 3 | 0 | 0 |
| 4 | 2,062 | 9 | 8 | 3 | 0 | 0 |
| 5 | 2,062 | 8 | 8 | 3 | 0 | 0 |
| **Median** | **2,062** | **9** | **8** | **3** | **0** | **0** |

The BOOKING read median fell by 2,059 pages, or 99.85%. Indexed CPU and elapsed results were below SQL Server's displayed millisecond timer resolution; they are not literal zero-cost executions.

### Representative Actual Execution Plans

| Phase | BOOKING access | Index | Actual Rows Read | Actual Rows | Operator logical reads | Key Lookup |
|---|---|---|---:|---:|---:|---|
| BASE | Clustered Index Scan | `pk_booking` | 100,022 | 1 | 2,062 | None |
| INDEXED | Index Seek | `ix_booking_overlap_lock` (C1) | 1 | 1 | 3 | None |

The Stream Aggregate remained, while BOOKING access changed from scanning the entire 100,022-row clustered index to a one-row C1 seek. The read and rows-read evidence—not merely the operator-name change—demonstrates a material benefit attributable to C1.

## 8. W2 — Room Finder

### Five measured runs

| Run | BASE BOOKING reads | BASE maintenance reads | BASE total reads | BASE CPU ms | BASE elapsed ms | INDEXED BOOKING reads | INDEXED maintenance reads | INDEXED total reads | INDEXED CPU ms | INDEXED elapsed ms |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2,062 | 5 | 2,078 | 11 | 10 | 10 | 4 | 25 | 0 | 0 |
| 2 | 2,062 | 5 | 2,078 | 10 | 9 | 10 | 4 | 25 | 0 | 0 |
| 3 | 2,062 | 5 | 2,078 | 10 | 10 | 10 | 4 | 25 | 0 | 0 |
| 4 | 2,062 | 5 | 2,078 | 10 | 10 | 10 | 4 | 25 | 1 | 0 |
| 5 | 2,062 | 5 | 2,078 | 11 | 10 | 10 | 4 | 25 | 0 | 0 |
| **Median** | **2,062** | **5** | **2,078** | **10** | **10** | **10** | **4** | **25** | **0** | **0** |

The unchanged noncandidate reads were 7 for SPACE and 4 for SPACE_FACILITY in every phase. Total reads fell 98.80%, but attribution must be separated:

- C1 reduced BOOKING reads from 2,062 to 10, a 2,052-read (99.52%) reduction.
- C3 reduced MAINTENANCE_RECORD reads from 5 to 4, only one logical read on a 125-row table.
- Indexed CPU and elapsed medians were below the displayed millisecond resolution. The joint candidate phase does not permit that timing change to be divided reliably between C1 and C3.

### Representative Actual Execution Plans

| Branch / phase | Access | Index | Actual Rows Read | Actual Rows | Operator logical reads | Key Lookup |
|---|---|---|---:|---:|---:|---|
| BOOKING BASE | Clustered Index Scan | `pk_booking` | 100,022 | 0 | 2,062 | None |
| BOOKING INDEXED | Index Seek | `ix_booking_overlap_lock` (C1) | Not emitted | 0 | 10 | None |
| Maintenance BASE | Clustered Index Scan | `pk_maintenance_record` | 125 | 0 | 5 | None |
| Maintenance INDEXED | Index Seek | `ix_g09_maintenance_room_finder` (C3) | Not emitted | 0 | 4 | None |

SQL Server did not emit `ActualRowsRead` for the two zero-output INDEXED seeks, so no value is inferred. The plan retained nested-loop anti-semi-join processing for the `EXCEPT`/facility logic. C1 and C3 were both genuinely selected, but almost all stable read reduction came from C1.

## 9. W3 — Approved Booking Hours by Semester

### Five measured runs

| Run | BASE BOOKING reads | BASE total reads | BASE CPU ms | BASE elapsed ms | INDEXED BOOKING reads | INDEXED total reads | INDEXED CPU ms | INDEXED elapsed ms |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2,062 | 2,148 | 30 | 30 | 83 | 169 | 15 | 15 |
| 2 | 2,062 | 2,148 | 33 | 33 | 83 | 169 | 16 | 15 |
| 3 | 2,062 | 2,148 | 31 | 31 | 83 | 169 | 16 | 15 |
| 4 | 2,062 | 2,148 | 31 | 30 | 83 | 169 | 14 | 14 |
| 5 | 2,062 | 2,148 | 31 | 30 | 83 | 169 | 15 | 15 |
| **Median** | **2,062** | **2,148** | **31** | **30** | **83** | **169** | **15** | **15** |

Total reads fell 92.13%; BOOKING reads fell 95.97%. Median CPU fell 51.61%, and median elapsed time fell 50%. SPACE remained at 2 reads and SEMESTER remained at 84 reads, so the read improvement is entirely in BOOKING access.

### Representative Actual Execution Plans

| Phase | BOOKING access | Index | Actual Rows Read | Actual Rows | Operator logical reads | Key Lookup |
|---|---|---|---:|---:|---:|---|
| BASE | Clustered Index Scan | `pk_booking` | 100,022 | 75,722 | 2,062 | None |
| INDEXED | Index Seek | `ix_g09_booking_semester_reporting` (C2) | 12,302 | 12,302 | 83 | None |

The Hash Match aggregate and Hash Match left outer join remained. C2 performed three status/range seeks, returned exactly the 12,302 qualifying semester rows, and covered the required BOOKING columns without a Key Lookup. C1 was not selected for W3; therefore W3 is evidence for C2, not C1.

## 10. W4 — Booking Count by Weekday/Hour

### Five measured runs

| Run | BASE BOOKING reads | BASE total reads | BASE CPU ms | BASE elapsed ms | INDEXED BOOKING reads | INDEXED total reads | INDEXED CPU ms | INDEXED elapsed ms |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2,062 | 2,064 | 28 | 27 | 83 | 85 | 7 | 6 |
| 2 | 2,062 | 2,064 | 29 | 28 | 83 | 85 | 6 | 5 |
| 3 | 2,062 | 2,064 | 28 | 28 | 83 | 85 | 6 | 5 |
| 4 | 2,062 | 2,064 | 28 | 28 | 83 | 85 | 7 | 7 |
| 5 | 2,062 | 2,064 | 27 | 27 | 83 | 85 | 7 | 6 |
| **Median** | **2,062** | **2,064** | **28** | **28** | **83** | **85** | **7** | **6** |

Total reads fell 95.88%; BOOKING reads fell 95.97%. Median CPU fell 75%, and median elapsed time fell 78.57%.

### Representative Actual Execution Plans

| Phase | BOOKING access | Index | Actual Rows Read | Actual Rows | Operator logical reads | Key Lookup |
|---|---|---|---:|---:|---:|---|
| BASE | Clustered Index Scan | `pk_booking` | 100,022 | 75,722 | 2,062 | None |
| INDEXED | Index Seek | `ix_g09_booking_semester_reporting` (C2) | 12,302 | 12,302 | 83 | None |

The Hash Match aggregate remained. C2 supplied the qualifying rows through three covered status/range seeks, with `requested_end_time` evaluated as the remaining overlap predicate and no Key Lookup. C1 was not selected; W4's benefit belongs to C2.

## 11. Before vs After Summary

| Workload | BASE median total reads | INDEXED median total reads | Read reduction | BASE median CPU ms | INDEXED median CPU ms | BASE median elapsed ms | INDEXED median elapsed ms | Candidate actually responsible |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| W1 | 2,062 | 3 | 99.85% | 9 | 0* | 8 | 0* | C1 |
| W2 | 2,078 | 25 | 98.80% | 10 | 0* | 10 | 0* | Primarily C1; C3 saved one maintenance read |
| W3 | 2,148 | 169 | 92.13% | 31 | 15 | 30 | 15 | C2 |
| W4 | 2,064 | 85 | 95.88% | 28 | 7 | 28 | 6 | C2 |

`*` Below SQL Server's displayed millisecond timer resolution, not literal zero execution cost.

The optimizer selected C1 only for W1 and W2 BOOKING access, C2 only for W3/W4 BOOKING access, and C3 only for W2 maintenance access. No representative plan contained a Key Lookup.

## 12. Final Index Decisions

| Candidate | Decision | Why chosen | Evidence | Trade-off |
|---|---|---|---|---|
| C1 `ix_booking_overlap_lock` | **KEEP** | Equality prefix on space/status followed by overlap time boundaries; also required by Step 12 concurrency design | Actually selected for W1 and W2; W1 reads 2,062 -> 3 and rows read 100,022 -> 1; W2 BOOKING reads 2,062 -> 10 | Adds BOOKING write/storage cost, but it already existed, provides decisive read benefit, and has a concurrency role not duplicated by C2's key order |
| C2 `ix_g09_booking_semester_reporting` | **KEEP** | Status/time access path covering reporting joins, grouping inputs, and second overlap boundary | Actually selected for W3/W4; BOOKING reads 2,062 -> 83; rows read 100,022 -> 12,302; no Key Lookup; CPU/elapsed fell materially | Adds a second four-column BOOKING access path and write/storage amplification; justified here because C1 was not selected for the reporting workloads and cannot replace the measured C2 access path |
| C3 `ix_g09_maintenance_room_finder` | **REJECT** | Structurally matches W2 maintenance predicates | Actually selected, but maintenance reads improved only 5 -> 4 on 125 rows; total W2 benefit was overwhelmingly C1 | Adds maintenance-write and storage overhead for a one-page measured saving; reconsider only if maintenance volume or workload frequency grows materially |

### C1 defense

How verified: the optimizer actually used C1, eliminated 2,059 median reads in W1 and 2,052 BOOKING reads in W2, and reduced W1 Actual Rows Read from the full 100,022 rows to one. Its Step 12 concurrency role supplies additional operational justification. **KEEP**.

### C2 defense

How verified: the optimizer actually used C2 for both reporting workloads and did not use C1 there. C2 reduced BOOKING reads by 1,979 pages, limited Actual Rows Read to the 12,302 qualifying rows, avoided Key Lookups, and materially reduced median CPU and elapsed time. **KEEP**.

### C3 defense

How verified: C3 was selected, so it is not rejected for lack of optimizer use. It is rejected because stable evidence shows only one logical read saved on a 125-row table, while the candidate would still impose ongoing write and storage cost. The joint run provides no isolated timing evidence for C3. **REJECT** for the current system; reevaluate if table scale changes.

## 13. Index Trade-offs

### Read benefit

C1 and C2 serve different leading-key needs. C1 narrows by `space_code` and status for conflict/room exclusion and supports key-range concurrency locking. C2 narrows by status and semester time for reporting. Although they contain the same four explicit BOOKING columns in different key/include arrangements, the actual plans demonstrate that the order is not interchangeable for these workloads.

C3 is covering and was selected, but the maintenance table's 125-row size made the observed benefit negligible. A scan cost of five reads is already small.

### Write amplification

Every retained BOOKING index must be maintained on inserts, deletes, and changes to status, space, or requested times. Keeping both C1 and C2 therefore increases write CPU, log generation, page splits, and maintenance work relative to one index. The benchmark did not measure write throughput, but C1's concurrency role and the distinct, material read benefits of C1/C2 justify that cost for the tested workload.

C3 would likewise require maintenance for changes to space, impact, status, start, and completion values. Its one-read benefit does not justify that recurring cost at current scale.

### Storage

C1 and C2 each store one entry per BOOKING row and carry several variable/fixed-width booking columns plus the clustered key. Exact index page counts and sizes were not captured, so no storage number is invented. Their storage overlap is real but buys two access orders that SQL Server demonstrably selected for different workloads.

C3's absolute storage would be small at 125 rows, but small storage alone is not a reason to retain an index without material workload benefit.

## 14. Reproduction Instructions

The reproducible benchmark is `outputs/test-15-index-tuning-benchmark-G09.sql`; the analyzed raw output is `step15-codex-output.txt`.

For a future reproduction—not as part of this analysis-only continuation:

1. Prepare the populated `CampusSpaceManagementSystem` database and confirm the preflight requirements.
2. Use a controlled window with no concurrent BOOKING or MAINTENANCE_RECORD writes; C1 is temporarily disabled for clean BASE and is also a concurrency-support index.
3. Set the benchmark's `@execute_full_benchmark` safety flag to 1.
4. Capture Results, Messages, and all XML Actual Execution Plans.
5. Preserve the warm-up, representative-plan, and five-measured-run protocol exactly.
6. Analyze only the marked measured runs for medians; do not include warm-up, plan-capture, compile, or duplicate outer `sp_executesql` timings.
7. Require the final `Benchmark complete.` and `Original index existence and enabled/disabled state verified.` markers.

## 15. Restoration Verification

The completed output ends with both required success messages:

```text
Benchmark complete.
Original index existence and enabled/disabled state verified.
```

The original snapshot recorded C1 as present and enabled, with C2 and C3 absent. Therefore successful restoration means C1 was rebuilt/enabled and C2/C3 were removed after the experiment. No failure-path message appeared.

## 16. Limitations

- Results cover one SQL Server instance, one data distribution, and one deterministic parameter set per workload.
- Five warm-cache measured runs improve repeatability but do not characterize cold-cache behavior or production concurrency.
- Representative Actual Plans were captured once per workload/phase, not for each of the five measured executions.
- The INDEXED phase tested all three candidates together. Actual plans permit access-path attribution, but C3's isolated timing contribution cannot be separated from C1's W2 benefit.
- SQL Server's displayed timing precision reports several short indexed runs as 0 ms; these mean below displayed resolution.
- W2 returned one space and MAINTENANCE_RECORD contained only 125 rows, limiting generalization of C3's result to a much larger maintenance history.
- W1 used one real approved booking, and W3/W4 used one semester. Other parameter selectivities may lead to different plan choices.
- The benchmark measured reads and query timing, not write throughput, index build duration, fragmentation, or exact index storage size.
- Exclusive locks protected benchmark fairness, so the run does not measure C1's concurrency behavior directly; that role comes from the separate Step 12 design.
