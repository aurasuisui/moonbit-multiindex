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
// (see README.md — the API is under construction for v0.1.0)

///|
/// Library version string.
pub const VERSION : String = "0.1.0"

///|
/// A stable handle to a stored record: a slot index plus a generation counter.
///
/// The generation is bumped every time a slot is recycled, so a handle that
/// outlives its record can never silently resolve to a *different* record
/// (the ABA problem). Operations on a stale handle return `None` / `false`
/// rather than touching the new occupant of the slot.
pub struct RowId {
  slot : Int
  gen : Int
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
pub enum Conflict[K] {
  UniqueViolation(String, K, RowId)
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
