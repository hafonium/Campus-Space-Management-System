# Report Finalization Reference

Use this reference to finalize `outputs/15-index-tuning-report-G09.md`.

## Purpose

Turn real benchmark evidence into a defensible technical report.

The report must explain both design reasoning and measured evidence.

---

## Required report structure

1. Objective
2. Dataset and Environment
3. Exact Benchmark Parameters
4. Existing Indexes Before Tuning
5. Candidate Indexes and Rationale
6. Benchmark Methodology
7. W1 — Booking Conflict Check
8. W2 — Room Finder
9. W3 — Approved Booking Hours by Semester
10. W4 — Booking Count by Weekday/Hour
11. Before vs After Summary
12. Final Index Decisions
13. Index Trade-offs
14. Reproduction Instructions

---

## Candidate explanation format

For every candidate answer separately:

### Why chosen?

Explain from:

- equality / join predicates;
- range predicates;
- grouping;
- covering needs;
- existing index structure.

Use precise language.

Example style:

> `space_code` and `booking_status` provide a useful equality prefix for the conflict workload, while `requested_start_time` supplies the first usable range boundary. `requested_end_time` remains necessary for the second overlap condition.

Do not say:

> We indexed these columns because they appear in WHERE.

### How verified?

Explain from:

- median logical reads;
- Actual Rows Read;
- plan change;
- actual index used;
- median CPU/elapsed;
- write/storage cost.

Example style:

> The candidate is kept because the optimizer actually selected it and the workload's logical reads fell materially under the same query and parameters.

---

## Five-run tables

For each workload show all measured values or enough detail to demonstrate the median.

Use:

- BASE reads;
- INDEXED reads;
- BASE CPU;
- INDEXED CPU;
- BASE elapsed;
- INDEXED elapsed.

Do not use plan-capture timing as a measured-run median.

---

## W2 reporting

Because multiple tables contribute to W2:

- report BOOKING reads separately;
- report MAINTENANCE_RECORD reads separately;
- report total query reads when available.

This makes index attribution defensible.

---

## Plan interpretation

State:

- plan before;
- plan after;
- actual index used;
- Key Lookup status when relevant.

Do not write:

> Index Seek is faster.

Prefer:

> The optimizer changed from a broad scan to targeted indexed access, reducing logical reads from X to Y.

---

## Final decision table

Use:

| Candidate | Decision | Why chosen | Evidence | Trade-off |
|---|---|---|---|---|

Allowed decisions:

- KEEP
- MODIFY
- REJECT / DEFER

---

## Trade-offs

Discuss:

- write amplification;
- storage;
- duplicated access paths;
- table size;
- workload frequency;
- concurrency role where relevant.

An index should not be kept merely because it improves one operator name.

---

## Reproduction instructions

Include:

- benchmark SQL path;
- required database preparation;
- no concurrent booking writes during clean BASE when concurrency index is disabled;
- Actual Plan capture;
- `STATISTICS IO/TIME`;
- five measured runs;
- restoration verification.

---

## Language precision

Use these distinctions consistently:

- candidate index = hypothesis worth testing;
- benchmark evidence = observed result;
- optimizer choice = actual selected access path;
- logical reads = page accesses from buffer cache;
- elapsed time = wall-clock execution time;
- CPU time = processor time consumed;
- covering index = query can obtain required columns without additional lookup;
- residual predicate = condition checked after the usable seek portion.

---

## Completion criteria

The final report must let a reviewer answer:

1. Why was each index proposed?
2. How was the experiment controlled?
3. What did SQL Server actually do?
4. How large was the measured change?
5. Why was each index kept, modified, or rejected?
