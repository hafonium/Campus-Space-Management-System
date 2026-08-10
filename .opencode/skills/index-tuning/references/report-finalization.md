# Report Finalization Reference

## Purpose

Turn the current-schema benchmark into a concise, defensible Step 15 report.

Target:

`outputs/15-index-tuning-report-G09.md`

The report explains the experiment; it does not duplicate the benchmark script.

---

## Required structure

1. Objective
2. Source/schema version used
3. Dataset and SQL Server environment
4. Exact benchmark parameters
5. Relevant indexes before tuning
6. Candidate hypotheses and rationale
7. Benchmark methodology
8. W1 — booking conflict search
9. W2 — room finder
10. W3 — approved booking hours / semester
11. W4 — booking count by weekday/hour / semester
12. Before-vs-after summary
13. Final index decisions
14. Trade-offs
15. Reproduction instructions
16. Limitations / semantic notes

---

## Source/schema note

State explicitly that the benchmark uses the current Phase 2 facility model:

```text
SPACE 1 -> N FACILITY
FACILITY.space_code -> SPACE.space_code
```

and that `SPACE_FACILITY` is not part of the benchmarked schema.

For W2, state that the current Step 16 function accepts physical
`facility_id` values through `FacilityListType`.

If the team considers that instance-based semantics a future design concern,
record it as a limitation. Do not silently reinterpret the workload in the
report.

---

## Candidate explanation

For each tested candidate answer:

### Why chosen?

Use:

- equality/join predicates;
- range boundaries;
- grouping/projection;
- covering;
- existing-index overlap.

### How verified?

Use:

- median logical reads;
- Actual Rows Read;
- actual index/operator;
- CPU/elapsed medians;
- table size;
- write/storage cost.

---

## W2 reporting

Report separately when material:

- SPACE;
- FACILITY;
- BOOKING;
- MAINTENANCE_RECORD;
- total query reads.

If a facility index candidate was considered or tested, state the result
explicitly.

---

## Five-run evidence

Show all five values or enough detail to verify the median.

Do not include warm-up/plan-capture timing in the median.

---

## Final decision table

Use:

| Candidate | Target workload(s) | Decision | Why chosen | Evidence | Trade-off |
|---|---|---|---|---|---|

Allowed decisions:

- KEEP
- MODIFY
- REJECT / DEFER

The table must include every candidate actually tested; do not hard-code the
report to only C1–C3 if C4 or another justified candidate was evaluated.

---

## Trade-offs

Discuss:

- storage;
- write amplification;
- index overlap;
- table cardinality;
- workload importance/frequency;
- C1 concurrency role.

Do not say an index is good only because SQL Server chose an Index Seek.

---

## Reproduction instructions

Include:

- benchmark SQL path;
- data-generator/expected booking scale;
- required migration and Step 16 version;
- no concurrent booking writes while C1 is disabled;
- Actual Plan capture;
- `STATISTICS IO/TIME`;
- five measured runs;
- restoration verification.

For a 500k scalability run, keep the earlier 100k result separate unless the
user explicitly requests replacing it.

---

## Language precision

Use:

- candidate = hypothesis;
- Actual Plan = optimizer evidence;
- logical reads = buffer-cache page accesses;
- CPU time = processor time;
- elapsed time = wall-clock time;
- residual predicate = condition checked after usable seek bounds;
- covering = required columns available without an extra lookup.

---

## Completion criteria

A reviewer should be able to answer:

1. Which schema/query revision was benchmarked?
2. Why was each candidate proposed?
3. Was BASE-vs-INDEXED controlled fairly?
4. Which index did SQL Server actually use?
5. How large was the measured difference?
6. Why was each index kept, modified, or rejected?
7. Was the original index state restored?
