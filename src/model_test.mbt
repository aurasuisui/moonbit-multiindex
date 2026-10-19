// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Differential test (M6): drive the real table and a naive linear-scan model with the
// SAME operation stream, and assert they agree after EVERY step.
//
// The model is deliberately stupid — an `Array[(RowId, V)]` plus linear scans — so it
// shares no code with the table's slot / generation / bucket machinery. The one thing
// it does borrow is the contract itself: non-unique queries answer "smallest slot
// first" (docs/SPEC.md §3.3), because a model that ignored that would disagree by
// design rather than by bug.

///|
/// The naive model: live records, in insertion order.
struct Model {
  records : Array[(@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))]
}

///|
/// One way a batch member can be refused: by a **live** record, or by an **earlier
/// member** of the same batch.
///
/// A member can hit both kinds at once, and the table reports whichever index it
/// walks first — its registry is a hash map, so that order is stable but not sorted
/// (docs/SPEC.md pins no order). The differential test therefore collects *all* the
/// clashes of the offending member and accepts whichever one the table names.
struct MemberClash {
  live : @aurasuisui/multiindex.RowId?
  at : Int32
  name : String
  key : Int32
}

///|
/// Which projected field a probe looks at: 0 -> "lo", 1 -> "hi", 2 -> "shared".
fn field_of(record : (Int32, Int32, Int32), field : Int32) -> Int32 {
  if field == 0 {
    record.0
  } else if field == 1 {
    record.1
  } else {
    record.2
  }
}

///|
fn unique_name(field : Int32) -> String {
  if field == 0 {
    "lo"
  } else {
    "hi"
  }
}

///|
fn Model::new() -> Model {
  { records: [], }
}

///|
fn Model::len(self : Model) -> Int32 {
  self.records.length()
}

///|
fn Model::add(
  self : Model,
  id : @aurasuisui/multiindex.RowId,
  record : (Int32, Int32, Int32),
) -> Unit {
  self.records.push((id, record))
}

///|
/// Where `id` sits in the model, or `-1` (a stale handle).
fn Model::find(self : Model, id : @aurasuisui/multiindex.RowId) -> Int32 {
  let mut i = 0
  let mut found = -1
  while i < self.records.length() {
    if self.records[i].0 == id {
      found = i
    }
    i = i + 1
  }
  found
}

///|
fn Model::drop(self : Model, at : Int32) -> (Int32, Int32, Int32) {
  let record = self.records[at].1
  let n = self.records.length()
  let mut j = at
  while j + 1 < n {
    self.records[j] = self.records[j + 1]
    j = j + 1
  }
  self.records.pop() |> ignore
  record
}

///|
/// The live record holding `key` on the unique `field`, or `None`.
fn Model::unique_by(
  self : Model,
  field : Int32,
  key : Int32,
) -> (@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))? {
  let mut i = 0
  while i < self.records.length() {
    if field_of(self.records[i].1, field) == key {
      return Some(self.records[i])
    }
    i = i + 1
  }
  None
}

///|
/// Every live record with `key` on `field`, smallest slot first (the contract).
fn Model::multi_by(
  self : Model,
  field : Int32,
  key : Int32,
) -> Array[(@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))] {
  let out : Array[(@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))] = []
  let mut i = 0
  while i < self.records.length() {
    if field_of(self.records[i].1, field) == key {
      out.push(self.records[i])
    }
    i = i + 1
  }
  out.sort_by(fn(a, b) { a.0.slot - b.0.slot })
  out
}

///|
/// Every live record ordered by `field`, optionally restricted to `[lo, hi]`
/// (`half_open` makes it `[lo, hi)`), ascending or descending; slots stay ascending
/// inside one key, which is what the ordered walks promise.
fn Model::ordered(
  self : Model,
  field : Int32,
  lo : Int32?,
  hi : Int32?,
  half_open : Bool,
  descending : Bool,
) -> Array[(@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))] {
  let out : Array[(@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))] = []
  let mut i = 0
  while i < self.records.length() {
    let key = field_of(self.records[i].1, field)
    let mut keep = true
    match lo {
      Some(low) => if key < low { keep = false }
      None => ()
    }
    match hi {
      Some(high) =>
        if half_open {
          if key >= high {
            keep = false
          }
        } else if key > high {
          keep = false
        }
      None => ()
    }
    if keep {
      out.push(self.records[i])
    }
    i = i + 1
  }
  out.sort_by(fn(a, b) {
    let ka = field_of(a.1, field)
    let kb = field_of(b.1, field)
    if ka != kb {
      if descending {
        kb - ka
      } else {
        ka - kb
      }
    } else {
      a.0.slot - b.0.slot
    }
  })
  out
}

///|
/// The unique index `record` would clash with, ignoring the record named by `skip`.
///
/// When both unique indexes clash, the reported one is the index whose **name sorts
/// first** — the contract docs/SPEC.md §7 fixes so that the answer cannot depend on the
/// registry's internal iteration order.
fn Model::clash(
  self : Model,
  record : (Int32, Int32, Int32),
  skip : @aurasuisui/multiindex.RowId?,
) -> (String, Int32, @aurasuisui/multiindex.RowId)? {
  let mut best_name : String? = None
  let mut best : (String, Int32, @aurasuisui/multiindex.RowId)? = None
  let mut field = 0
  while field <= 1 {
    let key = field_of(record, field)
    match self.unique_by(field, key) {
      Some((holder, _)) => {
        let mut hit = true
        match skip {
          Some(id) => if holder == id { hit = false }
          None => ()
        }
        if hit {
          let name = unique_name(field)
          let better = match best_name {
            None => true
            Some(current) => name < current
          }
          if better {
            best_name = Some(name)
            best = Some((name, key, holder))
          }
        }
      }
      None => ()
    }
    field = field + 1
  }
  best
}

///|
/// Every clash member `i` of `batch` would hit, against the model alone.
fn Model::clashes_of(
  self : Model,
  batch : Array[(Int32, Int32, Int32)],
  i : Int32,
) -> Array[MemberClash] {
  let out : Array[MemberClash] = []
  let mut field = 0
  while field <= 1 {
    let key = field_of(batch[i], field)
    match self.unique_by(field, key) {
      Some((holder, _)) =>
        out.push({ live: Some(holder), at: -1, name: unique_name(field), key, })
      None => {
        let mut earlier = -1
        let mut j = 0
        while j < i {
          if field_of(batch[j], field) == key {
            earlier = j
          }
          j = j + 1
        }
        if earlier >= 0 {
          out.push({ live: None, at: earlier, name: unique_name(field), key, })
        }
      }
    }
    field = field + 1
  }
  out
}

///|
/// The first member of `batch` that cannot be inserted at all, or `-1`.
fn Model::first_offender(
  self : Model,
  batch : Array[(Int32, Int32, Int32)],
) -> Int32 {
  let mut i = 0
  while i < batch.length() {
    if self.clashes_of(batch, i).length() > 0 {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Element-wise comparison of two `(RowId, record)` sequences.
fn assert_same_pairs(
  actual : Array[(@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))],
  expected : Array[(@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))],
) -> Unit raise {
  @test.assert_eq(actual.length(), expected.length())
  let mut i = 0
  while i < expected.length() {
    @test.assert_eq(actual[i], expected[i])
    i = i + 1
  }
}

///|
/// The key intervals the differential test probes, as `(lo, hi)`.
fn probe_ranges() -> Array[(Int32, Int32)] {
  [(0, 100), (0, 10), (10, 30), (5, 5), (30, 10), (7, 7)]
}

///|
/// Assert the table and the model agree on **every observable answer**.
fn assert_agrees(
  t : @aurasuisui/multiindex.Table[Int32, (Int32, Int32, Int32)],
  model : Model,
) -> Unit raise {
  @test.assert_eq(t.len(), model.len())
  @test.assert_eq(t.is_empty(), model.len() == 0)
  // insertion order, identity included
  let entries = t.iter().to_array()
  assert_same_pairs(entries, model.records)
  let mut i = 0
  while i < model.records.length() {
    let (id, record) = model.records[i]
    @test.assert_eq(t.get(id), Some(record))
    @test.assert_eq(t.contains(id), true)
    i = i + 1
  }
  // key lookups over a range that covers every fixture value
  let mut k = 0
  while k <= 60 {
    @test.assert_eq(t.get_by("lo", k), model.unique_by(0, k))
    @test.assert_eq(t.get_by("hi", k), model.unique_by(1, k))
    let matches = model.multi_by(2, k)
    let first : (@aurasuisui/multiindex.RowId, (Int32, Int32, Int32))? = if matches.length() ==
      0 {
      None
    } else {
      Some(matches[0])
    }
    @test.assert_eq(t.get_by("shared", k), first)
    @test.assert_eq(t.get_by("shared_sorted", k), first)
    assert_same_pairs(t.iter_by("shared", k).to_array(), matches)
    assert_same_pairs(t.iter_by("shared_sorted", k).to_array(), matches)
    k = k + 1
  }
  // ordered walks: the full sweeps, both directions, on both ordered quadrants
  assert_same_pairs(
    t.iter_asc_by("hi").to_array(),
    model.ordered(1, None, None, false, false),
  )
  assert_same_pairs(
    t.iter_desc_by("hi").to_array(),
    model.ordered(1, None, None, false, true),
  )
  assert_same_pairs(
    t.iter_asc_by("shared_sorted").to_array(),
    model.ordered(2, None, None, false, false),
  )
  assert_same_pairs(
    t.iter_desc_by("shared_sorted").to_array(),
    model.ordered(2, None, None, false, true),
  )
  // and every probe interval, closed and half-open
  let ranges = probe_ranges()
  let mut r = 0
  while r < ranges.length() {
    let (lo, hi) = ranges[r]
    assert_same_pairs(
      t.range_by("hi", lo, hi).to_array(),
      model.ordered(1, Some(lo), Some(hi), false, false),
    )
    assert_same_pairs(
      t.range_half_open_by("hi", lo, hi).to_array(),
      model.ordered(1, Some(lo), Some(hi), true, false),
    )
    assert_same_pairs(
      t.range_by("shared_sorted", lo, hi).to_array(),
      model.ordered(2, Some(lo), Some(hi), false, false),
    )
    assert_same_pairs(
      t.range_half_open_by("shared_sorted", lo, hi).to_array(),
      model.ordered(2, Some(lo), Some(hi), true, false),
    )
    r = r + 1
  }
  // the table must also believe its own invariants
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
}

///|
test "model differential: a scripted stream of every operation agrees with the model" {
  let t = triple_table()
  let model = Model::new()
  assert_agrees(t, model)
  // insert (including a refused one)
  let a = insert_ok(t, (1, 10, 7))
  model.add(a, (1, 10, 7))
  assert_agrees(t, model)
  match t.insert((1, 20, 8)) {
    Ok(_) => @test.fail("the unique `lo` key 1 is taken")
    Err(rejected) => @test.assert_eq(rejected.record, (1, 20, 8))
  }
  assert_agrees(t, model)
  // insert_many
  match t.insert_many([(2, 20, 7), (3, 30, 7)]) {
    Ok(ids) => {
      model.add(ids[0], (2, 20, 7))
      model.add(ids[1], (3, 30, 7))
    }
    Err(_) => @test.fail("the batch is clean")
  }
  assert_agrees(t, model)
  // update, modify
  match t.update(a, (1, 10, 9)) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal update")
  }
  model.records[model.find(a)] = (a, (1, 10, 9))
  assert_agrees(t, model)
  let b = model.records[1].0
  match t.modify(b, fn(record) { (record.0, 21, record.2) }) {
    Ok(_) => ()
    Err(_) => @test.fail("a legal modify")
  }
  model.records[model.find(b)] = (b, (2, 21, 7))
  assert_agrees(t, model)
  // remove, then clear
  match t.remove(a) {
    Some(value) => {
      @test.assert_eq(value, (1, 10, 9))
      model.drop(model.find(a)) |> ignore
    }
    None => @test.fail("a is live")
  }
  assert_agrees(t, model)
  t.clear()
  model.records.clear()
  assert_agrees(t, model)
}

///|
test "model differential: random streams agree after every step" {
  let r = @random.Rand::new()
  let mut round = 0
  while round < 12 {
    let t = triple_table()
    let model = Model::new()
    let issued : Array[@aurasuisui/multiindex.RowId] = []
    let mut step = 0
    while step < 50 {
      let op = r.int(limit=10)
      if op < 3 {
        let record = (r.int(limit=8), r.int(limit=8), r.int(limit=5))
        match model.clash(record, None) {
          Some((name, key, holder)) =>
            match t.insert(record) {
              Ok(_) => @test.fail("the model says " + name + " is taken")
              Err(rejected) => {
                @test.assert_eq(rejected.record, record)
                match rejected.conflict {
                  @aurasuisui/multiindex.UniqueViolation(n, k, h) => {
                    @test.assert_eq(n, name)
                    @test.assert_eq(k, key)
                    @test.assert_eq(h, holder)
                  }
                  @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
                    @test.fail(
                      "a single insert cannot report a batch duplicate",
                    )
                }
              }
            }
          None => {
            let id = insert_ok(t, record)
            issued.push(id)
            model.add(id, record)
          }
        }
      } else if op < 5 {
        let batch : Array[(Int32, Int32, Int32)] = [
          (r.int(limit=8), r.int(limit=8), r.int(limit=5)),
          (r.int(limit=8), r.int(limit=8), r.int(limit=5)),
        ]
        let offender = model.first_offender(batch)
        if offender < 0 {
          match t.insert_many(batch) {
            Ok(ids) => {
              let mut i = 0
              while i < ids.length() {
                issued.push(ids[i])
                model.add(ids[i], batch[i])
                i = i + 1
              }
            }
            Err(_) => @test.fail("the model accepts this batch")
          }
        } else {
          let clashes = model.clashes_of(batch, offender)
          match t.insert_many(batch) {
            Ok(_) => @test.fail("the model refuses this batch")
            Err(rejected) => {
              @test.assert_eq(rejected.record, batch[offender])
              match rejected.conflict {
                @aurasuisui/multiindex.UniqueViolation(name, key, holder) => {
                  let mut matched = false
                  let mut i = 0
                  while i < clashes.length() {
                    match clashes[i].live {
                      Some(expected) =>
                        if clashes[i].name == name &&
                          clashes[i].key == key &&
                          expected == holder {
                          matched = true
                        }
                      None => ()
                    }
                    i = i + 1
                  }
                  @test.assert_eq(matched, true)
                }
                @aurasuisui/multiindex.DuplicateInBatch(name, key, at) => {
                  let mut matched = false
                  let mut i = 0
                  while i < clashes.length() {
                    if clashes[i].at == at &&
                      clashes[i].name == name &&
                      clashes[i].key == key {
                      matched = true
                    }
                    i = i + 1
                  }
                  @test.assert_eq(matched, true)
                }
              }
            }
          }
        }
      } else if op < 7 {
        if issued.length() > 0 {
          let id = issued[r.int(limit=issued.length())]
          let at = model.find(id)
          let record = (r.int(limit=8), r.int(limit=8), r.int(limit=5))
          if at < 0 {
            match t.update(id, record) {
              Ok(_) => @test.fail("a stale handle must not update")
              Err(_) => ()
            }
          } else {
            match model.clash(record, Some(id)) {
              Some((name, key, holder)) =>
                match t.update(id, record) {
                  Ok(_) => @test.fail("the model says " + name + " is taken")
                  Err(rejected) =>
                    match rejected {
                      @aurasuisui/multiindex.Conflict(conflict, value) => {
                        @test.assert_eq(value, record)
                        match conflict {
                          @aurasuisui/multiindex.UniqueViolation(n, k, h) => {
                            @test.assert_eq(n, name)
                            @test.assert_eq(k, key)
                            @test.assert_eq(h, holder)
                          }
                          @aurasuisui/multiindex.DuplicateInBatch(_, _, _) =>
                            @test.fail(
                              "an update cannot report a batch duplicate",
                            )
                        }
                      }
                      @aurasuisui/multiindex.StaleHandle(_, _) =>
                        @test.fail("the handle is live")
                    }
                }
              None => {
                match t.update(id, record) {
                  Ok(_) => ()
                  Err(_) => @test.fail("a legal update")
                }
                model.records[at] = (id, record)
              }
            }
          }
        }
      } else if op < 8 {
        if issued.length() > 0 {
          let id = issued[r.int(limit=issued.length())]
          let at = model.find(id)
          let target = (r.int(limit=8), r.int(limit=8), r.int(limit=5))
          if at < 0 {
            match t.modify(id, fn(_) { target }) {
              Ok(_) => @test.fail("a stale handle must not modify")
              Err(_) => ()
            }
          } else {
            match model.clash(target, Some(id)) {
              Some(_) =>
                match t.modify(id, fn(_) { target }) {
                  Ok(_) => @test.fail("the model refuses this transformation")
                  Err(_) => ()
                }
              None => {
                match t.modify(id, fn(_) { target }) {
                  Ok(_) => ()
                  Err(_) => @test.fail("a legal modify")
                }
                model.records[at] = (id, target)
              }
            }
          }
        }
      } else if op < 9 {
        if issued.length() > 0 {
          let id = issued[r.int(limit=issued.length())]
          let at = model.find(id)
          if at < 0 {
            @test.assert_eq(t.remove(id), None)
          } else {
            let expected = model.records[at].1
            @test.assert_eq(t.remove(id), Some(expected))
            model.drop(at) |> ignore
          }
        }
      } else {
        t.clear()
        model.records.clear()
      }
      assert_agrees(t, model)
      step = step + 1
    }
    round = round + 1
  }
}
