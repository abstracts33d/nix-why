% NIX-WHY-OPTION(1) nix-why | nix-why user commands
% s33d
% 2026-05-27

# NAME

nix-why-option — module-system option resolution debugger

# SYNOPSIS

**nix-why-option** *flake-target* *option-path* [\<flags\>]

**nix-why-option** **eval** *expr* *option-path* [\<flags\>]

**nix-why-option** **what-sets** *flake-target* *option-path* [\<flags\>]

**nix-why-option** **why-not** *flake-target* *option-path* [\<flags\>]

**nix-why-option** **search** *flake-target* *pattern* [\<flags\>]

# DESCRIPTION

Resolve a single option path against an evaluated module-system
configuration (NixOS, home-manager, nix-darwin, flake-parts, or a
plain `lib.evalModules` result) and print:

- the final merged value
- the option's declared type
- every contributing definition with file:line, priority kind
  (`mkForce`, `mkDefault`, …) and `mkIf` guard recovery
- merge conflicts (when an option's definitions cannot be merged)

An undeclared freeform attribute (e.g. a `nix.settings.*` key) that has
a value in the config but no option declaration is reported with the
value read from config and `kind` `freeform`, rather than as not found.

The flake target may use any of these forms:

- `.#nixosConfigurations.<host>` — explicit
- `.#<host>` — shorthand; autodetects `nixosConfigurations`,
  `darwinConfigurations`, and `homeConfigurations` in order
- `<path>#<attr>` — non-cwd flake at a relative or absolute path
- `github:owner/repo#<attr>` — remote flake

# SUBCOMMANDS

**(default)**
:   Resolve *option-path*. Output includes definitions, declarations,
    and any conflict diagnostics.

**eval** *expr* *option-path*
:   Resolve *option-path* against the result of an inline Nix
    expression rather than a flake. Useful for one-off
    debugging without putting the test config in a flake.

**what-sets** *flake-target* *option-path*
:   Reverse-lookup: list every module that carries a definition for
    *option-path*, regardless of whether it won the merge or was
    filtered out by `mkIf`.

**why-not** *flake-target* *option-path*
:   Explain why *option-path* is not explicitly set. Surfaces
    `mkIf`-filtered candidates and the conditions they would need
    to fire.

**search** *flake-target* *pattern*
:   Fuzzy-match *pattern* against the dotted option paths in the
    options tree, descending into submodules to a configurable
    depth.

# FLAGS

**\--json**
:   Emit the full introspection AST as JSON. On failure, emits a
    structured error envelope (see **JSON OUTPUT** below).

**\--brief**, **-b**
:   One-line output: `<path> = <value>`.

**\--no-color**
:   Force-disable ANSI escapes (also respects the **NO_COLOR**
    environment variable).

**\--max-value** *N*
:   Truncate value rendering past *N* characters. Default `200`.

**\--show-trace**
:   Pass-through to `nix eval`. Useful only when debugging the
    tool itself; ordinary failures are mapped to one-line
    actionable errors without needing this flag.

**\--full**
:   Opt into the raw module-walk for per-definition line numbers,
    priority kinds, and `mkIf` guard sources. Best-effort: resolves
    for flat module lists, degrades or errors on deeply imported
    configurations (see **MODULE-WALK INTROSPECTION** below).

**\--verbose**
:   Emit informational notices (e.g. the module-walk opt-in tip).
    Silent by default.

**\--adapter** *name*
:   Force a specific adapter. One of `nixos`, `home-manager`,
    `nix-darwin`, `flake-parts`, `raw`. Default: autodetect from
    the flake-target shape.

**\--limit** *N*
:   `search` only — cap the number of matches shown. `0` disables
    truncation. Default `50`.

**-h**, **\--help**
:   Show short help and exit.

**\--version**
:   Print the nix-why version and exit.

# EXIT CODES

| Code | Meaning |
|------|---------|
| 0  | Option resolved (default), search returned ≥ 1 match, or no merge conflicts (conflict subcommand). |
| 1  | Option declared but not explicitly defined (default / why-not subcommands). |
| 2  | Option does not exist, or search returned 0 matches. |
| 3  | Flake target not found, schema mismatch, or unknown adapter. |
| 4  | Evaluation error (re-run with `--show-trace` for the raw Nix trace). |
| 64 | Usage error (bad flag, missing positional). |

# JSON OUTPUT

When **\--json** is passed, the response is a structured JSON object
on stdout. Every response carries a top-level `schemaVersion`
field; consumers should check for an `error` field first.

```
{ "schemaVersion": "1",
  "path": "services.openssh.enable",
  "kind": "option",
  "value": true,
  ... }
```

On failure:

```
{ "schemaVersion": "1",
  "error": { "tool": "nix-why-option",
             "kind": "flake-not-found",
             "message": "flake not found at /tmp/x" } }
```

See `docs/reference/json-schema.md` for the full per-subcommand
schemas and the list of stable `error.kind` values.

# MODULE-WALK INTROSPECTION (opt-in)

The default output reads the evaluated `options` tree: per-definition
file, winning value, winning priority and kind, type, and declaration
file:line. This works on any unmodified configuration and never
requires config changes.

The richest output (per-definition line numbers, priority kinds,
`mkIf` guard sources, and mkIf-filtered candidates) needs a raw
module-walk, opted into with **\--full**. It is best-effort: it
resolves for flat module lists but degrades or errors on deeply
imported configurations, because the module system exposes neither
the transitively-imported module list nor per-definition positions.
`moduleWalkAvailable` in the JSON output indicates which mode
produced the response.

# ENVIRONMENT

**NO_COLOR**
:   Force-disable ANSI escapes (also honoured by **\--no-color**).

**NIX_WHY_VERSION**
:   Override the version reported by **\--version**. Normally set
    by the package wrapper to the flake's `nixWhyVersion`.

**NIX_WHY_LIB**, **NIX_WHY_CLI_EXPR_DIR**, **NIX_WHY_CLI_SH**
:   Override the paths to the bundled library, driver expressions,
    and shared shell helpers. Set automatically by the package
    wrapper; only useful when running the bare script from a
    working tree.

# EXAMPLES

Resolve the SSH-enable option on host `krach`:

    $ nix-why-option .#krach services.openssh.enable

Discover the right option name for "tailscale":

    $ nix-why-option search .#krach tailscale

Reverse-lookup who sets the system state version:

    $ nix-why-option what-sets .#krach system.stateVersion

Explain why a port option is not set:

    $ nix-why-option why-not .#krach services.foo.port

Machine-readable resolve, piped to jq:

    $ nix-why-option --json .#krach services.openssh.enable | jq .value

# SEE ALSO

`nix-why-conflict(1)`, `nix-why-overlay(1)`, `nix-why-recursion(1)`,
`nix-eval(1)`, `nixos-option(8)`.

`docs/comparison.md` for a feature comparison against existing
tooling (`nixos-option`, `nix repl`, `manix`, `nix-doc`,
`nix-tree`).
