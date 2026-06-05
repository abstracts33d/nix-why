% NIX-WHY-RECURSION(1) nix-why | nix-why user commands
% s33d
% 2026-05-27

# NAME

nix-why-recursion — surface infinite-recursion cycles in --show-trace output

# SYNOPSIS

**nix-why-recursion** [\<flags\>] \< *trace.log*

*nix-eval-command* **\--show-trace** 2\>&1 | **nix-why-recursion** [\<flags\>]

# DESCRIPTION

Read a Nix `--show-trace` stderr capture on stdin, detect the
"infinite recursion encountered" marker, extract the `(description,
file:line:col)` frame pairs, and report two complementary views:

- **Last N frames before the error** — the call site closest to
  the cycle.
- **Frame-frequency table** — the `(file, line)` pairs that appear
  most often are usually the inner cycle.

This tool is intentionally simple: no module-system code, no
`nix eval` invocation. Hand it a trace, it tells you where the
loop lives.

# FLAGS

**\--limit** *N*
:   How many frames to show per section. Default `10`.

**\--json**
:   Emit `{ schemaVersion, hasRecursion, lastFrames[], topFrames[] }`
    as JSON. Note: JSON is emitted only when recursion is
    detected; the no-marker case exits with code 1 and no JSON.

**\--no-color**
:   Force-disable ANSI escapes (also respects **NO_COLOR**).

**-h**, **\--help**
:   Show short help and exit.

**\--version**
:   Print the nix-why version and exit.

# EXIT CODES

| Code | Meaning |
|------|---------|
| 0  | Recursion detected, report emitted. |
| 1  | No "infinite recursion" marker in input — input may not be a Nix `--show-trace` capture, or the eval succeeded. |
| 64 | Usage error. |

# EXAMPLES

Pipe a failing eval:

    $ nix eval .#myhost.config.system.build.toplevel --show-trace 2>&1 \
        | nix-why-recursion

Inspect an existing trace file with a wider window:

    $ nix-why-recursion --limit 25 < trace.log

# SEE ALSO

`nix-why-option(1)`, `nix-why-conflict(1)`, `nix-eval(1)`.
