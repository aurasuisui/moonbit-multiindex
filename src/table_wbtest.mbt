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
      @test.assert_eq(index_buckets(index).length(), 1)
    }
    None => @test.fail("the index vanished")
  }
  // removing one record shrinks the bucket ...
  t.remove(a) |> ignore
  match t.indexes.get("shared") {
    Some(index) => {
      assert_ints(index.slots(7), [b.slot])
      @test.assert_eq(index_buckets(index).length(), 1)
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
    Some(index) => @test.assert_eq(index_buckets(index).length(), 0)
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
      @test.assert_eq(index_buckets(index).length(), 0)
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
