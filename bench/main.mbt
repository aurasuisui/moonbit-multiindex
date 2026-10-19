// Timing benchmarks for aurasuisui/multiindex (published artifact).
//
// Standalone module, deliberately NOT part of the root package — same layout as
// `cmd/`: it imports the PUBLISHED package, so the numbers measure exactly what
// users install. Uses the official @bench framework (adaptive batching, winsorized
// statistics). Every closure ends in `b.keep(..)` so nothing is optimized away, and
// each closure performs `n` operations, so per-op cost = reported microseconds / n.
//
// Run with:  moon run --release bench/main.mbt
//
// Reporting discipline (see bench/README.md): the point is the **k-vs-throughput
// trade-off table** — "more indexes cost more per write" — not a single headline
// number. Every write benchmark is therefore run for k = 1, 2, 4, 8.

///|
/// One record. Eight `Int` fields, so a table can carry up to eight indexes over
/// the same records while every index still projects to the `Int` key type.
struct Row {
  a : Int32
  b : Int32
  c : Int32
  d : Int32
  e : Int32
  f : Int32
  g : Int32
  h : Int32
}

///|
/// `n` rows whose first four fields are distinct (so the unique indexes never collide).
///
/// The last four fields span both bucket regimes on purpose, because the interesting
/// question is *where the index stops winning*: `e` is nearly unique (≈2 records per
/// bucket — a selective key), while `f`/`g`/`h` cycle through tiny key spaces (up to
/// n/8 records per bucket — fat buckets).
fn make_rows(n : Int32) -> Array[Row] {
  let rows : Array[Row] = []
  for i in 0..<n {
    rows.push({
      a: i,
      b: i,
      c: i,
      d: i,
      e: i / 2,
      f: i % 32,
      g: i % 16,
      h: i % 8,
    })
  }
  rows
}

///|
/// A table with the first `k` indexes registered over `rows`.
fn build(rows : Array[Row], k : Int32) -> @multiindex.Table[Int32, Row] {
  let t : @multiindex.Table[Int32, Row] = @multiindex.Table::new()
  if k > 0 {
    let _ = t.register_unique("a", fn(r) { r.a })
  }
  if k > 1 {
    let _ = t.register_non_unique("b", fn(r) { r.b })
  }
  if k > 2 {
    let _ = t.register_unique_ordered("c", fn(r) { r.c })
  }
  if k > 3 {
    let _ = t.register_non_unique_ordered("d", fn(r) { r.d })
  }
  if k > 4 {
    let _ = t.register_non_unique("e", fn(r) { r.e })
  }
  if k > 5 {
    let _ = t.register_non_unique("f", fn(r) { r.f })
  }
  if k > 6 {
    let _ = t.register_non_unique("g", fn(r) { r.g })
  }
  if k > 7 {
    let _ = t.register_non_unique("h", fn(r) { r.h })
  }
  let mut i = 0
  while i < rows.length() {
    t.insert(rows[i]) |> ignore
    i = i + 1
  }
  t
}

///|
/// Deterministic LCG, so probe keys are spread the same way on every run.
fn next_state(state : Int32) -> Int32 {
  (state * 1103515245 + 12345) & 0x7FFF_FFFF
}

///|
/// The k values the write benchmarks sweep.
fn k_values() -> Array[Int32] {
  [1, 2, 4, 8]
}

///|
fn main {
  let n = 20_000
  let rows = make_rows(n)
  let bench = @bench.Bench()
  println(
    "# records per table: \{n}; reported microseconds are per ITERATION (n ops)",
  )

  let full = build(rows, 8)

  // ---- lookups: index vs linear scan -------------------------------------
  println("# [bench] get_by-unique.index")
  bench.bench(name="get_by-unique.index", count=5, fn() {
    let mut state = 0x1234_5678
    let mut acc = 0
    for _ in 0..<n {
      state = next_state(state)
      match full.get_by("a", state % n) {
        Some((_, row)) => acc = acc + row.a
        None => ()
      }
    }
    bench.keep(acc)
  })
  println("# [bench] get_by-unique.linear-scan")
  bench.bench(name="get_by-unique.linear-scan", count=5, fn() {
    let mut state = 0x1234_5678
    let mut acc = 0
    for _ in 0..<n {
      state = next_state(state)
      let wanted = state % n
      let mut i = 0
      while i < rows.length() {
        if rows[i].a == wanted {
          acc = acc + rows[i].a
        }
        i = i + 1
      }
    }
    bench.keep(acc)
  })
  // probes the FAT bucket: `g` cycles through 16 values, so each key holds n/16
  // records — the regime where the index stops paying for itself
  println("# [bench] iter_by-non-unique.fat-bucket.index")
  bench.bench(name="iter_by-non-unique.fat-bucket.index", count=5, fn() {
    let mut acc = 0
    for j in 0..<n {
      for _, row in full.iter_by("g", j % 16) {
        acc = acc + row.g
      }
    }
    bench.keep(acc)
  })
  println("# [bench] iter_by-non-unique.fat-bucket.linear-scan")
  bench.bench(name="iter_by-non-unique.fat-bucket.linear-scan", count=5, fn() {
    let mut acc = 0
    for j in 0..<n {
      let wanted = j % 16
      let mut i = 0
      while i < rows.length() {
        if rows[i].g == wanted {
          acc = acc + rows[i].g
        }
        i = i + 1
      }
    }
    bench.keep(acc)
  })
  println("# [bench] range_by-ordered.index")
  bench.bench(name="range_by-ordered.index", count=5, fn() {
    let mut acc = 0
    for _, row in full.range_by("c", n / 4, n / 2) {
      acc = acc + row.c
    }
    bench.keep(acc)
  })
  println("# [bench] range_by-ordered.linear-scan")
  bench.bench(name="range_by-ordered.linear-scan", count=5, fn() {
    let mut acc = 0
    let lo = n / 4
    let hi = n / 2
    let mut i = 0
    while i < rows.length() {
      if rows[i].c >= lo && rows[i].c <= hi {
        acc = acc + rows[i].c
      }
      i = i + 1
    }
    bench.keep(acc)
  })

  // ---- selectivity: where the index stops winning -------------------------
  println("# [bench] iter_by-non-unique.selective.index")
  bench.bench(name="iter_by-non-unique.selective.index", count=5, fn() {
    let mut state = 0x2468_1357
    let mut acc = 0
    for _ in 0..<n {
      state = next_state(state)
      for _, row in full.iter_by("e", state % (n / 2)) {
        acc = acc + row.e
      }
    }
    bench.keep(acc)
  })
  println("# [bench] iter_by-non-unique.selective.linear-scan")
  bench.bench(name="iter_by-non-unique.selective.linear-scan", count=5, fn() {
    let mut state = 0x2468_1357
    let mut acc = 0
    for _ in 0..<n {
      state = next_state(state)
      let wanted = state % (n / 2)
      let mut i = 0
      while i < rows.length() {
        if rows[i].e == wanted {
          acc = acc + rows[i].e
        }
        i = i + 1
      }
    }
    bench.keep(acc)
  })
  println("# [bench] range_by-ordered.narrow.index")
  bench.bench(name="range_by-ordered.narrow.index", count=5, fn() {
    let mut state = 0x2468_1357
    let mut acc = 0
    for _ in 0..<n {
      state = next_state(state)
      let pivot = state % (n - 20)
      for _, row in full.range_by("c", pivot, pivot + 10) {
        acc = acc + row.c
      }
    }
    bench.keep(acc)
  })
  println("# [bench] range_by-ordered.narrow.linear-scan")
  bench.bench(name="range_by-ordered.narrow.linear-scan", count=5, fn() {
    let mut state = 0x2468_1357
    let mut acc = 0
    for _ in 0..<n {
      state = next_state(state)
      let pivot = state % (n - 20)
      let mut i = 0
      while i < rows.length() {
        if rows[i].c >= pivot && rows[i].c <= pivot + 10 {
          acc = acc + rows[i].c
        }
        i = i + 1
      }
    }
    bench.keep(acc)
  })
  // ---- writes as k grows -------------------------------------------------
  let ks = k_values()
  for ki in 0..<ks.length() {
    let k = ks[ki]
    println("# [bench] insert-fresh.k\{k}")
    bench.bench(name="insert-fresh.k\{k}", count=5, fn() {
      let fresh = make_rows(n)
      let t = build(fresh, k)
      bench.keep(t.len())
    })
    println("# [bench] remove.k\{k}")
    bench.bench(name="remove.k\{k}", count=5, fn() {
      let t = build(rows, k)
      let ids = t.iter().to_array()
      let mut i = 0
      while i < ids.length() {
        t.remove(ids[i].0) |> ignore
        i = i + 1
      }
      bench.keep(t.len())
    })
  }

  // ---- slot reuse storm --------------------------------------------------
  println("# [bench] slot-reuse-storm.k8")
  bench.bench(name="slot-reuse-storm.k8", count=5, fn() {
    let t = build(rows, 8)
    let ids = t.iter().to_array()
    let mut churn = 0
    let mut i = 0
    while i < ids.length() {
      t.remove(ids[i].0) |> ignore
      let row = rows[i]
      match t.insert({ ..row, a: n + i, b: n + i, c: n + i, d: n + i, }) {
        Ok(_) => churn = churn + 1
        Err(_) => ()
      }
      i = i + 1
    }
    bench.keep(churn)
  })

  // The @bench framework collects the runs; this is where they are reported.
  println(bench.dump_summaries())
}
