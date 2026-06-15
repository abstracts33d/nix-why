#!/usr/bin/env bash
# tests/smoke/e2e.sh - end-to-end CLI exercise against a synthetic
# flake.
#
# Not gated by `nix flake check` (the synthetic flake needs to lock
# nixpkgs and Nix sandbox builds disallow that). Run manually before
# tagging a release, after big CLI refactors, or after any change to
# cli/expr/*.nix.
#
# Usage:
#   tests/smoke/e2e.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNTHETIC="${REPO_ROOT}/tests/synthetic"

if ! [[ -f "${SYNTHETIC}/flake.nix" ]]; then
  echo "e2e: synthetic flake not found at ${SYNTHETIC}/flake.nix" >&2
  exit 1
fi

cd "${SYNTHETIC}"

# Lock the synthetic flake if not already locked.
if ! [[ -f flake.lock ]]; then
  echo "e2e: locking synthetic flake (one-time)" >&2
  nix flake lock
fi

cd "${REPO_ROOT}"

OPTION="nix run ${REPO_ROOT}#option --"
CONFLICT="nix run ${REPO_ROOT}#conflict --"
OVERLAY="nix run ${REPO_ROOT}#overlay --"

declare -i failed=0
declare -i passed=0

ok() {
  printf '  \033[32m✓\033[0m %s\n' "$1"
  passed+=1
}
fail() {
  printf '  \033[31m✗\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  failed+=1
}

# ---------------------------------------------------------------------------
# nix-why-option default subcommand (resolve)
# ---------------------------------------------------------------------------
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

section "nix-why-option resolve"

j="$($OPTION --json "${SYNTHETIC}#nixosConfigurations.test" services.test.enable 2> /dev/null || echo "FAIL")"
if [[ $j == "FAIL" ]]; then
  fail "resolve services.test.enable" "command failed"
else
  v="$(echo "$j" | jq -r '.value')"
  k="$(echo "$j" | jq -r '.kind')"
  if [[ $v == "true" && $k == "option" ]]; then
    ok "services.test.enable resolves to true (kind=option)"
  else
    fail "services.test.enable wrong value/kind" "got kind=$k value=$v"
  fi
fi

j="$($OPTION --json "${SYNTHETIC}#nixosConfigurations.test" services.test.port 2> /dev/null || echo "FAIL")"
v="$(echo "$j" | jq -r '.value')"
if [[ $v == "9090" ]]; then
  ok "services.test.port resolves to 9090"
else
  fail "services.test.port wrong value" "got $v"
fi

j="$($OPTION --json "${SYNTHETIC}#nixosConfigurations.test" networking.hostName 2> /dev/null || echo "FAIL")"
v="$(echo "$j" | jq -r '.value')"
if [[ $v == "synthetic-test" ]]; then
  ok "networking.hostName resolves to synthetic-test"
else
  fail "networking.hostName wrong" "got $v"
fi

# Shorthand schema autodetect: .#test should resolve to nixosConfigurations.test
j="$($OPTION --json "${SYNTHETIC}#test" services.test.enable 2> /dev/null || echo "FAIL")"
v="$(echo "$j" | jq -r '.value')"
if [[ $v == "true" ]]; then
  ok "shorthand .#test autodetects nixosConfigurations"
else
  fail "shorthand autodetect failed" "got $v"
fi

# Nonexistent option -> exit 2
rc=0
$OPTION "${SYNTHETIC}#nixosConfigurations.test" services.bogus.does.not.exist 2> /dev/null > /dev/null || rc=$?
if [[ $rc == "2" ]]; then
  ok "nonexistent option -> exit 2"
else
  fail "nonexistent option exit code" "expected 2, got $rc"
fi

# Freeform / undeclared attr -> kind=freeform, value surfaced, exit 0.
rc=0
j="$($OPTION --json "${SYNTHETIC}#test" settings.undeclaredKey 2> /dev/null)" || rc=$?
k="$(printf '%s' "$j" | jq -r '.kind' 2> /dev/null)"
v="$(printf '%s' "$j" | jq -r '.value' 2> /dev/null)"
if [[ $rc == 0 && $k == "freeform" && $v == "free-value" ]]; then
  ok "freeform undeclared attr surfaces value (kind=freeform)"
else
  fail "freeform attr handling" "rc=$rc kind=$k value=$v"
fi

# ---------------------------------------------------------------------------
# nix-why-option search
# ---------------------------------------------------------------------------
section "nix-why-option search"

j="$($OPTION --json search "${SYNTHETIC}#test" "services.test" 2> /dev/null || echo "FAIL")"
n="$(echo "$j" | jq -r '.totalMatches')"
if [[ $n -ge "3" ]]; then
  ok "search 'services.test' finds >= 3 matches"
else
  fail "search too few matches" "got $n"
fi

# No matches -> exit 2
rc=0
$OPTION search "${SYNTHETIC}#test" "definitely-not-there" 2> /dev/null > /dev/null || rc=$?
if [[ $rc == "2" ]]; then
  ok "search with no matches -> exit 2"
else
  fail "search no-match exit code" "expected 2, got $rc"
fi

# ---------------------------------------------------------------------------
# nix-why-option what-sets
# ---------------------------------------------------------------------------
section "nix-why-option what-sets"

j="$($OPTION --json what-sets "${SYNTHETIC}#test" services.test.port 2> /dev/null || echo "FAIL")"
n="$(echo "$j" | jq -r '.setters | length')"
if [[ $n -ge "1" ]]; then
  ok "what-sets services.test.port finds >= 1 setter"
else
  fail "what-sets returned no setters" "got $n"
fi

# ---------------------------------------------------------------------------
# nix-why-option why-not
# ---------------------------------------------------------------------------
section "nix-why-option why-not"

# why-not on a default-only option exits 1 (informational), and that
# is correct - the test should not treat exit 1 as a hard failure.
rc=0
j="$($OPTION --json why-not "${SYNTHETIC}#test" services.test.onlyDefault 2> /dev/null)" || rc=$?
e="$(printf '%s' "$j" | jq -r '.isExplicitlySet' 2> /dev/null || echo error)"
if [[ $rc == 1 && $e == "false" ]]; then
  ok "why-not services.test.onlyDefault reports NOT explicitly set (exit 1)"
else
  fail "why-not isExplicitlySet wrong" "rc=$rc, e=$e"
fi

# gated.target has a filtered-out candidate, so this exits 0.
# mkIf-filtered candidates need the module-walk (--full); the
# synthetic flake's module list is flat, so the walk resolves.
rc=0
j="$($OPTION --json --full why-not "${SYNTHETIC}#test" gated.target 2> /dev/null)" || rc=$?
filtered="$(printf '%s' "$j" | jq -r '.filteredOutDefinitions | length' 2> /dev/null || echo 0)"
if [[ $rc == 0 && $filtered -ge 1 ]]; then
  ok "why-not gated.target surfaces filtered-out definition"
else
  fail "why-not did not surface mkIf-filtered def" "rc=$rc, filtered=$filtered"
fi

# ---------------------------------------------------------------------------
# nix-why-conflict
# ---------------------------------------------------------------------------
section "nix-why-conflict"

rc=0
j="$($CONFLICT --json "${SYNTHETIC}#nixosConfigurations.conflicting" services.test.enable 2> /dev/null)" || rc=$?
nc="$(echo "$j" | jq -r '.conflicts | length' 2> /dev/null)"
if [[ $rc == "1" ]] && [[ ${nc:-0} -ge "1" ]]; then
  ok "conflict on services.test.enable: exit 1, conflicts[] populated"
else
  fail "conflict expected" "rc=$rc, conflicts=${nc:-0}"
fi

rc=0
$CONFLICT --json "${SYNTHETIC}#nixosConfigurations.test" services.test.enable > /dev/null 2>&1 || rc=$?
if [[ $rc == "0" ]]; then
  ok "no-conflict on services.test.enable -> exit 0"
else
  fail "no-conflict exit code" "expected 0, got $rc"
fi

# ---------------------------------------------------------------------------
# nix-why-overlay (listing mode)
# ---------------------------------------------------------------------------
section "nix-why-overlay"

# Synthetic config does not provision pkgs via _module.args.pkgs, so
# overlay tool will report "could not locate overlays". That's a
# legitimate exit-3 result; we assert the exit code without claiming
# a richer behaviour the synthetic flake cannot supply.
rc=0
$OVERLAY "${SYNTHETIC}#nixosConfigurations.test" > /dev/null 2>&1 || rc=$?
if [[ $rc == "3" ]]; then
  ok "overlay on synthetic (no pkgs) -> exit 3 with discovery message"
else
  fail "overlay exit code" "expected 3, got $rc"
fi

# Schema-shorthand autodetect: `.#test` must resolve to
# nixosConfigurations.test (same as nix-why-option), reaching overlay
# DISCOVERY - not failing with "attribute path 'test' not found".
rc=0
out="$($OVERLAY "${SYNTHETIC}#test" 2>&1)" || rc=$?
if [[ $rc == "3" ]] && grep -q "could not locate overlays" <<< "$out"; then
  ok "overlay shorthand .#test autodetects (reaches discovery)"
else
  fail "overlay shorthand autodetect" "rc=$rc out=$(tr '\n' '|' <<< "$out" | head -c 160)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n\033[1m'
printf 'e2e summary: %d passed, %d failed\n' "$passed" "$failed"
printf '\033[0m'

((failed == 0))
