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
/// A `(lo, hi, shared)` table with all four quadrants registered: `lo` and `hi`
/// are unique keys, `shared` is not — so records can collide on `shared` (which
/// is what makes a multi-record bucket testable) while the unique keys stay free.
fn triple_table() -> @aurasuisui/multiindex.Table[Int32, (Int32, Int32, Int32)] raise {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32, Int32)] = @aurasuisui/multiindex.Table::new()
  assert_registered(t.register_unique("lo", fn(p) { p.0 }))
  assert_registered(t.register_unique_ordered("hi", fn(p) { p.1 }))
  assert_registered(t.register_non_unique("shared", fn(p) { p.2 }))
  assert_registered(
    t.register_non_unique_ordered("shared_sorted", fn(p) { p.2 }),
  )
  t
}

///|
/// The whole observable state of the three-record fixture, so a refused write can
/// be checked for **zero change** across iteration and every index.
fn assert_three_records(
  t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32, Int32)],
  a : @aurasuisui/multiindex.RowId,
  b : @aurasuisui/multiindex.RowId,
  c : @aurasuisui/multiindex.RowId,
) -> Unit raise {
  @test.assert_eq(t.len(), 3)
  let entries = t.iter().to_array()
  @test.assert_eq(entries.length(), 3)
  @test.assert_eq(entries[0], (a, (1, 10, 7)))
  @test.assert_eq(entries[1], (b, (2, 20, 7)))
  @test.assert_eq(entries[2], (c, (3, 30, 8)))
  @test.assert_eq(t.get_by("lo", 1), Some((a, (1, 10, 7))))
  @test.assert_eq(t.get_by("lo", 2), Some((b, (2, 20, 7))))
  @test.assert_eq(t.get_by("lo", 3), Some((c, (3, 30, 8))))
  @test.assert_eq(t.get_by("hi", 10), Some((a, (1, 10, 7))))
  @test.assert_eq(t.get_by("hi", 20), Some((b, (2, 20, 7))))
  @test.assert_eq(t.get_by("hi", 30), Some((c, (3, 30, 8))))
  @test.assert_eq(t.iter_by("shared", 7).to_array().length(), 2)
  @test.assert_eq(t.iter_by("shared", 8).to_array().length(), 1)
  @test.assert_eq(t.iter_by("shared_sorted", 7).to_array().length(), 2)
  @test.assert_eq(t.get_by("lo", 99), None)
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
fn matrix_table() -> @aurasuisui/multiindex.Table[Int32, (Int32, Int32)] raise {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32)] = @aurasuisui/multiindex.Table::new()
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
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
  @test.assert_eq(t.len(), 0)
  @test.assert_eq(t.is_empty(), true)
  @test.assert_eq(t.iter().to_array().length(), 0)
  @test.assert_eq(t.index_names().length(), 0)
}

///|
test "insert returns a handle that gets the record back" {
  let t : @aurasuisui/multiindex.Table[Int32, String] = @aurasuisui/multiindex.Table::new()
  let a = insert_ok(t, "a")
  let b = insert_ok(t, "b")
  @test.assert_eq(t.get(a), Some("a"))
  @test.assert_eq(t.get(b), Some("b"))
  @test.assert_eq(t.len(), 2)
  @test.assert_eq(t.is_empty(), false)
}

///|
test "remove returns the record and then rejects the same handle" {
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
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
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
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
  let t : @aurasuisui/multiindex.Table[Int32, String] = @aurasuisui/multiindex.Table::new()
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
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
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
  let t : @aurasuisui/multiindex.Table[(String, Int32), Int32] = @aurasuisui/multiindex.Table::new()
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
  // An *absent key* is an empty answer; an *absent index name* is a caller bug
  // that aborts (docs/SPEC.md §7.1). A MoonBit abort cannot be caught in-process,
  // so the decision is pinned through its testable halves: `has_index` here and
  // `Index::is_ordered` in `table_wbtest.mbt`.
  @test.assert_eq(t.get_by("u_hash", 99), None)
  @test.assert_eq(t.iter_by("u_hash", 99).to_array().length(), 0)
  @test.assert_eq(t.has_index("nope"), false)
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
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
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
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
  @test.assert_eq(t.has_index("k"), false)
  assert_registered(t.register_unique("k", fn(v) { v }))
  @test.assert_eq(t.has_index("k"), true)
  @test.assert_eq(t.has_index("other"), false)
  @test.assert_eq(t.has_index(""), false)
}

///|
test "contains reports live handles only" {
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
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
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::with_capacity(
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
  let zero : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::with_capacity(
    0,
  )
  @test.assert_eq(zero.len(), 0)
  let negative : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::with_capacity(
    -5,
  )
  @test.assert_eq(negative.len(), 0)
  @test.assert_eq(negative.iter().to_array().length(), 0)
}

///|
test "registering over a non-empty table backfills it" {
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
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
  let t : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
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
  // atomic: the index is not registered at all — no half-filled index. (Querying
  // a name that was never registered now aborts, docs/SPEC.md §7.1, so the absence
  // is asserted through the registry instead.)
  @test.assert_eq(t.index_names().length(), 0)
  @test.assert_eq(t.has_index("low_digit"), false)
  @test.assert_eq(t.len(), 2)
  // and a name that does not conflict still registers afterwards
  assert_registered(t.register_unique("high_digit", fn(v) { v / 10 }))
  @test.assert_eq(t.index_names().length(), 1)
}

///|
test "a unique collision is reported with the record and changes nothing" {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32)] = @aurasuisui/multiindex.Table::new()
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
        @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
          @test.fail("a single insert cannot report a batch duplicate")
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

// ---------------------------------------------------------------------------
// M3 update path
// ---------------------------------------------------------------------------

///|
test "regression: updating into an occupied unique key changes nothing" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 7))
  let b = insert_ok(t, (2, 20, 7))
  let c = insert_ok(t, (3, 30, 8))
  assert_three_records(t, a, b, c)
  // `a` tries to take a key that `b` already holds on the unique "lo" index — the
  // probe-found bug: without an excluding-self conflict check the bucket ends up
  // with two holders.
  match t.update(a, (2, 11, 9)) {
    Ok(_) => @test.fail("a duplicate unique key must not be accepted")
    Err(rejected) =>
      match rejected {
        @aurasuisui/multiindex.Conflict(conflict, value) => {
          @test.assert_eq(value, (2, 11, 9)) // the record came back untouched
          match conflict {
            @aurasuisui/multiindex.UniqueViolation(name, key, holder) => {
              @test.assert_eq(name, "lo")
              @test.assert_eq(key, 2)
              @test.assert_eq(holder, b)
            }
            @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
              @test.fail("an update cannot report a batch duplicate")
          }
        }
        @aurasuisui/multiindex.StaleHandle(_, _) =>
          @test.fail("the handle was live")
      }
  }
  // zero change: length, iteration (identity + value) and every index answer
  assert_three_records(t, a, b, c)
}

///|
test "update excludes self: rewriting a record with its own keys is legal" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 7))
  insert_ok(t, (2, 20, 7)) |> ignore
  match t.update(a, (1, 10, 9)) {
    Ok(_) => ()
    Err(_) => @test.fail("a record keeps its own unique keys")
  }
  @test.assert_eq(t.get(a), Some((1, 10, 9)))
  @test.assert_eq(t.get_by("lo", 1), Some((a, (1, 10, 9))))
  @test.assert_eq(t.get_by("hi", 10), Some((a, (1, 10, 9))))
  // only the shared key moved: 7 -> 9
  @test.assert_eq(t.iter_by("shared", 9).to_array().length(), 1)
  @test.assert_eq(t.iter_by("shared", 7).to_array().length(), 1)
  @test.assert_eq(t.iter_by("shared_sorted", 9).to_array().length(), 1)
}

///|
test "modify is atomic even when two unique indexes would both break" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 7))
  let b = insert_ok(t, (2, 20, 7))
  let c = insert_ok(t, (3, 30, 8))
  assert_three_records(t, a, b, c)
  // the new record collides on "lo" (2 belongs to `b`) AND on "hi" (20 belongs to
  // `b`): a half-committing implementation would fix one index and then notice the
  // other one.
  match t.modify(a, fn(_) { (2, 20, 9) }) {
    Ok(_) => @test.fail("a double conflict must not be accepted")
    Err(rejected) =>
      match rejected {
        @aurasuisui/multiindex.Conflict(_, value) =>
          @test.assert_eq(value, (2, 20, 9))
        @aurasuisui/multiindex.StaleHandle(_, _) =>
          @test.fail("the handle was live")
      }
  }
  // neither index was touched
  assert_three_records(t, a, b, c)
}

///|
test "stale handles never touch the new occupant of the slot" {
  let t = triple_table()
  let old = insert_ok(t, (1, 10, 7))
  @test.assert_eq(t.remove(old), Some((1, 10, 7)))
  let fresh = insert_ok(t, (1, 20, 8))
  @test.assert_eq(fresh.slot, old.slot) // the slot was recycled under a new handle
  match t.update(old, (5, 50, 5)) {
    Ok(_) => @test.fail("a stale handle must not update anything")
    Err(rejected) =>
      match rejected {
        @aurasuisui/multiindex.StaleHandle(id, pending) => {
          @test.assert_eq(id, old)
          @test.assert_eq(pending, Some((5, 50, 5))) // the record came back
        }
        @aurasuisui/multiindex.Conflict(_, _) =>
          @test.fail("expected StaleHandle")
      }
  }
  match t.modify(old, fn(_) { (5, 50, 5) }) {
    Ok(_) => @test.fail("a stale handle must not modify anything")
    Err(rejected) =>
      match rejected {
        @aurasuisui/multiindex.StaleHandle(id, pending) => {
          @test.assert_eq(id, old)
          @test.assert_eq(pending, None) // nothing to transform, nothing to give back
        }
        @aurasuisui/multiindex.Conflict(_, _) =>
          @test.fail("expected StaleHandle")
      }
  }
  // the live record in that slot is untouched, in every index
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(t.get(fresh), Some((1, 20, 8)))
  @test.assert_eq(t.get_by("lo", 1), Some((fresh, (1, 20, 8))))
  @test.assert_eq(t.get_by("hi", 20), Some((fresh, (1, 20, 8))))
  @test.assert_eq(t.iter_by("shared", 8).to_array().length(), 1)
  @test.assert_eq(t.iter_by("shared", 7).to_array().length(), 0)
  @test.assert_eq(t.get_by("lo", 5), None)
}

///|
test "modify runs its transformation exactly once and reindexes afterwards" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 7))
  let calls : Array[Int32] = [0]
  match
    t.modify(a, fn(record) {
      calls[0] = calls[0] + 1
      (record.0 + 1, record.1, record.2)
    }) {
    Ok(_) => ()
    Err(_) => @test.fail("the transformation is legal")
  }
  @test.assert_eq(calls[0], 1)
  @test.assert_eq(t.get(a), Some((2, 10, 7)))
  @test.assert_eq(t.get_by("lo", 2), Some((a, (2, 10, 7))))
  @test.assert_eq(t.get_by("lo", 1), None) // the old unique key is gone
  @test.assert_eq(t.get_by("hi", 10), Some((a, (2, 10, 7)))) // unchanged key stays
  @test.assert_eq(t.iter_by("shared", 7).to_array().length(), 1)
  // a refused modify still ran the transformation exactly once (it had to, to learn
  // what the new record would be) and changed nothing
  let holder = insert_ok(t, (3, 30, 8))
  let calls2 : Array[Int32] = [0]
  match
    t.modify(a, fn(_) {
      calls2[0] = calls2[0] + 1
      (3, 10, 7)
    }) {
    Ok(_) => @test.fail("3 is taken by another record")
    Err(_) => ()
  }
  @test.assert_eq(calls2[0], 1)
  @test.assert_eq(t.get(a), Some((2, 10, 7)))
  @test.assert_eq(t.get(holder), Some((3, 30, 8)))
  @test.assert_eq(t.get_by("lo", 2), Some((a, (2, 10, 7))))
  @test.assert_eq(t.get_by("lo", 3), Some((holder, (3, 30, 8))))
}

// ---------------------------------------------------------------------------
// M4 ordered queries
// ---------------------------------------------------------------------------

///|
test "iter_asc_by walks both ordered quadrants by key" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  let b = insert_ok(t, (2, 20, 2))
  let c = insert_ok(t, (3, 30, 1))
  let d = insert_ok(t, (4, 40, 3))
  // unique + ordered: one entry per key
  let unique = t.iter_asc_by("hi").to_array()
  @test.assert_eq(unique.length(), 4)
  @test.assert_eq(unique[0], (a, (1, 10, 1)))
  @test.assert_eq(unique[1], (b, (2, 20, 2)))
  @test.assert_eq(unique[2], (c, (3, 30, 1)))
  @test.assert_eq(unique[3], (d, (4, 40, 3)))
  // non-unique + ordered: keys ascending, and inside one key the slots ascending
  let multi = t.iter_asc_by("shared_sorted").to_array()
  @test.assert_eq(multi.length(), 4)
  @test.assert_eq(multi[0], (a, (1, 10, 1))) // key 1, slot 0
  @test.assert_eq(multi[1], (c, (3, 30, 1))) // key 1, slot 2
  @test.assert_eq(multi[2], (b, (2, 20, 2))) // key 2
  @test.assert_eq(multi[3], (d, (4, 40, 3))) // key 3
}

///|
test "iter_desc_by walks keys downwards, keeping slots ascending inside a bucket" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  let b = insert_ok(t, (2, 20, 2))
  let c = insert_ok(t, (3, 30, 1))
  let d = insert_ok(t, (4, 40, 3))
  let asc = t.iter_asc_by("shared_sorted").to_array()
  let desc = t.iter_desc_by("shared_sorted").to_array()
  @test.assert_eq(asc.length(), 4)
  @test.assert_eq(desc.length(), 4)
  // the direction proof, key by key: ascending walks 1,1,2,3 and descending walks
  // 3,2,1,1 — this cannot pass if the walk ignores the key order
  @test.assert_eq(asc[0].1.2, 1)
  @test.assert_eq(asc[1].1.2, 1)
  @test.assert_eq(asc[2].1.2, 2)
  @test.assert_eq(asc[3].1.2, 3)
  @test.assert_eq(desc[0].1.2, 3)
  @test.assert_eq(desc[1].1.2, 2)
  @test.assert_eq(desc[2].1.2, 1)
  @test.assert_eq(desc[3].1.2, 1)
  // inside the shared key 1, both directions hand the slots out ascending
  // (docs/SPEC.md: 桶内按槽位号升序) — so `desc` is a reverse at the *key* level,
  // not a byte-reverse of `asc`
  @test.assert_eq(asc[0], (a, (1, 10, 1)))
  @test.assert_eq(asc[1], (c, (3, 30, 1)))
  @test.assert_eq(desc[1], (b, (2, 20, 2)))
  @test.assert_eq(desc[2], (a, (1, 10, 1)))
  @test.assert_eq(desc[3], (c, (3, 30, 1)))
  // the unique quadrant is strictly ordered either way
  let unique_asc = t.iter_asc_by("hi").to_array()
  let unique_desc = t.iter_desc_by("hi").to_array()
  @test.assert_eq(unique_asc[0], (a, (1, 10, 1)))
  @test.assert_eq(unique_asc[3], (d, (4, 40, 3)))
  @test.assert_eq(unique_desc[0], (d, (4, 40, 3)))
  @test.assert_eq(unique_desc[3], (a, (1, 10, 1)))
}

///|
test "range_by is closed on both ends" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  let b = insert_ok(t, (2, 20, 2))
  let c = insert_ok(t, (3, 30, 1))
  let d = insert_ok(t, (4, 40, 3))
  // [10, 30] takes both endpoints (that is what "closed" means here)
  let mid = t.range_by("hi", 10, 30).to_array()
  @test.assert_eq(mid.length(), 3)
  @test.assert_eq(mid[0], (a, (1, 10, 1)))
  @test.assert_eq(mid[2], (c, (3, 30, 1)))
  // single point, full range, range with no match
  @test.assert_eq(t.range_by("hi", 20, 20).to_array().length(), 1)
  @test.assert_eq(t.range_by("hi", 10, 40).to_array().length(), 4)
  @test.assert_eq(t.range_by("hi", 0, 100).to_array().length(), 4)
  @test.assert_eq(t.range_by("hi", 11, 19).to_array().length(), 0)
  // lo > hi is an empty interval, not an error (docs/SPEC.md §7.1)
  @test.assert_eq(t.range_by("hi", 30, 10).to_array().length(), 0)
  // the non-unique quadrant returns whole buckets, slots ascending inside them
  let shared = t.range_by("shared_sorted", 1, 2).to_array()
  @test.assert_eq(shared.length(), 3)
  @test.assert_eq(shared[0], (a, (1, 10, 1)))
  @test.assert_eq(shared[1], (c, (3, 30, 1)))
  @test.assert_eq(shared[2], (b, (2, 20, 2)))
  @test.assert_eq(t.range_by("shared_sorted", 0, 0).to_array().length(), 0)
  ignore(d)
}

///|
test "range_half_open_by excludes hi and is empty when lo == hi" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  let b = insert_ok(t, (2, 20, 2))
  let c = insert_ok(t, (3, 30, 1))
  let d = insert_ok(t, (4, 40, 3))
  // [10, 30) drops the 30 record that the closed range kept
  let half = t.range_half_open_by("hi", 10, 30).to_array()
  @test.assert_eq(half.length(), 2)
  @test.assert_eq(half[0], (a, (1, 10, 1)))
  @test.assert_eq(half[1], (b, (2, 20, 2)))
  @test.assert_eq(t.range_half_open_by("hi", 10, 20).to_array().length(), 1)
  // lo == hi is empty by definition, on every quadrant
  @test.assert_eq(t.range_half_open_by("hi", 20, 20).to_array().length(), 0)
  @test.assert_eq(t.range_half_open_by("hi", 10, 10).to_array().length(), 0)
  @test.assert_eq(t.range_half_open_by("hi", 40, 40).to_array().length(), 0)
  @test.assert_eq(
    t.range_half_open_by("shared_sorted", 1, 1).to_array().length(),
    0,
  )
  // full and inverted ranges
  @test.assert_eq(t.range_half_open_by("hi", 0, 100).to_array().length(), 4)
  @test.assert_eq(t.range_half_open_by("hi", 30, 10).to_array().length(), 0)
  // the non-unique quadrant drops the whole `hi` bucket
  @test.assert_eq(
    t.range_half_open_by("shared_sorted", 1, 3).to_array().length(),
    3,
  )
  ignore(c)
  ignore(d)
}

///|
test "ordered queries on an empty table are empty" {
  let t = triple_table()
  @test.assert_eq(t.iter_asc_by("hi").to_array().length(), 0)
  @test.assert_eq(t.iter_desc_by("hi").to_array().length(), 0)
  @test.assert_eq(t.range_by("hi", 0, 100).to_array().length(), 0)
  @test.assert_eq(t.range_by("hi", 100, 0).to_array().length(), 0)
  @test.assert_eq(t.range_half_open_by("hi", 0, 100).to_array().length(), 0)
  @test.assert_eq(t.iter_asc_by("shared_sorted").to_array().length(), 0)
}

///|
test "ordered queries follow removals, updates and clear" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  let b = insert_ok(t, (2, 20, 2))
  @test.assert_eq(t.iter_asc_by("hi").to_array().length(), 2)
  t.remove(a) |> ignore
  @test.assert_eq(t.iter_asc_by("hi").to_array().length(), 1)
  @test.assert_eq(t.range_by("hi", 0, 100).to_array()[0], (b, (2, 20, 2)))
  // moving an ordered key re-sorts the walk
  match t.update(b, (2, 5, 2)) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal update must succeed")
  }
  @test.assert_eq(t.iter_asc_by("hi").to_array()[0], (b, (2, 5, 2)))
  @test.assert_eq(t.range_by("hi", 0, 9).to_array().length(), 1)
  @test.assert_eq(t.range_by("hi", 10, 100).to_array().length(), 0)
  @test.assert_eq(t.iter_desc_by("shared_sorted").to_array().length(), 1)
  t.clear()
  @test.assert_eq(t.iter_asc_by("hi").to_array().length(), 0)
  @test.assert_eq(t.range_by("shared_sorted", 0, 100).to_array().length(), 0)
}

///|
test "failure classification: the abort decisions are pinned by their predicates" {
  let t = triple_table()
  // 「名字写错」→ abort: `has_index` is the public, testable half of that decision.
  @test.assert_eq(t.has_index("hi"), true)
  @test.assert_eq(t.has_index("shared_sorted"), true)
  @test.assert_eq(t.has_index("never_registered"), false)
  @test.assert_eq(t.has_index(""), false)
  // 「问题问错了」→ abort: `Index::is_ordered` is the white-box half (see
  // table_wbtest.mbt). The two aborts themselves cannot be caught in-process —
  // a MoonBit panic is not an `Error` (MOONBIT_REF §0) — so predicates + code
  // review are the evidence, by design.
  // An *absent key* on an index that does exist is still just an empty answer:
  @test.assert_eq(t.get_by("hi", 999), None)
  @test.assert_eq(t.range_by("hi", 999, 1000).to_array().length(), 0)
}

// ---------------------------------------------------------------------------
// M5: insert_many
// ---------------------------------------------------------------------------

///|
test "insert_many hands out exactly the handles per-record inserts would" {
  let batch = triple_table()
  let stepwise = triple_table()
  let records : Array[(Int32, Int32, Int32)] = [
    (1, 10, 1),
    (2, 20, 2),
    (3, 30, 1),
  ]
  let ids = match batch.insert_many(records) {
    Ok(ids) => ids
    Err(_) => @test.fail("the batch has no conflicts")
  }
  @test.assert_eq(ids.length(), 3)
  let mut i = 0
  while i < records.length() {
    let expected = insert_ok(stepwise, records[i])
    // same handles, same contents, same index answers as one-at-a-time inserts
    @test.assert_eq(ids[i], expected)
    @test.assert_eq(batch.get(ids[i]), Some(records[i]))
    @test.assert_eq(
      batch.get_by("lo", records[i].0),
      Some((ids[i], records[i])),
    )
    @test.assert_eq(
      batch.get_by("hi", records[i].1),
      Some((ids[i], records[i])),
    )
    i = i + 1
  }
  @test.assert_eq(batch.len(), 3)
  @test.assert_eq(batch.iter_by("shared_sorted", 1).to_array().length(), 2)
  match batch.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
}

///|
test "insert_many fails the whole batch when two of its own records collide" {
  let t = triple_table()
  let a = insert_ok(t, (9, 90, 9))
  // both members project to 10 on the unique "hi" index
  let records : Array[(Int32, Int32, Int32)] = [(1, 10, 1), (2, 10, 2)]
  match t.insert_many(records) {
    Ok(_) =>
      @test.fail("a duplicate inside the batch must fail the whole batch")
    Err(rejected) => {
      // the *second* member is the offender and comes back untouched
      @test.assert_eq(rejected.record, (2, 10, 2))
      match rejected.conflict {
        // No record is live at that key — the whole batch was rejected atomically —
        // so the conflict names the *batch position* of the earlier member instead of
        // pretending some handle exists (docs/SPEC.md §2.2).
        @aurasuisui/multiindex.DuplicateInBatch(name, key, at) => {
          @test.assert_eq(name, "hi")
          @test.assert_eq(key, 10)
          @test.assert_eq(at, 0)
        }
        @aurasuisui/multiindex.UniqueViolation(_, _, _) =>
          @test.fail(
            "nothing is live at that key, so it cannot be a UniqueViolation",
          )
      }
    }
  }
  // zero change: nothing from the batch landed
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(t.get(a), Some((9, 90, 9)))
  @test.assert_eq(t.get_by("lo", 1), None)
  @test.assert_eq(t.get_by("lo", 2), None)
  @test.assert_eq(t.iter_by("shared_sorted", 1).to_array().length(), 0)
  @test.assert_eq(t.range_by("hi", 0, 100).to_array().length(), 1)
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
}

///|
test "insert_many fails the whole batch when it clashes with a live record" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  // the second member would take a key that `a` already holds on the unique "hi" index
  let records : Array[(Int32, Int32, Int32)] = [(2, 20, 2), (3, 10, 3)]
  match t.insert_many(records) {
    Ok(_) => @test.fail("the clash must fail the whole batch")
    Err(rejected) => {
      @test.assert_eq(rejected.record, (3, 10, 3))
      match rejected.conflict {
        @aurasuisui/multiindex.UniqueViolation(name, key, holder) => {
          @test.assert_eq(name, "hi")
          @test.assert_eq(key, 10)
          // here the holder is a *live* record, so the caller can go and look
          @test.assert_eq(holder, a)
          @test.assert_eq(t.contains(holder), true)
        }
        @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
          @test.fail("the clash is with a live record, not inside the batch")
      }
    }
  }
  @test.assert_eq(t.len(), 1)
  @test.assert_eq(t.get_by("lo", 2), None)
  @test.assert_eq(t.get_by("lo", 3), None)
  @test.assert_eq(t.get(a), Some((1, 10, 1)))
}

///|
test "insert_many handles the degenerate batch sizes" {
  let t = triple_table()
  let empty : Array[(Int32, Int32, Int32)] = []
  match t.insert_many(empty) {
    Ok(ids) => @test.assert_eq(ids.length(), 0)
    Err(_) => @test.fail("an empty batch cannot conflict")
  }
  @test.assert_eq(t.len(), 0)
  let single : Array[(Int32, Int32, Int32)] = [(1, 10, 1)]
  match t.insert_many(single) {
    Ok(ids) => @test.assert_eq(ids.length(), 1)
    Err(_) => @test.fail("a single record cannot conflict here")
  }
  @test.assert_eq(t.len(), 1)
  // with no unique index registered there is nothing a batch could collide on
  let plain : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::new()
  match plain.insert_many([1, 1, 1]) {
    Ok(ids) => @test.assert_eq(ids.length(), 3)
    Err(_) => @test.fail("no unique index is registered")
  }
  @test.assert_eq(plain.len(), 3)
}

// ---------------------------------------------------------------------------
// M5: public diagnostics
// ---------------------------------------------------------------------------

///|
test "verify_invariants accepts a healthy table through every operation" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  let b = insert_ok(t, (2, 20, 2))
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
  match t.insert_many([(3, 30, 3), (4, 40, 1)]) {
    Ok(_) => ()
    Err(_) => @test.fail("the batch has no conflicts")
  }
  match t.update(a, (1, 11, 1)) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal update must succeed")
  }
  match t.modify(b, fn(record) { (record.0, record.1, 9) }) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal modify must succeed")
  }
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
  t.remove(a) |> ignore
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
  t.clear()
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
}

///|
test "index_stats reports the bucket shape" {
  let t = triple_table()
  insert_ok(t, (1, 10, 7)) |> ignore
  let b = insert_ok(t, (2, 20, 7))
  insert_ok(t, (3, 30, 8)) |> ignore
  // the unique quadrants hold one entry per key
  let unique = t.index_stats("lo")
  @test.assert_eq(unique.buckets, 3)
  @test.assert_eq(unique.entries, 3)
  @test.assert_eq(unique.longest_bucket, 1)
  @test.assert_eq(unique.average_bucket, 1.0)
  // the non-unique quadrant groups by `.2`: key 7 twice, key 8 once
  let multi = t.index_stats("shared_sorted")
  @test.assert_eq(multi.buckets, 2)
  @test.assert_eq(multi.entries, 3)
  @test.assert_eq(multi.longest_bucket, 2)
  @test.assert_eq(multi.average_bucket, 1.5)
  // an index with no entries reports zeros, not a division by zero
  let empty = triple_table()
  let zero = empty.index_stats("shared")
  @test.assert_eq(zero.buckets, 0)
  @test.assert_eq(zero.entries, 0)
  @test.assert_eq(zero.longest_bucket, 0)
  @test.assert_eq(zero.average_bucket, 0.0)
  // and the numbers follow removals
  t.remove(b) |> ignore
  let after = t.index_stats("shared_sorted")
  @test.assert_eq(after.buckets, 2)
  @test.assert_eq(after.entries, 2)
  @test.assert_eq(after.longest_bucket, 1)
  @test.assert_eq(after.average_bucket, 1.0)
  @test.assert_eq(t.index_stats("lo").entries, 2)
}

// ---------------------------------------------------------------------------
// M7: multi-index conflicts report the name-ascending first index
// ---------------------------------------------------------------------------

///|
/// The same table as `triple_table`, but registered in the **opposite** order — used
/// to show the reported conflict does not depend on registration order.
fn reversed_triple_table() -> @aurasuisui/multiindex.Table[
  Int32,
  (Int32, Int32, Int32),
] raise {
  let t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32, Int32)] = @aurasuisui/multiindex.Table::new()
  assert_registered(
    t.register_non_unique_ordered("shared_sorted", fn(p) { p.2 }),
  )
  assert_registered(t.register_non_unique("shared", fn(p) { p.2 }))
  assert_registered(t.register_unique_ordered("hi", fn(p) { p.1 }))
  assert_registered(t.register_unique("lo", fn(p) { p.0 }))
  t
}

///|
test "a record violating two unique indexes reports the name-ascending first one" {
  // the fixture holds (1, 10, ·) and (2, 20, ·); the candidate (1, 20, ·) violates
  // BOTH `hi` (20 belongs to the second record) and `lo` (1 belongs to the first).
  // "hi" sorts before "lo", so that is the one that must be reported — whether the
  // indexes were registered lo-first or hi-first (docs/SPEC.md §7).
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  let b = insert_ok(t, (2, 20, 2))
  match t.insert((1, 20, 3)) {
    Ok(_) => @test.fail("both unique indexes are taken")
    Err(rejected) =>
      match rejected.conflict {
        @aurasuisui/multiindex.UniqueViolation(name, key, holder) => {
          @test.assert_eq(name, "hi")
          @test.assert_eq(key, 20)
          @test.assert_eq(holder, b)
        }
        @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
          @test.fail("a single insert cannot report a batch duplicate")
      }
  }
  @test.assert_eq(t.get(a), Some((1, 10, 1)))
  // the mirror-image registration order answers identically
  let r = reversed_triple_table()
  let ra = insert_ok(r, (1, 10, 1))
  let rb = insert_ok(r, (2, 20, 2))
  match r.insert((1, 20, 3)) {
    Ok(_) => @test.fail("both unique indexes are taken")
    Err(rejected) =>
      match rejected.conflict {
        @aurasuisui/multiindex.UniqueViolation(name, key, holder) => {
          @test.assert_eq(name, "hi")
          @test.assert_eq(key, 20)
          @test.assert_eq(holder, rb)
        }
        @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
          @test.fail("a single insert cannot report a batch duplicate")
      }
  }
  @test.assert_eq(r.get(ra), Some((1, 10, 1)))
}

///|
test "update and insert_many report the same name-ascending conflict" {
  let t = triple_table()
  let a = insert_ok(t, (1, 10, 1))
  let b = insert_ok(t, (2, 20, 2))
  // update `a` so that it would take *both* of `b` keys
  match t.update(a, (2, 20, 9)) {
    Ok(_) => @test.fail("both unique indexes are taken")
    Err(rejected) =>
      match rejected {
        @aurasuisui/multiindex.Conflict(conflict, value) => {
          @test.assert_eq(value, (2, 20, 9))
          match conflict {
            @aurasuisui/multiindex.UniqueViolation(name, key, holder) => {
              @test.assert_eq(name, "hi")
              @test.assert_eq(key, 20)
              @test.assert_eq(holder, b)
            }
            @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
              @test.fail("an update cannot report a batch duplicate")
          }
        }
        @aurasuisui/multiindex.StaleHandle(_, _) =>
          @test.fail("the handle is live")
      }
  }
  // and a one-member batch hitting the same two indexes
  match t.insert_many([(1, 20, 9)]) {
    Ok(_) => @test.fail("both unique indexes are taken")
    Err(rejected) => {
      @test.assert_eq(rejected.record, (1, 20, 9))
      match rejected.conflict {
        @aurasuisui/multiindex.UniqueViolation(name, _, _) =>
          @test.assert_eq(name, "hi")
        @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
          @test.fail("nothing is in the batch twice")
      }
    }
  }
  // neither refusal moved anything
  @test.assert_eq(t.get(a), Some((1, 10, 1)))
  @test.assert_eq(t.get(b), Some((2, 20, 2)))
  @test.assert_eq(t.len(), 2)
}
