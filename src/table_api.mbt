// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// The index registry's public surface: registration (with backfill) and the key
// lookups. Bucket *maintenance* lives in the chokepoints of `src/table.mbt`;
// nothing here touches `rows` / `order` / `gens` / `free`.
//
// Registration is atomic (docs/SPEC.md §3.1): the buckets are built first, in a
// local structure, and only published into the registry once the whole backfill
// has succeeded — a half-filled index is the worst state to debug.

///|
/// Register a **hashed unique** index under `name` (`Map[K, Int]`).
///
/// Registering against a non-empty table backfills it in insertion order.
/// Fails with `DuplicateName` when the name is taken, or with `UniqueViolation`
/// when the existing records already share a key — in both cases **nothing is
/// registered**.
pub fn[K : Hash + Eq, V] Table::register_unique(
  self : Table[K, V],
  name : String,
  project : (V) -> K,
) -> Result[Unit, RegisterError[K]] {
  if self.indexes.contains(name) {
    return Err(DuplicateName(name))
  }
  let buckets : Map[K, Int] = Map([])
  let mut i = 0
  while i < self.order.length() {
    let slot = self.order[i]
    match self.rows[slot] {
      Some(record) => {
        let key = project(record)
        match buckets.get(key) {
          Some(_) => return Err(UniqueViolation(name, key))
          None => buckets.set(key, slot)
        }
      }
      None =>
        abort("Table::register_unique: `order` names a slot with no record")
    }
    i = i + 1
  }
  self.indexes.set(name, Index::HashUnique({ name, project, }, buckets))
  Ok(())
}

///|
/// Register a **sorted unique** index under `name` (`SortedMap[K, Int]`).
///
/// Same contract as `register_unique`; the sorted quadrant additionally supports
/// the range queries of a later milestone.
pub fn[K : Compare, V] Table::register_unique_ordered(
  self : Table[K, V],
  name : String,
  project : (V) -> K,
) -> Result[Unit, RegisterError[K]] {
  if self.indexes.contains(name) {
    return Err(DuplicateName(name))
  }
  let buckets : @sorted_map.SortedMap[K, Int] = @sorted_map.SortedMap([])
  let mut i = 0
  while i < self.order.length() {
    let slot = self.order[i]
    match self.rows[slot] {
      Some(record) => {
        let key = project(record)
        match buckets.get(key) {
          Some(_) => return Err(UniqueViolation(name, key))
          None => buckets.set(key, slot)
        }
      }
      None =>
        abort(
          "Table::register_unique_ordered: `order` names a slot with no record",
        )
    }
    i = i + 1
  }
  self.indexes.set(name, Index::SortedUnique({ name, project, }, buckets))
  Ok(())
}

///|
/// Register a **hashed non-unique** index under `name`
/// (`Map[K, SortedSet[Int]]`).
///
/// Non-unique quadrants have no uniqueness constraint, so the only failure is a
/// duplicate name. Existing records are backfilled.
pub fn[K : Hash + Eq, V] Table::register_non_unique(
  self : Table[K, V],
  name : String,
  project : (V) -> K,
) -> Result[Unit, RegisterError[K]] {
  if self.indexes.contains(name) {
    return Err(DuplicateName(name))
  }
  let buckets : Map[K, @sorted_set.SortedSet[Int]] = Map([])
  let mut i = 0
  while i < self.order.length() {
    let slot = self.order[i]
    match self.rows[slot] {
      Some(record) => {
        let key = project(record)
        match buckets.get(key) {
          Some(set) => set.add(slot)
          None => buckets.set(key, @sorted_set.SortedSet([slot]))
        }
      }
      None =>
        abort("Table::register_non_unique: `order` names a slot with no record")
    }
    i = i + 1
  }
  self.indexes.set(name, Index::HashMulti({ name, project, }, buckets))
  Ok(())
}

///|
/// Register a **sorted non-unique** index under `name`
/// (`SortedMap[K, SortedSet[Int]]`).
///
/// Same contract as `register_non_unique`, in the sorted quadrant.
pub fn[K : Compare, V] Table::register_non_unique_ordered(
  self : Table[K, V],
  name : String,
  project : (V) -> K,
) -> Result[Unit, RegisterError[K]] {
  if self.indexes.contains(name) {
    return Err(DuplicateName(name))
  }
  let buckets : @sorted_map.SortedMap[K, @sorted_set.SortedSet[Int]] = @sorted_map.SortedMap([],
  )
  let mut i = 0
  while i < self.order.length() {
    let slot = self.order[i]
    match self.rows[slot] {
      Some(record) => {
        let key = project(record)
        match buckets.get(key) {
          Some(set) => set.add(slot)
          None => buckets.set(key, @sorted_set.SortedSet([slot]))
        }
      }
      None =>
        abort(
          "Table::register_non_unique_ordered: `order` names a slot with no record",
        )
    }
    i = i + 1
  }
  self.indexes.set(name, Index::SortedMulti({ name, project, }, buckets))
  Ok(())
}

// ---------------------------------------------------------------------------
// Key lookups
// ---------------------------------------------------------------------------

///|
/// The record the index `name` maps `key` to: its stable handle plus the value.
///
/// On a non-unique index this is the record in the **smallest slot** of the
/// bucket — deterministic, but not stable across operations (a removal elsewhere
/// changes which slot is smallest). Use `iter_by` for every match.
///
/// A key that is simply absent yields `None`; an **unknown index name aborts** —
/// looking up an index that was never registered is a caller bug, and answering it
/// with "no data" would hide that bug (docs/SPEC.md §7.1).
pub fn[K : Hash + Eq + Compare, V] Table::get_by(
  self : Table[K, V],
  name : String,
  key : K,
) -> (RowId, V)? {
  let index = self.require_index(name)
  // `slots` is ascending, so [0] is the smallest slot in the bucket.
  let slots = index.slots(key)
  if slots.length() == 0 {
    return None
  }
  self.record_at(slots[0])
}

///|
/// Every record the index `name` maps `key` to, as `(handle, value)` pairs in
/// ascending slot order. A unique index yields 0 or 1 pair, so both quadrants
/// share one shape.
///
/// The bucket is snapshotted when the iterator is created (so the yielded set is
/// stable), while mutation of the table mid-iteration aborts, exactly like
/// `Table::iter` (fail-fast on `version`).
pub fn[K : Hash + Eq + Compare, V] Table::iter_by(
  self : Table[K, V],
  name : String,
  key : K,
) -> Iter2[RowId, V] {
  let index = self.require_index(name)
  let slots = index.slots(key)
  let version = self.version
  let mut pos = 0
  Iter2::new(
    fn() -> (RowId, V)? {
      if self.version != version {
        abort("Table::iter_by: table mutated during iteration")
      }
      while pos < slots.length() {
        let slot = slots[pos]
        pos = pos + 1
        match self.record_at(slot) {
          Some(entry) => return Some(entry)
          None => continue
        }
      }
      None
    },
    size_hint=slots.length(),
  )
}

///|
/// The index registered under `name`, aborting when there is none.
///
/// The decision is *data* (`Table::has_index` is the public, testable form of it);
/// the abort is one line, and docs/SPEC.md §7.1 keeps a MoonBit panic — which no
/// `try`/`catch` can intercept — as the only way to report a caller bug.
fn[K, V] Table::require_index(self : Table[K, V], name : String) -> Index[K, V] {
  match self.indexes.get(name) {
    Some(index) => index
    None => abort("Table: no index named " + name + " is registered")
  }
}

///|
/// The **ordered** index registered under `name`, aborting when the name is
/// unknown or the index has no key order.
///
/// Asking a hash index for a range is a programming error, not an empty result
/// (docs/SPEC.md §7.1); `Index::is_ordered` is the testable half of that decision.
fn[K, V] Table::ordered_index(self : Table[K, V], name : String) -> Index[K, V] {
  let index = self.require_index(name)
  if index.is_ordered() {
    index
  } else {
    abort("Table: index " + name + " has no key order (hash quadrant)")
  }
}

///|
/// Drive a `BucketCursor` as `Iter2[RowId, V]`: one bucket at a time, aborting if
/// the table changes under the walk (fail-fast on `version`, like `Table::iter`).
fn[K, V] Table::cursor_iter(
  self : Table[K, V],
  cursor : BucketCursor,
) -> Iter2[RowId, V] {
  let version = self.version
  let mut pending : Array[Int] = []
  let mut pos = 0
  Iter2::new(fn() -> (RowId, V)? {
    if self.version != version {
      abort("Table: table mutated during iteration")
    }
    let mut result : (RowId, V)? = None
    let mut done = false
    while !done {
      if pos < pending.length() {
        let slot = pending[pos]
        pos = pos + 1
        match self.record_at(slot) {
          Some(entry) => {
            result = Some(entry)
            done = true
          }
          None => ()
        }
      } else {
        match (cursor.next)() {
          Some(slots) => {
            pending = slots
            pos = 0
          }
          None => done = true
        }
      }
    }
    result
  })
}

///|
/// Every record whose index key lies in the **closed** interval `[lo, hi]`,
/// ascending by key (and, inside one bucket, ascending by slot).
///
/// Forwarded to core's `SortedMap::range`, which is closed on both ends
/// (docs/SPEC.md §3.3.1 follows the platform here). `lo > hi` is an empty
/// interval, not an error. Aborts for an unknown name or a hash index (§7.1).
pub fn[K : Compare, V] Table::range_by(
  self : Table[K, V],
  name : String,
  lo : K,
  hi : K,
) -> Iter2[RowId, V] {
  let index = self.ordered_index(name)
  self.cursor_iter(index.range_cursor(lo, hi, true))
}

///|
/// Every record whose index key lies in the **half-open** interval `[lo, hi)`.
///
/// The closed range minus its `hi` entries (which sit at the end of the walk,
/// since keys come out ascending), so `lo == hi` is empty by construction.
pub fn[K : Compare, V] Table::range_half_open_by(
  self : Table[K, V],
  name : String,
  lo : K,
  hi : K,
) -> Iter2[RowId, V] {
  let index = self.ordered_index(name)
  self.cursor_iter(index.range_cursor(lo, hi, false))
}

///|
/// Every record in the index, ordered by key **ascending**.
pub fn[K : Compare, V] Table::iter_asc_by(
  self : Table[K, V],
  name : String,
) -> Iter2[RowId, V] {
  let index = self.ordered_index(name)
  self.cursor_iter(index.ordered_cursor(false))
}

///|
/// Every record in the index, ordered by key **descending** (within one key the
/// slots still come out ascending — only the key order flips).
pub fn[K : Compare, V] Table::iter_desc_by(
  self : Table[K, V],
  name : String,
) -> Iter2[RowId, V] {
  let index = self.ordered_index(name)
  self.cursor_iter(index.ordered_cursor(true))
}

///|
/// The registered index names, ascending.
///
/// "Ascending" is MoonBit's own `String` order, which is **shortlex**: shorter
/// names first, then code-unit order (`builtin/string.mbt`). So `["aa", "b"]`
/// enumerates as `["b", "aa"]`. Following the platform (as docs/SPEC.md §3.3.1
/// does for `range`) keeps this consistent with any caller-side `sort`.
pub fn[K, V] Table::index_names(self : Table[K, V]) -> Array[String] {
  let names = self.indexes.keys().to_array()
  names.sort()
  names
}

///|
/// Whether an index is registered under `name`.
pub fn[K, V] Table::has_index(self : Table[K, V], name : String) -> Bool {
  self.indexes.contains(name)
}
