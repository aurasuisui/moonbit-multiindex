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
const GEN_MAX : Int32 = 1073741824

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
  priv gens : Array[Int32]
  priv free : Array[Int32]
  priv order : Array[Int32]
  priv indexes : Map[String, Index[K, V]]
  priv mut len : Int32
  priv mut version : Int32
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

///|
/// Create an empty table whose slot storage is already sized for `cap` records.
///
/// The reserved slots are all vacant, so they all go on `free` — pushed
/// high-to-low, so the LIFO stack hands out slot 0 first and the first `cap`
/// inserts never have to grow the slot arrays. `cap <= 0` reserves nothing.
pub fn[K, V] Table::with_capacity(cap : Int32) -> Table[K, V] {
  let t = Table::new()
  let mut i = cap - 1
  while i >= 0 {
    t.rows.push(None)
    t.gens.push(0)
    t.free.push(i)
    i = i - 1
  }
  t
}

// ---------------------------------------------------------------------------
// Reads (no bounds: none of these touches an index)
// ---------------------------------------------------------------------------

///|
/// Number of live records.
pub fn[K, V] Table::len(self : Table[K, V]) -> Int32 {
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
/// Whether `id` names a live record (a stale handle answers `false`).
pub fn[K, V] Table::contains(self : Table[K, V], id : RowId) -> Bool {
  match self.get(id) {
    Some(_) => true
    None => false
  }
}

///|
/// The record in a live slot as `(handle, value)`; `None` when the slot is empty.
///
/// Reading the row copies the record value — the same shallow copy docs/SPEC.md
/// §3.3 accepts for queries (a record's own containers stay shared).
fn[K, V] Table::record_at(self : Table[K, V], slot : Int32) -> (RowId, V)? {
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
  self.find_conflict_excluding(value, -1)
}

///|
/// The unique-index collision `value` would cause **against some record other than
/// `exclude_slot`** (pass `-1` to exclude nothing), or `None`.
///
/// Excluding self is what makes "write a record back under a key it already holds" a
/// no-op instead of a conflict — docs/SPEC.md §5 rule 1, the bug the original probe
/// caught. Like `find_conflict`, this mutates nothing.
///
/// When several indexes would be violated at once, the one whose **name sorts first**
/// is reported (docs/SPEC.md §7): the registry is a hash map, so returning whichever
/// index the iteration happened to reach first would make the error depend on internal
/// ordering. Collecting the violations costs nothing on the happy path — this function
/// only runs it when it has already found a conflict.
fn[K : Hash + Eq + Compare, V] Table::find_conflict_excluding(
  self : Table[K, V],
  value : V,
  exclude_slot : Int32,
) -> Conflict[K]? {
  let mut best_name : String? = None
  let mut best : Conflict[K]? = None
  for name, index in self.indexes {
    if index.is_unique() {
      let key = index.project()(value)
      match index.holder(key) {
        Some(slot) =>
          if slot != exclude_slot {
            let better = match best_name {
              None => true
              Some(current) => name < current
            }
            if better {
              best_name = Some(name)
              best = Some(
                UniqueViolation(name, key, { slot, gen: self.gens[slot], }),
              )
            }
          }
        None => ()
      }
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Chokepoints (docs/DEVPLAN.md §4)
// ---------------------------------------------------------------------------

///|
/// Allocate a slot: reuse the most recently freed one (LIFO), or grow the slot
/// arrays by one. Retired slots are never in `free`, so they are never handed
/// out again (I9).
fn[K, V] Table::alloc_slot(self : Table[K, V]) -> Int32 {
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
fn[K, V] Table::order_remove(self : Table[K, V], slot : Int32) -> Unit {
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
  slot : Int32,
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
/// CHOKEPOINT (update): swap the record in `slot` for `value`, retargeting only
/// the index buckets whose projected key really changes.
///
/// The index work happens **before** the row is overwritten, so no bucket ever
/// points at a slot whose projection has stopped matching (I4), and the equal-key
/// indexes are not touched at all (docs/SPEC.md §5 rule 3). The caller must have
/// completed every uniqueness pre-check — this is the commit half.
fn[K : Hash + Eq + Compare, V] Table::modify_impl(
  self : Table[K, V],
  slot : Int32,
  value : V,
) -> Unit {
  let previous = match self.rows[slot] {
    Some(record) => record
    None =>
      abort(
        "Table::modify_impl: slot " + slot.to_string() + " holds no live record",
      )
  }
  for _, index in self.indexes {
    let project = index.project()
    index.retarget(slot, project(previous), project(value)) |> ignore
  }
  self.rows[slot] = Some(value)
  self.version = self.version + 1
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
/// Store every record of `values`, or none of them.
///
/// The whole batch is checked **before anything is written** (docs/SPEC.md §11):
/// each record is probed against the live table *and* against the earlier members of
/// the same batch, so a duplicate **inside** the batch fails exactly like one that
/// clashes with an existing record. On `Err` the table is what it was, and the
/// offending record comes back inside `Rejected` (the caller keeps its array too —
/// MoonBit arrays are references).
///
/// The reference implementation's `FromIterator` is **first-wins**; this library
/// deliberately does not copy that, because a silent winning rule contradicts
/// "a conflict is never silently overwritten" (the deviation is registered in
/// `tools/diffgen/README.md`).
///
/// `holder` in the conflict: against a live record it is that record's handle; for a
/// clash **inside the batch** it is the handle the earlier member would receive once
/// the batch is accepted, since no record is live there yet (see CHANGELOG Notes).
pub fn[K : Hash + Eq + Compare, V] Table::insert_many(
  self : Table[K, V],
  values : Array[V],
) -> Result[Array[RowId], Rejected[K, V]] {
  // Per unique index: the keys this batch has already claimed, and by which member.
  let claimed : Map[String, Map[K, Int32]] = Map([])
  let mut i = 0
  while i < values.length() {
    let value = values[i]
    // (a) Collect every violation this member hits — against a live record or against
    //     an earlier member — and report the one whose index name sorts first
    //     (docs/SPEC.md §7).
    let mut best_name : String? = None
    let mut best : Conflict[K]? = None
    for name, index in self.indexes {
      if index.is_unique() {
        let key = index.project()(value)
        let mut candidate : Conflict[K]? = None
        match index.holder(key) {
          Some(slot) =>
            candidate = Some(
              UniqueViolation(name, key, { slot, gen: self.gens[slot], }),
            )
          None =>
            match claimed.get(name) {
              Some(seen) =>
                match seen.get(key) {
                  // Not UniqueViolation: nothing is live at that key, and the batch
                  // position says exactly which member got there first.
                  Some(at) => candidate = Some(DuplicateInBatch(name, key, at))
                  None => ()
                }
              None => ()
            }
        }
        match candidate {
          Some(conflict) => {
            let better = match best_name {
              None => true
              Some(current) => name < current
            }
            if better {
              best_name = Some(name)
              best = Some(conflict)
            }
          }
          None => ()
        }
      }
    }
    match best {
      Some(conflict) => return Err({ conflict, record: value, })
      None => ()
    }
    // (b) No violation: claim this member's keys, in a second pass so that a refused
    //     member leaves no trace in `claimed`.
    for name, index in self.indexes {
      if index.is_unique() {
        let key = index.project()(value)
        match claimed.get(name) {
          Some(seen) => seen.set(key, i)
          None => {
            let seen : Map[K, Int32] = Map([])
            seen.set(key, i)
            claimed.set(name, seen)
          }
        }
      }
    }
    i = i + 1
  }
  let ids : Array[RowId] = []
  let mut j = 0
  while j < values.length() {
    ids.push(self.insert_impl(values[j]))
    j = j + 1
  }
  Ok(ids)
}

///|
/// Replace the record named by `id` with `value`.
///
/// The **excluding-self** check runs first (docs/SPEC.md §5 rule 1): writing a
/// record back under a key it already holds is not a conflict. Every unique index
/// is probed before anything is written, so on `Err` the table is exactly what it
/// was and `value` travels back inside `UpdateRejected`. A stale `id` yields
/// `Err(StaleHandle(id, Some(value)))` — the caller's record is never swallowed.
pub fn[K : Hash + Eq + Compare, V] Table::update(
  self : Table[K, V],
  id : RowId,
  value : V,
) -> Result[Unit, UpdateRejected[K, V]] {
  match self.get(id) {
    None => Err(StaleHandle(id, Some(value)))
    Some(_) =>
      match self.find_conflict_excluding(value, id.slot) {
        Some(conflict) => Err(Conflict(conflict, value))
        None => {
          self.modify_impl(id.slot, value)
          Ok(())
        }
      }
  }
}

///|
/// Replace the record named by `id` with `f(record)`.
///
/// `f` runs exactly once, before any mutation, and only the index buckets whose
/// projected key changes are touched (docs/SPEC.md §5 rule 4 — the ordering the
/// reference implementation gets wrong). A stale `id` yields
/// `Err(StaleHandle(id, None))`: with no record to transform there is no new
/// record to hand back.
pub fn[K : Hash + Eq + Compare, V] Table::modify(
  self : Table[K, V],
  id : RowId,
  f : (V) -> V,
) -> Result[Unit, UpdateRejected[K, V]] {
  match self.get(id) {
    None => Err(StaleHandle(id, None))
    Some(previous) => {
      let value = f(previous)
      match self.find_conflict_excluding(value, id.slot) {
        Some(conflict) => Err(Conflict(conflict, value))
        None => {
          self.modify_impl(id.slot, value)
          Ok(())
        }
      }
    }
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
