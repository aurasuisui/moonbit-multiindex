# tools/diffgen — differential-test fixture generator

Dev tooling for `moonbit-multiindex`'s **Tier 1 differential tests** (see
[`docs/RELEASE_CHECKLIST.md`](../../docs/RELEASE_CHECKLIST.md)). Not part of the MoonBit package
itself; standalone (not part of the root package) and never imported by `src/`.

## What it does

Runs the **reference implementation** — the Rust [`multi_index_map`] crate **v0.15.1**, pinned,
the porting source documented in [`docs/SPEC.md`](../../docs/SPEC.md) §0 — over the shared
operation streams, and emits a checked-in MoonBit fixture that `src/differential_test.mbt`
replays. **`moon test` therefore needs no Rust toolchain.**

Planned shared streams (to be fixed when M6 starts):

1. a golden sequence covering the four index quadrants and every conflict path;
2. a deterministic LCG stream mixing `insert` / `modify` / `remove` / `try_insert`
   across unique and non-unique indexes.

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
