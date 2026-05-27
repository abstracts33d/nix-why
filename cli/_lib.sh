# shellcheck shell=bash
# shellcheck disable=SC2034  # C_* color vars are read by sourcing scripts
# shellcheck disable=SC2154  # attr_expr is set by split_flake_target for callers

# Shared helpers for nix-why-* CLI scripts.
#
# Sourced from each script via:
#   : "${NIX_WHY_CLI_SH:=${self_dir}/_lib.sh}"
#   # shellcheck source=./_lib.sh
#   source "${NIX_WHY_CLI_SH}"
#
# Functions defined here depend only on POSIX builtins + coreutils
# (no GNU-specific behaviour). The caller is responsible for setting
# `no_color` (int 0/1) before calling nix_why_init_colors.

# Set up ANSI color variables based on $no_color (caller-set int).
# Defines C_RESET / C_BOLD / C_DIM / C_GREEN / C_RED / C_CYAN /
# C_YELLOW / C_MAGENTA in the caller's scope.
nix_why_init_colors() {
  if ((${no_color:-0})); then
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_GREEN=""
    C_RED=""
    C_CYAN=""
    C_YELLOW=""
    C_MAGENTA=""
  else
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
    C_YELLOW=$'\033[33m'
    C_MAGENTA=$'\033[35m'
  fi
}

# Strip the /nix/store/<hash>-<name>/ prefix from a path. Falls through
# for paths that do not look like store paths.
strip_store_prefix() {
  local p="$1"
  if [[ $p =~ ^/nix/store/[^/]+/(.+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$p"
  fi
}

# Resolve a flake reference to an absolute path (or leave registry
# URLs alone). builtins.getFlake requires either an absolute path or
# a registry/URL form.
absolutize_flake_ref() {
  local ref="$1"
  case "$ref" in
    github:* | gitlab:* | sourcehut:* | git+* | http://* | https://* | path:* | flake:*)
      printf '%s' "$ref"
      ;;
    /*)
      printf '%s' "$ref"
      ;;
    *)
      realpath -m -- "$ref"
      ;;
  esac
}

# Split <flake-ref>#<attr> into flake_ref + attr_expr globals.
# After return: $flake_ref is absolute and ready for builtins.getFlake;
# $attr_expr is the inside-flake attribute path (or "" if none).
split_flake_target() {
  local target="$1"
  if [[ $target == *"#"* ]]; then
    flake_ref="${target%%#*}"
    attr_expr="${target#*#}"
  else
    flake_ref="$target"
    attr_expr=""
  fi
  [[ -z $flake_ref ]] && flake_ref="."
  flake_ref="$(absolutize_flake_ref "$flake_ref")"
}

# "s"-suffix helper: empty for count==1, "s" otherwise. Bash's
# arithmetic ternary `((... ? a : b))` is integer-only, so a string
# ternary in $((...)) silently fails with "expression expected".
plural_s() {
  if [ "$1" -eq 1 ] 2> /dev/null; then printf ''; else printf 's'; fi
}
