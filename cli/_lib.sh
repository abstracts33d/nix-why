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
# Functions defined here depend only on POSIX builtins + coreutils,
# with portable fallbacks where GNU and BSD tools diverge (realpath).
# The caller is responsible for setting `no_color` (int 0/1) before
# calling nix_why_init_colors.

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

# Strip every /nix/store/<hash>-<name>/ occurrence from arbitrary text.
# For free-form strings (e.g. the why-not hint) that embed store paths,
# where strip_store_prefix (single-path) does not apply.
strip_store_in_text() {
  sed -E 's#/nix/store/[^/[:space:]]+/##g' <<< "$1"
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
      # BSD realpath (macOS) has no -m and older macOS ships none at
      # all; getFlake only needs an absolute path, not a canonical
      # one, so a plain $PWD join is a sufficient fallback.
      if ! realpath -m -- "$ref" 2> /dev/null; then
        case "$ref" in
          .) printf '%s' "$PWD" ;;
          ./*) printf '%s/%s' "$PWD" "${ref#./}" ;;
          *) printf '%s/%s' "$PWD" "$ref" ;;
        esac
      fi
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

# Guard a value-carrying flag: exit 64 with a usage message when the
# value is missing. Call before reading $2:
#   --limit) nix_why_require_arg nix-why-foo --limit $#; limit="$2"; shift 2 ;;
nix_why_require_arg() {
  local tool="$1" flag="$2" argc="$3"
  if ((argc < 2)); then
    echo "${tool}: ${flag} requires a value" >&2
    exit 64
  fi
}

# Validate that a flag value is a non-negative integer; exit 64
# otherwise. Catches both `--limit abc` and `--limit=abc` after the
# parse loop, before the value reaches arithmetic or `head -n`.
nix_why_require_int() {
  local tool="$1" flag="$2" value="$3"
  if ! [[ $value =~ ^[0-9]+$ ]]; then
    echo "${tool}: ${flag} expects a non-negative integer (got '${value}')" >&2
    exit 64
  fi
}

# "s"-suffix helper: empty for count==1, "s" otherwise. Bash's
# arithmetic ternary `((... ? a : b))` is integer-only, so a string
# ternary in $((...)) silently fails with "expression expected".
plural_s() {
  if [ "$1" -eq 1 ] 2> /dev/null; then printf ''; else printf 's'; fi
}

# Classify a captured nix-instantiate stderr blob into a (kind,
# message) pair suitable for either text or JSON rendering.
#
# Side-effects: sets the caller-scope globals `classify_kind` and
# `classify_message`.
#
# Kinds (stable, part of the JSON contract — see
# docs/reference/json-schema.md):
#   flake-not-found    - getFlake on a path that does not exist
#   attribute-missing  - attrByPath into the flake found nothing
#   nix-why-throw      - one of our own structured throw "nix-why: …"
#                        messages (adapter detect, schema autodetect,
#                        no attr after #, unknown adapter, ...)
#   eval-error         - anything else; the message is the bare
#                        contents of the final "error: " line
nix_why_classify_error() {
  local stderr_blob="$1"

  # Nix prints multiple "error:" lines in a trace. The final one is
  # typically the root cause; earlier ones are stack-frame chrome.
  local root_msg
  root_msg="$(printf '%s\n' "$stderr_blob" |
    grep -E '^[[:space:]]*error: ' |
    tail -1 |
    sed -E 's/^[[:space:]]*error: //')"

  case "$root_msg" in
    "path '"*"' does not exist")
      local path_inner="${root_msg#path \'}"
      path_inner="${path_inner%\' does not exist}"
      # Nix renders missing paths as `'//path/x'` (leading-slash
      # artifact from the path: URI scheme). Strip it.
      [[ $path_inner == //* ]] && path_inner="${path_inner#/}"
      classify_kind="flake-not-found"
      classify_message="flake not found at ${path_inner}"
      ;;
    "attribute '"*"' missing")
      # A raw Nix "attribute 'X' missing" is always a DEEP evaluation
      # error here: target resolution emits self-namespaced "nix-why:"
      # messages, never this. It means an option the config exposes could
      # not be introspected (an uncatchable attribute-missing inside the
      # module system - the native gap). Surface it honestly as an eval
      # failure, not as a flake-attribute lookup that "found nothing".
      classify_kind="eval-error"
      classify_message="${root_msg}"
      ;;
    "nix-why: "*)
      classify_kind="nix-why-throw"
      classify_message="${root_msg}"
      ;;
    "nix-why-"*": "*)
      classify_kind="nix-why-throw"
      classify_message="${root_msg}"
      ;;
    "")
      classify_kind="eval-error"
      classify_message=""
      ;;
    *)
      classify_kind="eval-error"
      classify_message="${root_msg}"
      ;;
  esac
}

# Emit a one-shot error to the right stream in the right format.
#
# Usage:
#   nix_why_emit_error <tool> <format> <kind> <message>
#
# format=="json": writes a JSON envelope to stdout (so consumers
# parse stdout regardless of success or failure). Schema:
#   { "schemaVersion": "1",
#     "error": { "tool": <tool>, "kind": <kind>, "message": <message> } }
#
# format anything else: writes "<tool>: <message>" to stderr, except
# when message already starts with "nix-why" - those are passed
# through verbatim (they are self-namespaced throws from the lib).
nix_why_emit_error() {
  local tool="$1"
  local format="$2"
  local kind="$3"
  local message="$4"

  if [[ $format == "json" ]]; then
    jq -n \
      --arg schemaVersion "1" \
      --arg tool "$tool" \
      --arg kind "$kind" \
      --arg message "$message" \
      '{ schemaVersion: $schemaVersion, error: { tool: $tool, kind: $kind, message: $message } }'
  else
    case "$message" in
      "nix-why: "* | "nix-why-"*": "*)
        printf '%s\n' "$message" >&2
        ;;
      "")
        printf '%s: evaluation failed (re-run with --show-trace for details)\n' "$tool" >&2
        ;;
      *)
        case "$kind" in
          eval-error)
            printf '%s: %s (re-run with --show-trace for details)\n' "$tool" "$message" >&2
            ;;
          *)
            printf '%s: %s\n' "$tool" "$message" >&2
            ;;
        esac
        ;;
    esac
  fi
}

# Classify a nix-instantiate stderr blob and emit a structured error.
#
# Usage:
#   nix_why_emit_error_from_stderr <tool> <format> <stderr-blob> <show-trace>
#
# When show-trace=1, the full original stderr is additionally written
# to fd 2 (so the user can debug the tool itself). The structured
# envelope still goes to its normal destination (stdout for json,
# stderr for text).
nix_why_emit_error_from_stderr() {
  local tool="$1"
  local format="$2"
  local stderr_blob="$3"
  local show_trace="${4:-0}"

  # shellcheck disable=SC2034  # classify_kind / classify_message are
  # set by classify and read by emit
  local classify_kind=""
  local classify_message=""
  nix_why_classify_error "$stderr_blob"

  nix_why_emit_error "$tool" "$format" "$classify_kind" "$classify_message"

  if ((show_trace)); then
    printf '%s\n' "$stderr_blob" >&2
  fi
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
