# Benchmark Analysis Reference

Use this reference only after real SQL Server benchmark output is available.

## Purpose

Answer:

1. What actually changed?
2. Which index did the optimizer actually use?
3. Was the improvement large enough to justify keeping the index?

Do not infer measurements that are missing.

---

## 1. Parse all measured runs

For every W1–W4:

Extract all five BASE and all five INDEXED runs.

Collect:

- per-table logical reads;
- total reads where useful;
- CPU time;
- elapsed time.

Use query-level timing records.

Do not count duplicate outer `sp_executesql` timing records.

Use the median of the five measured runs.

---

## 2. Prefer stable evidence

Evidence priority:

1. logical reads;
2. Actual Rows Read / pages accessed;
3. actual index and physical operator;
4. median CPU;
5. median elapsed time;
6. table size and write/storage overhead.

Timing is useful but noisy.
Logical reads and actual row/page access are usually more stable.

---

## 3. Read Actual Plans

For BASE and INDEXED identify:

- `Clustered Index Scan`;
- `Index Scan`;
- `Index Seek`;
- join strategy;
- aggregate strategy;
- Key Lookup;
- actual index name;
- Actual Rows Read;
- Actual Rows.

Do not say an index helped a workload merely because that index existed.

Use the plan to identify the index SQL Server actually selected.

---

## 4. Correct attribution

Candidate intent is not optimizer evidence.

Example principle:

If C2 was designed for semester reporting but W3's Actual Plan uses C1, then W3 improvement belongs to C1.

Write:

> W3 benefited from C1; W3 provides no direct evidence for C2.

Do not rewrite history to make the original candidate plan appear correct.

---

## 5. Do not equate Seek with good

A plan change:

`Scan -> Seek`

is not sufficient.

Ask:

- how many logical reads were saved?
- how many rows/pages were avoided?
- how large is the table?
- how often is the workload executed?
- what write/storage overhead does the index add?

A seek on a tiny table may have negligible practical value.

---

## 6. Defense record

For each candidate create:

```yaml
candidate: C?

why_chosen:
  - query/access-pattern rationale

observed_usage:
  W1: ...
  W2: ...
  W3: ...
  W4: ...

evidence:
  - reads before -> after
  - rows read before -> after
  - plan before -> after
  - median CPU
  - median elapsed

cost:
  - write maintenance
  - storage
  - overlap with existing indexes

decision:
  KEEP | MODIFY | REJECT / DEFER
```

This record directly answers:

- Why did we choose this candidate?
- How do we know whether it is good?

---

## 7. Decision logic

### KEEP

Use when evidence shows material workload benefit and the cost is justified.

### MODIFY

Use when the candidate concept is useful but:

- key order should change;
- INCLUDE columns should change;
- it duplicates another index;
- a narrower reusable index could serve the same purpose.

### REJECT / DEFER

Use when:

- optimizer does not use it;
- measured benefit is trivial;
- table is too small for the gain to matter;
- write/storage cost outweighs benefit;
- another existing index already provides the useful access path.

---

## 8. Important interpretations

### W1

A strong result typically shows the overlap query moving from broad BOOKING access to targeted access through C1.

Explain with reads/rows, not just the word `Seek`.

### W2

Separate:

- BOOKING reads;
- maintenance reads;
- total query reads.

If most improvement comes from C1, say so.

Do not over-credit C3 if maintenance is tiny.

### W3

Check which index is actually selected.
Do not assume C2.

### W4

Check whether the semester-reporting candidate is used and whether it avoids extra lookups.

---

## 9. Zero millisecond results

If SQL Server reports `0 ms`, state:

> below displayed millisecond timer resolution

Do not claim literal zero execution cost.

---

## Completion criteria

Analysis is complete only when:

- all five runs were considered;
- medians are computed;
- actual optimizer choices are identified;
- candidate attribution is correct;
- trade-offs are included;
- no measurement was fabricated.
