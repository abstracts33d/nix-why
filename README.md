# nix-why

[![ci](https://github.com/abstracts33d/nix-why/actions/workflows/ci.yml/badge.svg)](https://github.com/abstracts33d/nix-why/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> Why is this NixOS / home-manager / nix-darwin option set to this value?

`nix-why` is an umbrella for small, focused tools that answer diagnostic
questions about a Nix evaluation. The flagship `nix-why-option` explains
exactly why an option has the value it has; the sibling tools
(`nix-why-conflict`, `nix-why-recursion`, `nix-why-overlay`) cover three
adjacent investigations.

## Status

Pre-release. Library and CLI are functionally complete through the
roadmap's v0.5 milestone (option resolution, conflict explanation,
reverse lookup, search, "why is this not explicitly set?", overlay
attribution). The public contract lives under
[`docs/reference/`](docs/reference/) (JSON schema + man pages);
[`docs/comparison.md`](docs/comparison.md) maps nix-why against the
existing tooling.

## `nix-why-option` subcommands

| Subcommand | Purpose |
|---|---|
| (default) | resolve a single option to its final value with full provenance |
| `eval <expr>` | same, against an arbitrary Nix expression (raw evalModules or a flake output) |
| `what-sets` | list every module that defines an option, regardless of whether it won |
| `why-not` | explain why an option is *not* explicitly set, surfacing mkIf-filtered candidates |
| `search <pattern>` | find option paths in the target by infix pattern |

## Sibling tools

| Tool | Purpose |
|---|---|
| `nix-why-conflict <target> <option>` | Print only the merge-conflict block for an option. Exit 0 if clean, 1 if conflicts found. |
| `nix-why-recursion < trace.log` | Read a Nix `--show-trace` capture from stdin, surface the infinite-recursion cycle (last frames + frequency table). |
| `nix-why-overlay <target>` | List the nixpkgs overlays applied to a flake target and the attributes each contributes. |
| `nix-why-overlay <target> <attr-path>` | Attribute attribution: fold overlays against a baseline `nixpkgs` and report which overlay introduced / modified the attribute. |

## Example: resolve

```text
$ nix-why-option .#nixosConfigurations.krach services.openssh.enable

services.openssh.enable : bool
  value     true
  declared  nixpkgs/nixos/modules/services/openssh/sshd.nix:23

  3 definitions, winning priority 100 (default):

  ✓ modules/roles/workstation.nix:14
        priority 100  (default)
        → true

    modules/profiles/operator.nix:8
        priority 1000 (mkDefault)        ← overridden by higher-priority definitions
        → true

    modules/common/global/base.nix:42
        priority 100  (default, via mkIf)
        → true
        condition: config.fleet.server.enable  → false   ← filtered out
```

## Example: search and what-sets (discovery loop)

```sh
$ nix-why-option search .#nixosConfigurations.krach ssh
# -> candidate paths (services.openssh.enable, services.openssh.port, ...)

$ nix-why-option what-sets .#nixosConfigurations.krach services.openssh.enable
# -> list of modules that contain a definition for the option
```

## Flags

| Flag | Purpose |
|---|---|
| `--json` | Emit the full introspection AST as JSON. The stable contract for tool integrations. |
| `--brief` / `-b` | One-line output. |
| `--no-color` | Force-disable ANSI (also respects `NO_COLOR`). |
| `--max-value N` | Truncate value rendering past N characters (default 200). |
| `--show-trace` | Pass through to underlying `nix eval`. |
| `--full` | Opt into the raw module-walk (per-definition line, priority kind, mkIf guard source). Best-effort; see "Provenance fidelity". |
| `--verbose` | Emit informational notices (e.g. the module-walk opt-in tip). Silent by default. |
| `--adapter <name>` | Force a specific adapter (`nixos` / `home-manager` / `nix-darwin` / `flake-parts` / `raw`). |
| `--limit N` | (search only) Cap the result count. 0 disables truncation. Default 50. |

## Install

```sh
# One-off
nix run github:abstracts33d/nix-why -- .#krach services.openssh.enable

# Profile install
nix profile install github:abstracts33d/nix-why

# As a flake input + system package
inputs.nix-why.url = "github:abstracts33d/nix-why";
# then in your NixOS / nix-darwin / home-manager config:
environment.systemPackages = [ inputs.nix-why.packages.${system}.default ];

# Or apply the overlay to get pkgs.nix-why-option (+ siblings) everywhere:
nixpkgs.overlays = [ inputs.nix-why.overlays.default ];
environment.systemPackages = [ pkgs.nix-why-option ];
```

## Library

The Nix introspection library is exposed as a system-agnostic flake
output:

```nix
inputs.nix-why.lib.resolve  { modules ? [], config ? {}, options, path }
inputs.nix-why.lib.whatSets { modules ? [], config ? {}, options, path }
inputs.nix-why.lib.whyNot   { modules ? [], config ? {}, options, path }
inputs.nix-why.lib.search   { options, pattern, limit ? 50 }
inputs.nix-why.lib.adapters.adapt { name ? null, flakeOutput }
```

The library is the strategic asset; the bash CLI is a thin renderer
over its JSON output.

## Provenance fidelity

Two tiers, drawn by what the module system exposes natively:

| | Always available (any unmodified config) | Needs the raw module list |
|---|---|---|
| Per definition | file | line, priority kind, mkIf guard source |
| Whole option | winning value, winning priority, type, declaration file:line | mkIf-filtered candidates ("would have set it") |

The left column is the **default** on any config: read from the
evaluated `options` tree (NixOS-native, import-aware), no configuration
change, never fails.

The right column needs a raw module-walk, opted into with `--full`:

```sh
nix-why-option --full .#nixosConfigurations.krach services.openssh.enable
```

`--full` is best-effort. It resolves for **flat** module lists, but
degrades (or errors) on deeply imported configurations — most real
NixOS systems — because the module system exposes neither the
transitively-imported module list, nor per-definition positions, nor
mkIf-filtered candidates, and re-running raw modules outside their
evaluation throws uncatchably when they need unavailable `specialArgs`.
nix-why does not re-implement the module system's collection internals
to force this. Closing the gap natively — so every config gets full
provenance without reconstruction — is the upstream goal (a
module-system RFC); nix-why is the proof of need.

When `--full` cannot reconstruct the walk, output stays on the default
tier and `moduleWalkAvailable` is `false`; the resolved value, priority,
type and declaration remain correct. The tool degrades, it does not lie.

### Freeform / undeclared attributes

`nix.settings.*` and other freeform attrs have a value in the config
but are not declared options. nix-why surfaces them as `kind = "freeform"`
(value + type, no declaration or per-definition provenance) rather than
reporting "does not exist":

```sh
$ nix-why-option .#nixosConfigurations.krach nix.settings.experimental-features
nix.settings.experimental-features : list
  freeform   not a declared option; value read from config
  value     ["nix-command","flakes"]
```

### Scope

nix-why operates on **successful evaluations** of declared options. It
is not a closure/dependency tool (`nix-tree`, `nix why-depends`), a docs
search (`manix`), or a `--show-trace` replacement for failed builds. A
flake whose outputs do not evaluate under `builtins.getFlake`, or an
option that aborts uncatchably when forced, surfaces as a passed-through
evaluation error (exit 4), not a crash.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | option resolved (or search returned matches) |
| 1 | option declared but not defined |
| 2 | option does not exist / no search matches |
| 3 | flake target not found or wrong schema |
| 4 | evaluation error (passed through from `nix eval`) |
| 64 | usage error |

## License

MIT. See [LICENSE](LICENSE).
