// Manual A/B timing: ordered `remove` (shifts the `order` suffix) versus
// `swap_remove` (overwrites the hole with the tail entry) on the same data.
//
// Both paths perform the *same* recovery work (row clear, generation bump, free
// stack, every index bucket removal, len/version), so the difference isolates the
// `order` maintenance: O(len) shifting versus one swap + two `positions` stores.
//
// Measurement discipline (learned the hard way, see bench/README.md):
//
// - Build the table, materialise its handles, and warm it *outside* the clock,
//   and — crucially — keep all of that in the *caller*. A helper that builds its
//   own 100_000-row table measures ~10-15 us per deletion instead of ~0.7 us no
//   matter how many deletions are timed: the first allocation inside the timed
//   region triggers a whole-heap sweep whose cost is O(live rows), and that
//   one-off cost is then divided by the batch size. Build-inside-the-helper was
//   the bug behind the "swap_remove is linear after all" scare; with the build
//   hoisted into the caller the same deletion loop reports its true cost.
// - Warm with a drain of the last 20% of the handles: it primes the index and
//   `free`-stack paths, and it keeps the first timed allocation away from a
//   fresh, never-collected heap.
// - Delete `deletions` handles from the middle of the order, ascending, so the
//   ordered path always shifts about half of `order`.
// - Repeat and report the fastest run (the convention used elsewhere here).

///|
/// Handles of `t` in insertion (order) sequence, without the payload.
fn handles(t : @multiindex.Table[Int32, Row]) -> Array[@multiindex.RowId] {
  t.iter().to_array().map(fn(pair) { pair.0 })
}

///|
/// Drop `count` handles at the far end of the order, outside the clock.
fn warm_drain(
  t : @multiindex.Table[Int32, Row],
  ids : Array[@multiindex.RowId],
  count : Int32,
) -> Unit {
  let mut e = 0
  while e < count {
    t.swap_remove(ids[ids.length() - 1 - e]) |> ignore
    e = e + 1
  }
}

///|
/// Microseconds per deletion of `count` middle-of-order handles via `remove`.
fn time_remove(
  t : @multiindex.Table[Int32, Row],
  ids : Array[@multiindex.RowId],
  start : Int32,
  count : Int32,
) -> Double {
  let begin = @bench.monotonic_clock_start()
  let mut i = 0
  while i < count {
    t.remove(ids[start + i]) |> ignore
    i = i + 1
  }
  @bench.monotonic_clock_end(begin) / count.to_double()
}

///|
/// Microseconds per deletion of `count` middle-of-order handles via `swap_remove`.
fn time_swap_remove(
  t : @multiindex.Table[Int32, Row],
  ids : Array[@multiindex.RowId],
  start : Int32,
  count : Int32,
) -> Double {
  let begin = @bench.monotonic_clock_start()
  let mut i = 0
  while i < count {
    t.swap_remove(ids[start + i]) |> ignore
    i = i + 1
  }
  @bench.monotonic_clock_end(begin) / count.to_double()
}

///|
/// Three sizes x two shapes (k=1 isolates `order`; k=8 exercises every index
/// kind), fastest of `reps` batches, reported as microseconds per deletion.
pub fn run_swap_comparison() -> Unit {
  let sizes : Array[Int32] = [1_000, 10_000, 100_000]
  let reps = 3
  println(
    "# [manual] swap_remove vs remove: middle-of-order deletions, fastest of 3, us per deletion",
  )
  for size in sizes {
    for k in [1, 8] {
      let deletions = if size >= 10_000 { 1_000 } else { 250 }
      let warm = size / 5
      // Two tables: the ordered path leaves the order shifted, the swapping path
      // does not, and each measurement deserves the same starting state.
      let t_remove = build(make_rows(size), k)
      let ids_remove = handles(t_remove)
      warm_drain(t_remove, ids_remove, warm)
      let t_swap = build(make_rows(size), k)
      let ids_swap = handles(t_swap)
      warm_drain(t_swap, ids_swap, warm)
      // Keep every batch inside the surviving prefix: the warm drain took the
      // last `warm` handles away, and `reps` batches each consume `deletions`.
      let span = size - warm
      let offset = (span - deletions * 3) / 2
      let mut best_remove = 1.0e18
      let mut best_swap = 1.0e18
      let mut r = 0
      while r < reps {
        let base = offset + r * deletions
        let o = time_remove(t_remove, ids_remove, base, deletions)
        if o < best_remove {
          best_remove = o
        }
        let s = time_swap_remove(t_swap, ids_swap, base, deletions)
        if s < best_swap {
          best_swap = s
        }
        r = r + 1
      }
      println(
        "# swap_compare n=\{size} k=\{k} deletions=\{deletions} remove_us=\{best_remove} swap_remove_us=\{best_swap} speedup=\{best_remove / best_swap}x",
      )
    }
  }
}
