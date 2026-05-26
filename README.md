# nix-why

> Why is this NixOS / home-manager / nix-darwin option set to this value?

`nix-why` is an umbrella for small, focused tools that answer diagnostic
questions about a Nix evaluation. The first tool, `nix-why-option`, explains
exactly *why* an option has the value it has: final value, declaration
sites, every contributing definition with file, line, priority annotation,
and `mkIf` condition.

## Status

**Pre-release.** The design is approved; implementation has not started.
See [docs/design/2026-05-26-design.md](docs/design/2026-05-26-design.md) for
the full design.

## Example (target output, v0.1)

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
        priority 1500 (mkDefault)        ← overridden by higher-priority definitions
        → true

    modules/common/global/base.nix:42
        priority 100  (default, via mkIf)
        → true
        condition: config.fleet.server.enable  → true
```

## Documentation

- [Design spec](docs/design/2026-05-26-design.md) - canonical design document.
- [Docs index](docs/README.md) - full documentation tree.

## License

MIT. See [LICENSE](LICENSE).
