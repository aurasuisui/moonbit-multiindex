// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Black-box property tests: random `insert` / `remove` / `clear` sequences with
// the observable invariants re-checked after EVERY step — first on a table with
// no index, then on one with all four quadrants registered.
//
// The private-field form of I1 / I2 / I6 (and of the index invariants I3 / I4 /
// I5 / I7) lives in `property_wbtest.mbt`: MoonBit compiles `*_test.mbt` as an
// external package, so `free` / `order` / `gens` / `indexes` are not reachable
// from here (see CHANGELOG Notes/Deviations).

///|
/// Re-assert the black-box projection of the storage invariants against a shadow
/// model of the handles that should still be live, in insertion order:
/// - I2: `len()` agrees with the number of records `iter()` yields (and with the
///   number of model entries)
/// - every handle believed live still resolves to its record
/// - `iter()` walks the live records in insertion order, identity included
fn[K, V : Eq + Debug] check_observable(
  t : @aurasuisui/multiindex.Table[K, V],
  model : Array[(@aurasuisui/multiindex.RowId, V)],
) -> Unit raise {
  @test.assert_eq(t.len(), model.length())
  @test.assert_eq(t.is_empty(), model.length() == 0)
  let mut i = 0
  while i < model.length() {
    let (id, value) = model[i]
    @test.assert_eq(t.get(id), Some(value))
    i = i + 1
  }
  let seen = t.iter().to_array()
  @test.assert_eq(seen.length(), model.length())
  let mut j = 0
  while j < model.length() {
    @test.assert_eq(seen[j].0, model[j].0)
    @test.assert_eq(seen[j].1, model[j].1)
    j = j + 1
  }
}

///|
/// Drop `id` from the shadow model, asserting the removed value is the one the
/// model remembered.
fn[V : Eq + Debug] model_remove(
  model : Array[(@aurasuisui/multiindex.RowId, V)],
  id : @aurasuisui/multiindex.RowId,
  value : V,
) -> Unit raise {
  let mut i = 0
  let mut found = false
  while i < model.length() && !found {
    let (mid, mvalue) = model[i]
    if mid == id {
      @test.assert_eq(mvalue, value)
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
test "qc: observable invariants hold after every step of a random sequence" {
  let r = @random.Rand::new()
  let mut round = 0
  while round < 30 {
    let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
    let model : Array[(@aurasuisui/multiindex.RowId, Int)] = []
    let issued : Array[@aurasuisui/multiindex.RowId] = []
    // parallel to `issued`: whether that handle should still be live
    let alive : Array[Bool] = []
    let mut step = 0
    while step < 120 {
      let op = r.int(limit=10)
      if op < 6 {
        let id = match t.insert(step) {
          Ok(id) => id
          Err(_) =>
            @test.fail("insert conflicted although no index is registered")
        }
        issued.push(id)
        alive.push(true)
        model.push((id, step))
      } else if op < 9 {
        if issued.length() > 0 {
          let pick = r.int(limit=issued.length())
          let id = issued[pick]
          if alive[pick] {
            match t.remove(id) {
              Some(value) => {
                model_remove(model, id, value)
                alive[pick] = false
              }
              None => @test.fail("remove rejected a handle that was still live")
            }
          } else {
            @test.assert_eq(t.remove(id), None)
            @test.assert_eq(t.get(id), None)
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
      check_observable(t, model)
      step = step + 1
    }
    round = round + 1
  }
}

///|
test "qc: handles issued before clear never resolve after it" {
  let mut round = 0
  while round < 20 {
    let t : @aurasuisui/multiindex.Table[Int, Int] = @aurasuisui/multiindex.Table::new()
    let before : Array[@aurasuisui/multiindex.RowId] = []
    let mut i = 0
    while i < 12 {
      before.push(
        match t.insert(i) {
          Ok(id) => id
          Err(_) =>
            @test.fail("insert conflicted although no index is registered")
        },
      )
      i = i + 1
    }
    t.clear()
    let mut j = 0
    while j < 15 {
      let fresh = match t.insert(-j) {
        Ok(id) => id
        Err(_) =>
          @test.fail("insert conflicted although no index is registered")
      }
      @test.assert_eq(t.get(fresh), Some(-j))
      let mut k = 0
      while k < before.length() {
        @test.assert_eq(t.get(before[k]), None)
        @test.assert_eq(t.remove(before[k]), None)
        k = k + 1
      }
      @test.assert_eq(t.len(), j + 1)
      j = j + 1
    }
    round = round + 1
  }
}

// ---------------------------------------------------------------------------
// Indexed tables (M2)
// ---------------------------------------------------------------------------

///|
/// A table with all four quadrants registered over `(unique, unique, shared)`
/// records: the unique indexes project disjoint fields, so records can share a
/// non-unique key and really fill a bucket.
fn indexed_table() -> @aurasuisui/multiindex.Table[Int, (Int, Int, Int)] raise {
  let t : @aurasuisui/multiindex.Table[Int, (Int, Int, Int)] = @aurasuisui/multiindex.Table::new()
  let registrations : Array[
    Result[Unit, @aurasuisui/multiindex.RegisterError[Int]],
  ] = [
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
/// Every index must agree with the shadow model: the unique quadrants answer with
/// exactly the model record, and the non-unique bucket holds exactly the model
/// records that share the key, ascending by slot.
fn check_indexes(
  t : @aurasuisui/multiindex.Table[Int, (Int, Int, Int)],
  model : Array[(@aurasuisui/multiindex.RowId, (Int, Int, Int))],
) -> Unit raise {
  let mut i = 0
  while i < model.length() {
    let (id, record) = model[i]
    @test.assert_eq(t.get_by("lo", record.0), Some((id, record)))
    @test.assert_eq(t.get_by("hi", record.1), Some((id, record)))
    let bucket = t.iter_by("shared", record.2).to_array()
    let mut expected = 0
    let mut k = 0
    while k < model.length() {
      if model[k].1.2 == record.2 {
        expected = expected + 1
      }
      k = k + 1
    }
    @test.assert_eq(bucket.length(), expected)
    let mut previous_slot = -1
    let mut l = 0
    while l < bucket.length() {
      @test.assert_eq(bucket[l].0.slot > previous_slot, true)
      previous_slot = bucket[l].0.slot
      @test.assert_eq(bucket[l].1.2, record.2)
      l = l + 1
    }
    i = i + 1
  }
  // a key nobody used answers empty on every quadrant, never a panic
  @test.assert_eq(t.get_by("lo", -1), None)
  @test.assert_eq(t.get_by("shared", -1), None)
  @test.assert_eq(t.iter_by("shared", -1).to_array().length(), 0)
}

///|
test "qc: indexed tables keep every bucket consistent after each step" {
  let r = @random.Rand::new()
  let mut round = 0
  while round < 25 {
    let t = indexed_table()
    let model : Array[(@aurasuisui/multiindex.RowId, (Int, Int, Int))] = []
    let issued : Array[@aurasuisui/multiindex.RowId] = []
    let alive : Array[Bool] = []
    let mut step = 0
    while step < 80 {
      let op = r.int(limit=10)
      if op < 6 {
        // a deliberately small key space, so unique collisions really happen
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
            // accepted although a unique key was taken would be a bug
            @test.assert_eq(conflict, false)
            issued.push(id)
            alive.push(true)
            model.push((id, record))
          }
          Err(rejected) => {
            @test.assert_eq(conflict, true)
            // the refused record is handed back untouched
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
                model_remove(model, id, value)
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
      check_observable(t, model)
      check_indexes(t, model)
      step = step + 1
    }
    round = round + 1
  }
}

///|
/// Whether `candidate` collides with any live model record other than `skip`.
fn model_conflicts(
  model : Array[(@aurasuisui/multiindex.RowId, (Int, Int, Int))],
  skip : Int,
  candidate : (Int, Int, Int),
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
fn model_index(
  model : Array[(@aurasuisui/multiindex.RowId, (Int, Int, Int))],
  id : @aurasuisui/multiindex.RowId,
) -> Int {
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
test "qc: update and modify keep every bucket consistent after each step" {
  let r = @random.Rand::new()
  let mut round = 0
  while round < 20 {
    let t = indexed_table()
    let model : Array[(@aurasuisui/multiindex.RowId, (Int, Int, Int))] = []
    let issued : Array[@aurasuisui/multiindex.RowId] = []
    let alive : Array[Bool] = []
    let mut seed = 0
    while seed < 6 {
      let record = (seed, seed + 10, seed % 3)
      let id = match t.insert(record) {
        Ok(id) => id
        Err(_) => @test.fail("the seeded records have distinct unique keys")
      }
      issued.push(id)
      alive.push(true)
      model.push((id, record))
      seed = seed + 1
    }
    let mut step = 0
    while step < 80 {
      let op = r.int(limit=10)
      let pick = r.int(limit=issued.length())
      let id = issued[pick]
      // a small key space, so both unique indexes really do collide
      let candidate = (r.int(limit=8), r.int(limit=5) + 10, r.int(limit=3))
      if alive[pick] {
        let at = model_index(model, id)
        @test.assert_eq(at >= 0, true)
        let conflicted = model_conflicts(model, at, candidate)
        if op % 3 == 0 {
          match t.modify(id, fn(_) { candidate }) {
            Ok(_) => {
              @test.assert_eq(conflicted, false)
              model[at] = (id, candidate)
            }
            Err(rejected) =>
              match rejected {
                @aurasuisui/multiindex.Conflict(_, value) => {
                  @test.assert_eq(conflicted, true)
                  @test.assert_eq(value, candidate)
                }
                @aurasuisui/multiindex.StaleHandle(_, _) =>
                  @test.fail("the handle was live")
              }
          }
        } else if op < 8 {
          match t.update(id, candidate) {
            Ok(_) => {
              @test.assert_eq(conflicted, false)
              model[at] = (id, candidate)
            }
            Err(rejected) =>
              match rejected {
                @aurasuisui/multiindex.Conflict(_, value) => {
                  @test.assert_eq(conflicted, true)
                  @test.assert_eq(value, candidate)
                }
                @aurasuisui/multiindex.StaleHandle(_, _) =>
                  @test.fail("the handle was live")
              }
          }
        } else {
          match t.remove(id) {
            Some(value) => {
              model_remove(model, id, value)
              alive[pick] = false
            }
            None => @test.fail("remove rejected a handle that was still live")
          }
        }
      } else {
        // a stale handle: both paths must report it and change nothing
        match t.update(id, candidate) {
          Ok(_) => @test.fail("a stale handle must not update")
          Err(rejected) =>
            match rejected {
              @aurasuisui/multiindex.StaleHandle(back, pending) => {
                @test.assert_eq(back, id)
                @test.assert_eq(pending, Some(candidate))
              }
              @aurasuisui/multiindex.Conflict(_, _) =>
                @test.fail("expected StaleHandle")
            }
        }
        match t.modify(id, fn(_) { candidate }) {
          Ok(_) => @test.fail("a stale handle must not modify")
          Err(rejected) =>
            match rejected {
              @aurasuisui/multiindex.StaleHandle(back, pending) => {
                @test.assert_eq(back, id)
                @test.assert_eq(pending, None)
              }
              @aurasuisui/multiindex.Conflict(_, _) =>
                @test.fail("expected StaleHandle")
            }
        }
      }
      check_observable(t, model)
      check_indexes(t, model)
      step = step + 1
    }
    round = round + 1
  }
}
