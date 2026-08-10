# Workload Audit Reference

## Purpose

Freeze the actual Step 15 workloads from the current project before designing
indexes.

Do not let an old benchmark, old skill, or old design note override the current
schema and Step 16 implementation.

---

## 1. Source-consistency gate

Read the current:

- Phase 2 requirement change analysis;
- updated ERD/logical design;
- schema migration;
- concurrency implementation;
- analytical queries.

Confirm before proceeding:

### Facility schema

Expected current state:

```text
SPACE 1 -> N FACILITY
FACILITY(facility_id PK, facility_name, space_code FK NULL)
```

Migration semantics:

- existing M:N associations are converted into distinct physical FACILITY rows;
- facilities shared by several spaces are duplicated into separate rows;
- `facility_name` is no longer unique;
- `SPACE_FACILITY` is dropped.

If the deployed database still has the obsolete junction table because migration
has not been applied, do not silently benchmark a mixed schema.

### Step 16 dependency

The current room finder must reference `FACILITY` directly, not
`SPACE_FACILITY`.

If Step 16 still references the old junction table, STOP and fix Step 16 before
Step 15.

### Facility-ID semantics warning

The current Step 16 API accepts a TVP of `facility_id`.

After the 1:N migration, `facility_id` identifies a physical facility instance,
not a reusable facility type.

Step 15 must benchmark that exact implementation. Do not silently convert it to
`facility_name` or invent a facility-type relation.

If this instance-based behavior is not what the team wants, flag it as an
upstream semantic/design issue and resolve it before tuning.

---

## 2. Canonical workload rule

Concrete production query shape matters.

For W2–W4, use the final Step 16 implementation as the canonical source.
Prefer invoking the final inline TVFs directly when practical; this avoids
copy/paste drift and lets SQL Server optimize the actual production definition.

If the body must be inlined into the benchmark, copy the final body exactly
except for harmless aliases/formatting. Do not replace:

- TVP facility input with a different logical mechanism;
- `EXCEPT` with anti-joins or `NOT EXISTS`;
- W3 semester subqueries with precomputed date parameters;
- W4's SEMESTER join with direct date constants;
- predicate placement;
- grouping expressions.

For W1, the benchmark intentionally measures the overlap-search access path, not
the full trigger wrapper.

BASE and INDEXED must execute the same canonical form.

---

## 3. W1 — Booking conflict search

Canonical benchmark probe:

```sql
SELECT COUNT_BIG(*) AS overlapping_approved_bookings
FROM dbo.BOOKING
WHERE space_code = @p_space_code
  AND booking_status = 'approved'
  AND requested_start_time < @p_probe_end
  AND requested_end_time > @p_probe_start;
```

This intentionally omits trigger wrapper logic and self-exclusion. The purpose is
to measure the overlap access path that C1 supports.

Access pattern:

- `space_code`: equality
- `booking_status`: equality
- `requested_start_time`: first useful range
- `requested_end_time`: residual overlap condition

Known hypothesis:

```sql
BOOKING(space_code, booking_status, requested_start_time, requested_end_time)
```

C1 is also a Step 12 concurrency-supporting index. Index presence alone does not
provide correctness; SERIALIZABLE/key-range locking logic does.

W1 is independent of semester.

---

## 4. W2 — Room finder

Canonical source:

`dbo.fn_GetAvailableSpaces` in final Step 16.

Current production shape includes:

- required capacity;
- space status exclusion;
- `FacilityListType(facility_id)` TVP;
- facility membership through `FACILITY.space_code`;
- first `EXCEPT`: overlapping approved/checked_in/completed bookings;
- second `EXCEPT`: overlapping active out-of-service maintenance.

Do not replace the TVP with two scalar facility parameters merely to simplify the
benchmark. Parameter selection may put one or two rows into the TVP, but the
query/API shape stays the same.

Access patterns:

### SPACE

- `capacity >=`: range
- `current_status NOT IN (...)`: filter
- likely small table; a scan can be optimal

### FACILITY

Current subquery is conceptually:

```sql
SELECT F.facility_id
FROM dbo.FACILITY F
WHERE F.space_code = S.space_code
```

Access:

- `space_code`: equality
- output: `facility_id`

Inspect current indexes. SQL Server does not automatically create an index for
an FK.

If no useful `space_code`-leading index exists, record a facility-access
candidate hypothesis, for example:

```sql
FACILITY(space_code)
```

Whether it is worth testing/keeping depends on actual table size and W2 plan.
Do not create it automatically just because the FK exists.

### BOOKING exclusion

- `space_code`: join/equality
- `booking_status`: IN
- `requested_start_time`: range
- `requested_end_time`: second overlap boundary/residual

### MAINTENANCE exclusion

- `space_code`: join/equality
- `impact_level`: equality
- `status`: IN
- `start_time`: range
- `completion_time`: residual overlap boundary

---

## 5. W3 — Approved booking hours per space / semester

Canonical source:

`dbo.fn_CountApprovedBookingHourBySemester(@semester_id)`.

Preserve the final Step 16 structure:

- start from `SPACE`;
- `LEFT JOIN BOOKING`;
- approved-equivalent statuses in the join;
- semester start/end obtained through the current SEMESTER subqueries;
- full booking duration is summed;
- `GROUP BY S.space_code`.

Do not replace `@semester_id` with precomputed `@semester_start` and
`@semester_end_exclusive` inside the canonical workload. That can change
optimizer behavior and invalidates a query-shape comparison.

Access:

- `space_code`: join/grouping
- `booking_status`: IN
- `requested_start_time`: time boundary
- `requested_end_time`: second overlap boundary
- both time columns are duration payload

Known reporting hypothesis:

```sql
BOOKING(booking_status, requested_start_time, space_code)
INCLUDE (requested_end_time)
```

This remains a hypothesis; read the Actual Plan.

---

## 6. W4 — Approved booking count by weekday/hour/semester

Canonical source:

`dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester(@semester_id)`.

Preserve:

- join to `SEMESTER` by `@semester_id`;
- approved-equivalent status filter;
- overlap predicates;
- grouping by `DATENAME(WEEKDAY, requested_start_time)` and
  `DATEPART(HOUR, requested_start_time)`.

Access:

- `booking_status`: IN
- `requested_start_time`: time boundary and grouping input
- `requested_end_time`: second overlap boundary
- SEMESTER lookup by PK

The same reporting candidate as W3 may help, but only the Actual Plan can prove
usage.

---

## 7. Candidate derivation

Do not freeze the skill to exactly three candidates forever.

Known starting hypotheses for the current project are:

### C1 — overlap/concurrency

```sql
BOOKING(space_code, booking_status, requested_start_time, requested_end_time)
```

### C2 — semester reporting

```sql
BOOKING(booking_status, requested_start_time, space_code)
INCLUDE (requested_end_time)
```

### C3 — maintenance exclusion

```sql
MAINTENANCE_RECORD(space_code, impact_level, status, start_time)
INCLUDE (completion_time)
```

### C4 — facility lookup, conditional

Consider only if current inventory has no useful `FACILITY.space_code` access
path:

```sql
FACILITY(space_code)
```

C4 is especially likely to be REJECT/DEFER when FACILITY is tiny, but that is an
evidence/trade-off conclusion, not an assumption.

Also inspect whether a SPACE index is justified. Do not add one merely because
capacity/status appear in W2 if SPACE is tiny.

For every candidate record:

```yaml
candidate: C?
target_workloads: [...]
query_evidence:
  equality_or_join: [...]
  range: [...]
  grouping_or_output: [...]
existing_index_overlap: [...]
key_order_reasoning: [...]
include_reasoning: [...]
expected_effect: [...]
not_yet_proven: true
```

---

## Completion check

Do not proceed to benchmark design until:

- no benchmark dependency references obsolete `SPACE_FACILITY`;
- facility semantics are understood and intentionally preserved;
- W2/W3/W4 match final Step 16;
- W1 probe definition is documented;
- access patterns are classified;
- current indexes are inspected;
- candidate hypotheses are recorded;
- no candidate has been declared KEEP.
