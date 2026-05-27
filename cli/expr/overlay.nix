# Driver expression for nix-why-overlay. Handles both listing mode
# (attrPath == "") and attribution mode (attrPath given). Does not
# depend on the nix-why library - overlay attribution uses different
# evaluation machinery (cumulative pkgs.extend folds), not module-
# system introspection.
#
# Invoked as:
#   nix eval --impure --json -f overlay.nix \
#     --argstr flakeRef  <flake ref>
#     --argstr attr      <attribute path>
#     --argstr attrPath  <dotted attr-into-pkgs path | "" for listing>
{
  flakeRef,
  attr,
  attrPath ? "",
}:
let
  inherit ((import <nixpkgs> { })) lib;
  common = import ./_common.nix { inherit lib; };
  flake = builtins.getFlake flakeRef;

  parts = if attr == "" then [ ] else lib.splitString "." attr;
  target =
    if parts == [ ] then
      throw "nix-why-overlay: no attribute path given after '#'"
    else
      lib.attrByPath parts (throw "nix-why-overlay: attribute path '${attr}' not found in flake") flake;

  pathParts = if attrPath == "" then [ ] else lib.splitString "." attrPath;

  discovery =
    let
      tries = [
        (
          if
            target ? config
            && target.config ? nixpkgs
            && target.config.nixpkgs ? overlays
            && target.config ? _module
            && target.config._module ? args
            && target.config._module.args ? pkgs
          then
            {
              pkgs = target.config._module.args.pkgs;
              overlays = target.config.nixpkgs.overlays;
              nixpkgsConfig = target.config.nixpkgs.config or { };
            }
          else
            null
        )
        (
          if
            target ? _module
            && target._module ? args
            && target._module.args ? pkgs
            && target._module.args.pkgs ? overlays
          then
            {
              inherit (target._module.args) pkgs;
              overlays = target._module.args.pkgs.overlays;
              nixpkgsConfig = target._module.args.pkgs.config or { };
            }
          else
            null
        )
        (
          if target ? overlays && target ? pkgs && builtins.isList target.overlays then
            {
              inherit (target) pkgs overlays;
              nixpkgsConfig = target.pkgs.config or { };
            }
          else
            null
        )
        (
          if target ? lib && target ? stdenv && target ? overlays && builtins.isList target.overlays then
            {
              pkgs = target;
              inherit (target) overlays;
              nixpkgsConfig = target.config or { };
            }
          else
            null
        )
      ];
    in
    lib.findFirst (x: x != null) null tries;
in
if discovery == null then
  {
    inherit (common) schemaVersion;
    error = "could not locate overlays on the target. Tried NixOS/HM/darwin config.nixpkgs, _module.args.pkgs, target.overlays, and target-is-pkgs shapes. Point me at .#nixosConfigurations.<host> or .#legacyPackages.<system>.";
  }
else
  let
    inherit (discovery) pkgs;
    inherit (discovery) overlays;

    nixpkgsSrc = pkgs.path or null;
    canBuildBaseline = nixpkgsSrc != null;

    system = pkgs.stdenv.hostPlatform.system or builtins.currentSystem;

    baselinePkgs =
      if canBuildBaseline then
        import nixpkgsSrc {
          inherit system;
          config = discovery.nixpkgsConfig;
          overlays = [ ];
        }
      else
        null;

    cumulatives =
      if canBuildBaseline then
        lib.foldl (acc: ov: acc ++ [ ((lib.last acc).extend ov) ]) [ baselinePkgs ] overlays
      else
        [ ];

    tryRead = expr: builtins.tryEval expr;

    sigOf =
      pkgsInst:
      let
        tried = tryRead (lib.attrByPath pathParts null pkgsInst);
      in
      if !tried.success then
        { kind = "eval-error"; }
      else if tried.value == null then
        { kind = "missing"; }
      else
        let
          v = tried.value;
          drvTried = tryRead (v.drvPath or null);
          namesTried = tryRead (if builtins.isAttrs v then builtins.attrNames v else [ ]);
          strTried = tryRead (if builtins.isFunction v then "<function>" else builtins.toString v);
          drvField =
            name:
            let
              t = tryRead (v.${name} or null);
            in
            if t.success then t.value else null;
        in
        if builtins.isAttrs v && drvTried.success && drvTried.value != null then
          {
            kind = "derivation";
            drvPath = drvTried.value;
            fields = {
              name = drvField "name";
              version = drvField "version";
              pname = drvField "pname";
              outputName = drvField "outputName";
              system = drvField "system";
            };
          }
        else if builtins.isAttrs v then
          {
            kind = "attrset";
            attrNames = if namesTried.success then namesTried.value else [ ];
          }
        else if builtins.isFunction v then
          { kind = "function"; }
        else if builtins.isList v then
          {
            kind = "list";
            length = builtins.length v;
          }
        else
          {
            kind = builtins.typeOf v;
            value = if strTried.success then strTried.value else "(unprintable)";
          };

    signatures = map sigOf cumulatives;

    changedFields =
      prev: curr:
      if prev.kind != "derivation" || curr.kind != "derivation" then
        [ ]
      else
        let
          fieldNames = [
            "name"
            "version"
            "pname"
            "outputName"
            "system"
          ];
          diff = builtins.filter (fn: (prev.fields.${fn} or null) != (curr.fields.${fn} or null)) fieldNames;
        in
        if diff != [ ] then
          diff
        else if prev.drvPath != curr.drvPath then
          [ "drvPath" ]
        else
          [ ];

    diffOf =
      i:
      let
        prev = builtins.elemAt signatures i;
        curr = builtins.elemAt signatures (i + 1);
        same = prev == curr;
        prevMissing = prev.kind == "missing";
        currMissing = curr.kind == "missing";
        kind =
          if same then
            "unchanged"
          else if prevMissing && !currMissing then
            "introduced"
          else if !prevMissing && currMissing then
            "removed"
          else
            "modified";
      in
      {
        overlayIndex = i;
        inherit kind;
        prevKind = prev.kind;
        currKind = curr.kind;
        changedFields = if kind == "modified" then changedFields prev curr else [ ];
      };

    diffs = if pathParts == [ ] then [ ] else lib.genList diffOf (builtins.length overlays);

    changeDiffs = lib.filter (d: d.kind != "unchanged") diffs;

    synthName =
      idx: overlay:
      let
        applied = tryRead (overlay pkgs pkgs);
        names =
          if applied.success && builtins.isAttrs applied.value then builtins.attrNames applied.value else [ ];
        sample = lib.take 2 names;
        suffix = if builtins.length names > 2 then ", ..." else "";
      in
      if names == [ ] then
        "overlay ${toString idx}"
      else
        "overlay ${toString idx} (${lib.concatStringsSep ", " sample}${suffix})";

    overlayNames = lib.imap0 synthName overlays;

    summary =
      if pathParts == [ ] then
        null
      else
        let
          firstAppearance =
            let
              baseline = builtins.head signatures;
              firstChange = lib.findFirst (d: d.kind == "introduced") null diffs;
            in
            if baseline.kind != "missing" then
              "baseline"
            else if firstChange != null then
              builtins.elemAt overlayNames firstChange.overlayIndex
            else
              "never";
          lastModification =
            let
              last = lib.findFirst (_d: true) null (lib.reverseList changeDiffs);
            in
            if last == null then "none" else "${builtins.elemAt overlayNames last.overlayIndex} (${last.kind})";
        in
        {
          inherit firstAppearance lastModification;
          changeCount = builtins.length changeDiffs;
          finalKind = (lib.last signatures).kind;
        };

    # Listing mode: for each overlay, report the attribute names IT
    # contributed. The correct semantic is to call the overlay with
    # the same (final, prev) it received during its own `extend`:
    #   final = cumulatives[idx + 1]  (post-this-overlay)
    #   prev  = cumulatives[idx]      (pre-this-overlay)
    # When cumulatives is empty (no baseline available, e.g. pkgs.path
    # was unset), fall back to (pkgs, pkgs) which is approximate but
    # still useful for independent overlays.
    listingOverlays =
      let
        haveCumulatives = cumulatives != [ ];
        describe =
          idx: overlay:
          let
            applied =
              if haveCumulatives then
                tryRead (overlay (builtins.elemAt cumulatives (idx + 1)) (builtins.elemAt cumulatives idx))
              else
                tryRead (overlay pkgs pkgs);
            names =
              if applied.success && builtins.isAttrs applied.value then builtins.attrNames applied.value else [ ];
          in
          {
            index = idx;
            name = builtins.elemAt overlayNames idx;
            appliedOk = applied.success;
            attributeCount = builtins.length names;
            attributes = names;
          };
      in
      lib.imap0 describe overlays;
  in
  if pathParts == [ ] then
    {
      inherit (common) schemaVersion;
      mode = "listing";
      error = null;
      overlayCount = builtins.length overlays;
      overlays = listingOverlays;
    }
  else if !canBuildBaseline then
    {
      inherit (common) schemaVersion;
      mode = "attribution";
      error = "could not locate baseline nixpkgs source (pkgs.path is unset on this target). Attribution requires a baseline to fold overlays against.";
    }
  else
    {
      inherit (common) schemaVersion;
      mode = "attribution";
      error = null;
      path = attrPath;
      overlayCount = builtins.length overlays;
      inherit
        overlayNames
        signatures
        diffs
        summary
        ;
    }
