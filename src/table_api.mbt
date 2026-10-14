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
///
/// Deliberately **unconstrained**: the walk never compares keys, and the runtime
/// `abort` ("this index has no key order") tells a caller far more than a compile
/// error demanding `Compare` for what is merely a hash index (docs/SPEC.md §3.3).
pub fn[K, V] Table::iter_asc_by(
  self : Table[K, V],
  name : String,
) -> Iter2[RowId, V] {
  let index = self.ordered_index(name)
  self.cursor_iter(index.ordered_cursor(false))
}

///|
/// Every record in the index, ordered by key **descending** (within one key the
/// slots still come out ascending — only the key order flips). Unconstrained for
/// the same reason as `iter_asc_by`.
pub fn[K, V] Table::iter_desc_by(
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

// ---------------------------------------------------------------------------
// Diagnostics (docs/SPEC.md §3.4)
// ---------------------------------------------------------------------------

///|
/// Check every invariant on the *inside* of the table and report the **first**
/// violation, with enough context to locate it (docs/SPEC.md §3.4).
///
/// The message names the invariant (I1–I9) and the slot or key involved. A checker
/// that could only answer "false" would be of little use to its caller, which is why
/// this returns `Result[Unit, String]` rather than `Bool`. `K : Eq + Debug` is what
/// comparing keys and rendering them in messages costs — nothing more.
pub fn[K : Eq + Debug, V] Table::verify_invariants(
  self : Table[K, V],
) -> Result[Unit, String] {
  match self.verify_storage() {
    Err(message) => Err(message)
    Ok(_) => self.verify_indexes()
  }
}

///|
/// I1 / I2 / I6 / I9 — the storage half of `verify_invariants`.
fn[K : Eq + Debug, V] Table::verify_storage(
  self : Table[K, V],
) -> Result[Unit, String] {
  let n = self.rows.length()
  if self.gens.length() != n {
    return Err(
      "I2: `rows` holds " +
      n.to_string() +
      " slots but `gens` holds " +
      self.gens.length().to_string(),
    )
  }
  if self.len < 0 {
    return Err("I2: len is negative (" + self.len.to_string() + ")")
  }
  let live : Array[Bool] = Array::make(n, false)
  let mut live_count = 0
  let mut i = 0
  while i < n {
    match self.rows[i] {
      Some(_) => {
        live[i] = true
        live_count = live_count + 1
      }
      None => ()
    }
    i = i + 1
  }
  if live_count != self.len {
    return Err(
      "I2: len is " +
      self.len.to_string() +
      " but " +
      live_count.to_string() +
      " rows hold a record",
    )
  }
  if self.order.length() != self.len {
    return Err(
      "I2: len is " +
      self.len.to_string() +
      " but `order` holds " +
      self.order.length().to_string() +
      " slots",
    )
  }
  // I1: `order` is exactly the live slots, each once
  let in_order : Array[Bool] = Array::make(n, false)
  let mut j = 0
  while j < self.order.length() {
    let slot = self.order[j]
    if slot < 0 || slot >= n {
      return Err(
        "I1: `order` names slot " + slot.to_string() + ", which is out of range",
      )
    }
    if !live[slot] {
      return Err(
        "I1: `order` names slot " + slot.to_string() + ", which holds no record",
      )
    }
    if in_order[slot] {
      return Err("I1: slot " + slot.to_string() + " appears twice in `order`")
    }
    in_order[slot] = true
    j = j + 1
  }
  // I6: `free` is clean and disjoint from the live set
  let in_free : Array[Bool] = Array::make(n, false)
  let mut f = 0
  while f < self.free.length() {
    let slot = self.free[f]
    if slot < 0 || slot >= n {
      return Err(
        "I6: `free` names slot " + slot.to_string() + ", which is out of range",
      )
    }
    if in_free[slot] {
      return Err("I6: slot " + slot.to_string() + " appears twice on `free`")
    }
    if live[slot] {
      return Err("I6: slot " + slot.to_string() + " is both free and live")
    }
    in_free[slot] = true
    f = f + 1
  }
  // I9: a dead slot is free or retired for good
  let mut m = 0
  while m < n {
    if !live[m] && !in_free[m] && self.gens[m] != GEN_MAX {
      return Err(
        "I9: slot " +
        m.to_string() +
        " is dead and not free, but its generation " +
        self.gens[m].to_string() +
        " is below GEN_MAX",
      )
    }
    m = m + 1
  }
  Ok(())
}

///|
/// I3 / I4 / I5 / I7 — the index half of `verify_invariants`.
fn[K : Eq + Debug, V] Table::verify_indexes(
  self : Table[K, V],
) -> Result[Unit, String] {
  for name, index in self.indexes {
    let buckets = index.buckets()
    let mut entries = 0
    let mut b = 0
    while b < buckets.length() {
      let (key, slots) = buckets[b]
      if index.is_unique() && slots.length() > 1 {
        return Err(
          "I5: unique index " +
          @debug.to_string(name) +
          " holds " +
          slots.length().to_string() +
          " slots under key " +
          @debug.to_string(key),
        )
      }
      let seen : Array[Bool] = Array::make(self.rows.length(), false)
      let mut s = 0
      while s < slots.length() {
        let slot = slots[s]
        if slot < 0 || slot >= self.rows.length() {
          return Err(
            "I3: index " +
            @debug.to_string(name) +
            " holds out-of-range slot " +
            slot.to_string(),
          )
        }
        if seen[slot] {
          return Err(
            "I3: slot " +
            slot.to_string() +
            " appears twice in one bucket of index " +
            @debug.to_string(name),
          )
        }
        seen[slot] = true
        match self.rows[slot] {
          Some(record) => {
            let projected = index.project()(record)
            if projected != key {
              return Err(
                "I4: bucket " +
                @debug.to_string(key) +
                " of index " +
                @debug.to_string(name) +
                " holds slot " +
                slot.to_string() +
                ", whose record projects to " +
                @debug.to_string(projected),
              )
            }
          }
          None =>
            return Err(
              "I4: bucket " +
              @debug.to_string(key) +
              " of index " +
              @debug.to_string(name) +
              " holds slot " +
              slot.to_string() +
              ", which holds no record",
            )
        }
        s = s + 1
      }
      entries = entries + slots.length()
      b = b + 1
    }
    // I7, counting half: no entry missing, none extra
    if entries != self.len {
      return Err(
        "I7: index " +
        @debug.to_string(name) +
        " holds " +
        entries.to_string() +
        " entries but the table has " +
        self.len.to_string() +
        " live records",
      )
    }
    // I7, coverage half: every live record sits in the bucket for its own key
    let mut c = 0
    while c < self.order.length() {
      let slot = self.order[c]
      match self.rows[slot] {
        Some(record) => {
          let key = index.project()(record)
          let mut found = false
          let mut x = 0
          while x < buckets.length() {
            let (bucket_key, slots) = buckets[x]
            if bucket_key == key {
              let mut y = 0
              while y < slots.length() {
                if slots[y] == slot {
                  found = true
                }
                y = y + 1
              }
            }
            x = x + 1
          }
          if !found {
            return Err(
              "I7: the record in slot " +
              slot.to_string() +
              " is missing from index " +
              @debug.to_string(name) +
              " under key " +
              @debug.to_string(key),
            )
          }
        }
        None => ()
      }
      c = c + 1
    }
  }
  Ok(())
}

///|
/// Bucket-shape statistics of the index registered under `name` (docs/SPEC.md §3.4).
///
/// Works for every quadrant: "how concentrated is this index" is a question about
/// buckets, not about key order. An unknown name aborts (docs/SPEC.md §7.1).
pub fn[K, V] Table::index_stats(
  self : Table[K, V],
  name : String,
) -> IndexStats {
  let index = self.require_index(name)
  let buckets = index.buckets()
  let mut entries = 0
  let mut longest = 0
  let mut i = 0
  while i < buckets.length() {
    let slots = buckets[i].1
    entries = entries + slots.length()
    if slots.length() > longest {
      longest = slots.length()
    }
    i = i + 1
  }
  let count = buckets.length()
  let average = if count == 0 {
    0.0
  } else {
    entries.to_double() / count.to_double()
  }
  { buckets: count, entries, longest_bucket: longest, average_bucket: average, }
}
