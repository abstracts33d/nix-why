#!/usr/bin/env bash
# tests/smoke/real-config.sh - exercise the nix-why CLIs against an
# ACTUAL lib.nixosSystem (full NixOS module set), across the nixpkgs
# releases pinned in tests/real-config/flake.nix.
#
# Not gated by `nix flake check`: a full NixOS eval is heavy and the
# sandbox cannot lock nixpkgs. Run manually before tagging a release,
# after changes to cli/expr/*.nix or lib/internal/from-*.nix, and to
# catch module-system internal-coupling drift across releases.
#
# This is the regression guard for the crash where nix-why hard-crashed
# applying specialArgs-dependent function modules (builtins.tryEval does
# not catch "missing required argument"). The DEFAULT (options-surface)
# must always succeed; --full must degrade to a clean JSON error
# envelope, never crash the process.
#
# Usage:
#   tests/smoke/real-config.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="${REPO_ROOT}/tests/real-config"
OPTION="${REPO_ROOT}/cli/nix-why-option"
export NIX_WHY_LIB="${REPO_ROOT}/lib"

if ! [[ -f "${FIXTURE}/flake.nix" ]]; then
  echo "real-config: fixture flake not found at ${FIXTURE}/flake.nix" >&2
  exit 1
fi

pass=0
fail=0
ok() {
  echo "  ok: $1"
  pass=$((pass + 1))
}
bad() {
  echo "  FAIL: $1" >&2
  fail=$((fail + 1))
}

# Every nixosConfigurations attr in the fixture (one per nixpkgs release).
targets="$(nix eval --json "${FIXTURE}#nixosConfigurations" --apply builtins.attrNames 2>/dev/null | jq -r '.[]')"
if [[ -z "${targets}" ]]; then
  echo "real-config: no nixosConfigurations in fixture (is the flake locked?)" >&2
  exit 1
fi

opt="services.openssh.enable"

for t in ${targets}; do
  echo "== release: ${t} =="
  target="${FIXTURE}#nixosConfigurations.${t}"

  # 1. DEFAULT must succeed (options-surface), never crash.
  rc=0
  out="$("${OPTION}" --json "${target}" "${opt}" 2>/dev/null)" || rc=$?
  if ((rc != 0)); then
    bad "${t}: default resolve exited ${rc} (expected 0 - regression: crash on real config)"
  elif [[ "$(jq -r '.kind' <<<"${out}")" == "option" ]] \
    && [[ "$(jq -r '.value' <<<"${out}")" == "true" ]] \
    && [[ "$(jq -r '.winningPriority' <<<"${out}")" == "1000" ]]; then
    ok "${t}: default resolve -> options-surface (value=true, winningPriority=1000)"
  else
    bad "${t}: default resolve output unexpected: $(jq -c '{kind,value,winningPriority,moduleWalkAvailable}' <<<"${out}")"
  fi

  # 2. --full must degrade gracefully: success, OR a clean JSON error
  #    envelope (exit 4) - never an uncaught process crash / hang.
  rc=0
  out="$("${OPTION}" --full --json "${target}" "${opt}" 2>/dev/null)" || rc=$?
  if ((rc == 0)); then
    ok "${t}: --full resolved (flat enough for the module-walk)"
  elif ((rc == 4)) && [[ "$(jq -r '.error.tool // empty' <<<"${out}")" == "nix-why-option" ]]; then
    ok "${t}: --full degraded to a clean error envelope (rc=4)"
  else
    bad "${t}: --full neither resolved nor returned an error envelope (rc=${rc})"
  fi
done

echo ""
echo "real-config smoke: ${pass} passed, ${fail} failed"
((fail == 0))
