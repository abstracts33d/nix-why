# Changelog

All notable changes to this project are tracked here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses semantic versioning.

## Unreleased

### Post-v0.5 polish

Four deferred items from the original brainstorm are now shipped:

- **Function-module application** (lib): `from-modules.nix` no longer
  skips function modules. It reads `config._module.args` from the
  evaluated configuration (via the new `config` parameter on
  `resolve` / `whatSets`) and re-applies each function module with
  those args. Falls back to filtering args by `functionArgs` when
  the function rejects extras. This is the biggest single capability
  improvement since v0.1 - real NixOS modules (the vast majority of
  which are function-form) now contribute to the module-walk pass
  instead of silently falling back to options-surface fidelity.
  New fixture `tests/fixtures/function-module.nix` covers the path.

- **Overlay names** (nix-why-overlay): both listing and attribution
  modes now derive a synthetic display name per overlay from the
  first two top-level attributes it contributes - e.g.
  `overlay 0 (firefox, chromium, ...)` instead of bare `overlay 0`.
  Falls back to `overlay N` for overlays that contribute nothing or
  fail to evaluate.

- **Per-field derivation diff** (nix-why-overlay): when attribution
  reports a "modified" derivation, the diff now records which
  captured fields changed (`name`, `version`, `pname`,
  `outputName`, `system`, or `drvPath` for catch-all changes). The
  tree renderer prints them on a `changed fields:` line under the
  modified overlay's entry.

Documented in docs/roadmap/v0.5-overlay-attribution.md (Limitations
section).

- **Submodule traversal** (lib): paths that cross
  `lib.types.submodule` boundaries (e.g. `services.foo.enable` where
  `services.foo` is declared with a submodule type) now resolve
  correctly. The new `lib/internal/submodule-pivot.nix` detects
  submodule-typed options during `from-options`'s path walk, extracts
  each user module's contribution at the boundary prefix (preserving
  `mkIf` / `mkOverride` / `mkMerge` wrappers via the new
  `descendWithWrappers` helper), and re-evaluates the submodule via
  `lib.evalModules` with `getSubModules ++ syntheticModules`. The
  walker then continues path traversal in the resulting options tree.

  Supports:
    - single-instance `submodule` - the common service-options shape
    - `attrsOf (submodule {...})` - e.g.
      `services.nginx.virtualHosts.<key>.foo`; user-supplied key is
      consumed from the path during the pivot
    - arbitrary nesting - the pivot returns its synthetic modules so
      a nested submodule pivot can extract from them, preserving
      per-module attribution at every level

  Not supported (documented limitation):
    - `listOf (submodule {...})` - NixOS does not expose stable path
      syntax for indexed list-element introspection, so this remains
      out of scope

  New fixtures: `submodule-single`, `submodule-attrsof`,
  `submodule-nested`. The pre-existing `nested-submodule` fixture
  (direct nested options without a submodule wrapper) is preserved
  as the simpler companion case.

### v0.5 - overlay attribution

`nix-why-overlay` gains a second invocation form that does what the
original brief implied but the v0.4 MVP did not deliver: given a
flake target AND a dotted attribute path into pkgs, identify which
overlay introduced or modified the attribute.

Added:
- Attribution mode: `nix-why-overlay <flake-target> <attr-path>`.
  Builds a baseline `nixpkgs` (no overlays) from `pkgs.path`, folds
  the user's overlays cumulatively via `pkgs.extend`, computes a
  signature of the queried attribute at each step (drvPath for
  derivations, attrNames for attrsets, value for primitives), then
  diffs consecutive signatures into `introduced` / `modified` /
  `removed` / `unchanged` classifications.
- New AST shape with `mode: "attribution"` carrying signatures,
  per-overlay diffs, and a summary (firstAppearance,
  lastModification, changeCount, finalKind).
- Tree renderer prints a per-overlay history block + a summary
  block. Markers: `+` introduced, `~` modified, `-` removed, space
  unchanged.
- Exit code 1 when the attribute never appears in any overlay step.
- Exit code 3 when the baseline nixpkgs source cannot be located
  (target's pkgs lacks `pkgs.path`).
- Documented at docs/roadmap/v0.5-overlay-attribution.md.

The v0.4 listing mode (no attr-path) is unchanged.

Limitations explicitly out of scope:
- Overlays are reported by index. Source-position name recovery
  via `unsafeGetAttrPos` is future work.
- A "modified" derivation is reported as a single event; per-field
  diffs inside the derivation are not surfaced.
- Cost is O(N x nixpkgs eval) for N overlays. Caching deferred.

### Sibling tools

Added three siblings under the `nix-why` umbrella, each a separate
flake `apps` and `packages` entry:

- **`nix-why-conflict <flake-target> <option-path>`** - thin focused
  view on v0.2's conflict surface. Prints only the conflicts[] block
  from `resolve`'s AST and an exit code: 0 = clean, 1 = conflicts
  found. Useful when you already suspect a merge conflict and want a
  one-shot yes/no answer.

- **`nix-why-recursion`** - parses a `nix eval --show-trace` capture
  from stdin and surfaces infinite-recursion cycles. Two views: the
  last N frames before the error (most informative) and a frequency
  table of repeated (file, line, description) frames (the inner
  cycle). Pure text parser; no module-system introspection. JSON
  output supported.

- **`nix-why-overlay <flake-target>`** (MVP) - extracts the overlay
  list from a NixOS / nix-darwin / home-manager evaluated config or
  a flake's `legacyPackages.<system>`, applies each overlay against
  the resolved pkgs, and prints the top-level attributes each
  contributes. Per-attribute "which overlay set X?" attribution is
  not yet implemented - the fixed-point evaluation model differs
  enough from evalModules that it deserves its own iteration.

Tests: tests/siblings.bats covers argv parsing, help text, error
paths, and (for nix-why-recursion) parsing a synthetic trace + JSON
emission.

Flake outputs added: `packages.<sys>.{nix-why-conflict,
nix-why-recursion, nix-why-overlay}` and matching `apps.<sys>` apps.
A new `mkCliScript` helper in flake.nix consolidates the four
packaging derivations.

### v0.4 - "why is this option not explicitly set?"

Added:
- Library: `nix-why.lib.whyNot { modules ? [], options, path }`. Returns
  an AST split into `explicitDefinitions` (priority != 1500, mkIf
  guards held), `defaultDefinitions` (priority == 1500), and
  `filteredOutDefinitions` (gated by mkIf evaluating false). Surfaces
  a human-readable `hint` when an option is not explicitly set but
  has gated would-be-setters.
- CLI: `nix-why-option why-not <flake-target> <option-path>` subcommand
  with a dedicated tree renderer that switches on `isExplicitlySet`:
  green confirmation + explicit definitions when set, yellow "NOT
  explicitly set" + filtered candidates with their condition source
  when not.
- Exit codes for `why-not`: 0 when explicitly set or candidates
  found; 1 when only the type default contributes and there are no
  candidates.
- 3 inline lib tests: whyNot-explicitly-set, whyNot-default-only,
  whyNot-filtered-by-mkIf.

Design notes:
- The semantics rest on the observation that NixOS represents an
  option's declared `default` as a definition at priority 1500
  (mkOptionDefault). A `priority != 1500` filter is therefore the
  natural definition of "user-supplied configuration", and the
  natural way to answer the "why is this option not explicitly set?"
  question. `resolve` continues to report the unfiltered truth;
  `whyNot` is a different view onto the same data.
- An mkIf-gated user definition is **not** an explicit configuration
  - it is a candidate that did not fire. `explicitDefinitions`
  requires both priority != 1500 AND the guard to have held.

### v0.3 - reverse lookup + search

Added:
- Library: `nix-why.lib.whatSets { modules, specialArgs, config, options, path }`.
  Returns the same shape as resolve oriented around provenance: every
  module containing a definition for the option, regardless of whether
  the definition won, was overridden, or was filtered by mkIf.
- Library: `nix-why.lib.search { options, pattern, limit ? 50 }`. Walks
  the options tree and returns matching paths by infix pattern.
- CLI: `nix-why-option what-sets <flake-target> <option-path>` subcommand.
- CLI: `nix-why-option search <flake-target> <pattern>` subcommand.
- CLI: `--limit N` flag for the search subcommand.
- 5 inline tests in tests/lib.nix for whatSets / search.

### v0.2 - conflict explanation + eval subcommand

Added:
- Library: AST gains `valueError :: string | null` and
  `conflicts[] :: list of { kind, message, involvedDefinitions }`.
- Library: from-options detects when `tryEval (opt.value)` fails (mkForce
  collision, type mismatch, submodule key collision) and populates
  valueError; why-option surfaces a `merge-conflict` entry in conflicts[].
- CLI: tree renderer emits a CONFLICT block above the definitions list
  when conflicts is non-empty; the value line switches to
  `<unresolved - merge conflict>` (red) on conflict.
- CLI: `nix-why-option eval <expr> <option-path>` subcommand for
  arbitrary Nix expressions. Dispatches to the raw adapter when the
  result has a `modules` field, otherwise to autodetect.
- Fixtures: `mkforce-collision`, `type-mismatch`.

### v0.1 - option resolution

Initial public surface:

Library:
- `lib.resolve { modules, specialArgs ? {}, config, options, path }`
- `lib.render { ast, format ? "tree", maxValue ? 200, noColor ? false }`
  (stub - production rendering happens in the bash CLI)
- `lib.adapters.adapt { name ? null, flakeOutput }` with autodetect
- Internal modules: `priority`, `walker`, `from-options`, `from-modules`,
  `nix-source`
- Adapters: `nixos`, `home-manager`, `nix-darwin`, `flake-parts`, `raw`

CLI (`nix-why-option`):
- Primary form: `nix-why-option <flake-target> <option-path>`
- Schema autodetect: `.#krach` -> `nixosConfigurations.krach`
- Renderers: tree (default), brief (`-b`), JSON (`--json`)
- Flags: `--no-color`, `--max-value`, `--show-trace`, `--adapter`
- Exit codes: 0 / 1 / 2 / 3 / 4 / 64

Tests:
- 13 lib fixtures covering bool, mkDefault, mkForce, mkIf (true/false),
  mkMerge, list-merge, nested submodule, declared-but-undefined,
  nonexistent option, in-file duplicates, custom mkOverride priority,
  freeform modules
- 11 CLI bats tests covering argv parsing and help / error paths

Distribution:
- Flake outputs: `packages.<sys>.nix-why-option`, `apps.<sys>.option`,
  `lib`, `checks.<sys>.{treefmt,lib-tests,cli-tests}`, `devShells.<sys>`
- License: MIT
