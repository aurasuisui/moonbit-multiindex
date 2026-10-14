// Example: one record store, three ways to look at it.
//
// A competition keeps its players in a single `Table`. Every player is reachable
// three different ways, and all three views are maintained by the table itself:
//
//   * by id     — a UNIQUE index        (`get_by` answers with the one player)
//   * by team   — a NON-UNIQUE index    (`iter_by` walks the whole team)
//   * by score  — an ORDERED index      (`range_by` / `iter_desc_by` = leaderboard)
//
// The point of a multi-index table is that these are *views of the same records*:
// inserting, updating or removing a player keeps every view correct, and a refused
// write hands the record back instead of losing it.
//
// Standalone module (own `moon.mod`, imports the published package), so the root
// `moon check` / `moon test` never touches it. Run with:
//
//   moon run cmd/leaderboard
//
// Until the package is published, that import only resolves through a local workspace
// manifest (deliberately not committed — `moon publish` would package it):
//
//   printf 'members = [".", "bench", "cmd/leaderboard"]\n' > moon.work
//   moon run cmd/leaderboard
//   rm moon.work

///|
/// One player. The key type of the table is `Int`, so every index projects to an
/// `Int`: the id, the team number, or the score.
struct Player {
  id : Int
  name : String
  team : Int
  score : Int
} derive(Debug)

///|
/// Build the table every demo below shares: three indexes over the same records.
fn new_table() -> @multiindex.Table[Int, Player] {
  let t : @multiindex.Table[Int, Player] = @multiindex.Table::new()
  let _ = t.register_unique("id", fn(p) { p.id })
  let _ = t.register_non_unique("team", fn(p) { p.team })
  let _ = t.register_non_unique_ordered("score", fn(p) { p.score })
  t
}

///|
/// Insert, reporting what happened the way the API does: `Err` carries both the
/// conflict and the record that was refused (so nothing is ever lost).
fn add(t : @multiindex.Table[Int, Player], player : Player) -> Unit {
  match t.insert(player) {
    Ok(id) => println("  added  #\{player.id} \{player.name} (\{id})")
    Err(rejected) =>
      match rejected.conflict {
        @multiindex.UniqueViolation(index, key, holder) =>
          println(
            "  refused #\{rejected.record.id}: index \{index} already maps \{key} to \{holder}",
          )
        @multiindex.DuplicateInBatch(index, key, at) =>
          println("  refused #\{rejected.record.id}: duplicates batch member \{at} on \{index} (\{key})")
      }
  }
}

///|
/// Print one player, or say the handle found nothing.
fn show(label : String, found : (@multiindex.RowId, Player)?) -> Unit {
  match found {
    Some((id, p)) => println("  \{label}: #\{p.id} \{p.name} score \{p.score} (\{id})")
    None => println("  \{label}: nobody")
  }
}

///|
fn main {
  let t = new_table()
  println("== adding players ==")
  add(t, { id: 7, name: "ada", team: 1, score: 120 })
  add(t, { id: 9, name: "bob", team: 1, score: 340 })
  add(t, { id: 4, name: "cyd", team: 2, score: 210 })
  add(t, { id: 2, name: "dee", team: 2, score: 90 })
  add(t, { id: 7, name: "eve", team: 3, score: 500 }) // duplicate id -> refused, record returned
  println("  len = \{t.len()}")

  println("== by id (unique index) ==")
  show("get_by id 9", t.get_by("id", 9))
  show("get_by id 8", t.get_by("id", 8))

  println("== by team (non-unique index) ==")
  for id, p in t.iter_by("team", 1) {
    println("  team 1: #\{p.id} \{p.name} (\{id})")
  }

  println("== by score (ordered index) ==")
  for _, p in t.iter_desc_by("score") {
    println("  leaderboard: \{p.name} = \{p.score}")
  }
  println("  scores in [100, 340]:")
  for _, p in t.range_by("score", 100, 340) {
    println("    \{p.name} = \{p.score}")
  }

  println("== updating keeps every view in step ==")
  match t.modify(t.get_by("id", 4).unwrap().0, fn(p) { { ..p, score: 400 } }) {
    Ok(_) => println("  cyd now scores 400")
    Err(_) => println("  unexpected refusal")
  }
  println("  top score: \{t.iter_desc_by("score").to_array()[0].1.name}")

  println("== removing and reusing a slot ==")
  match t.get_by("id", 2) {
    Some((id, _)) => {
      t.remove(id) |> ignore
      println("  removed dee; len = \{t.len()}")
      println("  team 2 now has \{t.iter_by("team", 2).to_array().length()} player(s)")
      println("  the stale handle still answers: get = \{@debug.to_string(t.get(id))}")
    }
    None => println("  dee is gone already")
  }

  println("== diagnostics ==")
  let stats = t.index_stats("score")
  println(
    "  score index: \{stats.buckets} buckets, \{stats.entries} entries, longest \{stats.longest_bucket}, avg \{stats.average_bucket}",
  )
  match t.verify_invariants() {
    Ok(_) => println("  verify_invariants: Ok")
    Err(message) => println("  verify_invariants: \{message}")
  }
  println("  indexes: \{@debug.to_string(t.index_names())}")
}
