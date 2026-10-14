// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Table core — M1 (record storage).
//
// Layout (docs/DEVPLAN.md §2):
//   rows    slot storage; `None` marks a vacant slot
//   gens    per-slot generation, bumped once per recycle
//   free    free-slot stack (LIFO); retired slots never re-enter it (I9)
//   order   live slots in insertion order
//   indexes named secondary index registry (shape fixed here, filled in M2)
//
// Chokepoint discipline (docs/DEVPLAN.md §4): `insert_impl` and `remove_impl`
// are the only single-record paths allowed to touch rows + order + gens + free
// (+ indexes, from M2 on). `clear_impl` is the bulk-removal path — the analogue
// of bimap's `retain` — which retires every live slot in one O(n) sweep instead
// of looping `remove_impl` (that would be O(n²) through the order compaction).

///|
/// Largest generation a slot may hold before it is retired for good (I9).
///
/// `1 << 62`: far beyond any recycle count reachable in practice, and one past
/// it still fits in a 64-bit signed `Int`, so the `gens[slot] < GEN_MAX` test
/// that decides retirement can never overflow.
const GEN_MAX : Int = 1 << 62

///|
/// Registry entry of one secondary index: its name plus the projection that
/// maps a record to its key (docs/SPEC.md §3.5).
///
/// Declared in M1 so the `Table` layout is final before indexes exist; the
/// bucket operations that construct these land in M2 (execution brief §四,
/// option (b)).
priv struct IndexMeta[K, V] {
  name : String
  project : (V) -> K
}

///|
/// The four index quadrants — unique × sorted (docs/SPEC.md §3.5).
///
/// Declared in M1 (layout only, no bucket operations); M2 fills in the registry.
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
/// A record store with N secondary indexes over stable generational handles.
///
/// M1 delivers the storage core: slot allocation with LIFO reuse, per-slot
/// generations that make stale handles harmless (the ABA problem), insertion
/// order, and the un-indexed operations `insert` / `get` / `remove` / `len` /
/// `is_empty` / `clear` / `iter`. Index registration and the conflict-aware
/// writes arrive in M2/M3; `K` is the key type those indexes will project to.
pub struct Table[K, V] {
  priv rows : Array[V?]
  priv gens : Array[Int]
  priv free : Array[Int]
  priv order : Array[Int]
  priv indexes : Map[String, Index[K, V]]
  priv mut len : Int
  priv mut version : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create an empty table.
pub fn[K, V] Table::new() -> Table[K, V] {
  {
    rows: [],
    gens: [],
    free: [],
    order: [],
    indexes: Map([]),
    len: 0,
    version: 0,
  }
}

// ---------------------------------------------------------------------------
// Chokepoints (docs/DEVPLAN.md §4)
// ---------------------------------------------------------------------------

///|
/// Allocate a slot: reuse the most recently freed one (LIFO), or grow the slot
/// arrays by one. Retired slots are never in `free`, so they are never handed
/// out again (I9).
fn[K, V] Table::alloc_slot(self : Table[K, V]) -> Int {
  match self.free.pop() {
    Some(slot) => slot
    None => {
      let slot = self.rows.length()
      self.rows.push(None)
      self.gens.push(0)
      slot
    }
  }
}

///|
/// CHOKEPOINT (insert): take a slot, store the record, append it to `order`.
fn[K, V] Table::insert_impl(self : Table[K, V], value : V) -> RowId {
  let slot = self.alloc_slot()
  self.rows[slot] = Some(value)
  self.order.push(slot)
  self.len = self.len + 1
  self.version = self.version + 1
  { slot, gen: self.gens[slot], }
}

///|
/// Drop `slot` from `order`, keeping the insertion order of the rest (O(n)).
fn[K, V] Table::order_remove(self : Table[K, V], slot : Int) -> Unit {
  let n = self.order.length()
  let mut i = 0
  while i < n {
    if self.order[i] == slot {
      let mut j = i
      while j + 1 < n {
        self.order[j] = self.order[j + 1]
        j = j + 1
      }
      self.order.pop() |> ignore
      return
    }
    i = i + 1
  }
  abort("Table::order_remove: slot " + slot.to_string() + " is not in `order`")
}

///|
/// CHOKEPOINT (remove): clear the row, bump the slot generation, recycle the
/// slot — or retire it for good once the generation is exhausted (I9) — and
/// drop the slot from `order`. Returns the record that lived there.
///
/// Only `Table::remove` — after it has validated the handle — may call this.
/// `clear_impl` performs the same retirement inline, in bulk.
fn[K, V] Table::remove_impl(self : Table[K, V], slot : Int) -> V {
  let value = match self.rows[slot] {
    Some(v) => v
    None =>
      abort(
        "Table::remove_impl: slot " + slot.to_string() + " holds no live record",
      )
  }
  self.rows[slot] = None
  if self.gens[slot] < GEN_MAX {
    self.gens[slot] = self.gens[slot] + 1
    self.free.push(slot)
  }
  self.order_remove(slot)
  self.len = self.len - 1
  self.version = self.version + 1
  value
}

///|
/// CHOKEPOINT (bulk removal): retire every live slot in one O(n) sweep, then
/// drop the insertion order and the index registry.
///
/// Each live slot is retired exactly the way `remove_impl` retires one — row
/// cleared, generation bumped, slot pushed back on `free` (unless the
/// generation is exhausted, in which case the slot is retired for good). That is
/// what keeps `clear` from resurrecting old handles: a handle issued before the
/// clear can never resolve to a record stored after it (docs/CHANGELOG.md
/// Notes/Deviations).
fn[K, V] Table::clear_impl(self : Table[K, V]) -> Unit {
  let mut i = 0
  while i < self.order.length() {
    let slot = self.order[i]
    self.rows[slot] = None
    if self.gens[slot] < GEN_MAX {
      self.gens[slot] = self.gens[slot] + 1
      self.free.push(slot)
    }
    i = i + 1
  }
  self.order.clear()
  self.indexes.clear()
  self.len = 0
}

// ---------------------------------------------------------------------------
// Public API (M1: no indexes registered yet, so no write can conflict)
// ---------------------------------------------------------------------------

///|
/// Store `value` and return its stable handle.
///
/// M1 maintains no indexes, so this cannot fail yet; the `Result` is the shape
/// fixed by docs/SPEC.md §3.2, where a unique-index collision returns
/// `Err(Rejected)` with the record handed back and the table unchanged.
pub fn[K, V] Table::insert(
  self : Table[K, V],
  value : V,
) -> Result[RowId, Rejected[K, V]] {
  Ok(self.insert_impl(value))
}

///|
/// The record named by `id`, or `None` if `id` is stale.
///
/// A handle is stale when its generation no longer matches the slot's — the slot
/// was recycled (or the table cleared), so `id` names a record that is gone.
/// A stale handle never resolves to the slot's *current* occupant (ABA guard).
pub fn[K, V] Table::get(self : Table[K, V], id : RowId) -> V? {
  let slot = id.slot
  if slot < 0 || slot >= self.rows.length() {
    return None
  }
  if self.gens[slot] != id.gen {
    return None
  }
  self.rows[slot]
}

///|
/// Remove and return the record named by `id`, or `None` if `id` is stale.
///
/// A rejected handle leaves the table — and the slot's current occupant —
/// completely untouched.
pub fn[K, V] Table::remove(self : Table[K, V], id : RowId) -> V? {
  match self.get(id) {
    None => None
    Some(_) => Some(self.remove_impl(id.slot))
  }
}

///|
/// Number of live records.
pub fn[K, V] Table::len(self : Table[K, V]) -> Int {
  self.len
}

///|
/// Whether the table holds no live records.
pub fn[K, V] Table::is_empty(self : Table[K, V]) -> Bool {
  self.len == 0
}

///|
/// Drop every record and every index entry.
///
/// Storage is kept (the slot arrays are recycled, not freed) and every handle
/// issued before the call becomes stale, so a later insert can never resolve an
/// old handle. A clear of an already-empty table is not a change and leaves
/// `version` alone (I8).
pub fn[K, V] Table::clear(self : Table[K, V]) -> Unit {
  if self.len > 0 {
    self.clear_impl()
    self.version = self.version + 1
  }
}

///|
/// Iterate the live records in insertion order.
///
/// Mutating the table while an iteration is in flight aborts it (fail-fast,
/// keyed on the mutation counter `version`) instead of yielding a torn view.
pub fn[K, V] Table::iter(self : Table[K, V]) -> Iter[V] {
  let mut pos = 0
  let len = self.order.length()
  let version = self.version
  Iter::new(
    fn() -> V? {
      if self.version != version {
        abort("Table::iter: table mutated during iteration")
      }
      while pos < len {
        let slot = self.order[pos]
        pos = pos + 1
        match self.rows[slot] {
          Some(v) => return Some(v)
          None => continue
        }
      }
      None
    },
    size_hint=len,
  )
}
