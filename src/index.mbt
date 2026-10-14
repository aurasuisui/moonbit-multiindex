// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Index core (M2): one registry entry per secondary index, plus its bucket
// operations (docs/SPEC.md §3.5).
//
// Bucket entries are SLOT NUMBERS, never `RowId` (docs/SPEC.md §3.5):
// generations exist only to validate handles that arrive from outside, while
// buckets are written and read inside the chokepoints, so an entry always names
// the slot's current occupant. A generation stored in a bucket would be a second
// source of truth for a fact `gens` already owns.
//
// Bounds: one enum holds all four quadrants, so any operation that walks the
// registry needs the union of their bounds — `K : Hash + Eq + Compare`. Methods
// that never touch an index (`get` / `len` / `is_empty` / `iter`) stay
// unconstrained; the trade-off (a hash-only key type must also implement
// `Compare`) is recorded in CHANGELOG Notes/Deviations.

///|
/// Shared half of every index: its registry name and the projection that maps a
/// record to its key.
priv struct IndexMeta[K, V] {
  name : String
  project : (V) -> K
}

///|
/// One registered index — the 2×2 quadrants of docs/SPEC.md §3.5:
///
/// - `HashUnique`   unique + hashed      (`Map[K, Int]`)
/// - `SortedUnique` unique + sorted      (`SortedMap[K, Int]`)
/// - `HashMulti`    non-unique + hashed  (`Map[K, SortedSet[Int]]`)
/// - `SortedMulti`  non-unique + sorted  (`SortedMap[K, SortedSet[Int]]`)
priv enum Index[K, V] {
  HashUnique(IndexMeta[K, V], Map[K, Int])
  SortedUnique(IndexMeta[K, V], @sorted_map.SortedMap[K, Int])
  HashMulti(IndexMeta[K, V], Map[K, @sorted_set.SortedSet[Int]])
  SortedMulti(
    IndexMeta[K, V],
    @sorted_map.SortedMap[K, @sorted_set.SortedSet[Int]]
  )
}

///|
/// The index name it is registered under.
fn[K, V] Index::name(self : Index[K, V]) -> String {
  match self {
    HashUnique(meta, _) => meta.name
    SortedUnique(meta, _) => meta.name
    HashMulti(meta, _) => meta.name
    SortedMulti(meta, _) => meta.name
  }
}

///|
/// The projection from a record to this index's key.
fn[K, V] Index::project(self : Index[K, V]) -> (V) -> K {
  match self {
    HashUnique(meta, _) => meta.project
    SortedUnique(meta, _) => meta.project
    HashMulti(meta, _) => meta.project
    SortedMulti(meta, _) => meta.project
  }
}

///|
/// Whether this index enforces key uniqueness (a conflict-checked quadrant).
fn[K, V] Index::is_unique(self : Index[K, V]) -> Bool {
  match self {
    HashUnique(_, _) => true
    SortedUnique(_, _) => true
    HashMulti(_, _) => false
    SortedMulti(_, _) => false
  }
}

///|
/// Slot that currently holds `key`. Always `None` for a non-unique index — those
/// quadrants have no conflict to report (docs/SPEC.md §3.5).
fn[K : Hash + Eq + Compare, V] Index::holder(
  self : Index[K, V],
  key : K,
) -> Int? {
  match self {
    HashUnique(_, buckets) => buckets.get(key)
    SortedUnique(_, buckets) => buckets.get(key)
    HashMulti(_, _) => None
    SortedMulti(_, _) => None
  }
}

///|
/// Record that `slot` projects to `key` (called from the insert chokepoint,
/// which has already rejected any unique collision).
fn[K : Hash + Eq + Compare, V] Index::add(
  self : Index[K, V],
  slot : Int,
  key : K,
) -> Unit {
  match self {
    HashUnique(_, buckets) => buckets.set(key, slot)
    SortedUnique(_, buckets) => buckets.set(key, slot)
    HashMulti(_, buckets) =>
      match buckets.get(key) {
        Some(set) => set.add(slot)
        None => buckets.set(key, @sorted_set.SortedSet([slot]))
      }
    SortedMulti(_, buckets) =>
      match buckets.get(key) {
        Some(set) => set.add(slot)
        None => buckets.set(key, @sorted_set.SortedSet([slot]))
      }
  }
}

///|
/// Drop `slot` from the bucket of `key`, removing a bucket that becomes empty.
///
/// The bucket must exist and (for a unique quadrant) must name this very slot:
/// anything else means an upstream invariant is already broken, and a silent
/// no-op would hide it, so this aborts instead.
fn[K : Hash + Eq + Compare, V] Index::remove(
  self : Index[K, V],
  slot : Int,
  key : K,
) -> Unit {
  let index_name = self.name()
  match self {
    HashUnique(_, buckets) =>
      match buckets.get(key) {
        Some(holder) => {
          if holder != slot {
            abort(
              "Index::remove(" +
              index_name +
              "): unique bucket for a key holds slot " +
              holder.to_string() +
              ", not " +
              slot.to_string(),
            )
          }
          buckets.remove(key)
        }
        None =>
          abort(
            "Index::remove(" +
            index_name +
            "): no unique bucket for the removed record",
          )
      }
    SortedUnique(_, buckets) =>
      match buckets.get(key) {
        Some(holder) => {
          if holder != slot {
            abort(
              "Index::remove(" +
              index_name +
              "): unique bucket for a key holds slot " +
              holder.to_string() +
              ", not " +
              slot.to_string(),
            )
          }
          buckets.remove(key)
        }
        None =>
          abort(
            "Index::remove(" +
            index_name +
            "): no unique bucket for the removed record",
          )
      }
    HashMulti(_, buckets) =>
      match buckets.get(key) {
        Some(set) => {
          if !set.contains(slot) {
            abort(
              "Index::remove(" +
              index_name +
              "): multi bucket does not hold the removed slot",
            )
          }
          set.remove(slot)
          if set.is_empty() {
            buckets.remove(key)
          }
        }
        None =>
          abort(
            "Index::remove(" +
            index_name +
            "): no multi bucket for the removed record",
          )
      }
    SortedMulti(_, buckets) =>
      match buckets.get(key) {
        Some(set) => {
          if !set.contains(slot) {
            abort(
              "Index::remove(" +
              index_name +
              "): multi bucket does not hold the removed slot",
            )
          }
          set.remove(slot)
          if set.is_empty() {
            buckets.remove(key)
          }
        }
        None =>
          abort(
            "Index::remove(" +
            index_name +
            "): no multi bucket for the removed record",
          )
      }
  }
}

///|
/// The slots stored under `key`, ascending (`[]` when the key is absent).
///
/// A unique quadrant yields 0 or 1 slot, a non-unique one all of them — the same
/// shape for both, which is what lets `get_by` / `iter_by` treat them uniformly.
fn[K : Hash + Eq + Compare, V] Index::slots(
  self : Index[K, V],
  key : K,
) -> Array[Int] {
  match self {
    HashUnique(_, buckets) =>
      match buckets.get(key) {
        Some(slot) => [slot]
        None => []
      }
    SortedUnique(_, buckets) =>
      match buckets.get(key) {
        Some(slot) => [slot]
        None => []
      }
    HashMulti(_, buckets) =>
      match buckets.get(key) {
        Some(set) => set.to_array()
        None => []
      }
    SortedMulti(_, buckets) =>
      match buckets.get(key) {
        Some(set) => set.to_array()
        None => []
      }
  }
}

///|
/// Drop every bucket. The registration itself survives — `Table::clear` drops
/// records and index entries, it does not unregister the schema.
fn[K, V] Index::clear(self : Index[K, V]) -> Unit {
  match self {
    HashUnique(_, buckets) => buckets.clear()
    SortedUnique(_, buckets) => buckets.clear()
    HashMulti(_, buckets) => buckets.clear()
    SortedMulti(_, buckets) => buckets.clear()
  }
}
