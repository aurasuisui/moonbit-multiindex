# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

> **镜像纪律**:本文件与 [`AGENTS.md`](AGENTS.md)(面向 Codex/其他 agent)内容同源,
> **改动时必须两处同步**。

## What this is

`aurasuisui/multiindex` — a **record store with N secondary indexes** for MoonBit, published on
mooncakes.io. `Table[K, V]` stores records and maintains any number of named indexes over them
(unique / non-unique / sorted), with stable generational `RowId` handles.

It generalizes the author's `aurasuisui/bimap` (two mutually-inverse unique indexes) to **N
independent indexes**, and adds record identity + non-unique indexes, which bimap does not have.
Pure MoonBit; does **not** depend on `aurasuisui/bimap` or `aurasuisui/indexmap`.

## Commands

```bash
moon check          # type check
moon test           # run all tests
moon fmt            # format (CI enforces `moon fmt --check`)
moon build          # build

moon test -f "*unique*"                  # only tests whose name matches the glob
moon test -i 0 src/table_test.mbt        # only the 0-th test in one file
moon test -u                             # regenerate snapshots (debug_inspect only)
```

The five-step CI (`.github/workflows/ci.yml`) that must all stay green:

```
moon fmt --check → moon check → moon info && git diff --exit-code → moon test → moon build
```

**The `moon info && git diff --exit-code` step is load-bearing:** `src/pkg.generated.mbti` is a
checked-in interface snapshot. Change a public signature → run `moon info` and commit the
regenerated file, or CI fails.

`cmd/*` example packages and `bench/` are standalone (they import the **published** package),
so root `moon check`/`moon test` never touches them.

## Architecture

```
Table[K, V]
├── rows    : Array[V?]                      ← slot storage; None = free slot
├── gens    : Array[Int]                     ← per-slot generation, +1 on recycle
├── free    : Array[Int]                     ← free-slot stack (LIFO)
├── order   : Array[Int]                     ← live slots in insertion order
├── indexes : Map[String, Index[K, V]]       ← hash indexes (unique / non-unique)
├── sorted  : Map[String, SortedIndex[K, V]] ← sorted indexes (range queries)
├── mut len : Int
└── mut version : Int                        ← mutation counter (fail-fast iterators)
```

Indexes store **slot numbers, never values**; values live only in `rows`. See
[`docs/DEVPLAN.md`](docs/DEVPLAN.md) §2 for the full layout.

### Invariants (docs/DEVPLAN.md §3)

```
I1 order slots live & unique      I2 live count == len == order.length()
I3 no duplicate slots in a bucket I4 bucket entry projects back to the bucket key
I5 unique index bucket length <= 1  I6 free disjoint from live, no duplicates
I7 every live record is in the right bucket of every index   I8 version only on real change
```

**I5 + I7 must be checked as a pair** — I7 catches "missing", I5 catches "extra".
`check_invariants` in `property_test.mbt` is the guard; when in doubt, it's the truth.

### Chokepoints (the #1 source of bugs)

`insert_impl` / `remove_impl` / `update_impl` are the only places allowed to touch
`rows` + `order` + `indexes` + `gens` + `free` together.

**Three high-risk paths (probe-validated):**
1. `update` must conflict-check **excluding self**.
2. Conflict checks run **before any mutation** — on `Err` the table is unchanged.
3. No observable intermediate state between bucket-del and bucket-add (fast-path equal keys).

## Testing conventions

- Tests are **black-box**: always the `@aurasuisui/multiindex.` prefix.
- `*_wbtest.mbt` files read private fields — that is where I6 / generation-monotonicity
  assertions belong.
- Avoid `debug_inspect` inside loops with varying values; use `@test.assert_eq` / `@test.fail`.
- Helper functions calling `@test.assert_eq` must be declared `-> Unit raise`.
- Every new mutating feature must extend `check_invariants` — weakening an invariant assertion
  to make a test pass is forbidden (it is this library's lifeblood).

## Style

- `snake_case` functions, `PascalCase` types, `UPPER_CASE` constants.
- Public API gets a `///|` doc block; internal helpers documented too.
- Qualified trait calls: `Hash::hash(x)`, `Show::to_string(x)`.
- `.length()` not `.size()`; `raise` effect annotation not `!`.
- **MoonBit gotcha**: struct type parameters cannot carry trait bounds
  (`struct Index[K : Hash + Eq, V]` is a syntax error) — put bounds on methods.

## Source map

- `src/lib.mbt` — public re-exports, `VERSION`, `RowId`, `Conflict`.
- `src/table.mbt` — `Table` core + the three chokepoints.
- `src/index.mbt` — `Index` / `SortedIndex` + bucket add/del.
- `src/table_api.mbt` — `register_*` / `get_by` / `iter_by` / `range_by` / `update`.
- `src/table_iter.mbt` — fail-fast iterators.
- `src/table_traits.mbt`, `src/json.mbt` — traits and JSON round-trip.

## Documentation map & reading order

Full map: [`docs/README.md`](docs/README.md).
New session: **CLAUDE.md (this) → README.md → CONTRIBUTING.md → `docs/SPEC.md`** (only when
touching public API). Task session: follow [`docs/SESSION_PLAYBOOK.md`](docs/SESSION_PLAYBOOK.md).

**Before you finish any task**, follow the Doc Sync Convention in CONTRIBUTING.md and update the
`docs/README.md` map if you add or remove a doc. **Before any `moon publish` / version bump**,
run `docs/RELEASE_CHECKLIST.md` end-to-end.

## Licensing / provenance

Apache-2.0. Multi-index container API shape informed by Rust `multi_index_map`; record identity
follows the slot+generation scheme of `slotmap` / `generational-arena`; documentation and test
layering follow the author's `moonbit-bimap`. Robin Hood engine (if adopted) is adapted from
`aurasuisui/indexmap` (Apache-2.0). See [`docs/DEVPLAN.md`](docs/DEVPLAN.md) §7 and
`CHANGELOG.md` Notes/Deviations. Keep attribution current if you touch those files.
