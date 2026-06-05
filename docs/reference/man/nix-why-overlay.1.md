% NIX-WHY-OVERLAY(1) nix-why | nix-why user commands
% s33d
% 2026-05-27

# NAME

nix-why-overlay — list and attribute nixpkgs overlays applied to a flake target

# SYNOPSIS

**nix-why-overlay** *flake-target* [\<flags\>]                  (listing mode)

**nix-why-overlay** *flake-target* *attr-path* [\<flags\>]      (attribution mode)

# DESCRIPTION

Two modes:

**Listing**
:   Without an *attr-path*: report every overlay applied to the
    flake target's `pkgs`, in order, with a synthesised label
    derived from the attributes it contributed.

**Attribution**
:   With an *attr-path* (e.g. `python3` or `python3.pkgs.requests`):
    fold each overlay against a baseline nixpkgs and report which
    overlay introduced / modified / removed the queried attribute.

The tool locates `pkgs` and `overlays` on the target via a chain of
shape probes: NixOS/HM/darwin `config.nixpkgs.overlays`,
`_module.args.pkgs.overlays`, `target.overlays`, or a bare pkgs
shape with an `overlays` field. Synthetic flakes that don't
provision pkgs will exit 3 with a discovery error.

# FLAGS

**\--json**
:   Emit the listing or attribution result as JSON.

**\--no-color**
:   Force-disable ANSI escapes (also respects **NO_COLOR**).

**\--limit** *N*
:   Cap the number of attribute names shown per overlay in
    listing mode. Default `20`.

**\--show-trace**
:   Pass-through to `nix eval` for debugging the tool itself.

**-h**, **\--help**
:   Show short help and exit.

**\--version**
:   Print the nix-why version and exit.

# EXIT CODES

| Code | Meaning |
|------|---------|
| 0  | Overlays listed (listing) or attribution completed (attribution). |
| 1  | Attribution: attribute never appeared in any overlay step. |
| 3  | Flake target not found, no overlays discoverable, or baseline nixpkgs source could not be located. |
| 4  | Evaluation error. |
| 64 | Usage error. |

# DISCOVERY-LEVEL ERRORS (special-case)

Unlike the other CLIs, the overlay tool surfaces discovery-level
failures (no overlays located, no baseline) via the `error: string`
field in its normal output shape rather than the unified error
envelope. This is because discovery failures still produce a
partially-populated response (e.g. `overlayCount`, `mode`). See
`docs/reference/json-schema.md` for the full schema.

# JSON OUTPUT

Listing mode:

```
{ "schemaVersion": "1",
  "mode": "listing",
  "error": null,
  "overlayCount": N,
  "overlays": [ { index, name, appliedOk, attributeCount, attributes } ] }
```

Attribution mode adds `path`, `overlayNames`, `signatures`,
`diffs`, and `summary`.

# EXAMPLES

List overlays applied to a host's pkgs:

    $ nix-why-overlay .#krach

Attribute the origin of `nix-output-monitor`:

    $ nix-why-overlay .#krach nix-output-monitor

# SEE ALSO

`nix-why-option(1)`, `nix-why-conflict(1)`, `nix-tree(1)`.
