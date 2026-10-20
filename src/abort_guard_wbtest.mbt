// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// THE test "panic ..." SUITE FOR THE ABORT GUARDS.
//
// These lines used to be called untestable: "a MoonBit panic is not an Error,
// so an abort cannot be observed in-process". The premise is right, the
// conclusion is not: moon test gives every test whose NAME starts with
// "panic " the negative property "this test must panic", and a trapped instance
// satisfies it, so the guards are observable after all.
//
// The framework property is only as strong as the fixture, though: the same
// convention also passes when the FIXTURE panics first, or when one of the
// test's own precondition assertions fails. Two rules keep that from hiding a
// deleted guard:
//
// 1. A panic test has exactly two parts: a fixture builder, then one trigger
//    call. Every precondition (record value, check_invariants, index name,
//    bucket contents) is asserted inside the builder, BEFORE the sabotage that
//    puts the table into the state the guard refuses, so the trigger call is the
//    only statement left that can panic. The trigger is the test's last
//    statement.
// 2. Every builder is ALSO run by an ordinary-named companion test at the bottom
//    of this file. If a builder ever stops building the state it describes, the
//    companion fails loudly instead of the panic test passing for the wrong
//    reason.
//
// Negative property (framework-provided, nothing to assert here): delete or
// relax a guard and its test no longer panics, so moon test reports
// "panic is expected" and the suite turns red. The property was checked by
// deleting guards in a scratch copy of this package; for the guards whose removal
// would not compile (a match arm that has to produce the function's value) the
// property is that of the relaxation an author would write: answering a
// placeholder instead of aborting.

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

///|
/// Whether an optional value is None.
///
/// @test.assert_eq needs Debug, which Option does not implement in core, so
/// optional results are asserted through predicates instead.
fn[T] ag_none(value : T?) -> Bool {
  match value {
    None => true
    Some(_) => false
  }
}

///|
/// Whether an optional value is Some(_).
fn[T] ag_some(value : T?) -> Bool {
  match value {
    None => false
    Some(_) => true
  }
}

///|
/// The four index quadrants, as a fixture selector.
priv enum AgQuadrant {
  AgHashUnique
  AgSortedUnique
  AgHashMulti
  AgSortedMulti
}

///|
/// Insert value, failing if a table the fixture just built refuses the write.
fn ag_insert(t : Table[Int32, Int32], value : Int32) -> RowId raise {
  match t.insert(value) {
    Ok(id) => id
    Err(_) => @test.fail("fixture: a write with free keys must succeed")
  }
}

///|
/// A table with exactly one live record (7, slot 0) and one index u over its key,
/// in the given quadrant.
///
/// This is the legal state every Index::remove fixture starts from; each caller
/// then sabotages exactly one thing. check_invariants proves the table really is
/// legal before the sabotage, so no guard can be reached through an
/// already-broken table.
fn ag_one_record(quadrant : AgQuadrant) -> (Table[Int32, Int32], RowId) raise {
  let t : Table[Int32, Int32] = Table::new()
  let registered = match quadrant {
    AgHashUnique => t.register_unique("u", fn(value) { value })
    AgSortedUnique => t.register_unique_ordered("u", fn(value) { value })
    AgHashMulti => t.register_non_unique("u", fn(value) { value })
    AgSortedMulti => t.register_non_unique_ordered("u", fn(value) { value })
  }
  match registered {
    Ok(_) => ()
    Err(_) => @test.fail("fixture: registration on an empty table must succeed")
  }
  let id = ag_insert(t, 7)
  check_invariants(t)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(id.slot, 0)
  @test.assert_eq(t.order.length(), 1)
  @test.assert_eq(t.has_index("u"), true)
  @test.assert_eq(t.indexes.length(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Slot the unique bucket for key currently names (unique quadrants only).
fn ag_holder(t : Table[Int32, Int32], key : Int32) -> Int32? raise {
  match t.indexes.get("u") {
    Some(index) => index.holder(key)
    None => @test.fail("fixture: index u vanished")
  }
}

///|
/// Slots stored under key, ascending: the quadrant-agnostic view of a bucket.
fn ag_slots(t : Table[Int32, Int32], key : Int32) -> Array[Int32] raise {
  match t.indexes.get("u") {
    Some(index) => index.slots(key)
    None => @test.fail("fixture: index u vanished")
  }
}

///|
/// Whether a MULTI bucket for key still exists, whatever it holds.
fn ag_has_multi_bucket(t : Table[Int32, Int32], key : Int32) -> Bool raise {
  match t.indexes.get("u") {
    Some(HashMulti(_, buckets)) => ag_some(buckets.get(key))
    Some(SortedMulti(_, buckets)) => ag_some(buckets.get(key))
    _ => @test.fail("fixture: u must be one of the multi quadrants here")
  }
}

///|
/// Whether a MULTI bucket for key holds slot.
fn ag_multi_bucket_holds(
  t : Table[Int32, Int32],
  key : Int32,
  slot : Int32,
) -> Bool raise {
  match t.indexes.get("u") {
    Some(HashMulti(_, buckets)) =>
      match buckets.get(key) {
        Some(set) => set.contains(slot)
        None => false
      }
    Some(SortedMulti(_, buckets)) =>
      match buckets.get(key) {
        Some(set) => set.contains(slot)
        None => false
      }
    _ => @test.fail("fixture: u must be one of the multi quadrants here")
  }
}

// ---------------------------------------------------------------------------
// index.mbt: Index::remove refuses a bucket that disagrees with the row
// ---------------------------------------------------------------------------

///|
/// Hash-unique bucket for key 7 names slot 9, not the record's own slot 0.
fn ag_fx_hash_unique_foreign_slot() -> (Table[Int32, Int32], RowId) raise {
  let (t, id) = ag_one_record(AgHashUnique)
  match ag_holder(t, 7) {
    Some(slot) => @test.assert_eq(slot, 0)
    None => @test.fail("fixture: the unique bucket must hold the record's slot")
  }
  // sabotage: the bucket names a slot that is not the record's
  match t.indexes.get("u") {
    Some(HashUnique(_, buckets)) => buckets.set(7, 9)
    _ => @test.fail("fixture: u must be the hash-unique quadrant")
  }
  match ag_holder(t, 7) {
    Some(slot) => @test.assert_eq(slot, 9)
    None => @test.fail("fixture: the sabotaged bucket must still exist")
  }
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): with the guard gone, remove would delete the
/// foreign bucket, return Some 7 and leak slot 9's entry, so this test would fail
/// with "panic is expected".
test "panic Index::remove aborts when a hash-unique bucket names a foreign slot" {
  let (t, id) = ag_fx_hash_unique_foreign_slot()
  t.remove(id) |> ignore
}

///|
/// Hash-unique bucket for key 7 is gone although the record is still live.
fn ag_fx_hash_unique_missing() -> (Table[Int32, Int32], RowId) raise {
  let (t, id) = ag_one_record(AgHashUnique)
  match ag_holder(t, 7) {
    Some(slot) => @test.assert_eq(slot, 0)
    None => @test.fail("fixture: the unique bucket must hold the record's slot")
  }
  // sabotage: the bucket is gone, the record is not
  match t.indexes.get("u") {
    Some(HashUnique(_, buckets)) => buckets.remove(7)
    _ => @test.fail("fixture: u must be the hash-unique quadrant")
  }
  @test.assert_eq(ag_none(ag_holder(t, 7)), true)
  @test.assert_eq(ag_slots(t, 7).length(), 0)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): with the guard gone, remove would silently
/// succeed and leave the reverse lookup lying, so this test would fail with
/// "panic is expected".
test "panic Index::remove aborts when a hash-unique bucket is missing" {
  let (t, id) = ag_fx_hash_unique_missing()
  t.remove(id) |> ignore
}

///|
/// Sorted-unique bucket for key 7 names slot 9.
fn ag_fx_sorted_unique_foreign_slot() -> (Table[Int32, Int32], RowId) raise {
  let (t, id) = ag_one_record(AgSortedUnique)
  match ag_holder(t, 7) {
    Some(slot) => @test.assert_eq(slot, 0)
    None => @test.fail("fixture: the unique bucket must hold the record's slot")
  }
  match t.indexes.get("u") {
    Some(SortedUnique(_, buckets)) => buckets.set(7, 9)
    _ => @test.fail("fixture: u must be the sorted-unique quadrant")
  }
  match ag_holder(t, 7) {
    Some(slot) => @test.assert_eq(slot, 9)
    None => @test.fail("fixture: the sabotaged bucket must still exist")
  }
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): a deleted guard leaves the foreign bucket in
/// the sorted map and remove returns Some 7, so this test fails with
/// "panic is expected".
test "panic Index::remove aborts when a sorted-unique bucket names a foreign slot" {
  let (t, id) = ag_fx_sorted_unique_foreign_slot()
  t.remove(id) |> ignore
}

///|
/// Sorted-unique bucket for key 7 is gone although the record is still live.
fn ag_fx_sorted_unique_missing() -> (Table[Int32, Int32], RowId) raise {
  let (t, id) = ag_one_record(AgSortedUnique)
  match ag_holder(t, 7) {
    Some(slot) => @test.assert_eq(slot, 0)
    None => @test.fail("fixture: the unique bucket must hold the record's slot")
  }
  match t.indexes.get("u") {
    Some(SortedUnique(_, buckets)) => buckets.remove(7)
    _ => @test.fail("fixture: u must be the sorted-unique quadrant")
  }
  @test.assert_eq(ag_none(ag_holder(t, 7)), true)
  @test.assert_eq(ag_slots(t, 7).length(), 0)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): without the guard the removal succeeds although
/// the index has nothing to drop, so this test fails with "panic is expected".
test "panic Index::remove aborts when a sorted-unique bucket is missing" {
  let (t, id) = ag_fx_sorted_unique_missing()
  t.remove(id) |> ignore
}

///|
/// Hash-multi bucket for key 7 exists but no longer lists the record's slot 0.
fn ag_fx_hash_multi_membership() -> (Table[Int32, Int32], RowId) raise {
  let (t, id) = ag_one_record(AgHashMulti)
  @test.assert_eq(ag_multi_bucket_holds(t, 7, 0), true)
  @test.assert_eq(ag_slots(t, 7).length(), 1)
  // sabotage: the bucket stays, only its membership is broken
  match t.indexes.get("u") {
    Some(HashMulti(_, buckets)) =>
      match buckets.get(7) {
        Some(set) => set.remove(0)
        None => @test.fail("fixture: the multi bucket must exist")
      }
    _ => @test.fail("fixture: u must be the hash-multi quadrant")
  }
  @test.assert_eq(ag_has_multi_bucket(t, 7), true)
  @test.assert_eq(ag_multi_bucket_holds(t, 7, 0), false)
  @test.assert_eq(ag_slots(t, 7).length(), 0)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): a deleted guard would silently leave the record
/// in no bucket at all and return Some 7, so this test fails with
/// "panic is expected".
test "panic Index::remove aborts when a hash-multi bucket does not hold the slot" {
  let (t, id) = ag_fx_hash_multi_membership()
  t.remove(id) |> ignore
}

///|
/// Hash-multi bucket for key 7 is gone although the record is still live.
fn ag_fx_hash_multi_missing() -> (Table[Int32, Int32], RowId) raise {
  let (t, id) = ag_one_record(AgHashMulti)
  @test.assert_eq(ag_multi_bucket_holds(t, 7, 0), true)
  match t.indexes.get("u") {
    Some(HashMulti(_, buckets)) => buckets.remove(7)
    _ => @test.fail("fixture: u must be the hash-multi quadrant")
  }
  @test.assert_eq(ag_has_multi_bucket(t, 7), false)
  @test.assert_eq(ag_slots(t, 7).length(), 0)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): without the guard the removal succeeds and the
/// missing reverse entry stays missing, so this test fails with
/// "panic is expected".
test "panic Index::remove aborts when a hash-multi bucket is missing" {
  let (t, id) = ag_fx_hash_multi_missing()
  t.remove(id) |> ignore
}

///|
/// Sorted-multi bucket for key 7 exists but no longer lists slot 0.
fn ag_fx_sorted_multi_membership() -> (Table[Int32, Int32], RowId) raise {
  let (t, id) = ag_one_record(AgSortedMulti)
  @test.assert_eq(ag_multi_bucket_holds(t, 7, 0), true)
  @test.assert_eq(ag_slots(t, 7).length(), 1)
  match t.indexes.get("u") {
    Some(SortedMulti(_, buckets)) =>
      match buckets.get(7) {
        Some(set) => set.remove(0)
        None => @test.fail("fixture: the multi bucket must exist")
      }
    _ => @test.fail("fixture: u must be the sorted-multi quadrant")
  }
  @test.assert_eq(ag_has_multi_bucket(t, 7), true)
  @test.assert_eq(ag_multi_bucket_holds(t, 7, 0), false)
  @test.assert_eq(ag_slots(t, 7).length(), 0)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): a deleted guard would leave the bucket without
/// the record and return Some 7, so this test fails with "panic is expected".
test "panic Index::remove aborts when a sorted-multi bucket does not hold the slot" {
  let (t, id) = ag_fx_sorted_multi_membership()
  t.remove(id) |> ignore
}

///|
/// Sorted-multi bucket for key 7 is gone although the record is still live.
fn ag_fx_sorted_multi_missing() -> (Table[Int32, Int32], RowId) raise {
  let (t, id) = ag_one_record(AgSortedMulti)
  @test.assert_eq(ag_multi_bucket_holds(t, 7, 0), true)
  match t.indexes.get("u") {
    Some(SortedMulti(_, buckets)) => buckets.remove(7)
    _ => @test.fail("fixture: u must be the sorted-multi quadrant")
  }
  @test.assert_eq(ag_has_multi_bucket(t, 7), false)
  @test.assert_eq(ag_slots(t, 7).length(), 0)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): without the guard the removal succeeds although
/// the sorted map has no bucket to drop, so this test fails with
/// "panic is expected".
test "panic Index::remove aborts when a sorted-multi bucket is missing" {
  let (t, id) = ag_fx_sorted_multi_missing()
  t.remove(id) |> ignore
}

// ---------------------------------------------------------------------------
// index.mbt: the cursors refuse to invent an order for a hash quadrant
// ---------------------------------------------------------------------------

///|
/// A well-formed table whose only index is a HASH one, with its record intact.
///
/// The public gate (iter_asc_by / range_by) refuses such an index earlier, in
/// table_api.mbt; the guard tested here is the second line of defence inside the
/// cursor itself, reachable only by calling the cursor directly, which is what a
/// white-box test is for.
fn ag_fx_hash_index() -> Index[Int32, Int32] raise {
  let t : Table[Int32, Int32] = Table::new()
  match t.register_unique("u", fn(value) { value }) {
    Ok(_) => ()
    Err(_) => @test.fail("fixture: registration on an empty table must succeed")
  }
  let id = ag_insert(t, 7)
  check_invariants(t)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(id.slot, 0)
  @test.assert_eq(t.has_index("u"), true)
  match t.indexes.get("u") {
    Some(index) => {
      // the predicate the public gate consults: a hash quadrant has no key order
      @test.assert_eq(index.is_ordered(), false)
      @test.assert_eq(index.is_unique(), true)
      index
    }
    None => @test.fail("fixture: index u vanished")
  }
}

///|
/// Negative property (framework): a deleted guard would return a cursor over a
/// hash index (empty, since the hash quadrant has no range to walk) instead of
/// aborting, so this test fails with "panic is expected".
test "panic range_cursor aborts on a hash index instead of answering unordered" {
  let index = ag_fx_hash_index()
  index.range_cursor(0, 10, true) |> ignore
}

///|
/// Negative property (framework): a deleted guard would hand back a cursor whose
/// first step is None, indistinguishable from an empty index, so this test fails
/// with "panic is expected".
test "panic ordered_cursor aborts on a hash index instead of answering unordered" {
  let index = ag_fx_hash_index()
  index.ordered_cursor(false) |> ignore
}

// ---------------------------------------------------------------------------
// table.mbt: defensive reads (record_at / iter), not aborts
// ---------------------------------------------------------------------------

///|
/// record_at must answer None for a slot that is not even in the slot arrays.
/// The public callers only pass slots taken from order or a bucket, so this bound
/// only fires on a corrupted table: it returns, it does not abort.
test "record_at answers None for a slot past the end of the slot arrays" {
  let t : Table[Int32, Int32] = Table::new()
  @test.assert_eq(t.rows.length(), 0)
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(ag_none(t.record_at(0)), true)
}

///|
/// record_at must answer None for a slot that is in range but vacant (a removed
/// record). Also unreachable through the public API while the order invariant
/// holds, so it is a defensive return rather than an abort.
test "record_at answers None for a slot whose record was removed" {
  let t : Table[Int32, Int32] = Table::new()
  let id = ag_insert(t, 1)
  check_invariants(t)
  match t.remove(id) {
    Some(1) => ()
    _ => @test.fail("fixture: removing a live record must return it")
  }
  check_invariants(t)
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.rows.length(), 1)
  @test.assert_eq(ag_none(t.rows[id.slot]), true)
  @test.assert_eq(ag_none(t.record_at(id.slot)), true)
}

///|
/// A live iterator over a table that is then mutated, with the fail-fast key
/// (version) proven to have moved before the trigger.
fn ag_fx_iter_mutated() -> Iter2[RowId, Int32] raise {
  let t : Table[Int32, Int32] = Table::new()
  ag_insert(t, 1) |> ignore
  ag_insert(t, 2) |> ignore
  check_invariants(t)
  @test.assert_eq(t.len(), 2)
  let it = t.iter()
  // consume one record: the iterator is live and positioned inside order
  it.next() |> ignore
  let version = t.version
  match t.insert(3) {
    Ok(_) => ()
    Err(_) =>
      @test.fail("fixture: a table with no index cannot reject the write")
  }
  @test.assert_eq(t.len(), 3)
  @test.assert_eq(t.version, version + 1) // the fail-fast key really moved
  it
}

///|
/// Negative property (framework): a deleted guard would keep walking the old
/// order array and yield the third record, so this test fails with
/// "panic is expected".
test "panic iter aborts when the table is mutated during iteration" {
  let it = ag_fx_iter_mutated()
  it.next() |> ignore
}

///|
/// iter must step over an order entry whose record is gone instead of yielding a
/// None row. Unreachable while the order invariant I1 holds, hence a defensive
/// continue and a plain test rather than a panic test.
test "iter steps over an order entry whose record is gone" {
  let t : Table[Int32, Int32] = Table::new()
  let id = ag_insert(t, 1)
  check_invariants(t)
  t.rows[id.slot] = None // sabotage: order still names the slot
  @test.assert_eq(t.order.length(), 1)
  @test.assert_eq(t.order[0], id.slot)
  @test.assert_eq(t.len(), 1) // len is stale on purpose: the walker uses order
  let it = t.iter()
  @test.assert_eq(ag_none(it.next()), true)
}

// ---------------------------------------------------------------------------
// table.mbt: the order bookkeeping refuses a slot it cannot find
// ---------------------------------------------------------------------------

///|
/// A live record that order has already forgotten (its positions entry is still
/// 0, which is exactly the disagreement the guard refuses).
fn ag_fx_order_forgot_slot() -> (Table[Int32, Int32], RowId) raise {
  let t : Table[Int32, Int32] = Table::new()
  let id = ag_insert(t, 1)
  check_invariants(t)
  @test.assert_eq(t.order.length(), 1)
  @test.assert_eq(t.positions[id.slot], 0)
  t.order.clear() // sabotage: order forgets the live slot
  @test.assert_eq(t.order.length(), 0)
  @test.assert_eq(t.positions[id.slot], 0)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): with the guard gone the compaction loop would
/// simply not find the slot, order would stay empty while the row is dropped, and
/// this test fails with "panic is expected".
test "panic remove aborts when order has already forgotten the live slot" {
  let (t, id) = ag_fx_order_forgot_slot()
  t.remove(id) |> ignore
}

///|
/// A live record whose positions entry is the -1 sentinel and whose order is
/// empty: the guard refuses the missing position, and a deleted guard would find
/// last = -1, skip the move, pop an empty order and return normally.
fn ag_fx_order_position_lost() -> (Table[Int32, Int32], RowId) raise {
  let t : Table[Int32, Int32] = Table::new()
  let id = ag_insert(t, 1)
  check_invariants(t)
  @test.assert_eq(t.positions[id.slot], 0)
  @test.assert_eq(t.order.length(), 1)
  t.order.clear() // sabotage: the slot lost its order position
  t.positions[id.slot] = -1
  @test.assert_eq(t.positions[id.slot], -1)
  @test.assert_eq(t.order.length(), 0)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(ag_some(t.get(id)), true)
  (t, id)
}

///|
/// Negative property (framework): with the guard deleted, pos = -1 is treated as
/// an ordinary position and the removal returns normally instead of aborting (the
/// empty order makes that path reach a no-op pop rather than a trap), so this test
/// fails with "panic is expected".
test "panic swap_remove aborts when the slot has no position in order" {
  let (t, id) = ag_fx_order_position_lost()
  t.swap_remove(id) |> ignore
}

// ---------------------------------------------------------------------------
// table.mbt: the commit chokepoints refuse a vacant slot
// ---------------------------------------------------------------------------

///|
/// A legal, empty table whose one slot was vacated by an ordinary removal: the
/// slot is on free, order is empty, and rows[0] is None.
///
/// Returning the slot lets the two chokepoint tests call the private entry points
/// with the exact slot they asserted.
fn ag_fx_vacant_slot() -> (Table[Int32, Int32], Int32) raise {
  let t : Table[Int32, Int32] = Table::new()
  let id = ag_insert(t, 1)
  check_invariants(t)
  match t.remove(id) {
    Some(1) => ()
    _ => @test.fail("fixture: removing a live record must return it")
  }
  check_invariants(t)
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.order.length(), 0)
  @test.assert_eq(t.rows.length(), 1)
  @test.assert_eq(t.free.length(), 1)
  @test.assert_eq(t.free[0], id.slot)
  @test.assert_eq(ag_none(t.rows[id.slot]), true)
  (t, id.slot)
}

///|
/// Negative property (framework): remove_impl cannot return a value for a vacant
/// slot, so a deleted guard has no observable outcome but the missing panic; the
/// test then fails with "panic is expected".
test "panic remove_impl aborts when the slot holds no live record" {
  let (t, slot) = ag_fx_vacant_slot()
  t.remove_impl(slot, false) |> ignore
}

///|
/// Negative property (framework): modify_impl refuses the vacant slot before any
/// index work, so this test fails with "panic is expected" if the guard goes
/// away.
test "panic modify_impl aborts when the slot holds no live record" {
  let (t, slot) = ag_fx_vacant_slot()
  t.modify_impl(slot, 42) |> ignore
}

// ---------------------------------------------------------------------------
// table_api.mbt: registration refuses a backfill over a dangling order entry
// ---------------------------------------------------------------------------

///|
/// An empty table whose order array was made to name a vacant slot: the exact
/// disagreement the four register_* backfills refuse before publishing a
/// half-built index.
fn ag_fx_dangling_order_entry() -> Table[Int32, Int32] raise {
  let t : Table[Int32, Int32] = Table::new()
  let id = ag_insert(t, 1)
  check_invariants(t)
  match t.remove(id) {
    Some(1) => ()
    _ => @test.fail("fixture: removing a live record must return it")
  }
  check_invariants(t) // the empty table is legal before the sabotage
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.indexes.length(), 0)
  @test.assert_eq(t.rows.length(), 1)
  t.order.push(id.slot) // sabotage: order names a slot whose record is gone
  @test.assert_eq(t.order.length(), 1)
  @test.assert_eq(t.order[0], id.slot)
  @test.assert_eq(ag_none(t.rows[id.slot]), true)
  t
}

///|
/// Negative property (framework): a deleted guard would publish an index that
/// silently skips the dangling slot, so this test fails with "panic is expected".
test "panic register_unique aborts when order names a slot with no record" {
  let t = ag_fx_dangling_order_entry()
  t.register_unique("u", fn(value) { value }) |> ignore
}

///|
/// Negative property (framework): same negative property in the sorted-unique
/// quadrant, where a deleted guard publishes the index instead of aborting, so
/// this test fails with "panic is expected".
test "panic register_unique_ordered aborts when order names a slot with no record" {
  let t = ag_fx_dangling_order_entry()
  t.register_unique_ordered("u", fn(value) { value }) |> ignore
}

///|
/// Negative property (framework): same negative property in the hashed non-unique
/// quadrant, where a deleted guard publishes the index instead of aborting, so
/// this test fails with "panic is expected".
test "panic register_non_unique aborts when order names a slot with no record" {
  let t = ag_fx_dangling_order_entry()
  t.register_non_unique("u", fn(value) { value }) |> ignore
}

///|
/// Negative property (framework): same negative property in the sorted non-unique
/// quadrant, where a deleted guard publishes the index instead of aborting, so
/// this test fails with "panic is expected".
test "panic register_non_unique_ordered aborts when order names a slot with no record" {
  let t = ag_fx_dangling_order_entry()
  t.register_non_unique_ordered("u", fn(value) { value }) |> ignore
}

// ---------------------------------------------------------------------------
// Companion executions: a panic test cannot fail on a broken fixture, so the
// fixtures are rebuilt here, under ordinary names. If any assertion inside a
// builder stops holding, one of these tests fails and the suite is red.
// ---------------------------------------------------------------------------

///|
/// Rebuild every Index::remove fixture.
test "every Index::remove fixture builds the state its guard describes" {
  ag_fx_hash_unique_foreign_slot() |> ignore
  ag_fx_hash_unique_missing() |> ignore
  ag_fx_sorted_unique_foreign_slot() |> ignore
  ag_fx_sorted_unique_missing() |> ignore
  ag_fx_hash_multi_membership() |> ignore
  ag_fx_hash_multi_missing() |> ignore
  ag_fx_sorted_multi_membership() |> ignore
  ag_fx_sorted_multi_missing() |> ignore
}

///|
/// Rebuild the cursor fixture.
test "every cursor fixture exposes a hash-quadrant index" {
  ag_fx_hash_index() |> ignore
}

///|
/// Rebuild the fail-fast and order-bookkeeping fixtures.
test "every chokepoint fixture builds the state its guard describes" {
  ag_fx_iter_mutated() |> ignore
  ag_fx_order_forgot_slot() |> ignore
  ag_fx_order_position_lost() |> ignore
  ag_fx_vacant_slot() |> ignore
}

///|
/// Rebuild the registration fixture.
test "every registration fixture puts a dangling slot in order" {
  ag_fx_dangling_order_entry() |> ignore
}
