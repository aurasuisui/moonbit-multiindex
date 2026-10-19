// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// JSON round-trip tests (docs/SPEC.md §8): records and their insertion order survive,
// the registry does not travel, re-registering rebuilds every index, and malformed input
// is reported rather than swallowed.

///|
test "a round trip preserves the records and their insertion order" {
  let t = triple_table()
  insert_ok(t, (1, 10, 1)) |> ignore
  insert_ok(t, (2, 20, 2)) |> ignore
  let removed = insert_ok(t, (3, 30, 1))
  insert_ok(t, (4, 40, 3)) |> ignore
  // leave a hole, so the order under test is not simply "slot order"
  t.remove(removed) |> ignore
  let json = t.to_json()
  let loaded : @aurasuisui/multiindex.Table[Int32, (Int32, Int32, Int32)] = @aurasuisui/multiindex.Table::from_json(
    json,
  )
  @test.assert_eq(loaded.len(), t.len())
  // the registry deliberately does not travel
  @test.assert_eq(loaded.index_names().length(), 0)
  @test.assert_eq(t.index_names().length(), 4)
  // same records, same insertion order, same identities-after-reload
  let before = t.iter().to_array()
  let after = loaded.iter().to_array()
  @test.assert_eq(after.length(), before.length())
  let mut i = 0
  while i < before.length() {
    @test.assert_eq(after[i].1, before[i].1)
    i = i + 1
  }
  // and the JSON carries nothing else
  @test.assert_eq(json.stringify().contains("records"), true)
  @test.assert_eq(json.stringify().contains("index"), false)
}

///|
test "registering the indexes again makes the loaded table answer identically" {
  let t = triple_table()
  insert_ok(t, (1, 10, 7)) |> ignore
  insert_ok(t, (2, 20, 7)) |> ignore
  insert_ok(t, (3, 30, 8)) |> ignore
  let loaded : @aurasuisui/multiindex.Table[Int32, (Int32, Int32, Int32)] = @aurasuisui/multiindex.Table::from_json(
    t.to_json(),
  )
  // the §3.1 backfill does the reindexing — no second mechanism
  assert_registered(loaded.register_unique("lo", fn(p) { p.0 }))
  assert_registered(loaded.register_unique_ordered("hi", fn(p) { p.1 }))
  assert_registered(loaded.register_non_unique("shared", fn(p) { p.2 }))
  assert_registered(
    loaded.register_non_unique_ordered("shared_sorted", fn(p) { p.2 }),
  )
  @test.assert_eq(loaded.index_names().length(), 4)
  // every quadrant answers like the original
  let mut k = 0
  while k <= 40 {
    @test.assert_eq(
      loaded.get_by("hi", k).map(fn(pair) { pair.1 }),
      t.get_by("hi", k).map(fn(pair) { pair.1 }),
    )
    k = k + 1
  }
  @test.assert_eq(loaded.iter_by("shared", 7).to_array().length(), 2)
  @test.assert_eq(loaded.range_by("hi", 10, 30).to_array().length(), 3)
  @test.assert_eq(loaded.iter_desc_by("shared_sorted").to_array().length(), 3)
  @test.assert_eq(loaded.index_stats("shared").longest_bucket, 2)
  match loaded.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
}

///|
/// Run `from_json` and report whether it raised (a MoonBit `JsonDecodeError` **is**
/// catchable — unlike the `abort`s of docs/SPEC.md §7.1).
fn decode_raises(json : Json) -> Bool {
  let caught = try {
    let _ : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::from_json(
      json,
    )
    false
  } catch {
    _ => true
  }
  caught
}

///|
test "malformed input is reported, never silently accepted" {
  // no `records` field at all
  @test.assert_eq(decode_raises(@json.parse("{}")), true)
  // the field is there but not an array
  @test.assert_eq(decode_raises(@json.parse("{\"records\": 42}")), true)
  // the array holds something that cannot be a record of this type (strings, not ints)
  @test.assert_eq(
    decode_raises(@json.parse("{\"records\": [\"not-an-int\"]}")),
    true,
  )
  // and the empty-but-well-formed case is *not* an error
  @test.assert_eq(decode_raises(@json.parse("{\"records\": []}")), false)
  let empty : @aurasuisui/multiindex.Table[Int32, Int32] = @aurasuisui/multiindex.Table::from_json(
    @json.parse("{\"records\": []}"),
  )
  @test.assert_eq(empty.len(), 0)
}
