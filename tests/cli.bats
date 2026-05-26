#!/usr/bin/env bats
#
# CLI surface tests for nix-why-option. These tests exercise argv
# parsing, error handling, and exit code mapping. The full library
# behaviour is tested in tests/lib.nix via lib.runTests.
#
# Tier 3 smoke tests (real flake targets) live in tests/smoke/.

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export NIX_WHY_LIB="${REPO_ROOT}/lib"
  CLI="${REPO_ROOT}/cli/nix-why-option"
}

@test "help: --help exits 0 and shows usage" {
  run "${CLI}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--brief"* ]]
  [[ "$output" == *"--adapter"* ]]
  [[ "$output" == *"Exit codes:"* ]]
}

@test "help: -h works the same as --help" {
  run "${CLI}" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "usage: no args -> exit 64" {
  run "${CLI}"
  [ "$status" -eq 64 ]
  [[ "$output" == *"expected <flake-target> <option-path>"* ]]
}

@test "usage: only one positional -> exit 64" {
  run "${CLI}" only-one-arg
  [ "$status" -eq 64 ]
  [[ "$output" == *"expected <flake-target> <option-path>"* ]]
}

@test "usage: unknown flag -> exit 64" {
  run "${CLI}" --frobnicate .#krach foo.bar
  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "usage: eval subcommand with no positional args -> exit 64" {
  run "${CLI}" eval
  [ "$status" -eq 64 ]
  [[ "$output" == *"expected <expr> <option-path>"* ]]
}

@test "usage: eval subcommand with one positional -> exit 64" {
  run "${CLI}" eval '({modules=[];})'
  [ "$status" -eq 64 ]
  [[ "$output" == *"expected <expr> <option-path>"* ]]
}

@test "library: NIX_WHY_LIB pointing at nonexistent dir -> exit 64" {
  NIX_WHY_LIB="/nonexistent/path" run "${CLI}" .#krach foo.bar
  [ "$status" -eq 64 ]
  [[ "$output" == *"NIX_WHY_LIB does not point"* ]]
}

@test "argv: --max-value accepts a number" {
  run "${CLI}" --max-value 50 --help
  [ "$status" -eq 0 ]
}

@test "argv: --max-value=N (equals form) accepts a number" {
  run "${CLI}" --max-value=50 --help
  [ "$status" -eq 0 ]
}

@test "argv: --adapter accepts a name" {
  run "${CLI}" --adapter nixos --help
  [ "$status" -eq 0 ]
}

@test "argv: --no-color sets the flag" {
  run "${CLI}" --no-color --help
  [ "$status" -eq 0 ]
}
