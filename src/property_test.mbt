// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Black-box property tests: random `insert` / `remove` / `clear` sequences with
// the observable invariants re-checked after EVERY step.
//
// The private-field form of I1 / I2 / I6 lives in `property_wbtest.mbt`: MoonBit
// compiles `*_test.mbt` as an external package, so `free` / `order` / `gens` are
// not reachable from here (see CHANGELOG Notes/Deviations).

///|
/// Re-assert the black-box projection of the storage invariants against a shadow
/// model that holds the handles which should still be live, in insertion order:
/// - I2: `len()` agrees with the number of records `iter()` yields, and with the
///   number of model entries
/// - every handle believed live still resolves to its record
/// - `iter()` walks the live records in insertion order
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
  let seen : Array[V] = []
  for value in t.iter() {
    seen.push(value)
  }
  @test.assert_eq(seen.length(), model.length())
  let mut j = 0
  while j < model.length() {
    @test.assert_eq(seen[j], model[j].1)
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
            @test.fail("insert returned Err although no index is registered")
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
            // a stale handle must be rejected and must not touch its slot's
            // current occupant (ABA guard); check_observable re-verifies that
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
            @test.fail("insert returned Err although no index is registered")
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
          @test.fail("insert returned Err although no index is registered")
      }
      @test.assert_eq(t.get(fresh), Some(-j))
      // every stale handle stays dead ...
      let mut k = 0
      while k < before.length() {
        @test.assert_eq(t.get(before[k]), None)
        @test.assert_eq(t.remove(before[k]), None)
        k = k + 1
      }
      // ... and every record inserted after the clear is still there
      @test.assert_eq(t.len(), j + 1)
      j = j + 1
    }
    round = round + 1
  }
}
