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
  HashUnique(IndexMeta[K, V], Map[K, Int32])
  SortedUnique(IndexMeta[K, V], @sorted_map.SortedMap[K, Int32])
  HashMulti(IndexMeta[K, V], Map[K, @sorted_set.SortedSet[Int32]])
  SortedMulti(
    IndexMeta[K, V],
    @sorted_map.SortedMap[K, @sorted_set.SortedSet[Int32]]
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
/// Which quadrant this index lives in, as the public `IndexKind` — the
/// classification `Table::index_entries` reports back to the caller.
fn[K, V] Index::kind(self : Index[K, V]) -> IndexKind {
  match self {
    HashUnique(_, _) => IndexKind::HashUnique
    SortedUnique(_, _) => IndexKind::SortedUnique
    HashMulti(_, _) => IndexKind::HashMulti
    SortedMulti(_, _) => IndexKind::SortedMulti
  }
}

///|
/// Slot that currently holds `key`. Always `None` for a non-unique index — those
/// quadrants have no conflict to report (docs/SPEC.md §3.5).
fn[K : Hash + Eq + Compare, V] Index::holder(
  self : Index[K, V],
  key : K,
) -> Int32? {
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
  slot : Int32,
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
  slot : Int32,
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
/// Point `slot` at `new_key` instead of `old_key`, and report whether any bucket
/// moved.
///
/// **Equal keys are the fast path** of docs/SPEC.md §5 rule 3: the bucket already
/// names this slot and the record's remaining fields are not indexed, so nothing
/// is deleted and re-added — no intermediate state exists to observe. Returns
/// `false` exactly in that case (the white-box tests observe this with a key
/// type that counts hashing).
fn[K : Hash + Eq + Compare, V] Index::retarget(
  self : Index[K, V],
  slot : Int32,
  old_key : K,
  new_key : K,
) -> Bool {
  if old_key == new_key {
    return false
  }
  self.remove(slot, old_key)
  self.add(slot, new_key)
  true
}

///|
/// The slots stored under `key`, ascending (`[]` when the key is absent).
///
/// A unique quadrant yields 0 or 1 slot, a non-unique one all of them — the same
/// shape for both, which is what lets `get_by` / `iter_by` treat them uniformly.
fn[K : Hash + Eq + Compare, V] Index::slots(
  self : Index[K, V],
  key : K,
) -> Array[Int32] {
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
/// The smallest slot stored under `key` (`None` when the key is absent), **without
/// materializing the bucket**.
///
/// This is the only thing `Table::get_by` needs, so a lookup on a fat bucket no
/// longer copies every slot just to read the first one (docs/SPEC.md §13 R1:
/// 638 ms → 28 ms per 20 000 lookups into 1 250-record buckets).
fn[K : Hash + Eq + Compare, V] Index::first_slot(
  self : Index[K, V],
  key : K,
) -> Int32? {
  match self {
    HashUnique(_, buckets) => buckets.get(key)
    SortedUnique(_, buckets) => buckets.get(key)
    HashMulti(_, buckets) =>
      match buckets.get(key) {
        Some(set) => set.iter().next()
        None => None
      }
    SortedMulti(_, buckets) =>
      match buckets.get(key) {
        Some(set) => set.iter().next()
        None => None
      }
  }
}

///|
/// Whether this index is one of the two **ordered** quadrants.
///
/// This is the predicate behind the docs/SPEC.md §7.1 rule that asking a hash
/// index for a range is a programming error: the *decision* is testable here,
/// while the `abort` that acts on it cannot be caught in-process (a MoonBit panic
/// is not an `Error`).
fn[K, V] Index::is_ordered(self : Index[K, V]) -> Bool {
  match self {
    HashUnique(_, _) => false
    SortedUnique(_, _) => true
    HashMulti(_, _) => false
    SortedMulti(_, _) => true
  }
}

///|
/// A cursor over the buckets of an ordered index: each call hands out one bucket/
/// slots (already ascending, the way buckets keep them), or `None` at the end.
///
/// Only one bucket is materialized per step, so a walk over a huge range never
/// builds the whole result at once (docs/SPEC.md §3.3 asks range queries to stay
/// lazy).
priv struct BucketCursor {
  next : () -> Array[Int32]?
}

///|
/// Cursor over the buckets of an **ordered** index whose key lies in `[lo, hi]`,
/// ascending by key; `include_hi = false` narrows it to the half-open `[lo, hi)`.
///
/// `lo > hi` is legal and simply yields nothing — an empty interval is a value,
/// not an error (docs/SPEC.md §7.1).
fn[K : Compare, V] Index::range_cursor(
  self : Index[K, V],
  lo : K,
  hi : K,
  include_hi : Bool,
) -> BucketCursor {
  match self {
    SortedUnique(_, buckets) => {
      let source = buckets.range(lo, hi)
      {
        next: fn() -> Array[Int32]? {
          let mut found : Array[Int32]? = None
          let mut scanning = true
          while scanning {
            match source.next() {
              Some((key, slot)) =>
                if include_hi || key != hi {
                  found = Some([slot])
                  scanning = false
                }
              None => scanning = false
            }
          }
          found
        },
      }
    }
    SortedMulti(_, buckets) => {
      let source = buckets.range(lo, hi)
      {
        next: fn() -> Array[Int32]? {
          let mut found : Array[Int32]? = None
          let mut scanning = true
          while scanning {
            match source.next() {
              Some((key, set)) =>
                if include_hi || key != hi {
                  found = Some(set.to_array())
                  scanning = false
                }
              None => scanning = false
            }
          }
          found
        },
      }
    }
    _ =>
      abort("Index::range_cursor: the index has no key order (hash quadrant)")
  }
}

///|
/// Cursor over **every** bucket of an ordered index, ascending — or, with
/// `descending`, in reverse key order.
///
/// Ascending walks the `SortedMap` iterator lazily. Descending has to collect the
/// buckets first, because core has no reverse iterator for `SortedMap`; that cost
/// is documented rather than hidden (the *range* queries stay lazy in both
/// directions). Bucket contents still come out slot-ascending either way — only
/// the key order flips.
fn[K, V] Index::ordered_cursor(
  self : Index[K, V],
  descending : Bool,
) -> BucketCursor {
  match self {
    SortedUnique(_, buckets) =>
      if descending {
        let all : Array[Array[Int32]] = []
        for _, slot in buckets {
          all.push([slot])
        }
        reversed_cursor(all)
      } else {
        let source = buckets.iter2()
        {
          next: fn() -> Array[Int32]? {
            match source.next() {
              Some((_, slot)) => Some([slot])
              None => None
            }
          },
        }
      }
    SortedMulti(_, buckets) =>
      if descending {
        let all : Array[Array[Int32]] = []
        for _, set in buckets {
          all.push(set.to_array())
        }
        reversed_cursor(all)
      } else {
        let source = buckets.iter2()
        {
          next: fn() -> Array[Int32]? {
            match source.next() {
              Some((_, set)) => Some(set.to_array())
              None => None
            }
          },
        }
      }
    _ =>
      abort("Index::ordered_cursor: the index has no key order (hash quadrant)")
  }
}

///|
/// Walk a collected bucket list from the back: the descending half of
/// `ordered_cursor`.
fn reversed_cursor(all : Array[Array[Int32]]) -> BucketCursor {
  let mut pos = all.length() - 1
  {
    next: fn() -> Array[Int32]? {
      if pos < 0 {
        return None
      }
      let bucket = all[pos]
      pos = pos - 1
      Some(bucket)
    },
  }
}

///|
/// Every bucket of the index as `(key, slots)`, in the index's own iteration order.
///
/// The enumeration primitive behind `Table::verify_invariants` and
/// `Table::index_stats`. It materializes, so it does not belong on a query path.
fn[K, V] Index::buckets(self : Index[K, V]) -> Array[(K, Array[Int32])] {
  let out : Array[(K, Array[Int32])] = []
  match self {
    HashUnique(_, buckets) =>
      for key, slot in buckets {
        out.push((key, [slot]))
      }
    SortedUnique(_, buckets) =>
      for key, slot in buckets {
        out.push((key, [slot]))
      }
    HashMulti(_, buckets) =>
      for key, set in buckets {
        out.push((key, set.to_array()))
      }
    SortedMulti(_, buckets) =>
      for key, set in buckets {
        out.push((key, set.to_array()))
      }
  }
  out
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
