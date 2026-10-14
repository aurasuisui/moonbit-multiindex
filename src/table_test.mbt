// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Black-box unit tests: the M1 storage core plus the M2 index registry.
//
// MoonBit compiles `*_test.mbt` as an *external* package, so everything here
// goes through the public API; the private-field half of the suite lives in
// `table_wbtest.mbt` and `property_wbtest.mbt`.

///|
/// Insert and unwrap: only fails when a unique index really is violated.
fn[K : Hash + Eq + Compare, V] insert_ok(
  t : @aurasuisui/multiindex.Table[K, V],
  value : V,
) -> @aurasuisui/multiindex.RowId raise {
  match t.insert(value) {
    Ok(id) => id
    Err(_) => @test.fail("insert returned Err although no unique key is taken")
  }
}

///|
/// Unwrap a registration that must succeed.
fn[K] assert_registered(
  result : Result[Unit, @aurasuisui/multiindex.RegisterError[K]],
) -> Unit raise {
  match result {
    Ok(_) => ()
    Err(_) => @test.fail("registration unexpectedly failed")
  }
}

///|
/// The record values in insertion order.
fn[K, V] values_of(t : @aurasuisui/multiindex.Table[K, V]) -> Array[V] {
  let out : Array[V] = []
  let entries = t.iter().to_array()
  let mut i = 0
  while i < entries.length() {
    out.push(entries[i].1)
    i = i + 1
  }
  out
}

///|
/// Element-wise array equality (no `Eq`/`Debug` instance for arrays needed).
fn[V : Eq + Debug] assert_values(
  actual : Array[V],
  expected : Array[V],
) -> Unit raise {
  @test.assert_eq(actual.length(), expected.length())
  let mut i = 0
  while i < expected.length() {
    @test.assert_eq(actual[i], expected[i])
    i = i + 1
  }
}

///|
/// A table with all four quadrants registered over `(unique key, multi key)`.
fn matrix_table() -> @aurasuisui/multiindex.Table[Int, (Int, Int)] raise {
  let t : @aurasuisui/multiindex.Table[Int, (Int, Int)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique("u_hash", fn(p) { p.0 }))
  assert_registered(t.register_unique_ordered("u_sorted", fn(p) { p.0 }))
  assert_registered(t.register_non_unique("m_hash", fn(p) { p.1 }))
  assert_registered(t.register_non_unique_ordered("m_sorted", fn(p) { p.1 }))
  t
}

// ---------------------------------------------------------------------------
// M1 storage core
// ---------------------------------------------------------------------------

///|
test "a fresh table is empty" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.is_empty(), true)
  @test.assert_eq(t.iter().to_array().length(), 0)
  @test.assert_eq(t.index_names().length(), 0)
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
  let b = insert_ok(t, 2)
  let c = insert_ok(t, 3)
  t.remove(b) |> ignore
  let d = insert_ok(t, 4)
  assert_values(values_of(t), [1, 3, 4])
  // the same iteration also hands out the identity of each record
  let entries = t.iter().to_array()
  @test.assert_eq(entries[0].0, a)
  @test.assert_eq(entries[1].0, c)
  @test.assert_eq(entries[2].0, d)
}

///|
test "a recycled slot rejects the stale handle and keeps the new occupant" {
  let t : @aurasuisui/multiindex.Table[Int, String] = @aurasuisui/multiindex.Table::new()
  let old = insert_ok(t, "old")
  @test.assert_eq(t.remove(old), Some("old"))
  let fresh = insert_ok(t, "fresh")
  @test.assert_eq(fresh.slot, old.slot)
  @test.assert_eq(fresh.gen > old.gen, true)
  @test.assert_eq(t.get(old), None)
  @test.assert_eq(t.remove(old), None)
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
  @test.assert_eq(t.iter().to_array().length(), 0)
  @test.assert_eq(t.get(a), None)
  @test.assert_eq(t.get(b), None)
  @test.assert_eq(t.remove(a), None)
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

// ---------------------------------------------------------------------------
// M2 index registry
// ---------------------------------------------------------------------------

///|
test "registration matrix: four quadrants, names ascending" {
  let t = matrix_table()
  let names = t.index_names()
  @test.assert_eq(names.length(), 4)
  // shortlex order: the six-character names come first (see the dedicated test)
  @test.assert_eq(names[0], "m_hash")
  @test.assert_eq(names[1], "u_hash")
  @test.assert_eq(names[2], "m_sorted")
  @test.assert_eq(names[3], "u_sorted")
}

///|
test "every quadrant answers get_by and iter_by" {
  let t = matrix_table()
  let a = insert_ok(t, (1, 10))
  let b = insert_ok(t, (2, 10))
  // unique quadrants: one record per key
  @test.assert_eq(t.get_by("u_hash", 1), Some((a, (1, 10))))
  @test.assert_eq(t.get_by("u_sorted", 1), Some((a, (1, 10))))
  // non-unique quadrants: `get_by` answers with the smallest slot in the bucket
  @test.assert_eq(t.get_by("m_hash", 10), Some((a, (1, 10))))
  @test.assert_eq(t.get_by("m_sorted", 10), Some((a, (1, 10))))
  // `iter_by` enumerates the whole bucket, ascending by slot
  let bucket = t.iter_by("m_hash", 10).to_array()
  @test.assert_eq(bucket.length(), 2)
  @test.assert_eq(bucket[0], (a, (1, 10)))
  @test.assert_eq(bucket[1], (b, (2, 10)))
  // a unique index speaks the same shape: 0 or 1 entry
  @test.assert_eq(t.iter_by("u_sorted", 1).to_array().length(), 1)
  @test.assert_eq(t.iter_by("u_sorted", 3).to_array().length(), 0)
  // unknown index name: empty answers, never a panic (SPEC §7)
  @test.assert_eq(t.get_by("nope", 1), None)
  @test.assert_eq(t.iter_by("nope", 1).to_array().length(), 0)
}

///|
test "a duplicate index name is refused and changes nothing" {
  let t = matrix_table()
  let a = insert_ok(t, (1, 10))
  match t.register_unique("u_hash", fn(p) { p.1 }) {
    Ok(_) => @test.fail("re-registering an existing name must fail")
    Err(@aurasuisui/multiindex.DuplicateName(name)) =>
      @test.assert_eq(name, "u_hash")
    Err(_) => @test.fail("expected DuplicateName")
  }
  // the original projection is still the one in force, and nothing else moved
  @test.assert_eq(t.index_names().length(), 4)
  @test.assert_eq(t.get_by("u_hash", 1), Some((a, (1, 10))))
  @test.assert_eq(t.get_by("u_hash", 10), None)
  @test.assert_eq(t.len(), 1)
}

///|
test "index_names is ascending in MoonBit's shortlex string order" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_non_unique("aa", fn(v) { v }))
  assert_registered(t.register_non_unique("b", fn(v) { v }))
  let names = t.index_names()
  // `String : Compare` compares length first (builtin/string.mbt), so the short
  // name wins even though "aa" < "b" lexicographically — platform semantics,
  // the same call docs/SPEC.md §3.3.1 made for `range`.
  @test.assert_eq(names[0], "b")
  @test.assert_eq(names[1], "aa")
}
// ---------------------------------------------------------------------------
// §12 ledger: has_index / with_capacity / contains
// ---------------------------------------------------------------------------

///|
test "has_index tracks the registry" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  @test.assert_eq(t.has_index("k"), false)
  assert_registered(t.register_unique("k", fn(v) { v }))
  @test.assert_eq(t.has_index("k"), true)
  @test.assert_eq(t.has_index("other"), false)
  @test.assert_eq(t.has_index(""), false)
}

///|
test "contains reports live handles only" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  let a = insert_ok(t, 1)
  @test.assert_eq(t.contains(a), true)
  t.remove(a) |> ignore
  @test.assert_eq(t.contains(a), false)
  // the slot gets reused, but the old handle stays dead
  let b = insert_ok(t, 2)
  @test.assert_eq(b.slot, a.slot)
  @test.assert_eq(t.contains(b), true)
  @test.assert_eq(t.contains(a), false)
}

///|
test "with_capacity reserves slots without inventing records" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::with_capacity(
    8,
  )
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.is_empty(), true)
  @test.assert_eq(t.iter().to_array().length(), 0)
  // the reserved slots are handed out in ascending order
  let a = insert_ok(t, 10)
  let b = insert_ok(t, 20)
  @test.assert_eq(a.slot, 0)
  @test.assert_eq(b.slot, 1)
  @test.assert_eq(a.gen, 0)
  @test.assert_eq(t.len(), 2)
  // and recycling still works on top of the reservation
  t.remove(a) |> ignore
  let c = insert_ok(t, 30)
  @test.assert_eq(c.slot, 0)
  @test.assert_eq(c.gen, 1)
  @test.assert_eq(t.contains(a), false)
  @test.assert_eq(t.get(c), Some(30))
  // a non-positive capacity behaves exactly like `new`
  let zero : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::with_capacity(
    0,
  )
  @test.assert_eq(zero.len(), 0)
  let negative : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::with_capacity(
    -5,
  )
  @test.assert_eq(negative.len(), 0)
  @test.assert_eq(negative.iter().to_array().length(), 0)
}

///|
test "registering over a non-empty table backfills it" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  let a = insert_ok(t, 100)
  let b = insert_ok(t, 200)
  assert_registered(t.register_unique("k", fn(v) { v }))
  assert_registered(t.register_non_unique("low_digit", fn(v) { v % 10 }))
  // both records were scanned in, and are queryable right away
  @test.assert_eq(t.get_by("k", 100), Some((a, 100)))
  @test.assert_eq(t.get_by("k", 200), Some((b, 200)))
  @test.assert_eq(t.get_by("k", 300), None)
  @test.assert_eq(t.iter_by("low_digit", 0).to_array().length(), 2)
  @test.assert_eq(t.iter_by("low_digit", 0).to_array()[1], (b, 200))
}

///|
test "backfilling a conflicting unique index registers nothing" {
  let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
  insert_ok(t, 1) |> ignore
  insert_ok(t, 11) |> ignore
  match t.register_unique("low_digit", fn(v) { v % 10 }) {
    Ok(_) => @test.fail("the backfill must report the duplicate key")
    Err(@aurasuisui/multiindex.UniqueViolation(name, key)) => {
      @test.assert_eq(name, "low_digit")
      @test.assert_eq(key, 1)
    }
    Err(_) => @test.fail("expected UniqueViolation")
  }
  // atomic: the index is not registered at all — no half-filled index
  @test.assert_eq(t.index_names().length(), 0)
  @test.assert_eq(t.get_by("low_digit", 1), None)
  @test.assert_eq(t.len(), 2)
  // and a name that does not conflict still registers afterwards
  assert_registered(t.register_unique("high_digit", fn(v) { v / 10 }))
  @test.assert_eq(t.index_names().length(), 1)
}

///|
test "a unique collision is reported with the record and changes nothing" {
  let t : @aurasuisui/multiindex.Table[Int, (Int, Int)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique("u", fn(p) { p.0 }))
  let a = insert_ok(t, (1, 10))
  let before = values_of(t)
  match t.insert((1, 99)) {
    Ok(_) => @test.fail("a duplicate unique key must not be stored")
    Err(rejected) => {
      // the record comes back untouched ...
      @test.assert_eq(rejected.record, (1, 99))
      // ... together with the conflict that refused it
      match rejected.conflict {
        @aurasuisui/multiindex.UniqueViolation(name, key, holder) => {
          @test.assert_eq(name, "u")
          @test.assert_eq(key, 1)
          @test.assert_eq(holder, a)
        }
      }
    }
  }
  // zero change: same records, same answers
  @test.assert_eq(t.len(), before.length())
  assert_values(values_of(t), before)
  @test.assert_eq(t.get_by("u", 1), Some((a, (1, 10))))
  @test.assert_eq(t.get_by("u", 2), None)
  // the key is free again once its holder is gone
  t.remove(a) |> ignore
  let c = insert_ok(t, (1, 99))
  @test.assert_eq(t.get_by("u", 1), Some((c, (1, 99))))
}

///|
test "remove keeps every index consistent and frees the unique key" {
  let t = matrix_table()
  let a = insert_ok(t, (1, 10))
  let b = insert_ok(t, (2, 10))
  t.remove(a) |> ignore
  // both unique quadrants forgot the key, the non-unique bucket shrank
  @test.assert_eq(t.get_by("u_hash", 1), None)
  @test.assert_eq(t.get_by("u_sorted", 1), None)
  @test.assert_eq(t.get_by("m_hash", 10), Some((b, (2, 10))))
  @test.assert_eq(t.get_by("m_sorted", 10), Some((b, (2, 10))))
  @test.assert_eq(t.iter_by("m_hash", 10).to_array().length(), 1)
  @test.assert_eq(t.iter_by("m_sorted", 10).to_array().length(), 1)
  // the freed unique key is insertable again, and lands in every index
  let c = insert_ok(t, (1, 11))
  @test.assert_eq(t.get_by("u_hash", 1), Some((c, (1, 11))))
  @test.assert_eq(t.iter_by("m_hash", 11).to_array().length(), 1)
  @test.assert_eq(t.iter_by("m_sorted", 11).to_array().length(), 1)
}

///|
test "clear empties the index entries but keeps the registrations" {
  let t = matrix_table()
  insert_ok(t, (1, 10)) |> ignore
  t.clear()
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.index_names().length(), 4)
  @test.assert_eq(t.get_by("u_hash", 1), None)
  @test.assert_eq(t.iter_by("m_hash", 10).to_array().length(), 0)
  // the schema survived, so the next insert is indexed again
  let a = insert_ok(t, (1, 10))
  @test.assert_eq(t.get_by("u_hash", 1), Some((a, (1, 10))))
  @test.assert_eq(t.iter_by("m_sorted", 10).to_array().length(), 1)
}
