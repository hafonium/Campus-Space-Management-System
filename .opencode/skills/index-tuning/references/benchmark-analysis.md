# Benchmark Analysis Reference

Use only real SQL Server benchmark evidence.

## Purpose

Determine which access paths actually changed and whether each tested index is
worth its recurring cost.

---

## 1. Parse measured runs

For W1–W4 collect all five BASE and five INDEXED measured runs.

Extract:

- per-table logical reads;
- total logical reads where useful;
- CPU time;
- elapsed time.

Exclude warm-up and plan-capture executions.

Use query-level timing. Ignore duplicate outer `sp_executesql` timing records if
present.

Use medians.

---

## 2. Evidence priority

Prefer:

1. logical reads;
2. Actual Rows Read;
3. actual index/operator;
4. Key Lookup presence;
5. median CPU;
6. median elapsed;
7. table size and write/storage cost.

Timing is noisier than IO/row-access evidence.

`0 ms` means below displayed timer resolution, not literal zero cost.

---

## 3. Actual Plan attribution

For each workload identify:

- Scan/Seek operator;
- actual index name;
- Actual Rows Read vs Actual Rows;
- joins/aggregates where relevant;
- Key Lookup.

Do not credit an index merely because it existed in INDEXED phase.

If a workload improves while the optimizer uses another candidate, attribute the
benefit to the index actually selected.

---

## 4. W2 must be decomposed

Because W2 touches several tables, report separately when material:

- SPACE reads;
- FACILITY reads;
- BOOKING reads;
- MAINTENANCE_RECORD reads;
- total reads.

This is now especially important because the 1:N schema may introduce a
`FACILITY(space_code)` candidate.

If C4 is tested:

- verify whether the W2 plan actually uses it;
- compare FACILITY reads/rows;
- consider FACILITY table size;
- do not KEEP it just because a Seek appears.

---

## 5. W3/W4 query-shape check

Before interpreting C2, confirm the benchmark really executed the current Step 16
functions/query bodies using `@semester_id`.

If the benchmark replaced them with precomputed semester start/end parameters,
treat the result as a different experiment, not authoritative evidence for the
production workload.

---

## 6. Decision logic

### KEEP

Material, repeatable benefit on an important workload justifies storage/write
maintenance.

### MODIFY

The idea is useful, but key order/INCLUDE width/duplication can improve.

### REJECT / DEFER

Use when:

- optimizer does not use it;
- benefit is trivial;
- table is too small;
- another index already supplies the useful path;
- recurring write/storage cost outweighs the gain.

A Scan-to-Seek change by itself is never enough.

---

## 7. Candidate defense record

For every tested candidate:

```yaml
candidate: C?
why_chosen:
  - access-pattern rationale

observed_usage:
  W1: ...
  W2: ...
  W3: ...
  W4: ...

evidence:
  logical_reads: ...
  actual_rows_read: ...
  plan: ...
  cpu_median: ...
  elapsed_median: ...

cost:
  storage: ...
  write_maintenance: ...
  overlap_with_other_indexes: ...

decision: KEEP | MODIFY | REJECT / DEFER
```

---

## Completion criteria

Analysis is complete only when:

- all measured runs are accounted for;
- medians are correct;
- current production query shape is confirmed;
- actual optimizer choices are identified;
- multi-table W2 attribution is separated;
- trade-offs are explicit;
- no measurement is invented.
