// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// Trait-method promotion policy (docs/STYLE.md §C, §H.1).
//
// `derive(...)` and a hand-written `pub impl Show` promote their trait methods to
// regular methods of the type — a deprecated behaviour that `moonc` reports once per
// impl as `[0079]`. Each one is answered here, following the official three-part
// scheme used by `moonbitlang/core`:
//
//   1. methods worth blessing as regular API -> `pub extend` (promoted)
//   2. the rest                              -> deprecated + hidden, so the generated
//      interface (and `--deny-warn`) stays clean while the trait implementations
//      themselves keep working unchanged.
//
// `Show::output` stays hand-written in `src/lib.mbt`; nothing here changes behaviour,
// only how the methods surface.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend RowId with Eq::{equal}

///|
pub extend Conflict with Eq::{equal}

///|
pub extend RegisterError with Eq::{equal}

///|
pub extend UpdateRejected with Eq::{equal}

///|
pub extend IndexStats with Eq::{equal}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend RowId with Eq::{not_equal}

///|
#deprecated("Use Hash::hash via the trait instead", skip_current_package=true)
#doc(hidden)
pub extend RowId with Hash::{hash, hash_combine}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend RowId with @debug.Debug::{to_repr}

///|
#deprecated("Use `Show::output` via the trait, or `to_string`", skip_current_package=true)
#doc(hidden)
pub extend RowId with Show::{to_string, output}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend Conflict with @debug.Debug::{to_repr}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Conflict with Eq::{not_equal}

///|
#deprecated("Use `Show::output` via the trait, or `to_string`", skip_current_package=true)
#doc(hidden)
pub extend Conflict with Show::{to_string, output}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend Rejected with @debug.Debug::{to_repr}

///|
#deprecated("Use `Show::output` via the trait, or `to_string`", skip_current_package=true)
#doc(hidden)
pub extend Rejected with Show::{to_string, output}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend RegisterError with @debug.Debug::{to_repr}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend RegisterError with Eq::{not_equal}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend UpdateRejected with @debug.Debug::{to_repr}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend UpdateRejected with Eq::{not_equal}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend IndexStats with @debug.Debug::{to_repr}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend IndexStats with Eq::{not_equal}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend IndexKind with @debug.Debug::{to_repr}

///|
#deprecated("Use `Show::output` via the trait, or `to_string`", skip_current_package=true)
#doc(hidden)
pub extend IndexKind with Show::{to_string, output}
