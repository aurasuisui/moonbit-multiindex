# bench — timing benchmarks

Timing benchmarks built on the official `@bench` framework (`moonbitlang/core/bench`), run in
**native + release**. See [`docs/RELEASE_CHECKLIST.md`](../docs/RELEASE_CHECKLIST.md) Tier 3.

```bash
moon run --release bench/main.mbt
```

`bench/` is a **standalone module** (its own `moon.mod`) that imports the **published**
`aurasuisui/multiindex`, matching the layout used by `aurasuisui/bimap` and
`aurasuisui/indexmap`. Root `moon check` / `moon test` therefore never touches it.

## Planned baselines

| Benchmark | Baseline | What it shows |
|---|---|---|
| `get_by` on a unique index | linear scan over `Array[V]` | index lookup is O(1), not O(n) |
| `iter_by` on a non-unique index | linear scan + filter | bucket traversal cost |
| `range_by` on an ordered index | linear scan + filter | O(log n + k) vs O(n) |
| `insert` / `remove` as the index count k grows | k = 1, 2, 4, 8 | the O(k) index-maintenance cost is explicit and documented |
| slot reuse storm (insert/remove churn) | — | free-list behaviour and generation handling |

> Reporting discipline: publish the k-vs-throughput trade-off table in `README.md` rather than
> a single headline number — "more indexes cost more per write" is the honest framing.
## Measured results (2026-10-14, native + release, n = 20 000 records)

`moon run --release bench/main.mbt`; every closure performs **20 000 operations** except the two
`range_by` rows, which perform **one** query each. Figures are per operation, median of 5 runs.

| Benchmark | This library | Naive `Array[Row]` scan | Ratio |
|---|---|---|---|
| `get_by` on a unique index (all hits) | **0.23 µs** | 45.1 µs | **~193× faster** |
| `iter_by` on a non-unique index (≈312 per bucket) | 49.4 µs | 43.8 µs | ~0.9× (*slower*) |
| `range_by` over 25 % of the table (5 000 of 20 000) | 1 227 µs | 60.7 µs | ~20× (*slower*) |

| Writes vs. index count k | k = 1 | k = 2 | k = 4 | k = 8 |
|---|---|---|---|---|
| `insert` (fresh records) | 0.66 µs | 1.50 µs | 4.68 µs | 11.13 µs |
| `remove` | 29.1 µs | 32.5 µs | 40.0 µs | 46.6 µs |
| slot-reuse storm (`remove` + `insert`, k = 8) | — | — | — | 87.0 µs per pair |

### What the numbers actually say (the unflattering rows included)

1. **Point lookups are where the index pays off**: ~193× over a linear scan, and the gap grows
   with n (the scan is O(n); the lookup is O(1) no matter how fat the bucket is).
2. **`iter_by` on a fat non-unique bucket is *not* faster than a scan.** At ~312 records per
   bucket the index saves the *filtering*, not the *work* — both sides walk ~6.2 M records — and
   the index additionally pays iterator state plus one `(RowId, V)` copy per yielded record
   (the copy docs/SPEC.md §3.3 documents). Selective keys are where a bucket wins.
3. **`range_by` is slower than a scan on wide ranges**, same root cause: 5 000 yielded records
   cost 5 000 record copies, while the scan reads one `Int` per row and materializes nothing.
   The ordered index buys *selectivity* and *ordering*, not raw speed on full sweeps.
   → v0.2 candidate: an id-only (or key-only) walk for hot loops.
4. **`remove` is 20–44× more expensive than `insert` and grows with n.** Two effects stack: the
   `order` array is compacted in place (O(len)) and every index drops a bucket entry.
   **docs/SPEC.md §6 lists `remove` as O(I + Σ bucket), which ignores the order compaction** —
   this curve is what exposed the gap (see CHANGELOG Notes).
5. **The k-curve mixes two effects.** k = 1…4 register indexes over *distinct* keys (one-record
   buckets); k = 5…8 add non-unique indexes over tiny key spaces (up to 2 500 records per
   bucket). So "insert costs ~17× more at k = 8" is *not* a clean per-index law: it is eight
   indexes **plus** four fat buckets. Read it as "each index adds its own maintenance, and fat
   buckets cost more", not as a linear constant.
