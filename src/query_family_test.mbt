// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Black-box tests for the v0.4.0 M4 query family — `contains_by` / `count_by` /
// `first_by` / `last_by` (docs/SPEC.md §3.3).
//
// These are the read-only, non-materializing queries: they answer from a bucket's
// own `contains` / `length` / first slot instead of copying it (`Index::slots`
// materializes, which is why the implementation does not route through it). The
// fixtures deliberately use **fat buckets** — three records under one non-unique
// key — so the counting tests really count and the endpoint tests really reach a
// multi-record bucket.
//
// The abort halves of the contract live in `abort_guard_wbtest.mbt` (hash index
// for `first_by` / `last_by`, unknown name for `contains_by` / `count_by`),
// following SPEC §7.2's one-guard-per-panic-test rule.

///|
/// Test 1: `contains_by` answers in all four quadrants. Table-driven: each entry
/// is `(index name, a key that is present, a key that is absent)`, and the two
/// unique / two non-unique indexes project different fields, so a swapped
/// projection cannot pass by accident.
test "contains_by answers in all four quadrants" {
  let t = matrix_table()
  insert_ok(t, (1, 10)) |> ignore
  insert_ok(t, (2, 10)) |> ignore
  insert_ok(t, (3, 20)) |> ignore
  let cases : Array[(String, Int32, Int32)] = [
    ("u_hash", 1, 9),
    ("u_sorted", 1, 9),
    ("m_hash", 10, 99),
    ("m_sorted", 10, 99),
  ]
  let mut i = 0
  while i < cases.length() {
    let (name, present, absent) = cases[i]
    @test.assert_eq(t.contains_by(name, present), true)
    @test.assert_eq(t.contains_by(name, absent), false)
    i = i + 1
  }
  // the multi key really owns two records, so "present" is not a unique-only fact
  @test.assert_eq(t.count_by("m_hash", 10), 2)
  assert_invariants(t)
}

///|
/// Test 2: a key that has never been written is `false`, and **deleting the last
/// record under a key clears the bucket**, so `contains_by` flips back to `false`
/// (the tolerant removal path drops an emptied non-unique bucket and the unique
/// holder outright). Also checks the unique quadrant.
test "contains_by stops answering once the last record under the key is deleted" {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_non_unique("m", fn(p) { p.0 }))
  assert_registered(t.register_unique("u", fn(p) { p.1 }))
  @test.assert_eq(t.contains_by("m", 5), false)
  let a = insert_ok(t, (5, 1))
  let b = insert_ok(t, (5, 2))
  @test.assert_eq(t.contains_by("m", 5), true)
  @test.assert_eq(t.count_by("m", 5), 2)
  @test.assert_eq(t.remove(a), Some((5, 1)))
  // one record left: the bucket still exists
  @test.assert_eq(t.contains_by("m", 5), true)
  @test.assert_eq(t.count_by("m", 5), 1)
  @test.assert_eq(t.remove(b), Some((5, 2)))
  // the bucket is gone, not merely empty
  @test.assert_eq(t.contains_by("m", 5), false)
  @test.assert_eq(t.count_by("m", 5), 0)
  @test.assert_eq(t.iter_by("m", 5).to_array().length(), 0)
  // unique quadrant: the holder entry disappears with the record
  let c = insert_ok(t, (9, 3))
  @test.assert_eq(t.contains_by("u", 3), true)
  @test.assert_eq(t.count_by("u", 3), 1)
  @test.assert_eq(t.remove(c), Some((9, 3)))
  @test.assert_eq(t.contains_by("u", 3), false)
  @test.assert_eq(t.count_by("u", 3), 0)
  assert_invariants(t)
}

///|
/// Test 3: `count_by` is 0 or 1 on a unique index, the bucket size on a
/// non-unique one (three records under one key), and walks down to 0 as the bucket
/// is deleted record by record. Both hashed and ordered multi quadrants are
/// counted, so a unique-shaped shortcut cannot pass for the multi case.
test "count_by counts unique 0-or-1 and non-unique buckets down to zero" {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique("u", fn(p) { p.1 }))
  assert_registered(t.register_non_unique("m", fn(p) { p.0 }))
  assert_registered(t.register_non_unique_ordered("ms", fn(p) { p.0 }))
  @test.assert_eq(t.count_by("m", 7), 0)
  let a = insert_ok(t, (7, 1))
  let b = insert_ok(t, (7, 2))
  let c = insert_ok(t, (7, 3))
  @test.assert_eq(t.count_by("m", 7), 3)
  @test.assert_eq(t.count_by("ms", 7), 3)
  @test.assert_eq(t.count_by("m", 8), 0)
  @test.assert_eq(t.count_by("u", 1), 1)
  @test.assert_eq(t.count_by("u", 2), 1)
  @test.assert_eq(t.count_by("u", 99), 0)
  @test.assert_eq(t.remove(a), Some((7, 1)))
  @test.assert_eq(t.count_by("m", 7), 2)
  @test.assert_eq(t.remove(b), Some((7, 2)))
  @test.assert_eq(t.count_by("m", 7), 1)
  @test.assert_eq(t.remove(c), Some((7, 3)))
  @test.assert_eq(t.count_by("m", 7), 0)
  @test.assert_eq(t.count_by("ms", 7), 0)
  assert_invariants(t)
}

///|
/// Test 4: `first_by` / `last_by` answer `None` on an empty table and the
/// **smallest / largest key** afterwards — insertion order is deliberately not key
/// order, so "first inserted" and "first by key" are different answers.
test "first_by and last_by answer None on an empty table and the key endpoints after inserts" {
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique_ordered("u", fn(value) { value }))
  @test.assert_eq(t.first_by("u"), None)
  @test.assert_eq(t.last_by("u"), None)
  let c = insert_ok(t, 30)
  let a = insert_ok(t, 10)
  let b = insert_ok(t, 20)
  @test.assert_eq(t.first_by("u"), Some((a, 10)))
  @test.assert_eq(t.last_by("u"), Some((c, 30)))
  // the same answers the ascending walk's endpoints give
  let asc = t.iter_asc_by("u").to_array()
  @test.assert_eq(asc[0], (a, 10))
  @test.assert_eq(asc[asc.length() - 1], (c, 30))
  @test.assert_eq(t.get_by("u", 10), Some((a, 10)))
  @test.assert_eq(t.get_by("u", 20), Some((b, 20)))
  assert_invariants(t)
}

///|
/// Test 5: on a **non-unique ordered** index the endpoints are the smallest /
/// largest **key**, and inside that key the answer is the **smallest slot** —
/// exactly `get_by`'s routing, not "the last inserted". The test watches both
/// halves move: deleting the smallest-slot record of the endpoint bucket promotes
/// the next slot, and inserting a new smallest / largest key takes the endpoint
/// over.
test "first_by and last_by take the smallest slot of the endpoint bucket on a non-unique ordered index" {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_non_unique_ordered("m", fn(p) { p.0 }))
  let a = insert_ok(t, (10, 1)) // slot 0
  let b = insert_ok(t, (10, 2)) // slot 1
  let c = insert_ok(t, (20, 3)) // slot 2
  @test.assert_eq(t.first_by("m"), Some((a, (10, 1))))
  @test.assert_eq(t.last_by("m"), Some((c, (20, 3))))
  // a fourth record under the same smallest key does not change either endpoint
  let d = insert_ok(t, (10, 4))
  @test.assert_eq(t.get(d), Some((10, 4)))
  @test.assert_eq(t.first_by("m"), Some((a, (10, 1))))
  @test.assert_eq(t.last_by("m"), Some((c, (20, 3))))
  // deleting the smallest slot promotes the next slot of the same bucket
  @test.assert_eq(t.remove(a), Some((10, 1)))
  @test.assert_eq(t.first_by("m"), Some((b, (10, 2))))
  // ... which is the record get_by routes to for the same key
  @test.assert_eq(t.get_by("m", 10), Some((b, (10, 2))))
  @test.assert_eq(t.count_by("m", 10), 2) // b and d
  // a new smallest key takes the first endpoint over
  let e = insert_ok(t, (5, 5))
  @test.assert_eq(t.first_by("m"), Some((e, (5, 5))))
  @test.assert_eq(t.last_by("m"), Some((c, (20, 3))))
  // and a new largest key takes the last endpoint over
  let f = insert_ok(t, (30, 6))
  @test.assert_eq(t.last_by("m"), Some((f, (30, 6))))
  // the same answer as the descending walk's first step
  let desc = t.iter_desc_by("m").to_array()
  @test.assert_eq(desc[0], (f, (30, 6)))
  @test.assert_eq(t.count_by("m", 10), 2) // b and d, still
  assert_invariants(t)
}

///|
/// Test 6: both endpoints follow the write paths — `remove` and `swap_remove`
/// shrink / shift the key order, and `modify` moves the record's key, so the
/// endpoints must be re-read from the index rather than cached or derived from
/// insertion order.
test "first_by and last_by follow remove, swap_remove and modify to the new endpoints" {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique_ordered("u", fn(p) { p.0 }))
  let a = insert_ok(t, (10, 1))
  let b = insert_ok(t, (20, 2))
  let c = insert_ok(t, (30, 3))
  @test.assert_eq(t.first_by("u"), Some((a, (10, 1))))
  @test.assert_eq(t.last_by("u"), Some((c, (30, 3))))
  // remove the smallest key: the first endpoint moves to the next key
  @test.assert_eq(t.remove(a), Some((10, 1)))
  @test.assert_eq(t.first_by("u"), Some((b, (20, 2))))
  // swap_remove the largest key: the last endpoint moves down, and insertion
  // order no longer matters to the answer
  @test.assert_eq(t.swap_remove(c), Some((30, 3)))
  @test.assert_eq(t.last_by("u"), Some((b, (20, 2))))
  // modify the remaining record's key upward: both endpoints follow it
  match t.modify(b, fn(_) { (40, 2) }) {
    Ok(_) => ()
    Err(_) => @test.fail("modify to a free unique key must succeed")
  }
  @test.assert_eq(t.first_by("u"), Some((b, (40, 2))))
  @test.assert_eq(t.last_by("u"), Some((b, (40, 2))))
  // and downward again
  match t.modify(b, fn(_) { (5, 2) }) {
    Ok(_) => ()
    Err(_) => @test.fail("modify to a free unique key must succeed")
  }
  @test.assert_eq(t.first_by("u"), Some((b, (5, 2))))
  @test.assert_eq(t.last_by("u"), Some((b, (5, 2))))
  assert_invariants(t)
}

///|
/// Test 7: all four queries are **read-only** — they must not bump `version`.
/// A black-box test cannot read `version`, but an iterator is fail-fast on it:
/// if any of the four calls bumped the counter, the `next()` after them aborts.
test "the four new queries are read-only so a live iterator keeps walking" {
  let t = matrix_table()
  let a = insert_ok(t, (1, 10))
  let b = insert_ok(t, (2, 10))
  let c = insert_ok(t, (3, 20))
  let it = t.iter()
  it.next() |> ignore
  @test.assert_eq(t.contains_by("m_hash", 10), true)
  @test.assert_eq(t.count_by("m_sorted", 10), 2)
  @test.assert_eq(t.first_by("m_sorted"), Some((a, (1, 10))))
  @test.assert_eq(t.last_by("u_sorted"), Some((c, (3, 20))))
  @test.assert_eq(t.last_by("m_sorted"), Some((c, (3, 20))))
  @test.assert_eq(t.first_by("u_sorted"), Some((a, (1, 10))))
  // the iterator is still live: version never moved, so it walks to the end
  @test.assert_eq(t.len(), 3)
  let rest = it.to_array()
  @test.assert_eq(rest.length(), 2)
  @test.assert_eq(t.get_by("u_hash", 2), Some((b, (2, 10))))
  assert_invariants(t)
}
