---
name: index-tuning
description: >
  Perform Step 15 index tuning for the CS486 Campus Space Management System
  against the current Phase 2 schema and final workload implementation.
---

# Step 15 — Index Tuning

This skill is the orchestrator. Detailed rules live in `references/`.

## Core workflow

Always follow:

`source-of-truth audit -> freeze workloads -> classify access patterns -> candidate hypotheses -> controlled BASE/INDEXED benchmark -> actual evidence -> decision`

Never start from an index definition.

A candidate index is only a hypothesis until real SQL Server evidence supports it.

## Source-of-truth order

Before Step 15, read the current project artifacts in this order:

1. `outputs/08-requirement-change-analysis-G09.md` — intended Phase 2 business semantics.
2. `outputs/09-updated-erd-and-logical-design-G09.md` — current logical schema/cardinalities.
3. `outputs/10-schema-migration-G09.sql` — actual migrated physical schema.
4. `outputs/12-concurrency-implementation-G09.sql` — W1 overlap/concurrency access path and C1 role.
5. `outputs/16-analytical-queries-G09.sql` — concrete W2/W3/W4 production query implementations.
6. current high-volume data generator — actual benchmark scale/distribution.

If these artifacts disagree, STOP and report the disagreement. Do not silently
repair one artifact inside the benchmark.

For Step 15, benchmark the implementation that actually exists only after the
schema/query consistency gate passes.

## Current schema facts that must be revalidated

The current Phase 2 design changed facilities from M:N to 1:N:

- a `SPACE` can contain zero or many `FACILITY` rows;
- `FACILITY.space_code` is a nullable FK to `SPACE.space_code`;
- `facility_name` is not unique;
- `SPACE_FACILITY` is obsolete after migration.

The current Step 16 room finder uses `FacilityListType(facility_id)` and reads
`FACILITY` directly by `space_code`.

Do not silently replace facility IDs with facility names/types during Step 15.
If the team wants type-based facility search instead of instance-based IDs, that
is an upstream Step 16/business-semantics change and must be fixed before tuning.

## Design philosophy

Prefer the smallest benchmark that is:

- correct;
- reproducible;
- fair between BASE and INDEXED;
- executable;
- restoration-safe;
- easy to explain in an oral defense.

Avoid generic metadata frameworks, defensive code for hypothetical states, and
duplicated validation that does not protect a concrete risk in this project.

Do not optimize for a target line count; optimize for clarity.

## Required references

Read in order:

1. `references/workload-audit.md`
2. `references/benchmark-design.md`
3. `references/benchmark-analysis.md`
4. `references/report-finalization.md`

---

## Phase 1 — Workload audit

Read `references/workload-audit.md`.

Deliver:

- source-consistency result;
- frozen W1–W4 definitions;
- access-pattern classification;
- relevant current index inventory;
- candidate rationale records.

Do not mark any candidate KEEP yet.

---

## Phase 2 — Benchmark

Read `references/benchmark-design.md`.

Create or repair:

`outputs/15-index-tuning-benchmark-G09.sql`

The benchmark must:

- use the current 1:N FACILITY schema;
- preserve production query shape;
- use identical workload text/parameters in BASE and INDEXED;
- measure five runs after warm-up;
- capture representative Actual Plans separately;
- modify only indexes under test;
- restore their original state.

Do not disable unrelated performance indexes merely to manufacture a cleaner
baseline.

### Execution behavior

If the target SQL Server is available and the user did not explicitly request
validation-only:

1. validate the generated T-SQL;
2. execute the full benchmark;
3. capture Messages output and Actual Plans;
4. verify restoration;
5. save raw evidence;
6. continue to analysis and report generation.

If SQL Server is unavailable, stop after the strongest possible static
validation. Never fabricate measurements.

---

## Phase 3 — Evidence analysis

Read `references/benchmark-analysis.md`.

Use:

- median logical reads;
- Actual Rows Read;
- actual physical operators;
- actual index selected;
- Key Lookup presence;
- median CPU;
- median elapsed time;
- table size;
- write/storage cost.

Attribute benefits to the index the optimizer actually used.

---

## Phase 4 — Report

Read `references/report-finalization.md`.

Update:

`outputs/15-index-tuning-report-G09.md`

For every tested candidate answer separately:

1. Why was it worth testing?
2. What did SQL Server actually do?
3. What measurable benefit did it provide?
4. What recurring cost does it add?
5. Final decision: `KEEP`, `MODIFY`, or `REJECT / DEFER`.

A Scan-to-Seek change alone is not enough.

## Dataset scale

Do not hard-code one scale into the reusable skill.

The benchmark should accept or declare the expected experiment scale, e.g.
100k or 500k bookings, and validate it.

Changing scale must not silently change:

- W1–W4 semantics;
- candidate definitions for the same experiment;
- parameter-selection rules;
- measurement protocol.

When comparing 100k vs 500k, keep the earlier result as a baseline and produce a
separate scalability result unless the user explicitly wants replacement.

## Completion criteria

Step 15 is complete only when:

1. source artifacts are mutually consistent for the benchmarked schema/workloads;
2. W1–W4 are frozen from current implementation;
3. candidate rationales come from access patterns and existing indexes;
4. generated T-SQL is valid;
5. BASE/INDEXED use identical workload shape and parameter values;
6. real evidence exists when SQL Server is available;
7. medians use only measured runs;
8. Actual Plan attribution is correct;
9. original index state is restored and verified;
10. decisions include both benefit and maintenance cost.
