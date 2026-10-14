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
