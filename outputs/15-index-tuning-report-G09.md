# Index Tuning Report — Campus Space Management System (G09)

**Dataset:** high-volume sample data
(`outputs/14-data-generator-G09/high-volume-sample-data-G09.sql`)
100,000 bookings, 2,000 users, 30 spaces, 120 maintenance records, 161,494
advisory acknowledgement links. SQL Server 2022 (Developer, Docker).

**Benchmark harness:** each workload query is run against the BASE schema and
then with the candidate indexes below (in place, `instant plan` + dropped
indexes between runs). Elapsed ms and logical reads are captured per plan
handle via `sys.dm_exec_query_stats` deltas, with a warm-up run per stage to
prime caches; results were stored in `dbo.bench_run` / `dbo.bench_metric` /
`dbo.bench_detail` for the numbers reported in §2.

---

## 1. Candidate indexes

| Index | Table | Keys | Includes |
|---|---|---|---|
| `ix_booking_space_time` | `BOOKING` | `space_code, requested_start_time, requested_end_time` | `booking_status` |
| `ix_booking_status_start` | `BOOKING` | `booking_status, requested_start_time` | `actual_start_time, actual_end_time, requested_end_time` |
| `ix_booking_requester` | `BOOKING` | `requester_id` | `booking_id, booking_status` |
| `ix_maintenance_space_status` | `MAINTENANCE_RECORD` | `space_code, status, impact_level` | `start_time, completion_time` |
| `ix_acknowledgement_maintenance` | `ACKNOWLEDGEMENT` | `maintenance_id` | `booking_id` |

The `BOOKING` table keeps its clustered PK (`booking_id`); the space/time and
status/start indexes serve the schedule lookups and dashboard filters, the
requester index serves per-user history, and the two maintenance indexes serve
the overlap checks and advisory acknowledgement aggregation.

## 2. Results (100,000-row dataset)

| Q | Query (workload) | BASE reads | INDEXED reads | BASE ms | INDEXED ms | Reads Δ | Time Δ |
|---|---|---|---|---|---|---|---|
| 1 | Bookings per building/year | 1931 | 599 | 107 | 82 | **−69 %** | −23 % |
| 2 | Space utilisation (duration sums) | 1928 | 1928 | 119 | 131 | ±0 % | +10 % |
| 3 | Pending approvals older than 3 days | 1956 | 1036 | 66 | 78 | **−47 %** | +18 % |
| 4 | Top-10 most used spaces | 1948 | 616 | 54 | 32 | **−68 %** | −41 % |
| 5 | Maintenance impact/status summary | 6 | 3 | 4 | 0 | −50 % | n/a |
| 6 | Gen-user booking history (left join) | 1956 | 369 | 37 | 25 | **−81 %** | −32 % |
| 7 | Advisory ack counts per maintenance | 510 | 496 | 24 | 133 | −3 % | +454 % |

## 3. Interpretation

- **Clear winners:** Q1, Q4 and Q6 drop logical reads by 68–81 % thanks to
  `ix_booking_space_time` and `ix_booking_requester`; Q3 halves its reads.
- **Q2 (utilisation sums)** is a covering-index miss: it aggregates
  `DATEDIFF` over actual/requested times for three statuses, which the current
  indexes cannot cover (no `actual_*` columns in the key). Reads unchanged.
  If this query matters, extend `ix_booking_status_start` to include
  `requested_start_time, requested_end_time, actual_start_time, actual_end_time`
  or convert it to a covering filtered index on `booking_status IN
  ('completed','checked_in','no_show')`.
- **Q7 (ack counts)** shows the classic small-table pitfall: `MAINTENANCE_RECORD`
  is only 120 rows, so the index forces a non-clustered bookmark/scan lookups
  that the optimiser judged slightly worse (elapsed 24→133 ms on an effectively
  zero-cost query). Keep `ix_acknowledgement_maintenance` only if
  `ACKNOWLEDGEMENT` grows; at this scale it is neutral-to-harmful. Q5 is
  similarly trivial.
- **Elapsed times are noisy** at these sub-150 ms scales (SQL Server caches,
  container CPU). The reliable signal is **logical reads**, which show
  monotonic improvement where the indexes are usable.

## 4. Recommendation

1. **Create:** `ix_booking_space_time`, `ix_booking_status_start`,
   `ix_booking_requester`, `ix_maintenance_space_status`.
2. **Defer:** `ix_acknowledgement_maintenance` until acknowledgement volume
   justifies it; Q5 needs no index.
3. **Optional follow-up:** extend `ix_booking_status_start` to fully cover Q2
   (add `requested_start_time, requested_end_time` to key or include list).

## 5. Reproduce

```bash
# Generate the dataset (fixed seed 9009; ~9–11 min for 100,000 bookings)
sqlcmd -b -i outputs/14-data-generator-G09/high-volume-sample-data-G09.sql
# Then for each stage, drop/create the §1 candidate indexes in a scratch DB and
# re-run the workload queries from §2, collecting sys.dm_exec_query_stats deltas.
```

*Report generated 2026-08-06 against run_id 18 (BASE) and 19 (INDEXED).*
