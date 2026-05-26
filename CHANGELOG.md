# Changelog

All notable changes to this project are tracked here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses semantic versioning.

## Unreleased

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
