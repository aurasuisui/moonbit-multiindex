// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// WHITE-BOX invariant guard for the record store and its index registry.
//
// This file owns the invariant checker and the random-sequence drivers;
// `table_wbtest.mbt` holds the focused single-field probes (free stack,
// generations, retirement, bucket bookkeeping).
//
// `*_wbtest.mbt` files are compiled *inside* the package, which is the only place
// where I1 (`order` holds live slots, each once), I6 (`free` is clean) and the
// index invariants I3 / I4 / I5 / I7 can be asserted at all — MoonBit compiles
// `*_test.mbt` as an external package and `Table`'s fields are private (see
// CHANGELOG Notes/Deviations). `property_test.mbt` holds the black-box half.

///|
/// Assert every invariant of `t` by **delegating to the public checker**.
///
/// docs/SPEC.md §3.4 makes `Table::verify_invariants` the single implementation of
/// the invariant checks (I1–I9 plus the index invariants). A second copy here would
/// be free to drift away from the shipped one, so this wrapper does nothing but turn
/// the returned message into a test failure.
///
/// The "the guard is not vacuous" tests below matter **more** after this change, not
/// less: the checker under test is now the code the library ships, and only they can
/// show that it really rejects a corrupted table.
fn[K : Eq + Debug, V] check_invariants(t : Table[K, V]) -> Unit raise {
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
}

///|
/// A table with all four quadrants registered over `(unique, unique, shared)`
/// records: the two unique indexes project disjoint fields, so records can share
/// a non-unique key (which is what makes multi-record buckets testable).
fn wb_indexed_table() -> Table[Int32, (Int32, Int32, Int32)] raise {
  let t : Table[Int32, (Int32, Int32, Int32)] = Table::new()
  let registrations : Array[Result[Unit, RegisterError[Int32]]] = [
    t.register_unique("lo", fn(p) { p.0 }),
    t.register_unique_ordered("hi", fn(p) { p.1 }),
    t.register_non_unique("shared", fn(p) { p.2 }),
    t.register_non_unique_ordered("shared_sorted", fn(p) { p.2 }),
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
/// Insert a record whose keys the caller knows are free.
fn wb_insert_indexed(
  t : Table[Int32, (Int32, Int32, Int32)],
  record : (Int32, Int32, Int32),
) -> RowId raise {
  match t.insert(record) {
    Ok(id) => id
    Err(_) => @test.fail("insert conflicted although the test chose a free key")
  }
}

///|
/// Drop `id` from a shadow model, asserting the removed value.
fn wb_model_remove(
  model : Array[(RowId, (Int32, Int32, Int32))],
  id : RowId,
  value : (Int32, Int32, Int32),
) -> Unit raise {
  let mut i = 0
  let mut found = false
  while i < model.length() && !found {
    if model[i].0 == id {
      @test.assert_eq(model[i].1, value)
      let n = model.length()
      let mut j = i
      while j + 1 < n {
        model[j] = model[j + 1]
        j = j + 1
      }
      model.pop() |> ignore
      found = true
    }
    i = i + 1
  }
  @test.assert_eq(found, true)
}

///|
test "qc: invariants hold after every step of a random insert/remove sequence" {
  let r = @random.Rand()
  let mut round = 0
  while round < 30 {
    let t : Table[Int32, Int32] = Table::new()
    let issued : Array[RowId] = []
    // parallel to `issued`: whether that handle should still be live
    let alive : Array[Bool] = []
    let mut step = 0
    while step < 150 {
      let op = r.int(limit=10)
      if op < 6 {
        match t.insert(step) {
          Ok(id) => {
            issued.push(id)
            alive.push(true)
          }
          Err(_) =>
            @test.fail("insert returned Err although no index is registered")
        }
      } else if op < 9 {
        if issued.length() > 0 {
          let pick = r.int(limit=issued.length())
          let id = issued[pick]
          let removed = t.remove(id)
          if alive[pick] {
            match removed {
              Some(_) => ()
              None => @test.fail("remove rejected a handle that was still live")
            }
            alive[pick] = false
          } else {
            @test.assert_eq(removed, None)
          }
        }
      } else {
        t.clear()
        let mut k = 0
        while k < alive.length() {
          alive[k] = false
          k = k + 1
        }
      }
      check_invariants(t)
      step = step + 1
    }
    round = round + 1
  }
}

///|
test "qc: indexed tables satisfy I3/I4/I5/I7 after every step" {
  let r = @random.Rand()
  let mut round = 0
  while round < 25 {
    let t = wb_indexed_table()
    let model : Array[(RowId, (Int32, Int32, Int32))] = []
    let issued : Array[RowId] = []
    let alive : Array[Bool] = []
    let mut step = 0
    while step < 80 {
      let op = r.int(limit=10)
      if op < 6 {
        // a small key space, so unique collisions really happen
        let record = (r.int(limit=5), r.int(limit=4), r.int(limit=3))
        let mut conflict = false
        let mut i = 0
        while i < model.length() {
          if model[i].1.0 == record.0 || model[i].1.1 == record.1 {
            conflict = true
          }
          i = i + 1
        }
        match t.insert(record) {
          Ok(id) => {
            @test.assert_eq(conflict, false)
            issued.push(id)
            alive.push(true)
            model.push((id, record))
          }
          Err(rejected) => {
            @test.assert_eq(conflict, true)
            @test.assert_eq(rejected.record, record)
          }
        }
      } else if op < 9 {
        if issued.length() > 0 {
          let pick = r.int(limit=issued.length())
          let id = issued[pick]
          if alive[pick] {
            match t.remove(id) {
              Some(value) => {
                wb_model_remove(model, id, value)
                alive[pick] = false
              }
              None => @test.fail("remove rejected a handle that was still live")
            }
          } else {
            @test.assert_eq(t.remove(id), None)
          }
        }
      } else {
        t.clear()
        model.clear()
        let mut k = 0
        while k < alive.length() {
          alive[k] = false
          k = k + 1
        }
      }
      check_invariants(t)
      step = step + 1
    }
    round = round + 1
  }
}

///|
test "the invariant guard is not vacuous: it rejects a corrupted free list" {
  let t : Table[Int32, Int32] = Table::new()
  let a = wb_insert(t, 1)
  let b = wb_insert(t, 2)
  t.remove(b) |> ignore
  check_invariants(t)
  t.free.push(b.slot) // corrupt I6: the same slot twice on `free`
  let caught = try {
    check_invariants(t)
    false
  } catch {
    _ => true
  }
  @test.assert_eq(caught, true)
  @test.assert_eq(t.get(a), Some(1))
}

///|
test "the invariant guard is not vacuous: it rejects a corrupted order array" {
  let t : Table[Int32, Int32] = Table::new()
  let a = wb_insert(t, 1)
  check_invariants(t)
  t.order.push(a.slot) // corrupt I1: the same live slot twice in `order`
  let caught = try {
    check_invariants(t)
    false
  } catch {
    _ => true
  }
  @test.assert_eq(caught, true)
}

///|
test "the invariant guard is not vacuous: it rejects a corrupted positions array" {
  let t : Table[Int32, Int32] = Table::new()
  let a = wb_insert(t, 1)
  let b = wb_insert(t, 2)
  check_invariants(t)
  t.positions[b.slot] = 0 // corrupt I1: b sits at order index 1, not 0
  let caught = try {
    check_invariants(t)
    false
  } catch {
    _ => true
  }
  @test.assert_eq(caught, true)
  @test.assert_eq(t.get(a), Some(1))
}

///|
test "the invariant guard is not vacuous: it rejects a dead slot without the -1 sentinel" {
  let t : Table[Int32, Int32] = Table::new()
  let a = wb_insert(t, 1)
  let b = wb_insert(t, 2)
  t.remove(b) |> ignore
  check_invariants(t)
  t.positions[b.slot] = 1 // corrupt I1: a dead slot must carry -1
  let caught = try {
    check_invariants(t)
    false
  } catch {
    _ => true
  }
  @test.assert_eq(caught, true)
  @test.assert_eq(t.get(a), Some(1))
}

///|
test "the invariant guard is not vacuous: it rejects a dangling order entry" {
  let t : Table[Int32, Int32] = Table::new()
  let a = wb_insert(t, 1)
  t.remove(a) |> ignore
  check_invariants(t)
  t.order.push(a.slot) // corrupt I2/I1: `order` names a slot that is not live
  let caught = try {
    check_invariants(t)
    false
  } catch {
    _ => true
  }
  @test.assert_eq(caught, true)
}

///|
test "the invariant guard is not vacuous: it rejects a bucket whose record is gone" {
  let t = wb_indexed_table()
  let id = wb_insert_indexed(t, (1, 10, 7))
  check_invariants(t)
  t.rows[id.slot] = None // corrupt: every index still lists the slot (I4/I7)
  let caught = try {
    check_invariants(t)
    false
  } catch {
    _ => true
  }
  @test.assert_eq(caught, true)
}

///|
test "the invariant guard is not vacuous: it rejects a bucket entry under the wrong key" {
  let t = wb_indexed_table()
  let a = wb_insert_indexed(t, (1, 10, 7))
  let b = wb_insert_indexed(t, (2, 20, 7))
  check_invariants(t)
  match t.indexes.get("lo") {
    Some(index) => index.add(b.slot, 1) // I4: b projects to 2, not to 1
    None => @test.fail("the index vanished")
  }
  let caught = try {
    check_invariants(t)
    false
  } catch {
    _ => true
  }
  @test.assert_eq(caught, true)
  @test.assert_eq(t.get(a), Some((1, 10, 7)))
}

// ---------------------------------------------------------------------------
// M3: update / modify under the invariant guard
// ---------------------------------------------------------------------------

///|
/// Whether `candidate` collides with any live model record other than `skip`.
fn wb_model_conflicts(
  model : Array[(RowId, (Int32, Int32, Int32))],
  skip : Int32,
  candidate : (Int32, Int32, Int32),
) -> Bool {
  let mut i = 0
  let mut conflict = false
  while i < model.length() {
    if i != skip && (model[i].1.0 == candidate.0 || model[i].1.1 == candidate.1) {
      conflict = true
    }
    i = i + 1
  }
  conflict
}

///|
/// Where `id` sits in the model, or `-1`.
fn wb_model_index(
  model : Array[(RowId, (Int32, Int32, Int32))],
  id : RowId,
) -> Int32 {
  let mut i = 0
  let mut found = -1
  while i < model.length() {
    if model[i].0 == id {
      found = i
    }
    i = i + 1
  }
  found
}

///|
test "qc: update / modify keep the invariants intact after every step" {
  let r = @random.Rand()
  let mut round = 0
  while round < 20 {
    let t = wb_indexed_table()
    let model : Array[(RowId, (Int32, Int32, Int32))] = []
    let issued : Array[RowId] = []
    let alive : Array[Bool] = []
    let mut seed = 0
    while seed < 6 {
      let record = (seed, seed + 10, seed % 3)
      let id = wb_insert_indexed(t, record)
      issued.push(id)
      alive.push(true)
      model.push((id, record))
      seed = seed + 1
    }
    let mut step = 0
    while step < 60 {
      let pick = r.int(limit=issued.length())
      let id = issued[pick]
      // a small key space, so both unique indexes really do collide
      let candidate = (r.int(limit=8), r.int(limit=5) + 10, r.int(limit=3))
      if alive[pick] {
        let at = wb_model_index(model, id)
        @test.assert_eq(at >= 0, true)
        let conflicted = wb_model_conflicts(model, at, candidate)
        let outcome = if r.int(limit=2) == 0 {
          t.modify(id, fn(_) { candidate })
        } else {
          t.update(id, candidate)
        }
        match outcome {
          Ok(_) => {
            @test.assert_eq(conflicted, false)
            model[at] = (id, candidate)
          }
          Err(rejected) =>
            match rejected {
              Conflict(_, value) => {
                @test.assert_eq(conflicted, true)
                @test.assert_eq(value, candidate)
              }
              StaleHandle(_, _) => @test.fail("the handle was live")
            }
        }
      } else {
        // a stale handle: both paths report it and change nothing
        match t.update(id, candidate) {
          Ok(_) => @test.fail("a stale handle must not update")
          Err(_) => ()
        }
        match t.modify(id, fn(_) { candidate }) {
          Ok(_) => @test.fail("a stale handle must not modify")
          Err(_) => ()
        }
      }
      check_invariants(t)
      step = step + 1
    }
    round = round + 1
  }
}
