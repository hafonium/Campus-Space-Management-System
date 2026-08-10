# Benchmark Design Reference

## Purpose

Create a fair and reproducible SQL Server BASE-vs-INDEXED experiment without
building a production-grade benchmarking framework.

Target:

`outputs/15-index-tuning-benchmark-G09.sql`

---

## 1. Minimal preflight

Validate only concrete requirements of this experiment:

- required tables exist: `BOOKING`, `SPACE`, `FACILITY`,
  `MAINTENANCE_RECORD`, `SEMESTER`;
- `FACILITY.space_code` exists;
- benchmarked Step 16 functions exist;
- obsolete `SPACE_FACILITY` is not required by current Step 16;
- data meets the expected booking scale for this experiment;
- booking data covers the required academic-year range;
- approved/approved-equivalent rows exist;
- maintenance rows exist;
- a usable semester exists.

Use a configurable value, for example:

```sql
DECLARE @ExpectedBookingCount BIGINT = 500000;
```

Print concise dataset facts.

Do not embed a large generic schema validator.

---

## 2. Environment and relevant index inventory

Print:

- SQL Server version/edition;
- compatibility level;
- recovery model.

Inspect only relevant indexes on:

- BOOKING;
- FACILITY;
- MAINTENANCE_RECORD;
- SPACE;
- SEMESTER.

This inventory is part of candidate reasoning.

---

## 3. Preserve production workloads

### W1

Use the frozen overlap probe from `workload-audit.md`.

### W2

Prefer executing final:

```sql
dbo.fn_GetAvailableSpaces(
    @required_capacity,
    @start_time,
    @end_time,
    @required_facilities
)
```

with the actual `dbo.FacilityListType` TVP.

Do not replace the TVP with `(VALUES (@f1), (@f2))` in the canonical measured
workload.

### W3/W4

Prefer executing the final functions by `@semester_id`.

Do not precompute semester boundaries and substitute a structurally simpler
query.

Using the final functions directly is preferred because they are inline TVFs and
it prevents benchmark/query drift.

---

## 4. Deterministic parameters

Parameters must come from real data and be reused unchanged between BASE and
INDEXED.

### W1

Choose a real approved booking anywhere in the dataset and use its:

- `space_code`;
- start;
- end.

W1 is not tied to the W3/W4 semester.

### W2

Choose deterministically:

- one usable space;
- its real capacity;
- one or two real facility IDs from that same space;
- one valid interval that returns at least one room.

Populate the real `FacilityListType` TVP.

Keep selection straightforward. If the primary selection cannot produce a valid
result, fail clearly or add one justified fallback. Do not build a multi-stage
fallback framework by default.

Run W2 once as a viability check outside measured runs.

### W3/W4

Choose one semester ID with a meaningful number of approved-equivalent bookings.

Print exact parameters.

---

## 5. Candidate set is derived, not hard-coded forever

Start from the hypotheses produced by workload audit.

For the current project, likely candidates include C1–C3 and possibly C4
(`FACILITY(space_code)`) after the 1:N migration.

Before changing a candidate:

- record whether it exists;
- record whether it is enabled;
- verify its expected definition if the name already exists.

Use direct checks for the small known candidate set.

Do not build a generic `#ExpectedCandidateColumns` metadata framework unless a
real conflicting-index problem requires it.

Snapshot only indexes this benchmark will modify.

Never modify PK, UNIQUE, or integrity indexes.

---

## 6. Clean BASE

BASE means candidate indexes under evaluation are absent/disabled as appropriate.

Rules:

- if C1 already exists, it may be temporarily disabled because it is part of the
  experiment;
- C1 also supports Step 12 concurrency, so run no concurrent booking writes while
  it is disabled;
- if C2/C3/C4 did not exist originally, they remain absent in BASE;
- do not disable unrelated pre-existing performance indexes.

The goal is to isolate candidate effect without creating an artificial database
that production never has.

---

## 7. Avoid benchmark-distorting safety machinery

Run in a controlled no-write benchmark window.

Do NOT acquire `TABLOCKX` on BOOKING/MAINTENANCE for the whole benchmark by
default.

Do NOT hold one long transaction across all measured runs merely for restoration.

Those choices can distort the experiment and make the script much harder to
defend.

Use direct `TRY/CATCH` restoration and a short controlled execution window.

If the environment cannot guarantee no concurrent writes, stop and ask for a
safe window rather than silently adding heavyweight locking.

---

## 8. Measurement protocol

For BASE:

1. warm W1–W4 once with IO/TIME output off;
2. capture one representative Actual Plan per workload outside measured runs;
3. enable `SET STATISTICS IO ON`;
4. enable `SET STATISTICS TIME ON`;
5. execute each workload five measured times.

Then create/rebuild only the candidates under test.

For INDEXED, repeat with:

- exact same dataset;
- exact same canonical workloads;
- exact same parameter values;
- exact same run count.

Use clear markers:

```text
BASE W1 run 1
...
INDEXED W4 run 5
```

Plan-capture executions and warm-ups do not enter timing medians.

---

## 9. SQL validity gate

Before full execution, validate:

- variables/scopes;
- TVP declarations and function calls;
- `sp_executesql` bindings if dynamic SQL is used;
- candidate DDL;
- temp-table scope if used;
- TRY/CATCH restoration state.

If SQL Server is available, validate by actually compiling/executing the
preflight/viability path before the expensive run.

Do not embed hundreds of lines of compile-metadata machinery in the final script
when the agent can perform validation directly against SQL Server.

---

## 10. Restoration

On success restore each tested candidate to its original state:

- originally absent -> absent;
- originally enabled -> enabled;
- originally disabled -> disabled.

Verify.

On failure, TRY/CATCH must make the same best-effort restoration and rethrow the
original error.

Only tested candidate indexes should require restoration logic.

---

## 11. Execution behavior

If SQL Server is available and the user has not explicitly requested
validation-only:

- execute the full benchmark;
- save raw Messages output;
- save/capture representative Actual Plans;
- verify restoration;
- continue to analysis.

If SQL Server is unavailable, stop after static validation and provide exact run
instructions.

Never fabricate evidence.

---

## 12. Output contract

Raw evidence must expose:

- environment;
- dataset scale;
- exact parameters;
- candidate original state;
- W2 TVP contents and viability result count;
- five BASE runs;
- five INDEXED runs;
- Actual Plan evidence;
- restoration confirmation.
