# Step 15 — Index Tuning Report (G09)

## 1. Objective

This report evaluates four index candidates against the current production
workloads using the official 500k BASE-versus-INDEXED experiment. Decisions are
based only on the raw evidence in
`outputs/15-index-tuning-report-G09/step15-benchmark-output-500k.txt`.

## 2. Source and schema version

The benchmark passed its current-schema and workload compilation gates. It used
the Phase 2 model:

```text
SPACE 1 -> N FACILITY
FACILITY.space_code -> SPACE.space_code
```

`SPACE_FACILITY` was absent. W2 invoked the final
`dbo.fn_GetAvailableSpaces` inline TVF with physical `facility_id` values in
`dbo.FacilityListType`. W3 and W4 invoked the final Step 16 inline TVFs using a
`semester_id`; semester dates were not substituted into simplified benchmark
queries. W1 used the frozen booking-overlap probe.

## 3. Dataset and SQL Server environment

| Item | Observed value |
|---|---:|
| SQL Server | 2022, version 16.0.4265.3, Developer Edition (64-bit) |
| Compatibility level | 160 |
| Recovery model | FULL |
| Generated bookings | 500,000 |
| Total bookings | 500,022 |
| Approved bookings | 72,861 |
| Approved-equivalent bookings | 378,635 |
| Booking range | 2023-09-01 08:00 to 2026-09-21 16:00 |
| Booking span | 1,116 days |
| Spaces | 130 |
| Facilities | 43 |
| Maintenance records | 485 |
| Semesters | 6 |

## 4. Exact benchmark parameters

| Workload | Parameters |
|---|---|
| W1 | `space_code = CR-M3-1006`; start `2026-07-10 10:00`; end `2026-07-10 12:00` |
| W2 | anchor `AUD-MC-1000`; capacity `500`; start `2026-09-22 18:00`; end `2026-09-22 20:00`; facility IDs `1, 3`; viability result `1` |
| W3/W4 | `semester_id = 1`; 59,022 qualifying booking rows |

The same parameters and query text were used in BASE and INDEXED.

## 5. Relevant indexes before tuning

The pre-benchmark inventory contained only these relevant indexes:

- `BOOKING.pk_booking` (clustered, unique);
- `FACILITY.pk_facility` (clustered, unique);
- `MAINTENANCE_RECORD.pk_maintenance_record` (clustered, unique);
- `SEMESTER.pk_semester` and `uq_semester_semester_name`;
- `SPACE.pk_space` and `uq_space_location`.

All four tested candidates were reported as originally absent and enabled-state
zero. The FACILITY inventory had no other index whose leading key was
`space_code`, so C4 did not duplicate an existing access path.

## 6. Candidate hypotheses

| Candidate | Definition | Rationale |
|---|---|---|
| C1 | `BOOKING(space_code, booking_status, requested_start_time, requested_end_time)` | Supports equality on space/status, the first overlap range, and the remaining overlap boundary. It also supplies the access path needed by the Step 12 concurrency design. |
| C2 | `BOOKING(booking_status, requested_start_time, space_code) INCLUDE (requested_end_time)` | Supports approved-equivalent status and semester-time filtering while covering reporting columns for W3/W4. |
| C3 | `MAINTENANCE_RECORD(space_code, impact_level, status, start_time) INCLUDE (completion_time)` | Supports W2's active out-of-service maintenance exclusion and covers its second overlap boundary. |
| C4 | `FACILITY(space_code)` | Tests the missing FK-side access path used by W2 to find physical facility instances for a space. |

Each definition was a hypothesis until the Actual Plans and measurements were
examined.

## 7. Benchmark methodology

The benchmark used one controlled database and dataset for both phases. For
each phase it warmed W1-W4 once, captured one representative Actual Plan per
workload outside measurement, then executed five measured runs with
`STATISTICS IO` and `STATISTICS TIME` enabled. INDEXED used all four candidates;
BASE used none because all were originally absent.

Medians below use only the five measured executions. Warm-ups, Actual Plan
captures, compile timings, and duplicate outer timing records are excluded. In
particular, first-run INDEXED compile records of 2/2 ms (W1), 18/19 ms (W2),
14/14 ms (W3), and 5/5 ms (W4) are not execution measurements. A displayed
`0 ms` means below SQL Server's timer resolution, not zero work.

## 8. All five measured runs

Values are ordered run 1 through run 5. Logical reads are total buffer-cache
page accesses for the query, including the two-page W2 TVP worktable.

| Workload | Phase | Total logical reads (five runs) | CPU ms (five runs) | Elapsed ms (five runs) | Median reads / CPU / elapsed |
|---|---|---|---|---|---|
| W1 | BASE | 14,671; 14,671; 14,671; 14,671; 14,671 | 209; 219; 254; 230; 230 | 25; 31; 36; 35; 26 | 14,671 / 230 / 31 |
| W1 | INDEXED | 4; 4; 4; 4; 4 | 0; 0; 0; 0; 0 | 0; 0; 0; 0; 0 | 4 / 0 / 0 |
| W2 | BASE | 13,991; 13,991; 13,991; 13,991; 13,991 | 271; 261; 262; 262; 263 | 270; 261; 262; 262; 263 | 13,991 / 262 / 262 |
| W2 | INDEXED | 27; 27; 27; 27; 27 | 1; 0; 0; 1; 0 | 0; 0; 0; 0; 0 | 27 / 0 / 0 |
| W3 | BASE | 14,938; 14,938; 14,938; 14,938; 14,938 | 621; 661; 674; 715; 636 | 76; 76; 75; 77; 68 | 14,938 / 661 / 76 |
| W3 | INDEXED | 631; 631; 631; 631; 631 | 39; 39; 39; 39; 38 | 38; 38; 38; 39; 38 | 631 / 39 / 38 |
| W4 | BASE | 14,673; 14,673; 14,673; 14,673; 14,673 | 538; 542; 614; 611; 655 | 56; 61; 64; 62; 72 | 14,673 / 611 / 62 |
| W4 | INDEXED | 366; 366; 366; 366; 366 | 37; 37; 36; 37; 37 | 37; 37; 36; 36; 36 | 366 / 37 / 36 |

### Per-table logical reads

Every value in this table was identical in all five runs of its phase.

| Workload | Table/work object | BASE reads per run | INDEXED reads per run |
|---|---|---:|---:|
| W1 | BOOKING | 14,671 | 4 |
| W2 | BOOKING | 13,965 | 9 |
| W2 | MAINTENANCE_RECORD | 12 | 4 |
| W2 | SPACE | 8 | 8 |
| W2 | FACILITY | 4 | 4 |
| W2 | TVP worktable | 2 | 2 |
| W2 | **Total** | **13,991** | **27** |
| W3 | BOOKING | 14,671 | 364 |
| W3 | SEMESTER | 264 | 264 |
| W3 | SPACE | 3 | 3 |
| W3 | Worktable/Workfile | 0 | 0 |
| W3 | **Total** | **14,938** | **631** |
| W4 | BOOKING | 14,671 | 364 |
| W4 | SEMESTER | 2 | 2 |
| W4 | Worktable/Workfile | 0 | 0 |
| W4 | **Total** | **14,673** | **366** |

## 9. W1 — booking conflict search

BASE scanned `BOOKING.pk_booking`: 500,022 rows were read to produce one
qualifying row. INDEXED used an `Index Seek` on C1
`ix_booking_overlap_lock`: one row was read and one produced, with no Key
Lookup. Logical reads fell from a median 14,671 to 4 (99.97%). Median CPU fell
from 230 ms to below 1 ms and elapsed time from 31 ms to below 1 ms.

This improvement is directly attributable to C1 because it is the index named
by the INDEXED Actual Plan.

## 10. W2 — room finder

W2 returned one viable space in both phases. Its evidence must be decomposed
because three candidates appeared in the INDEXED plan:

| Component | BASE Actual Plan | INDEXED Actual Plan | Attribution |
|---|---|---|---|
| BOOKING | Clustered scan of `pk_booking`; 500,022 rows read, 0 produced; 13,965 reads | Seek on C1; 2 rows read, 0 produced; 9 reads | C1 supplied almost all of W2's reduction. |
| MAINTENANCE_RECORD | Clustered scan of `pk_maintenance_record`; 485 rows read, 0 produced; 12 reads | Seek on C3; 0 rows read/produced; 4 reads | C3 saved 8 reads, but on a 485-row table. |
| FACILITY | Clustered seeks on `pk_facility`; 2 rows read/produced; 4 reads | Seeks on C4; 2 rows read/produced; 4 reads | C4 changed the access path but saved no reads. |
| SPACE | Scan/seek operations; main scan read 130 rows; 8 reads total | Same row access and 8 reads | No candidate benefit. |
| TVP worktable | 2 rows and 2 reads | 2 rows and 2 reads | Unchanged. |

Total median reads fell from 13,991 to 27 (99.81%), while median CPU/elapsed
fell from 262/262 ms to below 1 ms. The combined timing change cannot be divided
precisely among candidates; operator and per-table evidence shows that C1 was
dominant, C3 was minor, and C4 provided no IO reduction. C2 was not selected by
W2. No Key Lookup occurred.

## 11. W3 — approved booking hours per semester

BASE scanned `BOOKING.pk_booking`, reading 500,022 rows and producing 378,635
approved-equivalent rows before downstream semester filtering. INDEXED selected
C2 `ix_g09_booking_semester_reporting`, reading and producing exactly 59,022
rows. No Key Lookup was present because the candidate covered the required
booking columns.

BOOKING reads fell from 14,671 to 364 (97.52%); total reads fell from 14,938 to
631 (95.78%). Median CPU fell from 661 to 39 ms (94.10%) and median elapsed time
from 76 to 38 ms (50.00%). The 264 SEMESTER reads and three SPACE reads were
unchanged. The benefit is attributable to C2, the index selected in the plan.

## 12. W4 — booking count by weekday/hour/semester

BASE scanned `BOOKING.pk_booking`, again reading 500,022 rows and producing
378,635 approved-equivalent rows before semester filtering. INDEXED used C2 and
read/produced 59,022 booking rows. No Key Lookup occurred.

Total reads fell from 14,673 to 366 (97.51%). Median CPU fell from 611 to 37 ms
(93.94%), and median elapsed time from 62 to 36 ms (41.94%). The two SEMESTER
reads were unchanged. This result is directly attributable to C2.

## 13. Before-versus-after summary

| Workload | Median reads BASE -> INDEXED | Read reduction | Median CPU ms | Median elapsed ms | Index actually responsible |
|---|---:|---:|---:|---:|---|
| W1 | 14,671 -> 4 | 99.97% | 230 -> <1 | 31 -> <1 | C1 |
| W2 | 13,991 -> 27 | 99.81% | 262 -> <1 | 262 -> <1 | Mainly C1; small C3 contribution; no C4 read saving |
| W3 | 14,938 -> 631 | 95.78% | 661 -> 39 | 76 -> 38 | C2 |
| W4 | 14,673 -> 366 | 97.51% | 611 -> 37 | 62 -> 36 | C2 |

## 14. Final index decisions

| Candidate | Target workload(s) | Decision | Evidence | Trade-off |
|---|---|---|---|---|
| C1 `ix_booking_overlap_lock` | W1, W2, concurrency access path | **KEEP** | Optimizer used it for W1 and W2. W1 reads fell 14,671 -> 4; W2 BOOKING reads fell 13,965 -> 9. It eliminated full scans of 500,022 bookings. | Four-key index on the largest and most write-active table; booking inserts and changes to space, status, or times maintain it. The measured benefit and concurrency role justify the cost. |
| C2 `ix_g09_booking_semester_reporting` | W3, W4 | **KEEP** | Optimizer selected it for both reports. BOOKING reads fell 14,671 -> 364 with no lookup; CPU reductions exceeded 93%. | A second wide BOOKING index with one INCLUDE adds meaningful storage and write amplification. Its status-leading order serves global semester reports that C1's space-leading order cannot. |
| C3 `ix_g09_maintenance_room_finder` | W2 | **DEFER** | It was used and reduced MAINTENANCE_RECORD reads 12 -> 4 and rows read 485 -> 0, but only eight pages were saved on a 485-row table. No isolated timing benefit can be assigned. | Four keys plus one included column add maintenance-write and storage cost. Reconsider when maintenance volume grows or an isolated C3 benchmark shows material benefit. |
| C4 `ix_g09_facility_space` | W2 | **REJECT** | It was selected, but FACILITY stayed at four reads and 2 rows read/produced in both phases. The table has only 43 rows. | Adds an access path to maintain on facility inserts and `space_code` updates without any measured read benefit. |

`KEEP` is a deployment recommendation, not the final database state of this
experiment. Because all candidates were originally absent, restoration removed
all four after measurement.

## 15. Read, write, storage, and overlap trade-offs

C1 and C2 both target BOOKING but are not duplicates: C1 begins with
`space_code` for per-space overlap probes, while C2 begins with
`booking_status` for cross-space semester reports. Their combined recurring
cost is significant on 500,022 rows, but each produced a distinct, repeatable
reduction on important workloads.

C3 and C4 target much smaller tables. C3 did produce a better access path, but
the current absolute saving is too small to justify acceptance from this run.
C4 produced no IO saving at all. The benchmark did not capture allocated index
bytes or write-throughput measurements, so no storage size or DML overhead is
invented; these costs are evaluated qualitatively from key width, included
columns, table cardinality, and affected updates.

The clean rebuild also showed C1 absent even though it supports the Step 12
concurrency access path. This report recommends C1, but does not modify an
upstream migration or concurrency artifact; deployment ownership should be
resolved separately.

## 16. Restoration verification

The raw output recorded all four candidates as originally absent. The run ended
with both:

```text
Benchmark complete.
Original candidate index existence and enabled/disabled state verified.
```

Therefore the benchmark restored every candidate to its actual pre-benchmark
existence/enabled state. The benchmark gate was subsequently reset to
`@ExecuteFullBenchmark = 0`.

## 17. Reproduction

- Benchmark SQL: `outputs/15-index-tuning-benchmark-G09.sql`
- Generator: `outputs/14-data-generator-G09/high-volume-sample-data-G09.sql`
- Official raw evidence:
  `outputs/15-index-tuning-report-G09/step15-benchmark-output-500k.txt`
- Required build order: Steps 05, 06, 10, 12, 14 (500k), 16, then Step 15
- Run validation with the gate at `0`; run the controlled full experiment with
  the gate at `1`; return it to `0` afterward.
- Permit no concurrent booking writes while C1 is absent or disabled.
- Preserve the separate warm-up, Actual Plan capture, and five measured runs per
  workload and phase.

## 18. Limitations and semantic notes

- This is one SQL Server instance, one warm-cache dataset, and one deterministic
  parameter set per workload; results are not a concurrency or cold-cache test.
- Physical reads were zero in measured runs. Logical reads are therefore the
  strongest repeatable evidence; elapsed time remains environment-sensitive.
- Candidates were introduced as one INDEXED set. Actual Plans identify which
  index served each operator, but timing effects for C1/C3/C4 inside W2 were not
  isolated individually.
- W2 used a future interval with one viable result and no returned booking or
  maintenance conflicts. Different interval density may change residual work.
- FACILITY and MAINTENANCE_RECORD contained only 43 and 485 rows respectively,
  limiting conclusions about C3/C4 at future scale.
- W2 preserves the current physical-instance `facility_id` semantics. If the
  intended business API is facility type/name based, that is an upstream design
  change rather than an index-tuning change.
- W3 retained 264 SEMESTER reads caused by the current production function
  shape; changing that function was outside the candidate experiment.
- `0 ms` measurements are below display resolution. Compile and duplicate outer
  timing records were excluded, as were warm-ups and plan captures.
- Storage bytes, write throughput, and concurrent locking behavior were not
  measured.
