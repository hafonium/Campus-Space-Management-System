# Benchmark Design Reference

Use this reference to create or repair `outputs/15-index-tuning-benchmark-G09.sql`.

## Purpose

Turn candidate-index hypotheses into a controlled, reproducible SQL Server experiment.

The benchmark must compare BASE and INDEXED fairly.

---

## 1. Preflight

Before changing indexes, validate the database.

Check at least:

- required tables exist:
  - `BOOKING`
  - `SPACE`
  - `SPACE_FACILITY`
  - `FACILITY`
  - `MAINTENANCE_RECORD`
  - `SEMESTER`
- `BOOKING >= 100000`;
- booking data spans at least three academic years;
- active/approved booking rows exist;
- maintenance rows exist;
- semester coverage exists.

Print:

- total bookings;
- active/approved count;
- maintenance count;
- first/last booking time;
- date span;
- semester coverage.

Fail early if the benchmark cannot be meaningful.

---

## 2. Print SQL Server environment

Print at least:

- product version;
- edition;
- compatibility level;
- recovery model.

The benchmark report must identify the execution environment.

---

## 3. Inspect current indexes

Read:

- `sys.indexes`
- `sys.index_columns`
- `sys.columns`

Print relevant indexes for:

- BOOKING;
- SPACE;
- SPACE_FACILITY;
- MAINTENANCE_RECORD;
- SEMESTER.

Snapshot the original existence and enabled/disabled state of every performance index the benchmark may modify.

Never disable/drop:

- PK indexes;
- UNIQUE constraints;
- indexes required purely for integrity.

---

## 4. Candidate-name safety

Before reusing C1, C2, or C3 by name, verify its exact definition.

Check:

- uniqueness;
- constraint status;
- index type;
- ordered key columns;
- included columns.

If an existing index with the candidate name has a different definition:

STOP.

Do not overwrite or repurpose it silently.

---

## 5. Candidate set

The Step 15 candidate set is:

### C1

```sql
CREATE INDEX ix_booking_overlap_lock
ON dbo.BOOKING (
    space_code,
    booking_status,
    requested_start_time,
    requested_end_time
);
```

Rationale:

- supports W1 overlap search;
- strongly relevant to W2 booking exclusion;
- may support W3 through `space_code`;
- also supports Step 12 key-range locking access.

### C2

```sql
CREATE INDEX ix_g09_booking_semester_reporting
ON dbo.BOOKING (
    booking_status,
    requested_start_time,
    space_code
)
INCLUDE (requested_end_time);
```

Rationale:

- targets semester-reporting access;
- status + start-time form a useful search path;
- `requested_end_time` is covered for the second overlap condition.

### C3

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

Rationale:

- matches room-finder maintenance join/equality/range predicates.

These are candidates only. Do not mark them KEEP before measuring.

---

## 6. Deterministic parameter selection

Parameters must come from real data and be reproducible.

### Semester for W3/W4

Prefer a semester with substantial qualifying rows.

Print:

- semester id;
- start;
- exclusive end;
- qualifying row count.

### W1

Select a real row with:

```sql
booking_status = 'approved'
```

Use its:

- `space_code`;
- `requested_start_time`;
- `requested_end_time`.

Do not constrain W1 to the W3/W4 semester.

### W2 facilities

Prefer two facilities that co-occur on real spaces.

If no valid pair exists:

- fall back to one valid facility.

Fail if no facility assignment exists.

### W2 time interval

Prefer an active out-of-service maintenance interval with:

```text
status IN ('reported', 'in_progress')
```

If no preferred interval exists, use a deterministic valid fallback.

### W2 capacity

Choose a capacity that is satisfiable by real spaces with the selected facility requirements.

---

## 7. Parameter viability validation

Before BASE:

- verify W1 parameters are non-null;
- verify semester has qualifying rows;
- execute W2 once or otherwise validate it;
- print W2 result count;
- print selected facilities and all exact parameters.

Do not enter the benchmark with obviously invalid or degenerate parameters.

---

## 8. Single source of canonical workload SQL

Define each canonical W1-W4 SQL body exactly once.

The canonical bodies come from `workload-audit.md`.

Reuse the same body for:

- BASE warm-up;
- BASE plan capture;
- BASE measured runs;
- INDEXED warm-up;
- INDEXED plan capture;
- INDEXED measured runs.

"Same query" means the same relational/query structure, not merely a query
that returns the same result.

Do not rewrite:

- `EXCEPT` as `NOT EXISTS`;
- `NOT EXISTS` as joins;
- W1 by adding/removing self-exclusion logic;
- aggregation/query projection;
- JOIN/WHERE predicate structure;
- Step 16 analytical query bodies.

Only parameterization, formatting, aliases, and comments may differ.

If the generated benchmark body differs structurally from the canonical body,
the benchmark-design phase has failed and must be corrected before the SQL
validity gate.

---

## 9. Clean BASE

BASE means candidate performance indexes must not influence the workload.

Temporarily disable the relevant non-unique performance indexes.

Special case:

`ix_booking_overlap_lock` also supports concurrency.

If temporarily disabled:

- run no concurrent booking writes;
- keep the benchmark controlled;
- restore the index exactly afterward.

Never disable integrity indexes.

---

## 10. BASE execution protocol

Use this order:

1. BASE warm-up with statistics off.
2. Optional representative Actual Plan capture.
3. Enable:

```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
```

4. Execute W1–W4 five measured times each.

Use clear markers:

```text
BASE W1 run 1
...
BASE W4 run 5
```

Actual-plan capture timings are not part of the five-run timing medians.

---

## 11. INDEXED execution protocol

Create/rebuild the candidate indexes.

Then use the exact same:

- dataset;
- query bodies;
- parameters;
- run count.

Order:

1. INDEXED warm-up.
2. representative Actual Plan capture.
3. five measured runs for W1–W4.

Use clear markers.

---

## 12. Restoration

At the end:

- drop candidates that did not originally exist;
- rebuild originally enabled indexes if required;
- restore originally disabled indexes to disabled;
- verify original existence and enabled/disabled state.

Print completion markers such as:

```text
Benchmark complete.
Original index existence and enabled/disabled state verified.
```

---

## 13. Failure safety

Wrap temporary index-state changes in robust `TRY/CATCH`.

On failure:

1. disable benchmark-only `STATISTICS XML/IO/TIME` settings if active;
2. remove newly introduced candidates when appropriate;
3. restore every snapshotted index to its original state;
4. verify as far as possible;
5. rethrow the original error.

The benchmark must not leave the database in an unknown index state.

---

## 14. SQL validity gate

Before declaring the generated benchmark ready for execution, perform a final
T-SQL validity review over the complete script.

Treat executable validity as a separate requirement from benchmark-design
correctness. A benchmark can be logically correct and still be unusable because
the generated T-SQL does not compile.

Check at minimum:

- every variable is declared and remains in scope where it is used;
- every dynamic-SQL parameter passed to `sys.sp_executesql` matches the
  corresponding parameter definition;
- every argument passed through `EXEC` / `sp_executesql` is a valid T-SQL
  procedure-argument form;
- if an argument value requires a function call or expression, compute that
  value into a local variable first when required by T-SQL, then pass the
  variable;
- temp tables referenced by dynamic SQL exist in the same session and in a
  valid scope;
- variables referenced by `TRY/CATCH` restoration logic remain in scope;
- `GO` separators do not accidentally break variable, temp-table, or
  restoration state;
- candidate-index `CREATE`, `ALTER`, `DISABLE`, `REBUILD`, and `DROP`
  statements are syntactically valid;
- repeated workload calls use parameter names and types that exactly match the
  canonical workload parameter list.

For example, do not generate a procedure call that passes a computed expression
directly where SQL Server requires a variable or constant:

```sql
EXEC sys.sp_executesql
    @stmt = @W2_SQL,
    @params = @W2_PARAMS,
    @p_capacity = @w2_capacity,
    @p_facility_1 = @w2_facility_1,
    @p_facility_2 = ISNULL(@w2_facility_2, @w2_facility_1),
    @p_start_time = @w2_start_time,
    @p_end_time = @w2_end_time;
```

Materialize the value first:

```sql
DECLARE @w2_facility_2_effective INT;

SET @w2_facility_2_effective =
    ISNULL(@w2_facility_2, @w2_facility_1);

EXEC sys.sp_executesql
    @stmt = @W2_SQL,
    @params = @W2_PARAMS,
    @p_capacity = @w2_capacity,
    @p_facility_1 = @w2_facility_1,
    @p_facility_2 = @w2_facility_2_effective,
    @p_start_time = @w2_start_time,
    @p_end_time = @w2_end_time;
```

### Validation behavior

If a real SQL Server environment is available:

1. perform a compile/syntax validation before the expensive benchmark run;
2. fix any syntax, binding, or scope error;
3. only then proceed to the BASE/INDEXED execution.

If SQL Server is unavailable:

1. perform the strongest static validation possible;
2. state explicitly that runtime validation is still pending;
3. do not claim the benchmark has been execution-validated.

Do not mark the benchmark as ready for human execution until this gate has
passed as far as the available environment allows.

---

## 15. Output contract

The benchmark output must expose enough information for another agent to analyze without guessing:

- environment;
- dataset preflight;
- semester coverage;
- original index inventory;
- exact parameters;
- facilities;
- W2 result count;
- five BASE runs;
- five INDEXED runs;
- Actual Plans or ShowPlan XML;
- restoration confirmation.

Never print invented benchmark values.
