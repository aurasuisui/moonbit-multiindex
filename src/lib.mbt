// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// moonbit-multiindex: a record store with N secondary indexes over stable
// generational IDs.
//
// A `Table[K, V]` stores records of type `V` and maintains any number of
// named secondary indexes over them. Each index projects a record to a key of
// type `K`; an index may be **unique** (one record per key, like one side of a
// `BiMap`), **non-unique** (many records per key), or **sorted** (ordered by
// key, supporting range queries).
//
// A `BiMap` is the special case of exactly two unique indexes that are mutual
// inverses; this library generalizes that to N indexes, each maintained
// consistently across insert / update / remove.
//
// # Quick Start
//
// (see README.md — the API is stabilized as of v0.2.0)

///|
/// Library version string.
pub const VERSION : String = "0.2.0"

///|
/// A stable handle to a stored record: a slot index plus a generation counter.
///
/// The generation is bumped every time a slot is recycled, so a handle that
/// outlives its record can never silently resolve to a *different* record
/// (the ABA problem). Operations on a stale handle return `None` / `false`
/// rather than touching the new occupant of the slot.
pub struct RowId {
  slot : Int32
  gen : Int32
} derive(Eq, Hash, Debug)

///|
/// Display form: `RowId(slot, gen)`.
pub impl Show for RowId with fn output(self : RowId, logger : &Logger) {
  logger.write_string("RowId(")
  logger.write_string(self.slot.to_string())
  logger.write_string(", ")
  logger.write_string(self.gen.to_string())
  logger.write_string(")")
}

///|
/// A uniqueness violation reported *before* any mutation happens.
///
/// Deliberately has **no** "no conflict" variant — the absence of a conflict is
/// spelled `None` at the call site. (A redundant nullary variant would force
/// every caller to match it and collides with `Option::None` in pattern
/// position; see docs/SPEC.md §Design lessons.)
///
/// - `UniqueViolation(index, key, holder)` — the unique index named `index`
///   already maps `key` to the live record `holder`.
/// - `DuplicateInBatch(index, key, at)` — one `insert_many` batch contains two
///   records that project to the same `key` on the unique index `index`; `at` is
///   the position of the **earlier** member in that batch. No record is live at
///   `key`: the whole batch is rejected atomically (docs/SPEC.md §11), so a handle
///   would have been a lie — the batch position is the honest answer.
pub enum Conflict[K] {
  UniqueViolation(String, K, RowId)
  DuplicateInBatch(String, K, Int32)
} derive(Debug, Eq)

///|
/// Display form: `UniqueViolation(index, key, holder)`.
pub impl[K : Show] Show for Conflict[K] with fn output(
  self : Conflict[K],
  logger : &Logger,
) {
  match self {
    UniqueViolation(index, key, holder) => {
      logger.write_string("UniqueViolation(")
      logger.write_string(index)
      logger.write_string(", ")
      Show::output(key, logger)
      logger.write_string(", ")
      Show::output(holder, logger)
      logger.write_string(")")
    }
    DuplicateInBatch(index, key, at) => {
      logger.write_string("DuplicateInBatch(")
      logger.write_string(index)
      logger.write_string(", ")
      Show::output(key, logger)
      logger.write_string(", ")
      logger.write_string(at.to_string())
      logger.write_string(")")
    }
  }
}

///|
/// A write that was refused because a unique index already holds the key —
/// carrying the record back to the caller.
///
/// MoonBit passes records by value, so an `insert(v)` that reported only
/// `Conflict[K]` would consume `v` for good. Returning the *record itself*
/// inside the error keeps the caller's data intact; the idiomatic retry is:
///
/// ```moonbit nocheck
/// match table.insert(record) {
///   Ok(id) => id
///   Err(rejected) => retry_with(rejected.record)
/// }
/// ```
pub struct Rejected[K, V] {
  conflict : Conflict[K]
  record : V
} derive(Debug)

///|
/// Display form: `Rejected(conflict=..., record=...)`.
pub impl[K : Show, V : Show] Show for Rejected[K, V] with fn output(
  self : Rejected[K, V],
  logger : &Logger,
) {
  logger.write_string("Rejected(conflict=")
  Show::output(self.conflict, logger)
  logger.write_string(", record=")
  Show::output(self.record, logger)
  logger.write_string(")")
}

///|
/// Why an index registration was refused (docs/SPEC.md §2.4).
///
/// Registration never half-succeeds: on `Err` the registry and the records are
/// exactly what they were.
///
/// - `DuplicateName(name)` — an index of that name is already registered; the
///   existing one is **not** overwritten.
/// - `UniqueViolation(name, key)` — backfilling the unique index `name` found two
///   live records projecting to the same key. The key travels as itself, so
///   registering a unique index adds **no** `Show` bound on `K` (it mirrors
///   `Conflict[K]`).
pub enum RegisterError[K] {
  DuplicateName(String)
  UniqueViolation(String, K)
} derive(Debug, Eq)

///|
/// Why an update was refused (docs/SPEC.md §2.5).
///
/// - `StaleHandle(id, pending)` — `id` no longer names a live record. `update`
///   gives the record it was handed back (`Some(value)`); `modify` has none to
///   give (`None`: with no record to transform, no new record exists).
/// - `Conflict(conflict, value)` — a unique index already holds one of the
///   record's keys; the record always comes back.
///
/// Same principle as `Rejected`: a refused write never swallows the caller's data.
pub enum UpdateRejected[K, V] {
  StaleHandle(RowId, V?)
  Conflict(Conflict[K], V)
} derive(Debug, Eq)

///|
/// How the buckets of one index are distributed (docs/SPEC.md §3.4).
///
/// A degenerating projection shows up here: `longest_bucket` climbing while
/// `average_bucket` stays near 1 means many records pile into one bucket. An index
/// with no entries reports zero for everything (including the average).
pub struct IndexStats {
  buckets : Int32
  entries : Int32
  longest_bucket : Int32
  average_bucket : Double
} derive(Debug, Eq)

///|
/// Which of the four quadrants a registered index lives in — the public shadow of
/// the private `Index[K, V]` enum (src/index.mbt).
///
/// `Table::index_entries` hands these out next to the index names so a caller can
/// tell a conflict-checked index (`HashUnique` / `SortedUnique`) from a fan-out
/// one (`HashMulti` / `SortedMulti`) before reasoning about what a write may hit.
///
/// Deliberately **not** folded into `IndexStats`: that struct's fields are public,
/// so adding a name or a kind to it would break every external construction site
/// (a MAJOR break — Issue #4). A separate enum keeps `IndexStats` at MINOR.
pub(all) enum IndexKind {
  HashUnique
  SortedUnique
  HashMulti
  SortedMulti
} derive(Debug)

///|
/// Display form: the bare variant name (`HashUnique`, `SortedMulti`, ...).
pub impl Show for IndexKind with fn output(self : IndexKind, logger : &Logger) {
  match self {
    IndexKind::HashUnique => logger.write_string("HashUnique")
    IndexKind::SortedUnique => logger.write_string("SortedUnique")
    IndexKind::HashMulti => logger.write_string("HashMulti")
    IndexKind::SortedMulti => logger.write_string("SortedMulti")
  }
}
