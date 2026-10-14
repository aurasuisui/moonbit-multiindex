// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// WHITE-BOX invariant guard for the M1 record store.
//
// This file owns the invariant checker and the random-sequence driver;
// `table_wbtest.mbt` holds the focused single-field probes (free stack,
// generations, retirement).
//
// `*_wbtest.mbt` files are compiled *inside* the package, which is the only place
// where I1 ("`order` holds live slots, each once") and I6 ("`free` has no
// duplicates and never names a live slot") can be asserted at all — MoonBit
// compiles `*_test.mbt` as an external package and `Table`'s fields are private
// (see CHANGELOG Notes/Deviations). `property_test.mbt` holds the black-box half
// of the same properties.

///|
/// Assert every storage invariant of `t` directly on its private fields:
///
///   I1  every slot in `order` is live, and no slot appears twice
///   I2  live rows == `len` == `order.length()`
///   I6  `free` has no duplicates and is disjoint from the live set
///
/// plus the bookkeeping that makes I9 observable: `rows` and `gens` stay parallel
/// arrays, and every dead slot is either on `free` or **retired** — its generation
/// has reached `GEN_MAX`, so it can never be handed out again.
fn[K, V] check_invariants(t : Table[K, V]) -> Unit raise {
  @test.assert_eq(t.rows.length(), t.gens.length())
  @test.assert_eq(t.len >= 0, true)
  // I2, internal form: counter, insertion order and live rows all agree
  @test.assert_eq(t.order.length(), t.len)
  let n = t.rows.length()
  let live : Array[Bool] = Array::make(n, false)
  let mut live_count = 0
  let mut i = 0
  while i < n {
    match t.rows[i] {
      Some(_) => {
        live[i] = true
        live_count = live_count + 1
      }
      None => ()
    }
    i = i + 1
  }
  @test.assert_eq(live_count, t.len)
  // I1
  let in_order : Array[Bool] = Array::make(n, false)
  let mut j = 0
  while j < t.order.length() {
    let slot = t.order[j]
    @test.assert_eq(slot >= 0 && slot < n, true)
    @test.assert_eq(live[slot], true)
    @test.assert_eq(in_order[slot], false)
    in_order[slot] = true
    j = j + 1
  }
  @test.assert_eq(t.order.length(), live_count)
  // I6
  let in_free : Array[Bool] = Array::make(n, false)
  let mut k = 0
  while k < t.free.length() {
    let slot = t.free[k]
    @test.assert_eq(slot >= 0 && slot < n, true)
    @test.assert_eq(in_free[slot], false)
    @test.assert_eq(live[slot], false)
    in_free[slot] = true
    k = k + 1
  }
  // I9, observable form: dead and not free means retired for good
  let mut m = 0
  while m < n {
    if !live[m] && !in_free[m] {
      @test.assert_eq(t.gens[m], GEN_MAX)
    }
    m = m + 1
  }
}

///|
test "qc: invariants hold after every step of a random insert/remove sequence" {
  let r = @random.Rand::new()
  let mut round = 0
  while round < 30 {
    let t : Table[Int, Int] = Table::new()
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
test "the invariant guard is not vacuous: it rejects a corrupted free list" {
  let t : Table[Int, Int] = Table::new()
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
  let t : Table[Int, Int] = Table::new()
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
test "the invariant guard is not vacuous: it rejects a dangling order entry" {
  let t : Table[Int, Int] = Table::new()
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
