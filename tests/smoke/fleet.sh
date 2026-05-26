#!/usr/bin/env bash
# Tier 3 smoke tests: opt-in real-world verification against the
# author's actual fleet (abstracts33d/fleet). Not gated in CI.
#
# Run from the nix-why repo root:
#   ./tests/smoke/fleet.sh
#
# Requires the fleet repo to be checked out at $FLEET_PATH (default
# /home/s33d/dev/abstracts33d/fleet) and the user to have a working
# Nix evaluation environment.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLEET_PATH="${FLEET_PATH:-/home/s33d/dev/abstracts33d/fleet}"
CLI="${REPO_ROOT}/cli/nix-why-option"
export NIX_WHY_LIB="${REPO_ROOT}/lib"

if [[ ! -d "${FLEET_PATH}" ]]; then
  echo "smoke: FLEET_PATH not found: ${FLEET_PATH}" >&2
  exit 1
fi

cd "${FLEET_PATH}"

failed=0
run_case() {
  local label="$1"
  shift
  echo "=== ${label}"
  if ! "$@"; then
    echo "FAIL: ${label}" >&2
    failed=1
  fi
  echo
}

# 1. services.openssh.enable on krach should resolve to a defined bool.
run_case "krach: services.openssh.enable resolves" \
  bash -c "result=\$(${CLI} --json .#nixosConfigurations.krach services.openssh.enable); \
           [[ \$(echo \"\$result\" | jq -r .kind) == 'option' ]] && \
           [[ \$(echo \"\$result\" | jq -r .type) == 'bool' ]]"

# 2. networking.hostName on lab should equal "lab".
run_case "lab: networking.hostName == lab" \
  bash -c "result=\$(${CLI} --json .#nixosConfigurations.lab networking.hostName); \
           [[ \$(echo \"\$result\" | jq -r .value) == 'lab' ]]"

# 3. A nonexistent option exits 2.
run_case "bogus option exits 2" \
  bash -c "${CLI} --json .#nixosConfigurations.krach services.does.not.exist; \
           [[ \$? -eq 2 ]]"

if ((failed)); then
  echo "smoke: at least one case failed" >&2
  exit 1
fi
echo "smoke: all cases passed"
