// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// WHITE-BOX tests: these read (and, where a state is otherwise unreachable, set)
// the private fields of `Table` directly, because MoonBit compiles `*_test.mbt`
// as an external package — the free stack, the generation array and the
// insertion-order array are not observable through the public API at all.
//
// Scope: slot recycling (LIFO), per-slot generation monotonicity, I9 retirement,
// I6 bookkeeping and I8 (version) — the invariants of docs/DEVPLAN.md §3 that
// only exist on the inside. `check_invariants` itself lives in
// `property_wbtest.mbt`.

///|
/// Insert and unwrap inside the package, for tables with no unique index (a
/// conflict here would be a bug in the test, not in the table). Shared by both
/// white-box test files.
fn[K : Hash + Eq + Compare, V] wb_insert(
  t : Table[K, V],
  value : V,
) -> RowId raise {
  match t.insert(value) {
    Ok(id) => id
    Err(_) =>
      @test.fail("insert returned Err although no unique index is registered")
  }
}

///|
/// Assert an `Array[Int]` equals the expected literal, element by element
/// (avoids relying on an `Eq`/`Debug` instance for arrays).
fn assert_ints(actual : Array[Int], expected : Array[Int]) -> Unit raise {
  @test.assert_eq(actual.length(), expected.length())
  let mut i = 0
  while i < expected.length() {
    @test.assert_eq(actual[i], expected[i])
    i = i + 1
  }
}

///|
fn int_member(a : Array[Int], value : Int) -> Bool {
  let mut i = 0
  while i < a.length() {
    if a[i] == value {
      return true
    }
    i = i + 1
  }
  false
}

///|
test "the free stack recycles slots LIFO" {
  let t : Table[Int, Int] = Table::new()
  let a = wb_insert(t, 1)
  let b = wb_insert(t, 2)
  let c = wb_insert(t, 3)
  assert_ints(t.order, [a.slot, b.slot, c.slot])
  assert_ints(t.free, [])
  assert_ints(t.gens, [0, 0, 0])
  // freeing b then c stacks them; the LAST freed slot must come back first
  t.remove(b) |> ignore
  t.remove(c) |> ignore
  assert_ints(t.free, [b.slot, c.slot])
  assert_ints(t.order, [a.slot])
  let d = wb_insert(t, 4)
  @test.assert_eq(d.slot, c.slot)
  assert_ints(t.free, [b.slot])
  let e = wb_insert(t, 5)
  @test.assert_eq(e.slot, b.slot)
  assert_ints(t.free, [])
  assert_ints(t.gens, [0, 1, 1])
  check_invariants(t)
}

///|
test "each recycle bumps the slot generation by exactly one" {
  let t : Table[Int, Int] = Table::new()
  let first = wb_insert(t, 0)
  @test.assert_eq(t.gens[first.slot], 0)
  let mut previous = first
  let mut expected = 1
  let mut cycle = 0
  while cycle < 25 {
    t.remove(previous) |> ignore
    // the freed slot's generation has already moved on ...
    @test.assert_eq(t.gens[previous.slot], expected)
    // ... and the handle that recycles it carries exactly that generation
    let next = wb_insert(t, cycle)
    @test.assert_eq(next.slot, previous.slot)
    @test.assert_eq(next.gen, expected)
    previous = next
    expected = expected + 1
    cycle = cycle + 1
  }
  @test.assert_eq(t.len, 1)
  check_invariants(t)
}

///|
test "I9: a generation-exhausted slot is retired and never handed out again" {
  let t : Table[Int, Int] = Table::new()
  let id = wb_insert(t, 1)
  let slot = id.slot
  // white-box: pretend this slot has already burned through every generation
  t.gens[slot] = GEN_MAX
  let last : RowId = { slot, gen: GEN_MAX, }
  @test.assert_eq(t.get(last), Some(1))
  @test.assert_eq(t.remove(last), Some(1))
  // retired: not recycled, generation untouched, unreachable for good
  @test.assert_eq(int_member(t.free, slot), false)
  @test.assert_eq(t.gens[slot], GEN_MAX)
  @test.assert_eq(t.get(last), None)
  let mut i = 0
  while i < 5 {
    let next = wb_insert(t, i)
    @test.assert_eq(next.slot == slot, false)
    i = i + 1
  }
  @test.assert_eq(int_member(t.free, slot), false)
  check_invariants(t)
}

///|
test "a stale handle never reaches the slot's current occupant" {
  let t : Table[Int, String] = Table::new()
  let old = wb_insert(t, "old")
  t.remove(old) |> ignore
  let fresh = wb_insert(t, "fresh")
  @test.assert_eq(fresh.slot, old.slot)
  @test.assert_eq(fresh.gen, old.gen + 1)
  @test.assert_eq(t.remove(old), None)
  @test.assert_eq(t.rows[fresh.slot], Some("fresh"))
  @test.assert_eq(t.gens[fresh.slot], fresh.gen)
  @test.assert_eq(t.len, 1)
  assert_ints(t.order, [fresh.slot])
  assert_ints(t.free, [])
  check_invariants(t)
}

///|
test "version only moves on a real change (I8)" {
  let t : Table[Int, Int] = Table::new()
  let v0 = t.version
  t.clear() // clearing an empty table is not a change
  @test.assert_eq(t.version, v0)
  let a = wb_insert(t, 1)
  @test.assert_eq(t.version, v0 + 1)
  t.get(a) |> ignore // reads never bump the counter
  @test.assert_eq(t.version, v0 + 1)
  t.remove(a) |> ignore
  @test.assert_eq(t.version, v0 + 2)
  let b = wb_insert(t, 2)
  @test.assert_eq(t.version, v0 + 3)
  t.clear()
  @test.assert_eq(t.version, v0 + 4)
  @test.assert_eq(t.get(b), None)
  check_invariants(t)
}

///|
test "clear recycles every live slot and keeps storage allocated" {
  let t : Table[Int, Int] = Table::new()
  let a = wb_insert(t, 1)
  let b = wb_insert(t, 2)
  let c = wb_insert(t, 3)
  t.clear()
  @test.assert_eq(t.len, 0)
  @test.assert_eq(t.order.length(), 0)
  @test.assert_eq(t.rows.length(), 3)
  @test.assert_eq(t.gens.length(), 3)
  assert_ints(t.gens, [1, 1, 1])
  assert_ints(t.free, [a.slot, b.slot, c.slot])
  @test.assert_eq(t.get(a), None)
  @test.assert_eq(t.get(b), None)
  @test.assert_eq(t.get(c), None)
  let d = wb_insert(t, 4)
  @test.assert_eq(d.gen, 1)
  @test.assert_eq(int_member(t.free, d.slot), false)
  check_invariants(t)
}
// ---------------------------------------------------------------------------
// Index bucket bookkeeping (M2)
// ---------------------------------------------------------------------------

///|
test "index buckets store slot numbers and drop a bucket once it empties" {
  let t = wb_indexed_table()
  let a = wb_insert_indexed(t, (1, 10, 7))
  let b = wb_insert_indexed(t, (2, 20, 7))
  // the non-unique quadrant keeps both slots under the shared key, ascending
  match t.indexes.get("shared") {
    Some(index) => {
      assert_ints(index.slots(7), [a.slot, b.slot])
      assert_ints(index.slots(5), [])
      @test.assert_eq(index.buckets().length(), 1)
    }
    None => @test.fail("the index vanished")
  }
  // removing one record shrinks the bucket ...
  t.remove(a) |> ignore
  match t.indexes.get("shared") {
    Some(index) => {
      assert_ints(index.slots(7), [b.slot])
      @test.assert_eq(index.buckets().length(), 1)
    }
    None => @test.fail("the index vanished")
  }
  // ... and the unique quadrant of the removed record is empty again
  match t.indexes.get("lo") {
    Some(index) => assert_ints(index.slots(1), [])
    None => @test.fail("the index vanished")
  }
  // removing the last record leaves no bucket behind at all
  t.remove(b) |> ignore
  match t.indexes.get("shared") {
    Some(index) => @test.assert_eq(index.buckets().length(), 0)
    None => @test.fail("the index vanished")
  }
  check_invariants(t)
}

///|
test "clear drops every bucket but keeps the registrations" {
  let t = wb_indexed_table()
  let a = wb_insert_indexed(t, (1, 10, 7))
  @test.assert_eq(t.indexes.length(), 4)
  t.clear()
  @test.assert_eq(t.indexes.length(), 4) // the schema survives a clear
  match t.indexes.get("lo") {
    Some(index) => {
      @test.assert_eq(index.buckets().length(), 0)
      assert_ints(index.slots(1), [])
    }
    None => @test.fail("the registration was dropped")
  }
  @test.assert_eq(t.get(a), None)
  check_invariants(t)
}

///|
test "a stale handle cannot touch the index entries of the new occupant" {
  let t = wb_indexed_table()
  let old = wb_insert_indexed(t, (1, 10, 7))
  t.remove(old) |> ignore
  let fresh = wb_insert_indexed(t, (1, 20, 8))
  @test.assert_eq(fresh.slot, old.slot)
  // the stale handle is rejected, and every index still names the new record
  @test.assert_eq(t.remove(old), None)
  match t.indexes.get("lo") {
    Some(index) => assert_ints(index.slots(1), [fresh.slot])
    None => @test.fail("the index vanished")
  }
  match t.indexes.get("shared") {
    Some(index) => {
      assert_ints(index.slots(8), [fresh.slot])
      assert_ints(index.slots(7), []) // the old record left no trace
    }
    None => @test.fail("the index vanished")
  }
  check_invariants(t)
}

///|
test "a failed backfill leaves the registry and the buckets untouched" {
  let t : Table[Int, Int] = Table::new()
  let a = wb_insert(t, 1)
  let b = wb_insert(t, 11)
  check_invariants(t)
  let before = t.indexes.length()
  match t.register_unique("low_digit", fn(v) { v % 10 }) {
    Ok(_) => @test.fail("the backfill must report the duplicate key")
    Err(_) => ()
  }
  // white-box: nothing was published into the registry — not even partially
  @test.assert_eq(t.indexes.length(), before)
  @test.assert_eq(t.index_names().length(), 0)
  check_invariants(t)
  @test.assert_eq(t.get(a), Some(1))
  @test.assert_eq(t.get(b), Some(11))
  // the data is still intact enough to accept a non-conflicting registration
  match t.register_unique("by_ten", fn(v) { v / 10 }) {
    Ok(_) => ()
    Err(_) => @test.fail("registration unexpectedly failed")
  }
  @test.assert_eq(t.indexes.length(), 1)
  check_invariants(t)
}

///|
test "with_capacity pre-fills the free stack, highest slot first" {
  let t : Table[Int, Int] = Table::with_capacity(4)
  @test.assert_eq(t.rows.length(), 4)
  @test.assert_eq(t.gens.length(), 4)
  assert_ints(t.gens, [0, 0, 0, 0])
  // LIFO: slot 0 is on top, so allocation hands slots out in ascending order
  assert_ints(t.free, [3, 2, 1, 0])
  check_invariants(t)
  let a = wb_insert(t, 1)
  @test.assert_eq(a.slot, 0)
  assert_ints(t.free, [3, 2, 1])
  @test.assert_eq(t.order.length(), 1)
  check_invariants(t)
}

// ---------------------------------------------------------------------------
// M3: the fast path has to be *shown*, not asserted
// ---------------------------------------------------------------------------

///|
/// A key that counts how often it is hashed.
///
/// Every bucket operation (`get` / `set` / `remove`) hashes its key, so this
/// counter is a direct white-box measure of "did that index touch a bucket?" —
/// exactly what the equal-key fast path must be shown to avoid. `counter` is a
/// one-element array: a mutable cell shared by every copy of the key.
struct CountedKey {
  value : Int
  counter : Array[Int]
} derive(Debug)

///|
impl Eq for CountedKey with fn equal(self, other) {
  self.value == other.value
}

///|
impl Compare for CountedKey with fn compare(self, other) {
  self.value.compare(other.value)
}

///|
impl Hash for CountedKey with fn hash_combine(self, hasher) {
  self.counter[0] = self.counter[0] + 1
  Hash::hash_combine(self.value, hasher)
}

///|
/// A `(lo, hi, shared)` table whose keys are `CountedKey`s sharing `counter`.
fn counted_table(
  counter : Array[Int],
) -> Table[CountedKey, (Int, Int, Int)] raise {
  let t : Table[CountedKey, (Int, Int, Int)] = Table::new()
  let registrations : Array[Result[Unit, RegisterError[CountedKey]]] = [
    t.register_unique("lo", fn(p) { { value: p.0, counter, } }),
    t.register_unique_ordered("hi", fn(p) { { value: p.1, counter, } }),
    t.register_non_unique("shared", fn(p) { { value: p.2, counter, } }),
    t.register_non_unique_ordered("shared_sorted", fn(p) {
      { value: p.2, counter, }
    }),
  ]
  let mut i = 0
  while i < registrations.length() {
    match registrations[i] {
      Ok(_) => ()
      Err(_) => @test.fail("registration unexpectedly failed")
    }
    i = i + 1
  }
  t
}

///|
test "fast path: an update with unchanged keys performs no bucket work" {
  let counter : Array[Int] = [0]
  let t = counted_table(counter)
  let id = match t.insert((1, 10, 7)) {
    Ok(id) => id
    Err(_) => @test.fail("the first insert cannot conflict")
  }
  // control experiment: a lookup really does hash its key, so the counter is a
  // usable probe — without this the rest of the test could be vacuous
  let probe = counter[0]
  let hit = t.get_by("lo", { value: 1, counter, })
  match hit {
    Some(_) => ()
    None => @test.fail("the record should be in the index")
  }
  @test.assert_eq(counter[0] > probe, true)
  // (1) rewriting the record with its own keys must not touch a single bucket:
  // only the uniqueness pre-check hashes anything
  let before_same = counter[0]
  match t.update(id, (1, 10, 7)) {
    Ok(_) => ()
    Err(_) =>
      @test.fail("rewriting a record with its own keys is not a conflict")
  }
  let same_delta = counter[0] - before_same
  @test.assert_eq(same_delta > 0, true) // the pre-check did hash
  // (2) moving one shared key really does re-index that bucket
  let before_moved = counter[0]
  match t.update(id, (1, 10, 9)) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal update must succeed")
  }
  let moved_delta = counter[0] - before_moved
  // both runs paid for the same pre-check; only the moved one paid for buckets
  @test.assert_eq(moved_delta > same_delta, true)
}

///|
test "fast path: a sabotaged bucket proves the equal-key update never consults it" {
  let t = wb_indexed_table()
  let id = wb_insert_indexed(t, (1, 10, 7))
  check_invariants(t)
  // sabotage: empty the "lo" bucket behind the table\u2019s back. A slow path would
  // call `Index::remove` on it — which aborts on a missing bucket — or repopulate
  // it through `add`; the fast path must leave it exactly as it was.
  match t.indexes.get("lo") {
    Some(HashUnique(_, buckets)) => buckets.clear()
    _ => @test.fail("the index vanished")
  }
  match t.update(id, (1, 10, 7)) {
    Ok(_) => ()
    Err(_) =>
      @test.fail("rewriting a record with its own keys is not a conflict")
  }
  match t.indexes.get("lo") {
    Some(index) => @test.assert_eq(index.slots(1).length(), 0)
    _ => @test.fail("the index vanished")
  }
}

///|
test "an update never replaces a bucket container" {
  let t = wb_indexed_table()
  let id = wb_insert_indexed(t, (1, 10, 7))
  let before : Map[Int, @sorted_set.SortedSet[Int]] = match
    t.indexes.get("shared") {
    Some(HashMulti(_, buckets)) => buckets
    _ => @test.fail("the index vanished")
  }
  match t.update(id, (1, 10, 9)) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal update must succeed")
  }
  let after : Map[Int, @sorted_set.SortedSet[Int]] = match
    t.indexes.get("shared") {
    Some(HashMulti(_, buckets)) => buckets
    _ => @test.fail("the index vanished")
  }
  // the registry still holds the very same container object, not a rebuilt one
  @test.assert_eq(physical_equal(before, after), true)
}

///|
test "update and modify keep the storage invariants intact" {
  let t = wb_indexed_table()
  let a = wb_insert_indexed(t, (1, 10, 7))
  let b = wb_insert_indexed(t, (2, 20, 7))
  check_invariants(t)
  match t.update(a, (1, 10, 9)) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal update must succeed")
  }
  check_invariants(t)
  match t.modify(b, fn(record) { (record.0, 21, record.2) }) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal modify must succeed")
  }
  check_invariants(t)
  // a refused update leaves the table exactly as it was
  match t.update(a, (2, 11, 9)) {
    Ok(_) => @test.fail("2 belongs to b")
    Err(_) => ()
  }
  check_invariants(t)
  match t.get(a) {
    Some(value) => @test.assert_eq(value, (1, 10, 9))
    None => @test.fail("a vanished")
  }
  match t.get(b) {
    Some(value) => @test.assert_eq(value, (2, 21, 7))
    None => @test.fail("b vanished")
  }
}

// ---------------------------------------------------------------------------
// M4: the testable half of the failure classification
// ---------------------------------------------------------------------------

///|
/// docs/SPEC.md §7.1 turns two caller mistakes into `abort`s: an unknown index name
/// and a range query on a hash index. A MoonBit `abort` cannot be caught in-process
/// (it is a panic, not an `Error`), so the *decisions* are pinned here — `is_ordered`
/// is the white-box half, `Table::has_index` (see `table_test.mbt`) the public one —
/// while the `abort` lines themselves stay one-liners justified by code review.
test "is_ordered is true only for the two sorted quadrants" {
  let t = wb_indexed_table()
  match t.indexes.get("lo") {
    Some(index) => @test.assert_eq(index.is_ordered(), false)
    None => @test.fail("the index vanished")
  }
  match t.indexes.get("hi") {
    Some(index) => @test.assert_eq(index.is_ordered(), true)
    None => @test.fail("the index vanished")
  }
  match t.indexes.get("shared") {
    Some(index) => @test.assert_eq(index.is_ordered(), false)
    None => @test.fail("the index vanished")
  }
  match t.indexes.get("shared_sorted") {
    Some(index) => @test.assert_eq(index.is_ordered(), true)
    None => @test.fail("the index vanished")
  }
}

// ---------------------------------------------------------------------------
// M5: what the public checker actually says
// ---------------------------------------------------------------------------

///|
test "verify_invariants names I6 and the offending slot" {
  let t = wb_indexed_table()
  let a = wb_insert_indexed(t, (1, 10, 7))
  let b = wb_insert_indexed(t, (2, 20, 7))
  t.remove(b) |> ignore
  t.free.push(b.slot) // corrupt I6: the same slot twice on `free`
  match t.verify_invariants() {
    Ok(_) => @test.fail("a duplicated free slot must be reported")
    Err(message) => {
      @test.assert_eq(message.contains("I6"), true)
      @test.assert_eq(message.contains(b.slot.to_string()), true)
    }
  }
  ignore(a)
}

///|
test "verify_invariants names I7 when an index loses an entry" {
  let t = wb_indexed_table()
  let a = wb_insert_indexed(t, (1, 10, 7))
  // drop the record's bucket from the unique "lo" index behind the table's back
  match t.indexes.get("lo") {
    Some(HashUnique(_, buckets)) => buckets.remove(1)
    _ => @test.fail("the index vanished")
  }
  match t.verify_invariants() {
    Ok(_) => @test.fail("a missing index entry must be reported")
    Err(message) => {
      @test.assert_eq(message.contains("I7"), true)
      @test.assert_eq(message.contains("lo"), true)
    }
  }
  ignore(a)
}

///|
test "verify_invariants names I4, the bucket key and the real projection" {
  let t = wb_indexed_table()
  let a = wb_insert_indexed(t, (1, 10, 7))
  // move the slot into a bucket for a key it does not project to. The entry count
  // stays equal, so the I7 counting check cannot fire first and I4 is what reports.
  match t.indexes.get("lo") {
    Some(HashUnique(_, buckets)) => {
      buckets.remove(1)
      buckets.set(999, a.slot)
    }
    _ => @test.fail("the index vanished")
  }
  match t.verify_invariants() {
    Ok(_) => @test.fail("a mis-keyed bucket must be reported")
    Err(message) => {
      @test.assert_eq(message.contains("I4"), true)
      @test.assert_eq(message.contains("999"), true)
      @test.assert_eq(message.contains("lo"), true)
    }
  }
}

///|
/// I5 (a unique bucket never holds two slots) and I3 (no slot twice in one bucket)
/// are **structural** in this representation: a unique quadrant stores `Map[K, Int]`
/// and a bucket of a non-unique one is a `SortedSet[Int]`, so neither corruption can
/// be constructed from the inside. The checker keeps both as defensive cross-checks
/// (docs/SPEC.md §4 says so for I3); this test pins the structure that makes them
/// unreachable, so a future representation change cannot silently drop the guard.
test "the unique quadrants cannot expose a bucket with two slots (I5 holds by construction)" {
  let t = wb_indexed_table()
  wb_insert_indexed(t, (1, 10, 7)) |> ignore
  wb_insert_indexed(t, (2, 20, 7)) |> ignore
  wb_insert_indexed(t, (3, 30, 8)) |> ignore
  let mut unique_checked = 0
  for _, index in t.indexes {
    if index.is_unique() {
      let buckets = index.buckets()
      let mut i = 0
      while i < buckets.length() {
        @test.assert_eq(buckets[i].1.length(), 1)
        i = i + 1
      }
      unique_checked = unique_checked + 1
    }
  }
  @test.assert_eq(unique_checked, 2)
  // ... while the non-unique quadrant really does hold a two-slot bucket, so the
  // assertion above is not vacuous by accident of the fixture
  @test.assert_eq(t.index_stats("shared").longest_bucket, 2)
  @test.assert_eq(t.index_stats("shared_sorted").longest_bucket, 2)
}
