// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Black-box tests for `Table::rebuild_index` (v0.4.0 M2, docs/SPEC.md §3.1).
//
// The point of the method is repair: the records are the source of truth, so an
// index left stale by an external mutation (docs/SPEC.md §3.7, I4) can be
// re-derived in one step instead of `unregister_index` + fix + `register_*`.
// The fixtures below therefore all go *through* the public API and then dirty the
// table the documented way: a record read back from the table shares its
// `Array[Int32]` field with the stored one, so writing to it desynchronizes the
// buckets (`Rec` and `insert_ok` / `assert_registered` / `assert_invariants`
// live in the same black-box package, in `table_test.mbt`).

///|
/// What the index under `name` answers for `key`, reduced to the handle and the
/// record's **current** projection — a whole `Rec` has no `Eq`/`Debug`, so probe
/// results are compared through this shape.
fn rb_probe(
  t : @aurasuisui/multiindex.Table[Int32, Rec],
  name : String,
  key : Int32,
) -> (@aurasuisui/multiindex.RowId, Int32)? {
  match t.get_by(name, key) {
    Some((id, record)) => Some((id, record.tags[0]))
    None => None
  }
}

///|
/// The handles a walk yields, in walk order.
fn rb_ids(
  rows : Array[(@aurasuisui/multiindex.RowId, Rec)],
) -> Array[@aurasuisui/multiindex.RowId] {
  let ids : Array[@aurasuisui/multiindex.RowId] = []
  let mut i = 0
  while i < rows.length() {
    ids.push(rows[i].0)
    i = i + 1
  }
  ids
}

///|
/// Element-wise handle comparison: `Array` has no `Eq`/`Debug` instance, so
/// `assert_eq` on the arrays is not available.
fn rb_assert_ids(
  actual : Array[@aurasuisui/multiindex.RowId],
  expected : Array[@aurasuisui/multiindex.RowId],
) -> Unit raise {
  @test.assert_eq(actual.length(), expected.length())
  let mut i = 0
  while i < expected.length() {
    @test.assert_eq(actual[i], expected[i])
    i = i + 1
  }
}

///|
/// `iter()` before/after comparison, item by item (same reason: no `Eq` on
/// arrays).
fn[V : Eq + Debug] rb_assert_same_rows(
  before : Array[(@aurasuisui/multiindex.RowId, V)],
  after : Array[(@aurasuisui/multiindex.RowId, V)],
) -> Unit raise {
  @test.assert_eq(after.length(), before.length())
  let mut i = 0
  while i < before.length() {
    @test.assert_eq(after[i].0, before[i].0)
    @test.assert_eq(after[i].1, before[i].1)
    i = i + 1
  }
}

///|
/// Test 1: on a clean table a rebuild is a no-op as far as the outside is
/// concerned — `len`, the insertion-order walk (handles included), the rebuilt
/// index, the untouched index and the bucket statistics all stay identical.
test "rebuild_index on a clean table keeps every observable unchanged" {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique("lo", fn(p) { p.0 }))
  assert_registered(t.register_unique_ordered("hi", fn(p) { p.1 }))
  let a = insert_ok(t, (1, 10))
  let b = insert_ok(t, (2, 20))
  let c = insert_ok(t, (3, 30))
  assert_invariants(t)
  let before_len = t.len()
  let before_rows = t.iter().to_array()
  let before_stats = t.index_stats("lo")
  match t.rebuild_index("lo") {
    Ok(_) => ()
    Err(_) => @test.fail("rebuilding a clean index must succeed")
  }
  @test.assert_eq(t.len(), before_len)
  rb_assert_same_rows(before_rows, t.iter().to_array())
  @test.assert_eq(t.index_stats("lo"), before_stats)
  @test.assert_eq(t.get_by("lo", 1), Some((a, (1, 10))))
  @test.assert_eq(t.get_by("lo", 2), Some((b, (2, 20))))
  @test.assert_eq(t.get_by("lo", 3), Some((c, (3, 30))))
  // the index that was not rebuilt still answers from its own buckets
  @test.assert_eq(t.get_by("hi", 10), Some((a, (1, 10))))
  @test.assert_eq(t.get_by("hi", 20), Some((b, (2, 20))))
  @test.assert_eq(t.get_by("hi", 30), Some((c, (3, 30))))
  assert_invariants(t)
}

///|
/// Test 2: an empty table has nothing to scan, so a rebuild is the empty scan —
/// `Ok`, with the index still registered and still empty. Both an unsorted and a
/// sorted quadrant are covered.
test "rebuild_index on an empty table succeeds" {
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique("u", fn(value) { value }))
  assert_registered(t.register_non_unique_ordered("v", fn(value) { value }))
  match t.rebuild_index("u") {
    Ok(_) => ()
    Err(_) => @test.fail("rebuilding an empty index must succeed")
  }
  match t.rebuild_index("v") {
    Ok(_) => ()
    Err(_) => @test.fail("rebuilding an empty sorted index must succeed")
  }
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.is_empty(), true)
  @test.assert_eq(t.has_index("u"), true)
  @test.assert_eq(t.get_by("u", 1), None)
  @test.assert_eq(t.index_stats("u").entries, 0)
  @test.assert_eq(t.index_stats("v").buckets, 0)
  assert_invariants(t)
}

///|
/// Test 3: the repair this method exists for. A unique index goes stale through an
/// external mutation (I4), the checker reports it, and one rebuild makes the old
/// key stop matching, the new key start matching and the checker answer `Ok`.
test "rebuild_index repairs a unique index gone stale through external mutation" {
  let t : @aurasuisui/multiindex.Table[Int32, Rec] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique("first", fn(r) { r.tags[0] }))
  let a = insert_ok(t, { tags: [1], note: 0, })
  insert_ok(t, { tags: [2], note: 0, }) |> ignore
  // dirty the index the documented way: the array is shared with the stored record
  match t.get(a) {
    Some(r) => r.tags[0] = 5
    None => @test.fail("the fixture record must exist")
  }
  match t.verify_invariants() {
    Ok(_) => @test.fail("the fixture must start dirty: verify must report I4")
    Err(message) => @test.assert_eq(message.contains("I4"), true)
  }
  // the stale bucket still holds the old key, pointing at the mutated record
  match t.get_by("first", 1) {
    Some((id, r)) => {
      @test.assert_eq(id, a)
      @test.assert_eq(r.tags[0], 5)
    }
    None => @test.fail("the stale bucket must still hit the mutated record")
  }
  match t.rebuild_index("first") {
    Ok(_) => ()
    Err(_) =>
      @test.fail("the projections are distinct, so the rebuild must succeed")
  }
  match t.get_by("first", 1) {
    None => ()
    Some(_) => @test.fail("the old key must stop matching after the rebuild")
  }
  match t.get_by("first", 5) {
    Some((id, r)) => {
      @test.assert_eq(id, a)
      @test.assert_eq(r.tags[0], 5)
    }
    None => @test.fail("the new key must match after the rebuild")
  }
  assert_invariants(t)
}

///|
/// Test 4: the `Err` path is atomic. Two records are made to project to the same
/// key (the documented `modify` Err path leaves the record mutated), so the
/// rebuild must refuse — and every key of the old index, plus the bucket order,
/// must answer exactly as before. The dirty state stays dirty: neither better nor
/// worse.
///
/// The sorted unique quadrant is used here so that the bucket order itself is
/// observable (`iter_asc_by`), not just the per-key answers.
test "rebuild_index refuses a duplicate projection and leaves the old index untouched" {
  let t : @aurasuisui/multiindex.Table[Int32, Rec] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique_ordered("first", fn(r) { r.tags[0] }))
  let a = insert_ok(t, { tags: [1], note: 0, })
  insert_ok(t, { tags: [2], note: 0, }) |> ignore
  match
    t.modify(a, fn(r) {
      r.tags[0] = 2
      r
    }) {
    Ok(_) => @test.fail("the duplicate projection must be reported as Err")
    Err(_) => ()
  }
  // snapshot every observable answer of the index before the doomed rebuild
  let before_1 = rb_probe(t, "first", 1)
  let before_2 = rb_probe(t, "first", 2)
  let before_3 = rb_probe(t, "first", 3)
  let before_walk = rb_ids(t.iter_asc_by("first").to_array())
  match t.rebuild_index("first") {
    Ok(_) => @test.fail("two records project to 2, so the rebuild must fail")
    Err(UniqueViolation(_, key)) => @test.assert_eq(key, 2)
    Err(DuplicateName(_)) =>
      @test.fail("a rebuild never reports DuplicateName — the name exists")
  }
  // item by item, nothing moved
  @test.assert_eq(rb_probe(t, "first", 1), before_1)
  @test.assert_eq(rb_probe(t, "first", 2), before_2)
  @test.assert_eq(rb_probe(t, "first", 3), before_3)
  rb_assert_ids(rb_ids(t.iter_asc_by("first").to_array()), before_walk)
  // the refused rebuild did not "fix" the dirty state either
  match t.verify_invariants() {
    Ok(_) => @test.fail("the refused rebuild must not change the dirty state")
    Err(message) => @test.assert_eq(message.contains("I4"), true)
  }
}

///|
/// Test 5: all four quadrants, in one table, rebuilt one by one.
test "rebuild_index rebuilds all four quadrants" {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32, Int32)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique("lo", fn(p) { p.0 }))
  assert_registered(t.register_unique_ordered("hi", fn(p) { p.1 }))
  assert_registered(t.register_non_unique("shared", fn(p) { p.2 }))
  assert_registered(
    t.register_non_unique_ordered("shared_sorted", fn(p) { p.2 }),
  )
  let a = insert_ok(t, (1, 10, 7))
  let b = insert_ok(t, (2, 20, 7))
  let c = insert_ok(t, (3, 30, 8))
  let names : Array[String] = ["lo", "hi", "shared", "shared_sorted"]
  for name in names {
    match t.rebuild_index(name) {
      Ok(_) => ()
      Err(_) =>
        @test.fail("rebuilding a consistent index must succeed: " + name)
    }
  }
  @test.assert_eq(t.get_by("lo", 1), Some((a, (1, 10, 7))))
  @test.assert_eq(t.get_by("lo", 2), Some((b, (2, 20, 7))))
  @test.assert_eq(t.get_by("hi", 30), Some((c, (3, 30, 8))))
  @test.assert_eq(t.iter_by("shared", 7).to_array().length(), 2)
  @test.assert_eq(t.iter_by("shared_sorted", 7).to_array().length(), 2)
  @test.assert_eq(t.get_by("shared", 7), Some((a, (1, 10, 7))))
  @test.assert_eq(t.index_stats("shared").entries, 3)
  @test.assert_eq(t.index_stats("shared_sorted").entries, 3)
  @test.assert_eq(t.len(), 3)
  assert_invariants(t)
}

///|
/// Test 6: the in-flight cursor. Rebuilding replaces the bucket structure as a
/// whole instead of clearing it in place, so an ordered iterator created before
/// the call keeps walking the `SortedMap` snapshot it captured — it finishes, does
/// not abort, and still yields the **old** key order even though the rebuilt index
/// already answers in the new one.
test "rebuild_index leaves an in-flight ordered cursor on its old snapshot" {
  let t : @aurasuisui/multiindex.Table[Int32, Rec] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique_ordered("tags", fn(r) { r.tags[0] }))
  let a = insert_ok(t, { tags: [10], note: 0, })
  let b = insert_ok(t, { tags: [20], note: 0, })
  let c = insert_ok(t, { tags: [30], note: 0, })
  // dirty the keys: a now projects to 50, which moves it to the END of the order
  match t.get(a) {
    Some(r) => r.tags[0] = 50
    None => @test.fail("the fixture record must exist")
  }
  let before_count = t.len()
  let old_order : Array[@aurasuisui/multiindex.RowId] = [a, b, c]
  rb_assert_ids(rb_ids(t.iter_asc_by("tags").to_array()), old_order)
  // the cursor is created while the OLD bucket set is still registered
  let it = t.iter_asc_by("tags")
  match t.rebuild_index("tags") {
    Ok(_) => ()
    Err(_) =>
      @test.fail("the projections are distinct, so the rebuild must succeed")
  }
  let walked = rb_ids(it.to_array())
  @test.assert_eq(walked.length(), before_count)
  rb_assert_ids(walked, old_order)
  // ... while the rebuilt index itself already orders by the new keys
  let new_order : Array[@aurasuisui/multiindex.RowId] = [b, c, a]
  rb_assert_ids(rb_ids(t.iter_asc_by("tags").to_array()), new_order)
  assert_invariants(t)
}

///|
/// Test 7: the non-unique quadrants are repaired the same way — no uniqueness
/// constraint, so the rebuild cannot fail, and each record moves to the bucket of
/// its current projection.
test "rebuild_index repairs a non-unique index gone stale through external mutation" {
  let t : @aurasuisui/multiindex.Table[Int32, Rec] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_non_unique("tags", fn(r) { r.tags[0] }))
  let a = insert_ok(t, { tags: [1], note: 0, })
  let b = insert_ok(t, { tags: [1], note: 1, })
  match t.get(a) {
    Some(r) => r.tags[0] = 20
    None => @test.fail("the fixture record must exist")
  }
  match t.verify_invariants() {
    Ok(_) => @test.fail("the fixture must start dirty: verify must report I4")
    Err(message) => @test.assert_eq(message.contains("I4"), true)
  }
  // the stale bucket still files both records under the old key
  @test.assert_eq(t.iter_by("tags", 1).to_array().length(), 2)
  @test.assert_eq(t.iter_by("tags", 20).to_array().length(), 0)
  match t.rebuild_index("tags") {
    Ok(_) => ()
    Err(_) => @test.fail("a non-unique rebuild cannot conflict")
  }
  let stayed = t.iter_by("tags", 1).to_array()
  @test.assert_eq(stayed.length(), 1)
  @test.assert_eq(stayed[0].0, b)
  let moved = t.iter_by("tags", 20).to_array()
  @test.assert_eq(moved.length(), 1)
  @test.assert_eq(moved[0].0, a)
  assert_invariants(t)
}
