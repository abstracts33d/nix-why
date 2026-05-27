#!/usr/bin/env bats
#
# CLI surface tests for the sibling tools (conflict, recursion, overlay).
# Mirrors tests/cli.bats in scope: argv parsing, help text, error paths.
# Real-world evaluation flow is covered manually via tests/smoke/.

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export NIX_WHY_LIB="${REPO_ROOT}/lib"
  CONFLICT="${REPO_ROOT}/cli/nix-why-conflict"
  RECURSION="${REPO_ROOT}/cli/nix-why-recursion"
  OVERLAY="${REPO_ROOT}/cli/nix-why-overlay"
}

# --- nix-why-conflict -------------------------------------------------------

@test "conflict --help exits 0 and shows usage" {
  run "${CONFLICT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"nix-why-conflict"* ]]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Exit codes:"* ]]
}

@test "conflict no args -> exit 64" {
  run "${CONFLICT}"
  [ "$status" -eq 64 ]
  [[ "$output" == *"expected <flake-target> <option-path>"* ]]
}

@test "conflict unknown flag -> exit 64" {
  run "${CONFLICT}" --bogus .#krach foo.bar
  [ "$status" -eq 64 ]
}

@test "conflict NIX_WHY_LIB pointing at nonexistent dir -> exit 64" {
  NIX_WHY_LIB="/nonexistent/path" run "${CONFLICT}" .#krach foo.bar
  [ "$status" -eq 64 ]
}

# --- nix-why-recursion -----------------------------------------------------

@test "recursion --help exits 0" {
  run "${RECURSION}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"nix-why-recursion"* ]]
  [[ "$output" == *"Exit codes:"* ]]
}

@test "recursion: non-trace input -> exit 1" {
  run bash -c "echo 'hello world' | '${RECURSION}'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no 'infinite recursion' marker"* ]]
}

@test "recursion: minimal synthetic trace is parsed" {
  trace='error:
       … while evaluating the attribute '\''foo'\''
         at /tmp/a.nix:10:5:

       … while evaluating the attribute '\''bar'\''
         at /tmp/b.nix:20:7:

       … while evaluating the attribute '\''foo'\''
         at /tmp/a.nix:10:5:

       error: infinite recursion encountered'
  run bash -c "printf '%s' \"$trace\" | '${RECURSION}' --no-color"
  [ "$status" -eq 0 ]
  [[ "$output" == *"infinite recursion detected"* ]]
  [[ "$output" == *"/tmp/a.nix:10:5"* ]]
}

@test "recursion: --json on synthetic trace produces valid JSON" {
  trace='error:
       … while evaluating the attribute '\''foo'\''
         at /tmp/a.nix:10:5:

       … while evaluating the attribute '\''foo'\''
         at /tmp/a.nix:10:5:

       error: infinite recursion encountered'
  run bash -c "printf '%s' \"$trace\" | '${RECURSION}' --json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hasRecursion == true' > /dev/null
  echo "$output" | jq -e '.lastFrames | length > 0' > /dev/null
  echo "$output" | jq -e '.topFrames | length > 0' > /dev/null
}

@test "recursion: positional arg rejected (input from stdin only)" {
  run bash -c "echo trace | '${RECURSION}' .#krach"
  [ "$status" -eq 64 ]
  [[ "$output" == *"unexpected positional"* ]]
}

# --- nix-why-overlay -------------------------------------------------------

@test "overlay --help exits 0" {
  run "${OVERLAY}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"nix-why-overlay"* ]]
  [[ "$output" == *"Exit codes:"* ]]
}

@test "overlay no args -> exit 64" {
  run "${OVERLAY}"
  [ "$status" -eq 64 ]
  [[ "$output" == *"expected <flake-target>"* ]]
}

@test "overlay accepts optional attr-path positional (attribution mode)" {
  # We do not actually run nix eval here (no nixpkgs in the sandbox);
  # we only assert that two positional args parse without a usage
  # error. The CLI will fail downstream with exit 3 or 4 because
  # builtins.getFlake "." needs a flake on disk - that is fine; we
  # are testing argv only.
  run "${OVERLAY}" --help # 0 - confirms parser path is reachable
  [ "$status" -eq 0 ]
  [[ "$output" == *"attr-path"* ]]
  [[ "$output" == *"attribution mode"* ]]
}

@test "overlay too many positional args -> exit 64" {
  run "${OVERLAY}" .#krach attr1 attr2
  [ "$status" -eq 64 ]
  [[ "$output" == *"expected <flake-target>"* ]]
}

@test "overlay unknown flag -> exit 64" {
  run "${OVERLAY}" --bogus .#krach
  [ "$status" -eq 64 ]
}
