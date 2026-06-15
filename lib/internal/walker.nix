{ lib }:
let
  # COUPLING: the `_type` markers ("if"/"override"/"merge"/"order") and
  # their field names (.condition/.content/.priority/.contents) below are
  # nixpkgs module-system internals. They are pinned against the live
  # lib by the drift-guard in tests/lib.nix; a rename fails there loudly
  # rather than silently degrading the walk. Removing this shadow
  # re-implementation is RFC #2's goal.
  #
  # The recursive worker. Unwraps _type markers as it encounters them
  # (carrying their information into `ctx`), then descends one path
  # component at a time using `unsafeGetAttrPos` for line tracking.
  #
  # Returns a list of leaf records. Each record carries:
  #   - value:  the raw, fully-unwrapped value at the leaf
  #   - pos:    { file, line, column } | null  (deepest source position
  #             that was non-synthetic on the way down)
  #   - ctx.priority:    integer priority accumulated from mkOverride /
  #                      mkDefault / mkForce / mkOptionDefault wrappers
  #   - ctx.conditions:  list of mkIf conditions encountered on the way
  #                      down, in outer-to-inner order; each entry is
  #                      { condition :: bool; pos :: position | null }
  #
  # mkMerge fan-outs produce multiple records (one per merged value).
  walk =
    {
      value,
      pathParts,
      pos,
      ctx,
    }:
    let
      isAttr = builtins.isAttrs value;
      ty = if isAttr then (value._type or null) else null;
    in
    if ty == "if" then
      walk {
        value = value.content;
        inherit pathParts pos;
        ctx = ctx // {
          conditions = ctx.conditions ++ [
            {
              inherit (value) condition;
              inherit pos;
            }
          ];
        };
      }
    else if ty == "override" then
      walk {
        value = value.content;
        inherit pathParts pos;
        ctx = ctx // {
          inherit (value) priority;
        };
      }
    else if ty == "merge" then
      lib.concatMap (
        v:
        walk {
          value = v;
          inherit pathParts pos ctx;
        }
      ) value.contents
    else if ty == "order" then
      # mkBefore / mkAfter / mkOrder. The wrapper's `.priority` is the
      # list/string MERGE-ORDER rank, a different axis from the override
      # priority (mkForce/mkDefault) tracked in ctx - do NOT touch
      # ctx.priority. Just descend through to the underlying value, so
      # the wrapper does not leak into the leaf.
      walk {
        value = value.content;
        inherit pathParts pos ctx;
      }
    else if pathParts == [ ] then
      [
        {
          inherit value pos ctx;
        }
      ]
    else if !isAttr then
      [ ]
    else
      let
        head = builtins.head pathParts;
        tail = builtins.tail pathParts;
      in
      if !(value ? ${head}) then
        [ ]
      else
        let
          sub = value.${head};
          # unsafeGetAttrPos is an explicitly UNSTABLE builtin and
          # returns null for synthetic (compound-syntax) attributes.
          # Carry the previous known position when null; never throw.
          subPos = builtins.unsafeGetAttrPos head value;
          effectivePos = if subPos == null then pos else subPos;
        in
        walk {
          value = sub;
          pathParts = tail;
          pos = effectivePos;
          inherit ctx;
        };
in
{
  # walkConfig :: { config, pathParts } -> [{ value, pos, ctx }]
  #
  # Entry point. Starts the walk at a module's config with empty ctx
  # (priority = 100 = no wrapper, conditions = []).
  walkConfig =
    {
      config,
      pathParts,
    }:
    walk {
      value = config;
      inherit pathParts;
      pos = null;
      ctx = {
        priority = 100;
        conditions = [ ];
      };
    };
}
