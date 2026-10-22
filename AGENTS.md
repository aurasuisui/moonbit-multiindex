# AGENTS.md

Guidance for coding agents (Claude Code, Codex, and any other agent) working in this repository.

> **入口纪律**:本文件是本仓库面向所有编码 agent 的**唯一**会话入口 —— 不再维护
> `CLAUDE.md` 镜像,因此也不存在"两处同步"的漂移风险。改动命令 / 工具链 / 高层架构速览时,
> 只改这一处,并按 [`CONTRIBUTING.md`](CONTRIBUTING.md) 的文档同步约定联动其他文档。

## What this is

`aurasuisui/multiindex` — a **record store with N secondary indexes** for MoonBit, published on
mooncakes.io. `Table[K, V]` stores records and maintains any number of named indexes over them
(unique / non-unique / sorted), with stable generational `RowId` handles.

It generalizes the author's `aurasuisui/bimap` (two mutually-inverse unique indexes) to **N
independent indexes**, and adds record identity + non-unique indexes, which bimap does not have.
Pure MoonBit; does **not** depend on `aurasuisui/bimap` or `aurasuisui/indexmap`.

## Commands

```bash
moon check               # type check
moon test                # run all tests (default target only)
moon test --target all   # all four backends: wasm / wasm-gc / js / native — what CI runs
moon fmt                 # format (CI enforces `moon fmt --check`)
moon build               # build

moon test -f "*unique*"                  # only tests whose name matches the glob
moon test -i 0 src/table_test.mbt        # only the 0-th test in one file
moon test -u                             # regenerate snapshots (debug_inspect only)
```

The CI (`.github/workflows/ci.yml`) that must all stay green — eight checks in two jobs:

```
check-and-test:  moon fmt --check → moon check → moon check --deny-warn --target all
  → interface check (normalized `moon info`) → moon test → moon test --target all → moon build
example-smoke:   write moon.work (local workspace, gitignored) → cd cmd/leaderboard && moon run .
```

> The example job is not decoration: `cmd/leaderboard` is standalone and its manifest names a
> *published* version, so the job writes the verified `moon.work` recipe (no `[workspace]`
> header) to make the workspace member win, then greps the demo's output for its landmarks and
> for **this repo's** `VERSION` — the registry copy is an older version, so that line proves the
> local source ran. The `trap` removes the file even when the run fails.

> **CI installs the *latest* toolchain, and that is not a choice.** `cli.moonbitlang.com` serves
> only `latest`: twelve spellings of the version we develop against all answer 403, so a pinned
> version string is simply not downloadable — that 403 (inside `setup-moonbit`'s own download
> step) was the cause of the 13-second red runs from 2026-10-19. The consequence, accepted
> deliberately: toolchain drift is **detected, not prevented**. Every step prints `moon version`;
> if upstream floats to a formatter that rewrites code, `moon fmt --check` goes red and the log
> names the exact version. Follow it in a separate, fully green commit.
>
> A local toolchain older than `latest` therefore disagrees on *spelling*, not on semantics:
> `moon info` used to print `Int` where newer releases print `Int32`. The interface gate folds
> those two spellings (see the step's comment) and still catches every real signature change.

**The interface check is load-bearing:** `src/pkg.generated.mbti` is a
checked-in interface snapshot. Change a public signature → run `moon info` and commit the
regenerated file, or CI fails.

`cmd/*` example packages and `bench/` are standalone (they import the **published** package),
so root `moon check`/`moon test` never touches them.

## Architecture

```
Table[K, V]
├── rows    : Array[V?]                  ← slot storage; None = free slot
├── gens    : Array[Int]                 ← per-slot generation, +1 on recycle
├── free    : Array[Int]                 ← free-slot stack (LIFO); retired slots NEVER re-enter (I9)
├── order   : Array[Int]                 ← live slots in insertion order
├── indexes : Map[String, Index[K, V]]   ← the 2x2 index registry
├── mut len : Int
└── mut version : Int                    ← mutation counter (fail-fast iterators)

Index quadrants (matches the reference's hashed/ordered x unique/non-unique):
   unique + hashed   -> Map[K, Int]
   unique + ordered  -> SortedMap[K, Int]
   non-unique + hashed  -> Map[K, SortedSet[Int]]
   non-unique + ordered -> SortedMap[K, SortedSet[Int]]

Index entries store **slot numbers only, never RowId** — generations exist only to
validate caller-supplied handles; bucket entries are maintained inside the chokepoints
and always point at the current live record.
```

Indexes store **slot numbers, never values**; values live only in `rows`. See
[`docs/DEVPLAN.md`](docs/DEVPLAN.md) §2 for the full layout.

### Invariants (docs/DEVPLAN.md §3)

```
I1 order slots live & unique      I2 live count == len == order.length()
I3 no duplicate slots in a bucket I4 bucket entry projects back to the bucket key
I5 unique index bucket length <= 1  I6 free disjoint from live, no duplicates
I7 every live record is in the right bucket of every index   I8 version only on real change
I9 retired slots never re-enter free (generation exhausted -> slot permanently removed)
```

**I5 + I7 must be checked as a pair** — I7 catches "missing", I5 catches "extra".
`check_invariants` in `property_wbtest.mbt` is the guard; when in doubt, it's the truth.

### Chokepoints (the #1 source of bugs)

`insert_impl` / `remove_impl` / `modify_impl` / `clear_impl` are the only places allowed to
touch `rows` + `order` + `indexes` + `gens` + `free` together. (`clear_impl` is the bulk path —
looping `remove_impl` would be O(n²) through the `order` compaction.)

**Four high-risk paths (probe- and source-validated):**
1. `update` must conflict-check **excluding self**.
2. Conflict checks run **before any mutation** — on `Err` the table is unchanged.
3. No observable intermediate state between bucket-del and bucket-add (fast-path equal keys).
4. `modify` must finish **all** uniqueness pre-checks before committing any index change.
   The reference implementation removes-then-inserts and **panics mid-way, leaving dirty indexes**
   (`generators.rs:322-332`) — do not copy that ordering.

## Testing conventions

- Tests are **black-box**: always the `@aurasuisui/multiindex.` prefix.
- `*_wbtest.mbt` files read private fields — that is where I6 / generation-monotonicity
  assertions belong.
- Avoid `debug_inspect` inside loops with varying values; use `@test.assert_eq` / `@test.fail`.
- Helper functions calling `@test.assert_eq` must be declared `-> Unit raise`.
- Every new mutating feature must extend `check_invariants` — weakening an invariant assertion
  to make a test pass is forbidden (it is this library's lifeblood).

## Style

**The single source of truth for conventions is [`docs/STYLE.md`](docs/STYLE.md)** (naming, code
organisation, `extend` policy, doc comments, testing, package layout, license header — all traced to
the official `moonbitlang/core` repository). Language-level facts live in
[`docs/MOONBIT_REF.md`](docs/MOONBIT_REF.md). Project-specific must-knows:

- Black-box tests use the `@aurasuisui/multiindex.` prefix — a hard convention here.
- Qualified trait calls: `Hash::hash(x)`, `Show::to_string(x)` (avoids `[0083]`).
- `.length()` not `.size()`; `raise` effect annotation not `!`.
- **MoonBit gotcha**: struct/enum type parameters cannot carry trait bounds
  (`struct Index[K : Hash + Eq, V]` is a syntax error) — put bounds on methods.

## Source map

- `src/lib.mbt` — public types: `VERSION`, `RowId`, `Conflict` / `Rejected` / `RegisterError` /
  `UpdateRejected`, `IndexStats`, `IndexKind`, each with a hand-written `Show`.
- `src/table.mbt` — `Table` core, the chokepoints, the uniqueness pre-check `find_conflict`, and
  the write path (`insert` / `insert_many` / `insert_or_replace` / `update` / `modify` /
  `remove` / `swap_remove`).
- `src/index.mbt` — the `Index[K, V]` four-quadrant enum + bucket add/remove/slots.
- `src/extends.mbt` — official-style `pub extend` promotions (keeps `[0079]` at zero).
- `src/table_api.mbt` — `register_*` (atomic backfill), the query family (`get_by` / `iter_by` /
  `iter_asc_by` / `iter_desc_by` / `range_by` / `range_half_open_by`), and diagnostics
  (`index_names` / `index_entries` / `has_index` / `index_stats` / `verify_invariants`).
- `src/property_wbtest.mbt` — invariant driver over `verify_invariants`, plus the
  "the guard is not vacuous" meta-tests.
- `src/model_test.mbt` — differential vs a naive `Array[V]` linear-scan oracle, every step.
- `src/differential_test.mbt` + `src/differential_fixture_test.mbt` — replay of the checked-in
  golden sequence against Rust `multi_index_map` 0.15.1 (fixture generated by `tools/diffgen`,
  which needs Rust; **`moon test` does not**).
- `src/json.mbt` — JSON round-trip (`to_json` / `from_json`). Wire format is `{"records": [...]}`
  in insertion order; **indexes are not serialized** — call `register_*` after loading.
  `src/json_test.mbt` covers the round-trip, re-registration, and malformed input.
- Test files: `table_test.mbt` (black-box unit), `table_wbtest.mbt` (white-box + negative guard
  tests), `property_test.mbt` / `property_wbtest.mbt` (invariants, black- vs white-box),
  `model_test.mbt`, `differential_test.mbt` + `differential_fixture_test.mbt`, `json_test.mbt`,
  `bench_test.mbt` (stress), `abort_guard_wbtest.mbt` (`test "panic …"` suite: one trigger per
  reachable `abort` guard, each fixture re-run by a companion test). Iterators live **inline** in
  `table.mbt` / `table_api.mbt`; there is
  no separate `table_iter.mbt` / `table_traits.mbt` (a split that was planned and deliberately
  dropped — the inline form keeps the chokepoints in one file).
- `cmd/leaderboard` — runnable example; `bench/main.mbt` — timing benchmarks. Both are **standalone
  modules** importing the *published* package (`moon.work` is generated on demand, gitignored).

## Documentation map & reading order

Full map: [`docs/README.md`](docs/README.md).
New session: **AGENTS.md (this) → README.md → CONTRIBUTING.md → `docs/SPEC.md`** (only when
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
