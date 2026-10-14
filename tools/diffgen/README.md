# tools/diffgen — differential-test fixture generator

Dev tooling for `moonbit-multiindex`'s **Tier 1 differential tests** (see
[`docs/RELEASE_CHECKLIST.md`](../../docs/RELEASE_CHECKLIST.md)). Not part of the MoonBit package
itself; standalone (not part of the root package) and never imported by `src/`.

## What it does

Runs the **reference implementation** — the Rust [`multi_index_map`] crate **v0.15.1**, pinned,
the porting source documented in [`docs/SPEC.md`](../../docs/SPEC.md) §0 — over the shared
operation streams, and emits a checked-in MoonBit fixture that `src/differential_test.mbt`
replays. **`moon test` therefore needs no Rust toolchain.**

The **golden stream** it runs (11 steps) is the one implemented and checked in:

```
try_insert (1,10,7,1) ok   try_insert (2,20,7,2) ok   try_insert (3,30,8,1) ok
try_insert (1,40,9,3) REFUSED (hashed-unique `id` already holds 1)
try_insert (4,10,9,3) REFUSED (ordered-unique `ts` already holds 10)
try_insert (4,40,7,2) ok   (joins two existing non-unique buckets)
modify_ts  (2,15,*)   ok   (non-conflicting re-index)
remove     (3,*,*,*) ok   try_insert (3,30,8,1) ok (freed keys are reusable)
remove     (1,*,*,*) ok   try_insert (1,10,7,1) ok
```

Each step records what the reference saw afterwards: `len`, the whole record set sorted by
`id`, and which ids each of twelve probe keys answers.

### The second planned stream (LCG random ops) is **deliberately not implemented**

M6 was dispatched with two streams in mind; only one was built, on purpose:

- the random operation space is covered **far more densely** by `src/model_test.mbt`, which runs
  a naive linear-scan model against the table after *every* step of randomized streams — a
  checked-in fixture could only sample it more coarsely;
- a random fixture would have to be regenerated for every reference bump, so it would add
  **fixture-vs-Rust-version binding** for no extra coverage;
- what the fixture is genuinely for is **provenance**: pinning that our semantics agree with a
  mature implementation on the surface we *claim* to share. A golden sequence does that; a
  second, denser copy of the model test does not.

### Why the diffable surface is thinner than it first looked

1. **Only the *happy path* of `modify` is diffable.** The reference removes the old key, then
   inserts the new one, and **panics** if that collides — leaving its indexes half-updated
   (`generators.rs:322-332`). That is a defect, not a behaviour to align with, so a conflicting
   `modify` can never appear in the stream.
2. **Observations must be keyed by record content, not by handle.** The reference has no
   generations and no stable handle: its keys are bare `usize` slab indices, and slab reuse is
   invisible from outside. So the fixture pins content/len/membership, never identity.
3. **Conflict *paylods* are not isomorphic.** `try_insert` returns `Err(UniquenessError(elem))`
   without the key, while ours is `Rejected { Conflict[K], record }` (and `Conflict` has two
   variants, one of which — `DuplicateInBatch` — has no reference counterpart at all). Only the
   *outcome class* (accepted / refused, and on which index) can be compared.

## Golden-stream coverage, item by item

| Area | In the stream? | Note |
|---|---|---|
| hashed-unique (`id`) | ✅ | populated, probed, and refused on a duplicate |
| ordered-unique (`ts`) | ✅ | populated, probed, refused on a duplicate, and re-indexed by `modify` |
| hashed-non-unique (`tag`) | ✅ | two records share `tag = 7`; membership sets are compared |
| ordered-non-unique (`bin`) | ✅ | two records share `bin = 1` / `bin = 2`; membership compared |
| insert conflict (unique key held by a live record) | ✅ | steps 4 and 5 |
| remove + key reuse | ✅ | steps 8–11 |
| non-conflicting `modify` | ✅ | step 7 |
| **conflicting `modify`** | ❌ | the reference panics mid-way and leaves dirty indexes — see the "not diffable" table below |
| **generation / stale handles** | ❌ | the reference has no generations |
| **`insert_many` batch semantics** | ❌ | the reference is first-wins; ours fails the batch atomically |
| **`range_by` family** | ❌ | the reference exposes no range API |
| **bucket iteration order** | ❌ | both use ordered buckets, but the reference documents no order to pin; membership is compared *as a set* |
| error payload shape | ❌ | see "Conflict payloads are not isomorphic" above |

Anything in the ❌ rows is pinned by our own tests instead (`model_test.mbt`, the property
suites, and the regression nails), which is exactly what the table below records.
## Scope note — what can and cannot be diffed

**Diffable** (semantics shared with the reference): insert / remove / modify observations,
length changes, uniqueness-conflict outcomes, non-unique membership sets.

**NOT diffable** (deliberate deviations, pinned by our own tests instead — see
[`docs/SPEC.md`](../../docs/SPEC.md) §0.3):

| Deviation | Why it cannot be diffed |
|---|---|
| Generational `RowId` | The reference has no generations at all (`usize` slab keys) |
| `Rejected[K,V]` returning the record | The reference returns the element in `Err`, but panics on the `insert` path |
| Atomic `modify` | The reference **panics mid-way and leaves dirty indexes**; its outcome is not a defined behaviour to match |
| Bucket iteration order | Reference uses `BTreeSet<usize>`, ours `SortedSet[Int]` — same ordering, but the reference exposes no stable cross-check for it |
| `range_by` family | The reference exposes **no range API** |
| `insert_many` batch semantics | The reference's `FromIterator` is **first-wins**; ours fails the **whole batch atomically** (see `docs/SPEC.md` §11) |

## Regenerating the fixture

Requires a Rust toolchain (`rustup`/`cargo`) and crates.io access.

```bash
cd tools/diffgen
cargo run --release -- ../../src/differential_fixture_test.mbt
cd ../..
moon fmt          # normalize the generated formatting (CI enforces fmt)
moon test         # the differential tests must pass against the new fixture
```

Regenerate only when the shared op streams change or when re-pinning the reference crate;
commit `Cargo.lock` together with the fixture and record the upstream **commit hash** read
(the published 0.15.1 and upstream `master` differ).

[`multi_index_map`]: https://github.com/lun3x/multi_index_map
