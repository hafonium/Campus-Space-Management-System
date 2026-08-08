# Workload Audit Reference

Use this reference before designing any Step 15 index.

## Purpose

Freeze workload semantics and convert each query into an access pattern that can justify a candidate index.

Do not ask "what index should I create?" first.

Ask:

1. Which rows does this query need?
2. Which predicates narrow the search?
3. Which predicates are equality / IN / join conditions?
4. Which predicates are ranges?
5. Which columns are used for grouping, projection, or covering?
6. Does an existing index already provide a useful access path?

---

## Canonical workload-body rule

For Step 15, preserving business semantics is not enough. The concrete SQL
shape of each benchmark workload must also be frozen.

Index tuning measures optimizer behavior for a specific query formulation.
Two logically equivalent SQL queries may return the same result but produce
different execution plans, logical reads, join strategies, and index choices.

Therefore:

- use the canonical W1-W4 benchmark bodies defined in this reference;
- parameterization is allowed;
- formatting, aliases, comments, and parameter names may change;
- the relational/query structure must not change.

Do NOT perform equivalent-query rewrites such as:

- `EXCEPT` -> `NOT EXISTS`;
- `NOT EXISTS` -> anti-join;
- adding or removing predicates;
- changing `COUNT_BIG(*)` into row projection;
- moving predicates between `JOIN` and `WHERE` when it changes query shape;
- replacing a final Step 16 analytical query with another formulation that
  merely returns the same rows.

BASE and INDEXED must execute the same canonical body.

If the project implementation and the canonical benchmark body appear to
conflict, STOP and report the difference instead of silently rewriting the
workload.

---

## W1 — Booking conflict check

Canonical benchmark body:

```sql
SELECT COUNT_BIG(*) AS overlapping_approved_bookings
FROM dbo.BOOKING
WHERE space_code = @p_space_code
  AND booking_status = 'approved'
  AND requested_start_time < @p_probe_end
  AND requested_end_time > @p_probe_start;
```

Do not add the trigger's self-exclusion predicate
`booking_id <> @booking_id` to the benchmark body.

The benchmark is measuring the overlap-search access path, not replaying the
entire trigger statement.

Access pattern:

- `space_code`: equality
- `booking_status`: equality
- `requested_start_time`: range
- `requested_end_time`: residual range

Reasoning:

A useful B-tree prefix should first narrow the search to one space and one
booking status, then apply a usable time-range boundary.

A reasonable candidate is:

```sql
(space_code, booking_status, requested_start_time, requested_end_time)
```

This is a hypothesis, not proof of performance.

Important:

- W1 is not tied to a semester.
- Select W1 parameters from a real approved booking across the whole dataset.
- Do not force W1 into the semester selected for W3/W4.

---

## W2 — Room finder

Canonical benchmark body:

```sql
SELECT S.space_code
FROM dbo.SPACE S
WHERE S.capacity >= @p_capacity
  AND S.current_status NOT IN ('temporarily_closed', 'retired')
  AND NOT EXISTS (
      SELECT 1
      FROM (VALUES (@p_facility_1), (@p_facility_2)) AS RF(facility_id)
      WHERE RF.facility_id NOT IN (
          SELECT SF.facility_id
          FROM dbo.SPACE_FACILITY SF
          WHERE SF.space_code = S.space_code
      )
  )

EXCEPT

SELECT S.space_code
FROM dbo.SPACE S
JOIN dbo.BOOKING B
    ON B.space_code = S.space_code
WHERE B.booking_status IN ('approved', 'checked_in', 'completed')
  AND B.requested_end_time > @p_start_time
  AND B.requested_start_time < @p_end_time

EXCEPT

SELECT S.space_code
FROM dbo.SPACE S
JOIN dbo.MAINTENANCE_RECORD MR
    ON MR.space_code = S.space_code
WHERE MR.impact_level = 'out-of-service'
  AND MR.status IN ('reported', 'in_progress')
  AND MR.start_time < @p_end_time
  AND ISNULL(
        MR.completion_time,
        CONVERT(DATETIME2, '9999-12-31')
      ) > @p_start_time;
```

This query shape is frozen for Step 15.

Do not rewrite the two `EXCEPT` branches as correlated `NOT EXISTS`,
anti-joins, or another logically equivalent form.

Preserve all final Step 16 semantics:

- minimum capacity;
- space status availability;
- all required facilities;
- exclude overlapping approved / checked-in / completed bookings;
- exclude overlapping active out-of-service maintenance.

Relevant booking access pattern:

- join/equality: `space_code`
- equality/IN: `booking_status`
- range: `requested_start_time`
- residual overlap check: `requested_end_time`

Relevant maintenance access pattern:

- join/equality: `space_code`
- equality: `impact_level`
- equality/IN: `status`
- range: `start_time`
- overlap completion check: `completion_time`

Facility access:

Existing `SPACE_FACILITY(space_code, facility_id)` already begins with
`space_code`. Do not create a duplicate index without evidence.

`SPACE` is small; a scan may be optimal.

---

## W3 — Approved booking hours per space / semester

Use the final Step 16 query body directly, with only semester values
parameterized. Do not rewrite the LEFT JOIN, aggregation, or predicate placement.

Preserve:

```sql
requested_end_time > @semester_start
AND requested_start_time < @semester_end_exclusive
```

Relevant access pattern:

- join/grouping: `space_code`
- equality/IN: `booking_status`
- range: semester time predicates
- payload: `requested_start_time`, `requested_end_time`

Do not assume the reporting candidate will be selected.
The optimizer may prefer an existing index whose leading `space_code` matches the join/grouping access path.

---

## W4 — Approved booking count by weekday / hour / semester

Use the final Step 16 query body directly, with only semester values
parameterized. Do not rewrite its filtering or grouping structure.

Preserve the same overlap semantics as W3.

Relevant access pattern:

- equality/IN: `booking_status`
- range: `requested_start_time`
- residual overlap check: `requested_end_time`
- grouping expressions use `requested_start_time`

A reporting candidate may reasonably lead with:

```sql
booking_status, requested_start_time
```

and cover other needed columns.

---

## Candidate rationale record

Before writing `CREATE INDEX`, record:

```yaml
candidate: C?
target_workloads:
  - W?

query_evidence:
  equality_or_join:
    - ...
  range:
    - ...
  grouping_or_output:
    - ...

key_order_reasoning:
  - ...

include_reasoning:
  - ...

existing_index_overlap:
  - ...

hypothesis:
  expected_effect:
    - ...
  not_yet_proven: true
```

The point is to preserve the difference between:

- `why this index is worth testing`;
- `whether the benchmark later proves it is worth keeping`.

---

## Key-order reasoning

Use precise language.

Prefer:

> Equality/join predicates form a selective and usable B-tree prefix, followed by the first useful range predicate.

Do not claim:

> Equality columns must always come first.

Column order also depends on:

- selectivity;
- join order;
- grouping access;
- workload reuse;
- optimizer choices.

For interval overlap, an ordinary B-tree generally cannot turn both inequalities into a single perfect seek range. One time boundary may be used for seeking while the other remains a residual predicate or covered value.

---

## INCLUDE reasoning

Use `INCLUDE` when a column is needed to complete the query but does not need to participate in the search ordering.

A covering index can avoid extra lookups, but covering alone does not prove the index is worthwhile.

---

## Completion check

- canonical W1-W4 SQL bodies are identified and frozen;
- no workload has been replaced by a logically equivalent rewrite;
Before benchmark design, confirm:

- W1–W4 semantics are frozen;
- W1 is independent of semester;
- W3/W4 use exact overlap semantics;
- access patterns are classified;
- candidate rationale exists;
- no candidate has been declared `KEEP` yet.
