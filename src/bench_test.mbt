// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Stress (docs/DEVPLAN.md §8 / RELEASE_CHECKLIST Tier 3): >10k operations over a table
// whose non-unique index deliberately holds one very long bucket, plus a slot-reuse storm.
// The point is that nothing degrades into an inconsistency — the invariants are re-checked
// after each phase.

///|
test "stress: >10k operations with a long bucket keep the invariants" {
  let t = triple_table()
  let issued : Array[@aurasuisui/multiindex.RowId] = []
  let n = 5_000
  // 5 000 inserts; `.2` only ever takes four values, so one bucket grows to n/4
  let mut i = 0
  while i < n {
    match t.insert((i, i, i % 4)) {
      Ok(id) => issued.push(id)
      Err(_) => @test.fail("distinct .0/.1 keys cannot conflict")
    }
    i = i + 1
  }
  @test.assert_eq(t.len(), n)
  @test.assert_eq(t.index_stats("shared").longest_bucket, n / 4)
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
  // 2 500 removes (the long bucket sheds half its members)
  let mut j = 0
  while j < n / 2 {
    t.remove(issued[j]) |> ignore
    j = j + 1
  }
  @test.assert_eq(t.len(), n / 2)
  // the 2 500 removals were spread evenly over the four keys, so the long bucket
  // shrank by exactly that much: n/4 - (n/2)/4 = n/8
  @test.assert_eq(t.index_stats("shared").longest_bucket, n / 8)
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
  // 2 500 fresh inserts: every freed slot is recycled, generation bumped
  let mut k = 0
  while k < n / 2 {
    match t.insert((n + k, n + k, k % 4)) {
      Ok(_) => ()
      Err(_) => @test.fail("fresh keys cannot conflict")
    }
    k = k + 1
  }
  @test.assert_eq(t.len(), n)
  match t.verify_invariants() {
    Ok(_) => ()
    Err(message) => @test.fail(message)
  }
  // and the traversals still agree with the obvious counts
  @test.assert_eq(t.iter_by("shared", 0).to_array().length(), n / 4)
  @test.assert_eq(t.range_by("hi", 0, n + n).to_array().length(), n)
  @test.assert_eq(t.iter_desc_by("shared_sorted").to_array().length(), n)
  @test.assert_eq(t.iter_asc_by("hi").to_array().length(), n)
  // stale handles stay stale even after the storm
  @test.assert_eq(t.get(issued[0]), None)
  @test.assert_eq(t.remove(issued[0]), None)
}
