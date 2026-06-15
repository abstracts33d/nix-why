# nix-why vs. existing tools

A side-by-side of where nix-why-* fits in the existing
Nix-debugging toolbox, and where it deliberately doesn't.

## TL;DR table

| Capability | `nixos-option` | `definitionsWithLocations` | `nix repl :p` | `nix eval --show-trace` | `manix` | `nix-doc` | `nix-tree` | `nix why-depends` | **nix-why-option** |
|---|---|---|---|---|---|---|---|---|---|
| Final value of an option | ✓ | ✗ | ✓ | partial | ✗ | ✗ | ✗ | ✗ | **✓** |
| Per-definition file | partial | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **✓** |
| Per-definition line | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **✓** (`--full`)¹ |
| Priority kind (mkForce / mkDefault / …) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **✓**¹ |
| `mkIf` guard recovery | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **✓** (`--full`)¹ |
| "Why is this not set?" | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **✓** (`why-not`) |
| Merge-conflict diagnostic | partial | ✗ | ✗ | partial | ✗ | ✗ | ✗ | ✗ | **✓** (`nix-why-conflict`) |
| Overlay attribution | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **✓** (`nix-why-overlay`) |
| Reverse lookup (what sets X) | ✗ | partial | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **✓** (`what-sets`) |
| Fuzzy option search | partial | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | **✓** (`search`) |
| Module-system aware | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **✓** |
| Stable JSON output | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | partial | ✗ | **✓** (`schemaVersion`) |
| Pure Nix lib (no CLI shim) | ✗ | ✓ | n/a | n/a | ✗ | ✗ | ✗ | ✗ | **✓** |

¹ The winning definition's priority kind is always reported.
Per-definition line numbers, per-definition priority kinds, and
`mkIf` guard sources need the raw module-walk (`--full`,
best-effort on deeply imported configs) — see the README's
"Provenance fidelity" section.

## Per-tool detail

### `nixos-option`

The closest existing tool. Resolves an option against an evaluated
NixOS configuration and prints the final value plus type +
declarations. Rewritten as a Nix script (merged into nixpkgs
January 2025); the rewrite also prints definition files via
`definitionsWithLocations`, but still nothing below the file level.

- **What it does well:** ubiquitous, ships in nixpkgs, no extra
  flake input.
- **Where it falls short:**
  - No per-definition view — when an option has multiple
    contributing modules, `nixos-option` prints only the merged
    result; it doesn't show *who* contributed *what* at *which*
    priority.
  - No `mkIf` introspection — a definition silenced by a false
    `mkIf` is simply absent from the output. There is no way to
    answer "what would set this if conditions changed?".
  - No reverse lookup. Given an unexpected value, you cannot ask
    "list every module that has a definition for this option".
  - No machine-readable output. Parsing `nixos-option`'s text is a
    common but brittle pattern.
  - NixOS-only. Doesn't apply to home-manager, nix-darwin, or
    flake-parts configurations.

nix-why-option supersedes `nixos-option`'s diagnostic role on the
dimensions above for the common case, keeping the same one-liner
ergonomics. Caveat: the deepest tier (per-definition line numbers,
priority kinds, and `mkIf`-filtered candidates) is opt-in via `--full`
and best-effort — it degrades to options-surface fidelity on deeply
imported configurations (see the README's "Provenance fidelity"). The
default tier — winning value, priority, type, declaration, and freeform
values — is always available and never fails.

### `options.<path>.definitionsWithLocations`

The strongest existing alternative, and not a tool at all: the
module system itself exposes per-definition `{ file, value }`
records on every evaluated option (in nixpkgs since 2022). A
`nix repl` one-liner gets you the list of defining files:

```
nix-repl> :lf .
nix-repl> nixosConfigurations.host.options.services.openssh.enable.definitionsWithLocations
```

- **What it does well:** zero install, authoritative (it is the
  module system's own data), per-definition file + value.
- **Where it falls short:** file only — no line numbers, no
  priority kinds (values arrive post-`mkOverride`-strip), no `mkIf`
  recovery (filtered definitions are already gone), no merge
  diagnostics, interactive-only ergonomics, and you need to know
  the incantation.

nix-why's default options-surface mode is built on exactly this
data; the tool packages it with priority/type/declaration context,
exit codes, JSON, and the `--full` deep pass on top.

### `nixd` / `nil` (language servers)

Editor-side option support: hover documentation, goto-declaration
for options, completion against an evaluated config (nixd).

- **What they do well:** in-editor discovery while writing config.
- **Where they fall short:** declaration-side, not value-side. They
  answer "what is this option?" at edit time, not "why is it
  `false` right now on this host?" against the deployed eval. No
  merge/priority/conflict story, no scriptable output.

Complementary: nix-why is the post-eval forensic counterpart.

### `nix-inspect`

TUI browser for evaluated Nix values (ratatui-based).

- **What it does well:** interactive drill-down into a config's
  value tree, faster than `nix repl` for exploration.
- **Where it falls short:** value browsing only — shows what a
  value *is*, not which module/priority/guard made it that. No
  provenance, no JSON contract.

### `nix repl :p config.foo.bar`

Drop into the REPL, load the flake, eval an attribute and pretty-
print it.

- **What it does well:** unmatched flexibility — you can poke at
  *any* part of the eval, not just options.
- **Where it falls short:**
  - You see the value, not the chain that produced it. There's no
    "show me where this came from" command.
  - No priority annotation. `mkDefault true` and a bare `true` look
    identical post-merge.
  - No `mkIf` history. A silenced definition is just gone.
  - Interactive only — doesn't compose into scripts, CI checks, or
    structured tooling.

The REPL is the right tool for ad-hoc exploration; nix-why is the
right tool for "the value is what I didn't expect, give me the
story".

### `nix eval --show-trace`

The fallback when something throws. Renders the Nix evaluation
stack frame-by-frame.

- **What it does well:** points at the offending source location
  when evaluation *fails*.
- **Where it falls short:** silent about successful-but-wrong
  evaluations. `--show-trace` answers "where did this throw?"; it
  cannot answer "why did this merge come out to *that* value?" or
  "why is this option not set?".

`nix-why-recursion` is the small adjunct here: parse a
`--show-trace` capture and surface the inner loop frame frequency,
which is otherwise drowned in the trace dump.

### `manix`

Fuzzy search over option documentation across nixpkgs / home-
manager / nix-darwin.

- **What it does well:** discoverability — "what's the option for
  X?" with markdown-rendered docs.
- **Where it falls short:** documentation-side, not eval-side. It
  doesn't know what *your* configuration sets.

Complementary, not overlapping. `nix-why-option search` is a
lighter, eval-time alternative when you want to search the live
options tree of the configuration in front of you (including local
modules manix doesn't know about), but for cross-ecosystem docs
discovery manix is still the answer.

### `nix-doc`

Documentation/comment extraction for `lib.*` functions and
similar.

- **What it does well:** docstring spelunking on a Nix codebase.
- **Where it falls short:** also doc-side, not eval-side. No
  evaluated-configuration introspection.

No overlap with nix-why.

### `nix-tree`

Visualise a derivation's runtime closure (`buildInputs` graph).

- **What it does well:** "which package brought this dependency
  in?".
- **Where it falls short:** different layer — operates on built
  derivations, not on the module system.

No overlap. nix-why-overlay's attribution mode is the closest, but
it traces an overlay-stack provenance, not a closure graph.

### `nix why-depends`

Explain why a package is in the closure of another package.

- **What it does well:** "why is openssl in this image?".
- **Where it falls short:** same as nix-tree — closure layer, not
  module-system layer.

No overlap.

## Niches nix-why-* explicitly does NOT cover

- **Building derivations** — that's `nix build`. nix-why never
  builds anything except as a side-effect of evaluating
  `nixpkgsConfig` for overlay attribution.
- **Closure / dependency graph** — `nix-tree`, `nix why-depends`.
- **Cross-ecosystem documentation discovery** — `manix`.
- **Interactive exploration** — `nix repl`.
- **Generic `--show-trace` diagnosis when nothing was thrown** —
  out of scope; nix-why operates on successful evaluations.

## Why a separate tool instead of patching `nixos-option`?

1. **Schema reach.** `nixos-option` is NixOS-only; nix-why's
   adapter facade handles NixOS / home-manager / nix-darwin /
   flake-parts / plain `lib.evalModules` uniformly.
2. **Module-walk introspection.** Per-definition file:line +
   priority kind + `mkIf` guards require walking the raw modules
   list — a second pass that augments the options-surface result.
   `nixos-option` does only the surface pass.
3. **Pure-Nix library.** The same diagnostic primitives are
   callable from any Nix expression (e.g. CI checks, dashboards,
   flake checks), not just from a CLI. `nixos-option` is a shell
   script wrapping `nix-instantiate --eval`.
4. **Stable JSON output.** `schemaVersion`-versioned envelope for
   structured consumers. `nixos-option` predates this convention
   and its text output is parsed ad-hoc by every downstream tool.

That said: the *value* of nix-why's resolve mode could absolutely
be folded into a future `nixos-option v2` or `nix option resolve`
subcommand. The library is designed to be liftable into nixpkgs
proper — closing the native provenance gap upstream (a module-system
RFC) is the long-term path.
