// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Table core — records, generations, insertion order, and the chokepoints that
// keep the registry (`src/index.mbt`) consistent with them.
//
// Layout (docs/DEVPLAN.md §2):
//   rows    slot storage; `None` marks a vacant slot
//   gens    per-slot generation, bumped once per recycle
//   free    free-slot stack (LIFO); retired slots never re-enter it (I9)
//   order   live slots in insertion order
//   indexes named secondary index registry
//
// Chokepoint discipline (docs/DEVPLAN.md §4, docs/SPEC.md §5): `insert_impl`,
// `remove_impl` and `clear_impl` are the ONLY places allowed to touch
// rows + order + indexes + gens + free together. Everything else either reads,
// or validates first and then calls one of them.
//
// `clear_impl` is the bulk-removal path — the analogue of bimap's `retain` —
// retiring every live slot in one O(n) sweep instead of looping `remove_impl`
// (which would be O(n²) through the order compaction).

///|
/// Largest generation a slot may hold before it is retired for good (I9).
///
/// **MoonBit's `Int` is 32-bit signed** (`@int.max_value == 2147483647`) on every
/// target we ship — do not reason about it as 64-bit. `2^30` is the largest power
/// of two for which `GEN_MAX + 1` still fits, and it is far beyond any recycle
/// count reachable in practice.
///
/// Spelled as an explicit literal on purpose: `1 << 62` is *silently* reduced
/// modulo the 32-bit width to `1 << 30` — no error, no warning — so a shift would
/// change meaning without notice if `Int` ever widened.
const GEN_MAX : Int = 1073741824

///|
/// A record store with N secondary indexes over stable generational handles.
///
/// Records live in slots; `RowId` pairs a slot with the slot's generation, so a
/// handle that outlives its record is rejected instead of silently naming the
/// slot's next occupant (the ABA problem). Insertion order is preserved, and any
/// number of named secondary indexes (unique / non-unique, hashed / sorted) can be
/// registered over the records and are kept consistent by the chokepoints.
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
/// Create an empty table with no registered index.
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
// Reads (no bounds: none of these touches an index)
// ---------------------------------------------------------------------------

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
/// The record in a live slot as `(handle, value)`; `None` when the slot is empty.
///
/// Reading the row copies the record value — the same shallow copy docs/SPEC.md
/// §3.3 accepts for queries (a record's own containers stay shared).
fn[K, V] Table::record_at(self : Table[K, V], slot : Int) -> (RowId, V)? {
  if slot < 0 || slot >= self.rows.length() {
    return None
  }
  match self.rows[slot] {
    Some(value) => Some(({ slot, gen: self.gens[slot], }, value))
    None => None
  }
}

///|
/// Iterate the live records in insertion order, each as `(handle, value)`.
///
/// Mutating the table while an iteration is in flight aborts it (fail-fast,
/// keyed on the mutation counter `version`) instead of yielding a torn view.
pub fn[K, V] Table::iter(self : Table[K, V]) -> Iter2[RowId, V] {
  let mut pos = 0
  let len = self.order.length()
  let version = self.version
  Iter2::new(
    fn() -> (RowId, V)? {
      if self.version != version {
        abort("Table::iter: table mutated during iteration")
      }
      while pos < len {
        let slot = self.order[pos]
        pos = pos + 1
        match self.rows[slot] {
          Some(value) => return Some(({ slot, gen: self.gens[slot], }, value))
          None => continue
        }
      }
      None
    },
    size_hint=len,
  )
}

// ---------------------------------------------------------------------------
// Index maintenance
// ---------------------------------------------------------------------------

///|
/// The first unique-index collision `value` would cause, or `None`.
///
/// Read-only by construction: it projects `value` into every unique index and
/// asks for the current holder, so the caller can run it *before* any mutation
/// (docs/SPEC.md §5 rule 2) and still return a table that is byte-for-byte what
/// it was.
fn[K : Hash + Eq + Compare, V] Table::find_conflict(
  self : Table[K, V],
  value : V,
) -> Conflict[K]? {
  for name, index in self.indexes {
    if index.is_unique() {
      let key = index.project()(value)
      match index.holder(key) {
        Some(slot) =>
          return Some(
            UniqueViolation(name, key, { slot, gen: self.gens[slot], }),
          )
        None => ()
      }
    }
  }
  None
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
/// CHOKEPOINT (insert): take a slot, store the record, append it to `order`, and
/// add it to every registered index.
///
/// Uniqueness was already checked by `Table::insert` — this function is the
/// commit half, and it cannot fail.
fn[K : Hash + Eq + Compare, V] Table::insert_impl(
  self : Table[K, V],
  value : V,
) -> RowId {
  let slot = self.alloc_slot()
  self.rows[slot] = Some(value)
  self.order.push(slot)
  self.len = self.len + 1
  self.version = self.version + 1
  match self.rows[slot] {
    Some(record) =>
      for _, index in self.indexes {
        let key = index.project()(record)
        index.add(slot, key)
      }
    None => abort("Table::insert_impl: the slot it just wrote is empty")
  }
  { slot, gen: self.gens[slot], }
}

///|
/// CHOKEPOINT (remove): drop the record from every index, clear the row, bump the
/// slot generation, recycle the slot — or retire it for good once the generation
/// is exhausted (I9) — and drop the slot from `order`. Returns the record that
/// lived there.
///
/// Only `Table::remove` — after it has validated the handle — may call this.
/// `clear_impl` performs the same retirement inline, in bulk.
fn[K : Hash + Eq + Compare, V] Table::remove_impl(
  self : Table[K, V],
  slot : Int,
) -> V {
  let value = match self.rows[slot] {
    Some(v) => v
    None =>
      abort(
        "Table::remove_impl: slot " + slot.to_string() + " holds no live record",
      )
  }
  for _, index in self.indexes {
    let key = index.project()(value)
    index.remove(slot, key)
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
/// CHOKEPOINT (bulk removal): retire every live slot in one O(n) sweep, then drop
/// the insertion order and every index bucket.
///
/// Each live slot is retired exactly the way `remove_impl` retires one — row
/// cleared, generation bumped, slot pushed back on `free` (unless the generation
/// is exhausted, in which case the slot is retired for good). That is what keeps
/// `clear` from resurrecting old handles: a handle issued before the clear can
/// never resolve to a record stored after it (docs/SPEC.md §3.2).
///
/// Index *registrations* survive: `clear` drops records and index entries, not the
/// schema, so the next insert is indexed again.
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
  for _, index in self.indexes {
    index.clear()
  }
  self.len = 0
}

// ---------------------------------------------------------------------------
// Public writes
// ---------------------------------------------------------------------------

///|
/// Store `value` and return its stable handle.
///
/// Every unique index is probed **before anything is written** (docs/SPEC.md §5
/// rule 2). On a collision the table is exactly what it was, and the record comes
/// back inside `Err(Rejected)` — MoonBit passes records by value, so reporting the
/// conflict alone would destroy the caller's data.
pub fn[K : Hash + Eq + Compare, V] Table::insert(
  self : Table[K, V],
  value : V,
) -> Result[RowId, Rejected[K, V]] {
  match self.find_conflict(value) {
    Some(conflict) => Err({ conflict, record: value, })
    None => Ok(self.insert_impl(value))
  }
}

///|
/// Remove and return the record named by `id`, or `None` if `id` is stale.
///
/// A rejected handle leaves the table — and the slot's current occupant —
/// completely untouched.
pub fn[K : Hash + Eq + Compare, V] Table::remove(
  self : Table[K, V],
  id : RowId,
) -> V? {
  match self.get(id) {
    None => None
    Some(_) => Some(self.remove_impl(id.slot))
  }
}

///|
/// Drop every record and every index entry. Index registrations stay, so the next
/// insert is indexed again.
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
