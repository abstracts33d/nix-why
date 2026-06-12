# nix-why JSON schema reference

All `--json` outputs from the nix-why CLIs carry a top-level
`schemaVersion` field. This is the stability contract for downstream
integrations (CI checks, IDE plugins, dashboards) that parse nix-why
output.

## Current version

```
schemaVersion = "1"
```

The single source of truth lives at
[`cli/expr/_common.nix`](../../cli/expr/_common.nix). The
`nix-why-recursion` script duplicates the constant in bash (it does
not go through `nix eval`); keep both in sync when bumping.

## Versioning policy

- **Additive change** (new optional field, new value for an existing
  string enum) — `schemaVersion` stays the same. Consumers must
  ignore unknown fields.
- **Breaking change** (field removed, renamed, type changed, or
  semantics altered) — `schemaVersion` is bumped to the next integer
  (`"2"`, `"3"`, ...).

Consumers should fail loudly when they see an unexpected
`schemaVersion`. Treat a higher version as forward-incompatible until
the consumer is updated.

## Per-subcommand schemas

### `nix-why-option` (resolve)

Emitted by the default subcommand and by `eval`.

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `path` | string | Dotted option path |
| `kind` | `"option" \| "not-found" \| "not-an-option"` | Resolution category |
| `type` | string | Nix option type description |
| `value` | any | Final merged value, or `null` if `valueError` |
| `valueError` | string \| null | Set when evaluation of the value failed |
| `winningPriority` | int \| null | Priority of the winning definition |
| `winningPriorityKind` | string \| null | Label for the winning priority (`mkDefault`/`mkForce`/…), from the lib's single priority table |
| `isDefined` | bool | True if the option has at least one definition |
| `moduleWalkAvailable` | bool | True only when the raw module-walk ran (`--full`). The default options-surface output sets it false; `definitions[].line` and mkIf guards are then null, but `priority`/`priorityKind` are still populated from the winning priority. |
| `declarations[]` | object | `{ file, line, column }` for each declaration |
| `definitions[]` | object | `{ file, line, priority, priorityKind, value, wins, guardedBy }` |
| `conflicts[]` | object | Populated only when merge fails |

### `nix-why-option what-sets`

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `path` | string | Queried option path |
| `kind` | `"option" \| "not-found" \| "not-an-option"` | Resolution category |
| `type` | string | Option type description |
| `isDefined` | bool | True if the option has at least one definition |
| `declarations[]` | object | `{ file, line, column }` for each declaration |
| `setters[]` | object | `{ file, line, value, priority, priorityKind, guardedBy }`; `line` and `guardedBy` are null without the module-walk |
| `moduleWalkAvailable` | bool | True only when the raw module-walk ran (`--full`) |

### `nix-why-option why-not`

Emitted when an option exists but is not explicitly set, or is gated
out by an `mkIf`.

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `path` | string | Queried option path |
| `kind` | string | Resolution category |
| `type` | string | Option type description |
| `value` | any | Default value (or evaluation result) |
| `isExplicitlySet` | bool | False = option only has defaults |
| `moduleWalkAvailable` | bool | True only when the module-walk ran (`--full`); otherwise filtered/default definitions are options-surface only |
| `declarations[]` | object | Declaration sites |
| `defaultDefinitions[]` | object | Default-priority definitions |
| `explicitDefinitions[]` | object | Non-default definitions (if any) |
| `filteredOutDefinitions[]` | object | Definitions silenced by `mkIf` |
| `hint` | string \| null | Suggested user action |

### `nix-why-option search`

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `pattern` | string | The query pattern |
| `totalMatches` | int | Number of matches (may exceed truncated list) |
| `matches[]` | object | `{ path, type, declarations, isDefined }` |
| `truncated` | bool | True when result list was capped by `--limit` |

### `nix-why-conflict`

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `path` | string | Queried option path |
| `kind` | string | Resolution category |
| `type` | string | Option type description |
| `valueError` | string \| null | Set when conflict caused merge failure |
| `conflicts[]` | object | Conflict tuples; empty array = no conflict |

### `nix-why-overlay` (listing mode)

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `mode` | `"listing"` | |
| `error` | string \| null | Null on success |
| `overlayCount` | int | Number of overlays applied to pkgs |
| `overlays[]` | object | `{ index, name, appliedOk, attributeCount, attributes[] }` |

### `nix-why-overlay` (attribution mode)

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `mode` | `"attribution"` | |
| `error` | string \| null | |
| `path` | string | Attribute path queried inside `pkgs` |
| `overlayCount` | int | |
| `overlayNames[]` | string | Synthetic per-overlay labels |
| `signatures[]` | object | Per-overlay signature of the queried attribute |
| `diffs[]` | object | Per-step diff between cumulative signatures |
| `summary` | object | `{ firstAppearance, lastModification, changeCount, finalKind }` |

### `nix-why-recursion`

Emitted only when `infinite recursion` is detected in the input
trace.

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `hasRecursion` | bool | Always `true` when JSON is emitted |
| `lastFrames[]` | object | `{ pos, description }` for the last N frames |
| `topFrames[]` | object | `{ count, pos, description }` frequency view |

## Error envelopes

When a CLI exits with rc ≥ 2 *and* `--json` was requested, the
response is a structured error envelope written to **stdout** (so
consumers parse stdout regardless of success or failure):

```json
{
  "schemaVersion": "1",
  "error": {
    "tool": "nix-why-option",
    "kind": "flake-not-found",
    "message": "flake not found at /tmp/does-not-exist"
  }
}
```

A consumer should check for the presence of `error` before reading
the success-shape fields. If `error` is present, the success-shape
fields are not guaranteed to exist (and vice versa).

### Error kinds

| `kind` | Trigger | Typical exit |
|---|---|---|
| `flake-not-found` | `builtins.getFlake` could not read the given path | 3 |
| `attribute-missing` | `attrByPath` into the flake found nothing | 3 |
| `nix-why-throw` | One of the lib's structured `nix-why: …` throws (adapter detection, schema autodetect, no attr after `#`, unknown adapter, ...) | 3 |
| `option-not-found` | Option path did not exist in the options tree | 2 |
| `not-an-option` | Option path exists but is an intermediate attrset, not a leaf option | 2 |
| `internal-error` | Tool returned an unexpected AST `kind`; please report | 4 |
| `eval-error` | Any other `nix-instantiate` failure | 4 |

### Special-case: `nix-why-overlay`

The overlay tool surfaces discovery-level failures via the
`error: string \| null` field rather than the unified envelope above.
A discovery failure (overlays not located on the target) emits only
`{ schemaVersion, error }`; an attribution-baseline failure emits
`{ schemaVersion, mode, error }`. Consumers must treat every field
except `schemaVersion` and `error` as optional when `error` is
non-null. Eval-level failures still use the unified envelope.

### Usage-error exit (rc=64)

Argument-parsing errors (`--json` but no positional args, unknown
flag, etc.) print a plain-text message + the help banner to stderr
and exit 64 *without* emitting a JSON envelope. The expectation is
that scripted callers got their argv wrong and need a human-readable
correction, not a structured error.
