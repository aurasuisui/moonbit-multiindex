// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Black-box unit tests for the M1 record store.
//
// MoonBit compiles \`*_test.mbt\` as an *external* package, so everything here
// goes through the public API; the private-field half of the M1 test suite lives
// in \`table_wbtest.mbt\` and \`property_wbtest.mbt\`.

///|
/// Insert and unwrap. M1 registers no index, so \`insert\` cannot conflict; a
/// conflict here would mean the storage core is already wrong.
fn[K, V] insert_ok(
  t : @aurasuisui/multiindex.Table[K, V],
  value : V,
) -> @aurasuisui/multiindex.RowId raise {
  match t.insert(value) {
    Ok(id) => id
    Err(_) => @test.fail("insert returned Err although no index is registered")
  }
}

///|
test "a fresh table is empty" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.is_empty(), true)
  @test.assert_eq(t.iter().count(), 0)
}

///|
test "insert returns a handle that gets the record back" {
  let t : @aurasuisui/multiindex.Table[Int, String] = @aurasuisui/multiindex.Table::new()
  let a = insert_ok(t, "a")
  let b = insert_ok(t, "b")
  @test.assert_eq(t.get(a), Some("a"))
  @test.assert_eq(t.get(b), Some("b"))
  @test.assert_eq(t.len(), 2)
  @test.assert_eq(t.is_empty(), false)
}

///|
test "remove returns the record and then rejects the same handle" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  let a = insert_ok(t, 10)
  let b = insert_ok(t, 20)
  @test.assert_eq(t.remove(a), Some(10))
  @test.assert_eq(t.get(a), None)
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(t.remove(a), None)
  @test.assert_eq(t.get(b), Some(20))
  @test.assert_eq(t.len(), 1)
}

///|
test "iter yields live records in insertion order" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  let a = insert_ok(t, 1)
  insert_ok(t, 2) |> ignore
  insert_ok(t, 3) |> ignore
  t.remove(a) |> ignore
  insert_ok(t, 4) |> ignore
  let seen : Array[Int] = []
  for v in t.iter() {
    seen.push(v)
  }
  @test.assert_eq(seen.length(), 3)
  @test.assert_eq(seen[0], 2)
  @test.assert_eq(seen[1], 3)
  @test.assert_eq(seen[2], 4)
}

///|
test "a recycled slot rejects the stale handle and keeps the new occupant" {
  let t : @aurasuisui/multiindex.Table[Int, String] = @aurasuisui/multiindex.Table::new()
  let old = insert_ok(t, "old")
  @test.assert_eq(t.remove(old), Some("old"))
  let fresh = insert_ok(t, "fresh")
  // the freed slot is reused, but under a strictly newer generation
  @test.assert_eq(fresh.slot, old.slot)
  @test.assert_eq(fresh.gen > old.gen, true)
  // the stale handle is rejected by both reads and writes ...
  @test.assert_eq(t.get(old), None)
  @test.assert_eq(t.remove(old), None)
  // ... and never touches the record that now occupies the slot
  @test.assert_eq(t.get(fresh), Some("fresh"))
  @test.assert_eq(t.len(), 1)
}

///|
test "clear empties the table and invalidates every handle" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  let a = insert_ok(t, 1)
  let b = insert_ok(t, 2)
  t.clear()
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.is_empty(), true)
  @test.assert_eq(t.iter().count(), 0)
  @test.assert_eq(t.get(a), None)
  @test.assert_eq(t.get(b), None)
  @test.assert_eq(t.remove(a), None)
  // re-inserting reuses the storage but must not resurrect the old handles
  let c = insert_ok(t, 3)
  @test.assert_eq(t.get(a), None)
  @test.assert_eq(t.get(c), Some(3))
  @test.assert_eq(t.len(), 1)
}

///|
test "the key type is unconstrained while no index is registered" {
  let t : @aurasuisui/multiindex.Table[(String, Int), Int] = @aurasuisui/multiindex.Table::new()
  let a = insert_ok(t, 7)
  @test.assert_eq(t.get(a), Some(7))
  @test.assert_eq(t.remove(a), Some(7))
  @test.assert_eq(t.is_empty(), true)
}
