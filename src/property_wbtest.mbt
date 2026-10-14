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
/// Every bucket of `index` as `(key, slots)`, in the index's own iteration order.
///
/// The library itself does not enumerate buckets (M5's `index_stats` will); the
/// white-box tests need the raw view to assert I3 / I4 / I5 / I7, and being
/// in-package lets them open the private enum directly.
fn[K, V] index_buckets(index : Index[K, V]) -> Array[(K, Array[Int])] {
  let out : Array[(K, Array[Int])] = []
  match index {
    HashUnique(_, buckets) =>
      for key, slot in buckets {
        out.push((key, [slot]))
      }
    SortedUnique(_, buckets) =>
      for key, slot in buckets {
        out.push((key, [slot]))
      }
    HashMulti(_, buckets) =>
      for key, set in buckets {
        out.push((key, set.to_array()))
      }
    SortedMulti(_, buckets) =>
      for key, set in buckets {
        out.push((key, set.to_array()))
      }
  }
  out
}

///|
/// Assert every invariant of `t` directly on its private fields:
///
///   I1  every slot in `order` is live, and no slot appears twice
///   I2  live rows == `len` == `order.length()`
///   I6  `free` has no duplicates and is disjoint from the live set
///
/// and, for every registered index,
///
///   I3  no slot appears twice inside one bucket
///   I4  every bucket slot holds a record whose projection is that bucket's key
///   I5  a unique index never holds two records under one key
///   I7  every live record appears exactly once, under its own key (and no
///       bucket points at a slot that holds nothing)
///
/// plus the bookkeeping that makes I9 observable: `rows` and `gens` stay parallel
/// arrays, every dead slot is either on `free` or **retired** (generation at
/// `GEN_MAX`), and a registry key always equals the name inside the index.
fn[K : Hash + Eq + Compare + Debug, V] check_invariants(
  t : Table[K, V],
) -> Unit raise {
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
  // ---- index invariants ----------------------------------------------------
  for name, index in t.indexes {
    @test.assert_eq(index.name(), name)
    let buckets = index_buckets(index)
    let mut entries = 0
    let mut b = 0
    while b < buckets.length() {
      let (key, slots) = buckets[b]
      // I5
      if index.is_unique() {
        @test.assert_eq(slots.length() <= 1, true)
      }
      let seen : Array[Bool] = Array::make(n, false)
      let mut s = 0
      while s < slots.length() {
        let slot = slots[s]
        @test.assert_eq(slot >= 0 && slot < n, true)
        // I3
        @test.assert_eq(seen[slot], false)
        seen[slot] = true
        // I4 (and, in the `None` arm, the no-dangling-bucket half of I7)
        match t.rows[slot] {
          Some(record) => @test.assert_eq(index.project()(record), key)
          None =>
            @test.fail("an index bucket names a slot that holds no record")
        }
        s = s + 1
      }
      entries = entries + slots.length()
      b = b + 1
    }
    // I7, counting half: nothing missing, nothing extra
    @test.assert_eq(entries, t.len)
    // I7, coverage half: every live record sits in the bucket for its own key
    let mut c = 0
    while c < t.order.length() {
      let slot = t.order[c]
      match t.rows[slot] {
        Some(record) => {
          let key = index.project()(record)
          let slots = index.slots(key)
          let mut found = false
          let mut f = 0
          while f < slots.length() {
            if slots[f] == slot {
              found = true
            }
            f = f + 1
          }
          if !found {
            @test.fail("a live record is missing from one of its index buckets")
          }
        }
        None => ()
      }
      c = c + 1
    }
  }
}

///|
/// A table with all four quadrants registered over `(unique, unique, shared)`
/// records: the two unique indexes project disjoint fields, so records can share
/// a non-unique key (which is what makes multi-record buckets testable).
fn wb_indexed_table() -> Table[Int, (Int, Int, Int)] raise {
  let t : Table[Int, (Int, Int, Int)] = Table::new()
  let registrations : Array[Result[Unit, RegisterError[Int]]] = [
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
  t : Table[Int, (Int, Int, Int)],
  record : (Int, Int, Int),
) -> RowId raise {
  match t.insert(record) {
    Ok(id) => id
    Err(_) => @test.fail("insert conflicted although the test chose a free key")
  }
}

///|
/// Drop `id` from a shadow model, asserting the removed value.
fn wb_model_remove(
  model : Array[(RowId, (Int, Int, Int))],
  id : RowId,
  value : (Int, Int, Int),
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
test "qc: indexed tables satisfy I3/I4/I5/I7 after every step" {
  let r = @random.Rand::new()
  let mut round = 0
  while round < 25 {
    let t = wb_indexed_table()
    let model : Array[(RowId, (Int, Int, Int))] = []
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
