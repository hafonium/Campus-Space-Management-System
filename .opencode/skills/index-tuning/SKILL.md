---
name: index-tuning
description: >
  Complete Step 15 index tuning for the CS486 Campus Space Management System.
  Use this skill to audit workloads, design a reproducible SQL Server benchmark,
  analyze real benchmark evidence, and finalize KEEP/MODIFY/REJECT index decisions.
---

# Step 15 — Index Tuning

This file is the orchestrator for Step 15.

The detailed procedures are stored under `references/`.

## Core principle

Do not start from an index.

Always follow:

`workload -> access pattern -> candidate hypothesis -> controlled benchmark -> actual evidence -> decision`

A candidate index is only a hypothesis until benchmark evidence supports it.

## Required references

Read these references in order:

1. `references/workload-audit.md`
2. `references/benchmark-design.md`
3. `references/benchmark-analysis.md`
4. `references/report-finalization.md`

Do not skip a stage unless its output already exists and has been verified.

---

## Phase 1 — Audit workloads

Read `references/workload-audit.md`.

Goals:

- identify exactly W1–W4;
- preserve the final query semantics;
- classify query access patterns;
- identify relevant existing indexes;
- produce a short design rationale for each candidate.

Do not design indexes before the workload semantics are frozen.

Freezing a workload includes freezing its canonical SQL body, not only its
business meaning.

Do not allow logically equivalent query rewrites during Step 15. Index tuning
must measure the same concrete query formulation across agents and across
BASE/INDEXED runs.

Expected output:

- exact workload definitions;
- equality / IN / join predicates;
- range predicates;
- grouping / projection needs;
- candidate rationale records.

---

## Phase 2 — Design the benchmark

Read `references/benchmark-design.md`.

Create or repair:

`outputs/15-index-tuning-benchmark-G09.sql`

The benchmark must be behaviorally equivalent to the approved Step 15 experiment:

- dataset preflight;
- SQL Server environment output;
- current index inventory;
- original index-state snapshot;
- deterministic parameters from real data;
- clean BASE;
- BASE warm-up;
- BASE actual-plan capture;
- five BASE measured runs;
- candidate index creation/rebuild;
- INDEXED warm-up;
- INDEXED actual-plan capture;
- five INDEXED measured runs;
- restoration of original index state;
- restoration verification;
- safe failure handling.

The same workload query text and the same parameters must be used in BASE and INDEXED.

The workload body must also match the canonical W1-W4 body defined by
`references/workload-audit.md`.

Do not substitute an equivalent SQL formulation.

Never modify PK, UNIQUE, or integrity indexes for a benchmark baseline.

Before Phase 2 is considered complete, the generated benchmark must pass the
SQL validity gate defined in `references/benchmark-design.md`.

Treat these as separate requirements:

- benchmark-design correctness: the experiment is logically fair and safe;
- executable correctness: the generated T-SQL is syntactically valid, has
  correct parameter binding, and preserves required scope.

If a real SQL Server environment is available, perform a compile/syntax
validation before the expensive benchmark run. If SQL Server is unavailable,
perform the strongest static validation possible and state that runtime
validation is still pending.

---

## Human execution gate

If no real SQL Server execution environment is available:

STOP after producing the benchmark script.

Do not fabricate:

- logical reads;
- CPU time;
- elapsed time;
- actual execution plans;
- actual index choices.

Ask the user to run the benchmark and return the SQL Server Messages output and Actual Plans.

---

## Phase 3 — Analyze benchmark evidence

When real benchmark output exists, read:

`references/benchmark-analysis.md`

Extract evidence from all measured runs.

Use:

- median logical reads;
- median CPU time;
- median elapsed time;
- Actual Rows Read;
- actual physical operators;
- actual indexes used;
- Key Lookup presence;
- table size;
- write/storage cost.

Attribute improvements to the index the optimizer actually used, not to the index that was originally intended for that workload.

---

## Phase 4 — Finalize the report

Read:

`references/report-finalization.md`

Update:

`outputs/15-index-tuning-report-G09.md`

For every candidate, the report must answer two distinct questions:

### Why was this index chosen?

Answer from query structure and access-pattern reasoning.

### How do we know whether it is good?

Answer from real benchmark evidence and trade-offs.

Final decisions must be one of:

- `KEEP`
- `MODIFY`
- `REJECT / DEFER`

A `Scan -> Seek` change alone is never enough evidence to KEEP an index.

---

## Step 15 fixed workload set

The benchmark must cover exactly:

- W1 — booking conflict check;
- W2 — room finder;
- W3 — approved booking hours per space / semester;
- W4 — approved booking count by weekday / hour / semester.

Do not silently substitute unrelated reporting queries.

---

## Important project constraints

- W1 is not a semester workload. Its probe parameters must come from a real approved booking across the dataset.
- W3/W4 preserve Step 16 semester overlap semantics:

```sql
requested_end_time > @semester_start
AND requested_start_time < @semester_end_exclusive
```

- Existing `ix_booking_overlap_lock` may be required by Step 12 concurrency logic. A clean BASE may temporarily disable it only in a controlled benchmark with no concurrent booking writes, then restore it exactly.
- Do not hard-code previous benchmark metrics into the skill.
- Do not assume a candidate is useful merely because its definition looks reasonable.

---

## Completion criteria

Step 15 is complete only when:

1. workloads are semantically frozen;
2. canonical W1-W4 SQL bodies are frozen and no equivalent-query rewrite is used;
3. every candidate has a design rationale;
4. the generated T-SQL has passed the SQL validity gate as far as the available
   environment allows;
5. the benchmark is reproducible and restoration-safe;
6. real BASE and INDEXED evidence exists;
7. medians are calculated from measured runs;
8. execution-plan attribution is correct;
9. KEEP/MODIFY/REJECT decisions consider both benefit and cost;
10. the report explains both `why chosen` and `how verified`.
