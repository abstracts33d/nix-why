# nix-why

> Why is this NixOS / home-manager / nix-darwin option set to this value?

`nix-why` is an umbrella for small, focused tools that answer diagnostic
questions about a Nix evaluation. The flagship `nix-why-option` explains
exactly why an option has the value it has; the sibling tools
(`nix-why-conflict`, `nix-why-recursion`, `nix-why-overlay`) cover three
adjacent investigations.

## Status

Pre-release. Library and CLI are functionally complete through the
roadmap's v0.4 milestone (option resolution, conflict explanation,
reverse lookup, search, "why is this not explicitly set?").
Documentation is local-only under `docs/` while the design stabilises.

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
```

## Library

The Nix introspection library is exposed as a system-agnostic flake
output:

```nix
inputs.nix-why.lib.resolve  { modules ? [], options, path }
inputs.nix-why.lib.whatSets { modules ? [], options, path }
inputs.nix-why.lib.whyNot   { modules ? [], options, path }
inputs.nix-why.lib.search   { options, pattern, limit ? 50 }
inputs.nix-why.lib.adapters.adapt { name ? null, flakeOutput }
```

The library is the strategic asset; the bash CLI is a thin renderer
over its JSON output.

## Opt-in: full module-walk fidelity

By default the library degrades gracefully to options-surface fidelity
because NixOS / home-manager / nix-darwin do not expose the raw modules
list. To enable full per-definition line numbers and mkIf source
extraction, opt in by setting in your config:

```nix
_module.args.modules = <the same modules list passed to nixosSystem/lib.evalModules>;
```

The library reads this from the evaluated config and feeds it to the
module-walk introspection pass.

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
