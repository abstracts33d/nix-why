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

# Render a one-line actionable error from a captured nix-instantiate
# stderr blob, suppressing internal-library file paths and stack
# frames unless --show-trace was requested.
#
# Usage:
#   nix_why_render_error <tool-name> <stderr-blob> <show-trace-flag>
#
# When show-trace-flag is 0:
#   - Extract the most-specific "error: <message>" line (Nix emits the
#     root cause last in the trace)
#   - Translate well-known patterns into actionable one-liners:
#     - "path '<p>' does not exist"   -> "<tool>: flake not found at <p>"
#     - "attribute '<a>' missing"     -> "<tool>: attribute '<a>' not found in flake"
#     - "nix-why: <msg>"              -> "<msg>" (our own throws pass through)
#   - Anything else: prefix with "<tool>: " and emit the bare error line
#   - The internal stack frames, source previews, and store paths are
#     dropped on the floor
#
# When show-trace-flag is 1:
#   - The full original stderr is emitted verbatim (Nix already
#     produced a complete --show-trace dump if requested)
#
# Always prints to fd 2. Returns 0 if a known pattern matched, 1 on
# fallback.
nix_why_render_error() {
  local tool="$1"
  local stderr_blob="$2"
  local show_trace="${3:-0}"

  if ((show_trace)); then
    printf '%s\n' "$stderr_blob" >&2
    return 0
  fi

  # Nix prints multiple "error:" lines in a trace. The final one is
  # typically the root cause; the earlier ones are stack-frame chrome.
  local root_msg
  root_msg="$(printf '%s\n' "$stderr_blob" |
    grep -E '^[[:space:]]*error: ' |
    tail -1 |
    sed -E 's/^[[:space:]]*error: //')"

  # Nix renders missing paths as `'//path/to/x'` with a leading slash
  # artifact. Strip it back to the user-supplied form.
  local matched=0
  case "$root_msg" in
    "path '"*"' does not exist")
      local path_inner="${root_msg#path \'}"
      path_inner="${path_inner%\' does not exist}"
      [[ $path_inner == //* ]] && path_inner="${path_inner#/}"
      printf '%s: flake not found at %s\n' "$tool" "$path_inner" >&2
      matched=1
      ;;
    "attribute '"*"' missing")
      local attr="${root_msg#attribute \'}"
      attr="${attr%\' missing}"
      printf "%s: attribute '%s' not found in flake\n" "$tool" "$attr" >&2
      matched=1
      ;;
    "nix-why: "*)
      printf '%s\n' "$root_msg" >&2
      matched=1
      ;;
    "nix-why-"*": "*)
      printf '%s\n' "$root_msg" >&2
      matched=1
      ;;
    "")
      printf '%s: evaluation failed (re-run with --show-trace for details)\n' "$tool" >&2
      ;;
    *)
      printf '%s: %s (re-run with --show-trace for details)\n' "$tool" "$root_msg" >&2
      ;;
  esac

  return $((1 - matched))
}

# Print "<tool-name> <version>" to stdout.
#
# The version is taken from $NIX_WHY_VERSION (set by the package
# wrapper to the flake's nixWhyVersion). Falls back to "(dev)" for
# local development runs of the raw script.
#
# Callers pass their tool name (e.g. "nix-why-option"). The format
# matches `nix --version` ("nix (Nix) X.Y.Z") loosely but stays terse
# enough for scripted parsing.
nix_why_print_version() {
  local tool="${1:-nix-why}"
  printf '%s %s\n' "$tool" "${NIX_WHY_VERSION:-(dev)}"
}
