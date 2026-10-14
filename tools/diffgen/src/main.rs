//! diffgen — differential-test fixture generator for moonbit-multiindex.
//!
//! Runs the golden operation stream against the **Rust reference implementation**
//! (`multi_index_map` 0.15.1, pinned in Cargo.toml) and writes a MoonBit fixture that
//! `src/differential_test.mbt` replays against our `Table`. See README.md for the
//! deliberately thin diffable surface, and for the *second* (random) stream that is
//! intentionally not implemented.
//!
//! Usage:  cargo run --release -- ../../src/differential_fixture_test.mbt

use std::fmt::Write as _;
use std::fs;

use multi_index_map::MultiIndexMap;

/// The record under test: four indexed `u32` fields, one per index quadrant.
#[derive(MultiIndexMap, Clone, Debug)]
struct Rec {
    /// unique + hashed
    #[multi_index(hashed_unique)]
    id: u32,
    /// unique + ordered
    #[multi_index(ordered_unique)]
    ts: u32,
    /// non-unique + hashed
    #[multi_index(hashed_non_unique)]
    tag: u32,
    /// non-unique + ordered
    #[multi_index(ordered_non_unique)]
    bin: u32,
}

/// The keys probed after every step, per index:
/// unique quadrants answer 0 or 1 id, non-unique quadrants answer a set.
const PROBES: &[(&str, u32)] = &[
    ("id", 1),
    ("id", 3),
    ("id", 9),
    ("ts", 10),
    ("ts", 20),
    ("ts", 99),
    ("tag", 7),
    ("tag", 8),
    ("tag", 99),
    ("bin", 1),
    ("bin", 2),
    ("bin", 3),
];

/// Every record in the map, sorted by id (the reference iterates its slab in slot
/// order, which is not a semantic we want to pin).
fn records(map: &MultiIndexRecMap) -> Vec<(u32, u32, u32, u32)> {
    let mut out: Vec<(u32, u32, u32, u32)> = map
        .iter()
        .map(|(_, r)| (r.id, r.ts, r.tag, r.bin))
        .collect();
    out.sort_unstable();
    out
}

/// The ids matching one probe, sorted (so bucket order — which the reference does not
/// expose as a documented order — never enters the fixture).
fn probe_ids(map: &MultiIndexRecMap, index: &str, key: u32) -> Vec<u32> {
    let mut ids: Vec<u32> = match index {
        "id" => map.get_by_id(&key).map(|r| r.id).into_iter().collect(),
        "ts" => map.get_by_ts(&key).map(|r| r.id).into_iter().collect(),
        "tag" => map.get_by_tag(&key).iter().map(|r| r.id).collect(),
        "bin" => map.get_by_bin(&key).iter().map(|r| r.id).collect(),
        other => panic!("unknown index {other}"),
    };
    ids.sort_unstable();
    ids
}

/// One emitted step: the operation, whether it succeeded, and the observations.
struct Step {
    op: &'static str,
    rec: (u32, u32, u32, u32),
    ok: bool,
    len: usize,
    records: Vec<(u32, u32, u32, u32)>,
    probes: Vec<(String, u32, Vec<u32>)>,
}

fn snapshot(map: &MultiIndexRecMap, op: &'static str, rec: (u32, u32, u32, u32), ok: bool) -> Step {
    Step {
        op,
        rec,
        ok,
        len: map.len(),
        records: records(map),
        probes: PROBES
            .iter()
            .map(|(index, key)| (index.to_string(), *key, probe_ids(map, index, *key)))
            .collect(),
    }
}

fn moon_int_list(values: &[u32]) -> String {
    let items: Vec<String> = values.iter().map(|v| v.to_string()).collect();
    format!("[{}]", items.join(", "))
}

fn moon_record_list(values: &[(u32, u32, u32, u32)]) -> String {
    let items: Vec<String> = values
        .iter()
        .map(|(a, b, c, d)| format!("({a}, {b}, {c}, {d})"))
        .collect();
    format!("[{}]", items.join(", "))
}

fn main() {
    let out_path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "../../src/differential_fixture_test.mbt".to_string());

    // The derive macro generates Default / with_capacity, not `new`.
    let mut map = MultiIndexRecMap::with_capacity(16);
    let mut steps: Vec<Step> = Vec::new();

    // ---- the golden stream -------------------------------------------------
    // 1..3: the four quadrants get populated (tag/bin shared, to create real
    //       multi-record buckets)
    for rec in [(1, 10, 7, 1), (2, 20, 7, 2), (3, 30, 8, 1)] {
        let r = Rec { id: rec.0, ts: rec.1, tag: rec.2, bin: rec.3 };
        let ok = map.try_insert(r).is_ok();
        steps.push(snapshot(&map, "try_insert", rec, ok));
    }
    // 4: duplicate on the hashed-unique index
    let r = Rec { id: 1, ts: 40, tag: 9, bin: 3 };
    let ok = map.try_insert(r).is_ok();
    steps.push(snapshot(&map, "try_insert", (1, 40, 9, 3), ok));
    // 5: duplicate on the ordered-unique index
    let r = Rec { id: 4, ts: 10, tag: 9, bin: 3 };
    let ok = map.try_insert(r).is_ok();
    steps.push(snapshot(&map, "try_insert", (4, 10, 9, 3), ok));
    // 6: clean insert that joins two existing non-unique buckets
    let r = Rec { id: 4, ts: 40, tag: 7, bin: 2 };
    let ok = map.try_insert(r).is_ok();
    steps.push(snapshot(&map, "try_insert", (4, 40, 7, 2), ok));
    // 7: a *non-conflicting* modify (the conflicting path panics upstream, so it is
    //    not a behaviour to align with — see README "what cannot be diffed")
    let changed = map.modify_by_id(&2, |rec| rec.ts = 15).is_some();
    steps.push(snapshot(&map, "modify_ts", (2, 15, 0, 0), changed));
    // 8: remove by unique key
    let removed = map.remove_by_id(&3).is_some();
    steps.push(snapshot(&map, "remove", (3, 0, 0, 0), removed));
    // 9: the freed keys are reusable
    let r = Rec { id: 3, ts: 30, tag: 8, bin: 1 };
    let ok = map.try_insert(r).is_ok();
    steps.push(snapshot(&map, "try_insert", (3, 30, 8, 1), ok));
    // 10: remove one more, 11: and put the key back
    let removed = map.remove_by_id(&1).is_some();
    steps.push(snapshot(&map, "remove", (1, 0, 0, 0), removed));
    let r = Rec { id: 1, ts: 10, tag: 7, bin: 1 };
    let ok = map.try_insert(r).is_ok();
    steps.push(snapshot(&map, "try_insert", (1, 10, 7, 1), ok));

    // ---- emit the MoonBit fixture -----------------------------------------
    let mut out = String::new();
    writeln!(out, "// Copyright (c) 2026 moonbit-multiindex contributors").unwrap();
    writeln!(out, "// SPDX-License-Identifier: Apache-2.0").unwrap();
    writeln!(out).unwrap();
    writeln!(out, "// GENERATED FILE — DO NOT EDIT BY HAND.").unwrap();
    writeln!(out, "//").unwrap();
    writeln!(out, "// Source: the Rust reference implementation `multi_index_map` **0.15.1**").unwrap();
    writeln!(out, "// (pinned in `tools/diffgen/Cargo.toml`, checksummed by `Cargo.lock`).").unwrap();
    writeln!(out, "// Generator: `tools/diffgen` — regenerate with").unwrap();
    writeln!(out, "//   cd tools/diffgen && cargo run --release -- ../../src/differential_fixture_test.mbt").unwrap();
    writeln!(out, "// Generated: {} (golden stream: four quadrants + every diffable conflict path +", "2026-10-14").unwrap();
    writeln!(out, "// a non-conflicting modify + removes).").unwrap();
    writeln!(out, "//").unwrap();
    writeln!(out, "// CI needs **no Rust toolchain**: this fixture is checked in and replayed by").unwrap();
    writeln!(out, "// `src/differential_test.mbt`.").unwrap();
    writeln!(out).unwrap();
    writeln!(out, "///|").unwrap();
    writeln!(out, "/// One reference observation: the operation, whether it succeeded, and what the").unwrap();
    writeln!(out, "/// reference implementation then saw (`records` sorted by id, probe hits sorted).").unwrap();
    writeln!(out, "struct DiffStep {{").unwrap();
    writeln!(out, "  op : String").unwrap();
    writeln!(out, "  rec : (Int, Int, Int, Int)").unwrap();
    writeln!(out, "  ok : Bool").unwrap();
    writeln!(out, "  len : Int").unwrap();
    writeln!(out, "  records : Array[(Int, Int, Int, Int)]").unwrap();
    writeln!(out, "  probes : Array[(String, Int, Array[Int])]").unwrap();
    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();
    writeln!(out, "///|").unwrap();
    writeln!(out, "/// The golden stream, step by step.").unwrap();
    writeln!(out, "fn diff_fixture() -> Array[DiffStep] {{").unwrap();
    writeln!(out, "  [").unwrap();
    for step in &steps {
        let probes: Vec<String> = step
            .probes
            .iter()
            .map(|(index, key, ids)| format!("(\"{index}\", {key}, {})", moon_int_list(ids)))
            .collect();
        writeln!(
            out,
            "    {{ op: \"{}\", rec: {:?}, ok: {}, len: {}, records: {}, probes: [{}] }},",
            step.op,
            step.rec,
            step.ok,
            step.len,
            moon_record_list(&step.records),
            probes.join(", ")
        )
        .unwrap();
    }
    writeln!(out, "  ]").unwrap();
    writeln!(out, "}}").unwrap();

    fs::write(&out_path, out).expect("write fixture");
    println!("wrote {} steps to {out_path}", steps.len());
    println!("reference observations (op -> outcome, len):");
    for step in &steps {
        println!("  {:12} {:?} -> ok={} len={}", step.op, step.rec, step.ok, step.len);
    }
}