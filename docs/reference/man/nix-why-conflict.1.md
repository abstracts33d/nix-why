% NIX-WHY-CONFLICT(1) nix-why | nix-why user commands
% s33d
% 2026-05-27

# NAME

nix-why-conflict — focused view on merge conflicts for a single option

# SYNOPSIS

**nix-why-conflict** *flake-target* *option-path* [\<flags\>]

# DESCRIPTION

Reuses the nix-why resolve introspection but prints only the
conflicts[] block — useful when you already suspect a merge
conflict (`mkForce` collision, type mismatch, submodule key
collision) and want a clean "yes/no + what collides" answer
without the full resolution tree.

For the general resolve view that includes conflicts alongside the
winning value and contributing definitions, use
`nix-why-option(1)`.

# FLAGS

**\--json**
:   Emit the conflicts[] block (and minimal context) as JSON.

**\--no-color**
:   Force-disable ANSI escapes (also respects **NO_COLOR**).

**\--show-trace**
:   Pass-through to `nix eval` for debugging the tool itself.

**\--adapter** *name*
:   Force a specific adapter. See `nix-why-option(1)`.

**-h**, **\--help**
:   Show short help and exit.

**\--version**
:   Print the nix-why version and exit.

# EXIT CODES

| Code | Meaning |
|------|---------|
| 0  | Option resolved cleanly, no conflicts. |
| 1  | At least one conflict surfaced. |
| 2  | Option does not exist. |
| 3  | Flake target not found or wrong schema. |
| 4  | Evaluation error. |
| 64 | Usage error. |

# JSON OUTPUT

Schema includes `path`, `kind`, `type`, `valueError`, and
`conflicts[]`. See `docs/reference/json-schema.md` for the full
shape and error envelope.

# EXAMPLES

Detect a conflict on a single option:

    $ nix-why-conflict .#krach services.test.enable

CI gate: fail when any conflict appears:

    $ nix-why-conflict --json .#krach services.test.enable \
        | jq -e '.conflicts == []'

# SEE ALSO

`nix-why-option(1)`, `nix-why-overlay(1)`, `nix-why-recursion(1)`.
