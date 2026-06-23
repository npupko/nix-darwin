# Generic harness-asset fan-out.
#
# Lifts the old skills.nix mechanism into a typed, reusable home-manager option,
# `myConfig.harnessAssets.<name>`. Each named instance has ONE live source dir
# (`src`) and a `targets` map of farm-key -> $HOME-relative dir; its `items` are
# fanned out into one out-of-store symlink per (item x selected target).
#
# Design notes (carried over from the original skills.nix):
#   * home.file (not an activation script): home-manager auto-prunes links it no
#     longer manages and is dry-run/build-correct. Activation scripts ignore
#     DRY_RUN under nix-darwin (hm#7344).
#   * mkOutOfStoreSymlink takes an ABSOLUTE STRING, never a `./path` literal or
#     `toString ./path` — a literal would copy the source into the nix store and
#     point the link at /nix/store instead of the live dir (hm#2660). The
#     strMatching "^/.*" type rejects relative `src` at eval; the live-source
#     guarantee itself lives here, in the consumer (mkOutOfStoreSymlink).
#   * Sources are NOT read with builtins.readDir (impure in flakes + store copy);
#     each instance enumerates its items explicitly.
{ config, lib, ... }:
let
  cfg = config.myConfig.harnessAssets;

  # One home.file entry per (asset x item x selected target).
  entriesFor =
    _assetName: a:
    lib.concatLists (
      lib.mapAttrsToList (
        itemName: item:
        map (t: {
          name = "${a.targets.${t}}/${itemName}";
          value.source = config.lib.file.mkOutOfStoreSymlink "${a.src}/${itemName}";
        }) (if item.to == null then lib.attrNames a.targets else item.to) # `to` null/absent => all targets
      ) a.items
    );
in
{
  imports = [ ./skills.nix ]; # data instances live beside the mechanism

  options.myConfig.harnessAssets = lib.mkOption {
    default = { };
    description = ''
      Named asset farms symlinked from one live source dir into the per-harness
      dirs that read them. Each instance fans out one out-of-store symlink per
      (item x selected target); source stays live-editable (out of the Nix store).
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          src = lib.mkOption {
            type = lib.types.strMatching "/.+"; # absolute STRING (hm#2660); out-of-store (match anchors fully)
            description = "Absolute path to the dir holding the item folders. Consumed via mkOutOfStoreSymlink; never interned into the store.";
            example = "/Users/random/Projects/npupko/skills";
          };
          targets = lib.mkOption {
            type = lib.types.attrsOf lib.types.str; # farm-key -> $HOME-relative dir (no ~, no leading /)
            description = ''Map of farm key to a $HOME-relative dir, e.g. { agents = ".agents/skills"; claude = ".claude/skills"; }.'';
          };
          items = lib.mkOption {
            default = { };
            description = "Item folder name -> options. Omit `to` to link into ALL targets.";
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  to = lib.mkOption {
                    type = lib.types.nullOr (lib.types.listOf lib.types.str);
                    default = null; # null = every target of this asset
                    description = "Farm keys (subset of this asset's `targets`) to link into; null = all.";
                  };
                  status = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null; # informational only; ignored by the fan-out
                    description = ''Human label (e.g. "experimental"); has no effect on linking.'';
                  };
                };
              }
            );
          };
        };
      }
    );
  };

  config = {
    # Fail fast if an item's `to` names a target the asset doesn't define.
    assertions = lib.concatLists (
      lib.mapAttrsToList (
        an: a:
        let
          targetKeys = lib.attrNames a.targets;
        in
        lib.mapAttrsToList (inm: item: {
          assertion = item.to == null || builtins.all (t: builtins.elem t targetKeys) item.to;
          message = "myConfig.harnessAssets.${an}.items.${inm}.to references a target not in .targets (have: ${lib.concatStringsSep ", " targetKeys}).";
        }) a.items
      ) cfg
    );

    home.file = lib.listToAttrs (lib.concatLists (lib.mapAttrsToList entriesFor cfg));
  };
}
