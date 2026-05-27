# Changelog

All notable changes to this project are tracked here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses semantic versioning.

## Unreleased

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
