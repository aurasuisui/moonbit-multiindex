# bench — timing benchmarks

Timing benchmarks built on the official `@bench` framework (`moonbitlang/core/bench`), run in
**native + release**. See [`docs/RELEASE_CHECKLIST.md`](../docs/RELEASE_CHECKLIST.md) Tier 3.

```bash
# from the repo root: make the sibling modules workspace members (once per checkout)
Set-Content moon.work 'members = [".", "bench", "cmd/leaderboard"]'
moon run --release bench/main.mbt
```

`bench/` is a **standalone module** (its own `moon.mod`), matching the layout used by
`aurasuisui/bimap` and `aurasuisui/indexmap`; root `moon check` / `moon test` never touches it.

### It must measure the **local** module (B5)

`moon.work` is deliberately gitignored (`moon publish` would package it), so a bare checkout
has no workspace. The manifest's `"aurasuisui/multiindex@0.2.0"` is then a real registry
dependency and the benchmark would silently time the **published** 0.2.0, not `../src`.
The version string itself is mandatory syntax — dropping it makes `moon` fail with
`moon.mod only supports versioned registry dependencies in `import``. The workspace member
is what overrides the registry, so the recipe above is the supported way to run the bench.

Two pieces of evidence, both taken on 2026-10-19 with `moon 0.1.20261012` (at that time the
manifest still said `0.1.0`, hence the version in the transcript):

```text
$ moon tree                       # run from bench/
bench/multiindex_bench@0.0.0 (local C:\...\moonbit-multiindex\bench) [workspace member]:
└─ aurasuisui/multiindex -> aurasuisui/multiindex@0.1.0 (local C:\...\moonbit-multiindex) [workspace member]

$ moon run --release bench/main.mbt
# aurasuisui/multiindex VERSION: 0.1.0 (local workspace module)
```

Toolchain note: this `moon` lexes `moon.mod` as strict TOML **without comment support** — any
`#` (even after a valid key) fails with `Lexing error at <offset>..<offset+1>`. That is why the
manifests stay comment-free and the explanation lives here.

From M8 on, `bench/main.mbt` calls APIs that exist only in the local module, so a stale
registry resolution fails to compile instead of silently measuring the wrong code.

## M8 targets (written **before** implementing, 2026-10-19)

Every number below is measured in **one process, one machine, one build** (`moon run --release`),
against the *same* table the baseline uses (n = 20 000). The naive column must be a *scan that only
reads the slot index* — comparing an id-only walk with a scan that materializes records would flatter us.

| Path | Baseline (this checkout, 2026-10-19) | Target | Gate |
|---|---|---|---|
| fat-bucket id-only walk (`g`, ≈1 250/bucket) | 297 µs/op (`iter_by`) | **≤ 148 µs/op** | ≥ 2× faster |
| wide-range id-only walk (5 000 of 20 000) | 1.72 ms/op (`range_by`) | **≤ 860 µs/op** | ≥ 2× faster |
| `swap_remove` (k = 1) | 35.4 µs/op (`remove`) | **≤ 7.1 µs/op** | ≥ 5× faster |

> The baselines moved ~10–20 % against the 2026-10-14 table (same code, busier machine). Both sides of
> every ratio are re-measured now, so the ratio — not the absolute number — is the claim.

**Outcome (2026-10-19).** The `swap_remove` gate passed: 54.5 µs → **1.49 µs/op** at k = 1 on the
n = 20 000 fixture (target ≤ 7.1 µs), i.e. **36.7×**. The two id-only gates were **not** reached and
the API was **not** shipped: the best achievable shape (a callback walk that avoids every per-record
box) measured 1.70×, below the 2× gate written above, and the remaining cost is a property of
`moonbitlang/core`'s `Iter` (one boxed `Option` per element, ≈30 ns each), not of this library.
Decision and evidence: `docs/SPEC.md` §13 R2. This table is kept — gates that are written down
before the work should be visible whether they were met or missed.

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

## S8c: `swap_remove` vs `remove`, three sizes (measured 2026-10-19)

Same process, same machine, `moon run --release`, native. Two tables per configuration: each is
built, its handles materialised and a 20 % warm-up drain done **outside the clock**, then the same
`deletions` handles are deleted from the middle of the order, ascending, fastest of 3.
k = 1 registers only the unique index `a` (isolates the `order` maintenance); k = 8 registers all
eight indexes (adds the index work both paths share).

| n | deletions | `remove` (k=1) | `swap_remove` (k=1) | ratio | `remove` (k=8) | `swap_remove` (k=8) | ratio |
|---|---|---|---|---|---|---|---|
| 1 000 | 250 | 1.57 µs | 0.90 µs | 1.7× | 8.15 µs | 7.78 µs | 1.05× |
| 10 000 | 1 000 | 22.7 µs | 0.82 µs | **27.9×** | 25.2 µs | 5.41 µs | 4.7× |
| 100 000 | 1 000 | 255 µs | 0.84 µs | **303×** | 297 µs | 10.2 µs | 29× |

Read the k = 1 columns: `remove` grows 1.57 → 22.7 → 255 µs (**linear in n**, ≈ 10× per 10× rows)
while `swap_remove` stays at **0.82–0.90 µs** — flat, as O(1) must be. The gap is small at n = 1 000
only because shifting a 1 000-entry `Int32` array is itself cheap; the asymptote is what the API is for.
At k = 8 both paths pay the same eight index deletions, so the ratio compresses (29× at n = 100 000):
`swap_remove` removes *the order term*, it does not make index maintenance free.

Cross-check, same fixture as the targets table below (n = 20 000, `@bench`, k = 1):
`remove` **54.5 µs/op** vs `swap_remove` **1.49 µs/op** = **36.7×**; k = 8: 69.4 → 20.2 µs = 3.4×.

### Measurement note: build the fixture in the caller

An earlier version of this comparison timed a helper that built its own 100 000-row table. It
reported 10–15 µs per deletion *whatever the batch size*, which read as "swap_remove is linear after
all". It is not: sweeping the batch size at n = 100 000, k = 1 gives

| deletions timed | 100 | 1 000 | 4 000 | 10 000 |
|---|---|---|---|---|
| reported µs/deletion | 140 | 15 | 3.9 | 2.5 |

The **total** stays ≈ 14–25 ms — a one-off O(live rows) cost that lands inside the first timed
region (the first allocation after a fresh 100 000-row build triggers a whole-heap pass), divided by
the batch size. Hoisting the build, the handle materialisation and the warm drain into the caller
makes it disappear: 0.84 µs/deletion, 303×. In-package white-box timing agrees —
`order_swap_remove` alone 0.28 µs, `swap_remove` (all maintenance) 2.34 µs, `remove` 484 µs at
n = 100 000. **Any future benchmark here must keep the setup out of the timed helper**, and any
"O(1) operation got slower with n" reading should first be checked against the batch-size sweep.

## `positions` 的代价 (pre-S8b baseline vs S8c, measured 2026-10-19)

S8b added the resident `positions` array (slot → `order` index) that makes the swap O(1). It costs
one `Int32` per slot and, more importantly, one extra store **per entry moved by `order_remove`**.
Measured by running the *same* bench file against commit `64820b6` (S8a, before `positions`) in a
`git worktree`, then against S8c, same machine, same `moon run --release`, same n = 20 000 fixture:

| `@bench` (µs/op) | pre-S8b `64820b6` | S8c (HEAD) | delta |
|---|---|---|---|
| `insert` k = 1 | 0.950 | 0.981 | +3 % (noise) |
| `insert` k = 2 | 1.791 | 1.754 | −2 % (noise) |
| `insert` k = 4 | 5.744 | 6.135 | +7 % |
| `insert` k = 8 | 11.579 | 11.637 | +0.5 % |
| `remove` k = 1 | **34.76** | **54.53** | **+57 %** |
| `remove` k = 2 | 36.95 | 51.64 | +40 % |
| `remove` k = 4 | 46.86 | 58.93 | +26 % |
| `remove` k = 8 | 52.93 | 69.36 | +31 % |
| slot-reuse storm k = 8 | 102.4 | 144.1 | +41 % |

Read it as: **`insert` is unchanged** (it pays exactly one extra store, below run-to-run noise — note
the same two runs disagree by ~20 % on `get_by`, whose code did not change at all), while
**order-preserving `remove` regressed by a quarter to a half**. The mechanism is arithmetic, not a
mystery: a middle deletion at n = 20 000 shifts ≈ 10 000 entries, and each shifted entry now also
writes its `positions` slot — ≈ 2 ns per store, ≈ 20 µs per deletion, which is exactly the k = 1 gap
(34.8 → 54.5). This is the price of O(1) `swap_remove`; it is paid **only** by callers that keep
insertion order. S8b considered building `positions` lazily and rejected it (state machine + a branch
on every insert, docs/SPEC.md §13 R3).

## Measured results (2026-10-19, native + release, n = 20 000 records)

Per **operation**, median of 5 runs (`@bench` winsorizes internally). The fixture spans both bucket
regimes on purpose: `e` is nearly unique (≈2 records per bucket), while `g` cycles through 16 values
(n/16 ≈ 1 250 records per bucket).

| Benchmark | This library | Naive `Array[Row]` scan | Ratio |
|---|---|---|---|
| `get_by` on a unique index (all hits) | **0.24 µs** | 59.3 µs | **~245× faster** |
| `iter_by`, **selective** key (≈2/bucket) | **1.25 µs** | 61.3 µs | **~49× faster** |
| `iter_by`, **fat** bucket (≈1 250/bucket) | 308 µs | 56.9 µs | **~5.4× slower** |
| `range_by`, **narrow** range (11 of 20 000) | **6.4 µs** | 84.1 µs | **~13× faster** |
| `range_by`, **wide** range (5 000 of 20 000) | 1 819 µs | 83.1 µs | **~22× slower** |

(The 2026-10-14 run of the same fixtures read 0.25 / 1.02 / 285 / 5.7 / 1 785 µs — every ratio held
within noise. Absolute values drift 10–20 % between runs on this machine; only the ratio is a claim.)

| Writes vs. index count k | k = 1 | k = 2 | k = 4 | k = 8 |
|---|---|---|---|---|
| `insert` (fresh records) | 0.98 µs | 1.75 µs | 6.14 µs | 11.6 µs |
| `remove` | 54.5 µs | 51.6 µs | 58.9 µs | 69.4 µs |
| `swap_remove` | **1.49 µs** | **2.69 µs** | **10.2 µs** | **20.2 µs** |
| `swap_remove` vs `remove` | 36.7× | 19.2× | 5.8× | 3.4× |
| slot-reuse storm (`remove` + `insert`, k = 8) | — | — | — | 144 µs per pair |

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
   → measured in M8 and **rejected**: the least-boxed walk achievable on this toolchain is 1.70×, below
   the 2× gate (the cost is one boxed `Option` per element in `moonbitlang/core`'s `Iter`, ≈30 ns,
   not this library's tuple). See docs/SPEC.md §13 R2 — the candidate is closed, not pending.
4. **`remove` is 30–70× more expensive than `insert` and grows with n.** Two effects stack: the
   `order` array is compacted in place (O(len)) and every index drops a bucket entry.
   **docs/SPEC.md §6 listed `remove` as O(I + Σ bucket), which ignored the order compaction** — this
   curve is what exposed the gap (the SPEC was corrected to O(len + I + Σ log bucket), and S8c added
   `swap_remove` as the O(1) alternative: 36.7× faster at k = 1, 3.4× at k = 8 on this fixture).
5. **The k-curve mixes two effects.** k = 1…4 register indexes over *distinct* keys (one-record
   buckets); k = 5…8 add non-unique indexes over small key spaces (up to n/8 records per bucket).
   So "insert costs ~11× more at k = 8" is *not* a clean per-index law: it is eight indexes **plus**
   four fat buckets. Read it as "each index adds its own maintenance, and fat buckets cost more".

### Which removal? (the trade-off, in one table)

| You need | Use | Cost | Iteration order after the call |
|---|---|---|---|
| insertion order preserved (queues, replay, stable dumps) | `remove(id)` | O(len + I + Σ log bucket) | unchanged: still insertion order |
| only "gone, and fast" (bulk cleanup, drain loops, caches) | `swap_remove(id)` | O(I + Σ log bucket) — no `len` term | the last live slot takes the hole |

Both retire the slot identically (`rows`, generation bump, `free` stack, every index, `len`,
`version`), both return the removed record, and both leave the table untouched on a stale handle.
Records are never moved, so **every surviving `RowId` stays valid either way** — only the iteration
sequence differs. The 4 B/slot `positions` array (see docs/SPEC.md §13 R3) is what makes the swap
O(1); it is maintained by the four chokepoints, not by callers.

