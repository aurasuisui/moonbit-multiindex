# bench — timing benchmarks

Timing benchmarks built on the official `@bench` framework (`moonbitlang/core/bench`), run in
**native + release**. See [`docs/RELEASE_CHECKLIST.md`](../docs/RELEASE_CHECKLIST.md) Tier 3.

```bash
moon run --release bench/main.mbt
```

`bench/` is a **standalone module** (its own `moon.mod`) that imports the **published**
`aurasuisui/multiindex`, matching the layout used by `aurasuisui/bimap` and
`aurasuisui/indexmap`. Root `moon check` / `moon test` therefore never touches it.

> Before the package is published, that import only resolves through a local workspace manifest
> (`moon.work`, deliberately gitignored — `moon publish` would package it): from the repo root,
> `printf 'members = [".", "bench", "cmd/leaderboard"]\n' > moon.work`.

## Planned baselines

| Benchmark | Baseline | What it shows |
|---|---|---|
| `get_by` on a unique index | linear scan over `Array[V]` | index lookup is O(1), not O(n) |
| `iter_by` on a non-unique index | linear scan + filter | bucket traversal cost, **selective vs fat buckets** |
| `range_by` on an ordered index | linear scan + filter | O(log n + k) vs O(n), **narrow vs wide ranges** |
| `insert` / `remove` as the index count k grows | k = 1, 2, 4, 8 | the O(k) index-maintenance cost is explicit and documented |
| slot reuse storm (insert/remove churn) | — | free-list behaviour and generation handling |

> Reporting discipline: publish the k-vs-throughput trade-off table in `README.md` rather than
> a single headline number — "more indexes cost more per write" is the honest framing.
## Measured results (2026-10-14, native + release, n = 20 000 records)

Per **operation**, median of 5 runs (`@bench` winsorizes internally). The fixture spans both bucket
regimes on purpose: `e` is nearly unique (≈2 records per bucket), while `g` cycles through 16 values
(n/16 ≈ 1 250 records per bucket).

| Benchmark | This library | Naive `Array[Row]` scan | Ratio |
|---|---|---|---|
| `get_by` on a unique index (all hits) | **0.25 µs** | 59.3 µs | **~236× faster** |
| `iter_by`, **selective** key (≈2/bucket) | **1.02 µs** | 59.5 µs | **~58× faster** |
| `iter_by`, **fat** bucket (≈1 250/bucket) | 285 µs | 57.5 µs | **~5× slower** |
| `range_by`, **narrow** range (11 of 20 000) | **5.7 µs** | 66.9 µs | **~12× faster** |
| `range_by`, **wide** range (5 000 of 20 000) | 1 785 µs | 83.8 µs | **~21× slower** |

| Writes vs. index count k | k = 1 | k = 2 | k = 4 | k = 8 |
|---|---|---|---|---|
| `insert` (fresh records) | 0.74 µs | 1.59 µs | 5.00 µs | 8.48 µs |
| `remove` | 30.4 µs | 35.9 µs | 34.3 µs | 40.4 µs |
| slot-reuse storm (`remove` + `insert`, k = 8) | — | — | — | 90.5 µs per pair |

### The crossover is the point

1. **Point lookups are where the index always wins** — ~236×, and the gap *grows* with n: the scan
   is O(n), the lookup is O(1) however fat the bucket is.
2. **For traversal the index wins only while the key is selective.** At ≈2 records per bucket it is
   ~58× faster; at ≈1 250 per bucket it is ~5× *slower* than reading the array. Both sides walk the
   same matches — the index additionally pays iterator state and one `(RowId, V)` copy per yielded
   record (the copy docs/SPEC.md §3.3 documents). **The crossover sits where the bucket approaches
   the cost of a linear pass: at n = 20 000 that is a few hundred records per key.**
3. **Same story for ranges**: a narrow range (11 rows) is ~12× faster than scanning; a wide range
   (a quarter of the table) is ~21× slower, because 5 000 yielded records cost 5 000 copies while
   the scan reads one `Int` per row and materializes nothing. An ordered index buys *selectivity*
   and *ordering*, not raw speed on sweeps.
   → v0.2 candidate: an id-only (or key-only) walk for hot loops.
4. **`remove` is 30–50× more expensive than `insert` and grows with n.** Two effects stack: the
   `order` array is compacted in place (O(len)) and every index drops a bucket entry.
   **docs/SPEC.md §6 lists `remove` as O(I + Σ bucket), which ignores the order compaction** — this
   curve is what exposed the gap (the SPEC has since been corrected to O(len + I + Σ log bucket)).
5. **The k-curve mixes two effects.** k = 1…4 register indexes over *distinct* keys (one-record
   buckets); k = 5…8 add non-unique indexes over small key spaces (up to n/8 records per bucket).
   So "insert costs ~11× more at k = 8" is *not* a clean per-index law: it is eight indexes **plus**
   four fat buckets. Read it as "each index adds its own maintenance, and fat buckets cost more".
