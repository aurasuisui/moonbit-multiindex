// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Source: the Rust reference implementation `multi_index_map` **0.15.1**
// (pinned in `tools/diffgen/Cargo.toml`, checksummed by `Cargo.lock`).
// Generator: `tools/diffgen` — regenerate with
//   cd tools/diffgen && cargo run --release -- ../../src/differential_fixture_test.mbt
// Generated: 2026-10-14 (golden stream: four quadrants + every diffable conflict path +
// a non-conflicting modify + removes).
//
// CI needs **no Rust toolchain**: this fixture is checked in and replayed by
// `src/differential_test.mbt`.

///|
/// One reference observation: the operation, whether it succeeded, and what the
/// reference implementation then saw (`records` sorted by id, probe hits sorted).
struct DiffStep {
  op : String
  rec : (Int, Int, Int, Int)
  ok : Bool
  len : Int
  records : Array[(Int, Int, Int, Int)]
  probes : Array[(String, Int, Array[Int])]
}

///|
/// The golden stream, step by step.
fn diff_fixture() -> Array[DiffStep] {
  [
    {
      op: "try_insert",
      rec: (1, 10, 7, 1),
      ok: true,
      len: 1,
      records: [(1, 10, 7, 1)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, []),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, []),
        ("ts", 99, []),
        ("tag", 7, [1]),
        ("tag", 8, []),
        ("tag", 99, []),
        ("bin", 1, [1]),
        ("bin", 2, []),
        ("bin", 3, []),
      ],
    },
    {
      op: "try_insert",
      rec: (2, 20, 7, 2),
      ok: true,
      len: 2,
      records: [(1, 10, 7, 1), (2, 20, 7, 2)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, []),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, [2]),
        ("ts", 99, []),
        ("tag", 7, [1, 2]),
        ("tag", 8, []),
        ("tag", 99, []),
        ("bin", 1, [1]),
        ("bin", 2, [2]),
        ("bin", 3, []),
      ],
    },
    {
      op: "try_insert",
      rec: (3, 30, 8, 1),
      ok: true,
      len: 3,
      records: [(1, 10, 7, 1), (2, 20, 7, 2), (3, 30, 8, 1)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, [3]),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, [2]),
        ("ts", 99, []),
        ("tag", 7, [1, 2]),
        ("tag", 8, [3]),
        ("tag", 99, []),
        ("bin", 1, [1, 3]),
        ("bin", 2, [2]),
        ("bin", 3, []),
      ],
    },
    {
      op: "try_insert",
      rec: (1, 40, 9, 3),
      ok: false,
      len: 3,
      records: [(1, 10, 7, 1), (2, 20, 7, 2), (3, 30, 8, 1)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, [3]),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, [2]),
        ("ts", 99, []),
        ("tag", 7, [1, 2]),
        ("tag", 8, [3]),
        ("tag", 99, []),
        ("bin", 1, [1, 3]),
        ("bin", 2, [2]),
        ("bin", 3, []),
      ],
    },
    {
      op: "try_insert",
      rec: (4, 10, 9, 3),
      ok: false,
      len: 3,
      records: [(1, 10, 7, 1), (2, 20, 7, 2), (3, 30, 8, 1)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, [3]),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, [2]),
        ("ts", 99, []),
        ("tag", 7, [1, 2]),
        ("tag", 8, [3]),
        ("tag", 99, []),
        ("bin", 1, [1, 3]),
        ("bin", 2, [2]),
        ("bin", 3, []),
      ],
    },
    {
      op: "try_insert",
      rec: (4, 40, 7, 2),
      ok: true,
      len: 4,
      records: [(1, 10, 7, 1), (2, 20, 7, 2), (3, 30, 8, 1), (4, 40, 7, 2)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, [3]),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, [2]),
        ("ts", 99, []),
        ("tag", 7, [1, 2, 4]),
        ("tag", 8, [3]),
        ("tag", 99, []),
        ("bin", 1, [1, 3]),
        ("bin", 2, [2, 4]),
        ("bin", 3, []),
      ],
    },
    {
      op: "modify_ts",
      rec: (2, 15, 0, 0),
      ok: true,
      len: 4,
      records: [(1, 10, 7, 1), (2, 15, 7, 2), (3, 30, 8, 1), (4, 40, 7, 2)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, [3]),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, []),
        ("ts", 99, []),
        ("tag", 7, [1, 2, 4]),
        ("tag", 8, [3]),
        ("tag", 99, []),
        ("bin", 1, [1, 3]),
        ("bin", 2, [2, 4]),
        ("bin", 3, []),
      ],
    },
    {
      op: "remove",
      rec: (3, 0, 0, 0),
      ok: true,
      len: 3,
      records: [(1, 10, 7, 1), (2, 15, 7, 2), (4, 40, 7, 2)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, []),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, []),
        ("ts", 99, []),
        ("tag", 7, [1, 2, 4]),
        ("tag", 8, []),
        ("tag", 99, []),
        ("bin", 1, [1]),
        ("bin", 2, [2, 4]),
        ("bin", 3, []),
      ],
    },
    {
      op: "try_insert",
      rec: (3, 30, 8, 1),
      ok: true,
      len: 4,
      records: [(1, 10, 7, 1), (2, 15, 7, 2), (3, 30, 8, 1), (4, 40, 7, 2)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, [3]),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, []),
        ("ts", 99, []),
        ("tag", 7, [1, 2, 4]),
        ("tag", 8, [3]),
        ("tag", 99, []),
        ("bin", 1, [1, 3]),
        ("bin", 2, [2, 4]),
        ("bin", 3, []),
      ],
    },
    {
      op: "remove",
      rec: (1, 0, 0, 0),
      ok: true,
      len: 3,
      records: [(2, 15, 7, 2), (3, 30, 8, 1), (4, 40, 7, 2)],
      probes: [
        ("id", 1, []),
        ("id", 3, [3]),
        ("id", 9, []),
        ("ts", 10, []),
        ("ts", 20, []),
        ("ts", 99, []),
        ("tag", 7, [2, 4]),
        ("tag", 8, [3]),
        ("tag", 99, []),
        ("bin", 1, [3]),
        ("bin", 2, [2, 4]),
        ("bin", 3, []),
      ],
    },
    {
      op: "try_insert",
      rec: (1, 10, 7, 1),
      ok: true,
      len: 4,
      records: [(1, 10, 7, 1), (2, 15, 7, 2), (3, 30, 8, 1), (4, 40, 7, 2)],
      probes: [
        ("id", 1, [1]),
        ("id", 3, [3]),
        ("id", 9, []),
        ("ts", 10, [1]),
        ("ts", 20, []),
        ("ts", 99, []),
        ("tag", 7, [1, 2, 4]),
        ("tag", 8, [3]),
        ("tag", 99, []),
        ("bin", 1, [1, 3]),
        ("bin", 2, [2, 4]),
        ("bin", 3, []),
      ],
    },
  ]
}
