// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// JSON round-trip (docs/SPEC.md §8).
//
// **Indexes do not participate in serialization.** A projection is a runtime closure,
// so there is nothing serializable to write down for it. What travels is the record set
// in insertion order — `{"records": [...]}` — and `from_json` returns a table whose
// registry is **empty**. Re-registering the indexes afterwards rebuilds them through the
// §3.1 backfill scan, so "load then reindex" needs no second mechanism.

///|
/// The wire shape: the records, in insertion order.
priv struct TableJson[V] {
  records : Array[V]
} derive(ToJson, FromJson)

///|
/// Serialize the records in insertion order (docs/SPEC.md §8).
///
/// Nothing about the registry is written: two tables with different indexes but the same
/// records serialize to the same JSON.
pub fn[K, V : ToJson] Table::to_json(self : Table[K, V]) -> Json {
  let records : Array[V] = []
  for _, record in self.iter() {
    records.push(record)
  }
  ToJson::to_json({ records, })
}

///|
/// Rebuild a table from `{"records": [...]}`, records in the order they appear.
///
/// Malformed input raises `@json.JsonDecodeError` carrying the path to the offending
/// field (missing `records`, wrong type, bad element …) — nothing is silently dropped.
///
/// The returned table has **no registered index**; register them again and the backfill
/// scan reindexes every record. The bound is the one `insert` carries: restoring records
/// goes through the same chokepoint as any other insert.
pub fn[K : Hash + Eq + Compare, V : FromJson] Table::from_json(
  json : Json,
) -> Table[K, V] raise {
  let wire : TableJson[V] = @json.from_json(json)
  let t : Table[K, V] = Table::new()
  let mut i = 0
  while i < wire.records.length() {
    // A fresh table registers no index, so the commit half cannot conflict.
    t.insert(wire.records[i]) |> ignore
    i = i + 1
  }
  t
}
