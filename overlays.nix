# nixpkgs overlays. Each overlay is a workaround or local override; document
# the reason and removal condition so they can be dropped when no longer needed.
#
# Imported by configuration.nix as
#   nixpkgs.overlays = import ./overlays.nix { inherit inputs; };

{ inputs }:

[
  # a2a-sdk: litellm (claude/providers.nix) pulls a2a-sdk via its proxy extras.
  # a2a-sdk 0.3.26 is not cached on aarch64-darwin 26.05, so it builds from
  # source and its checkPhase fails: two e2e tests in
  # tests/e2e/push_notifications/ error with
  #   AttributeError: Can't get local object 'FastAPI.setup.<locals>.openapi'
  # — a FastAPI-internals incompatibility (821 pass, 2 error), not a real
  # regression. Disable checkPhase. Overriding the python313 set here is cheap:
  # verified via `darwin-rebuild build --dry-run` that only a2a-sdk and its
  # reverse-dep litellm rebuild (the fixed-point override does NOT mass-rebuild
  # the set on 26.05) — and litellm already builds from source anyway (its
  # streaming-firsttoken patch in claude/providers.nix busts its cache).
  #
  # Removal: drop once nixpkgs marks the e2e tests broken on darwin / bumps
  # a2a-sdk to a FastAPI-compatible release, or once a2a-sdk is cached.
  (final: prev: {
    python313 = prev.python313.override {
      packageOverrides = pyfinal: pyprev: {
        a2a-sdk = pyprev.a2a-sdk.overridePythonAttrs (_: { doCheck = false; });
      };
    };
  })

  # terminal-notifier: build from source (native aarch64) instead of nixpkgs'
  # 26.05 prebuilt, which unpacks the upstream x86_64-only release .zip and
  # trips macOS's "Support Ending for Intel-based Apps" warning under Rosetta.
  # See pkgs/terminal-notifier.nix for the full rationale. Tiny ObjC app → the
  # source build is seconds. Not a channel workaround: nixpkgs simply ships no
  # native aarch64 terminal-notifier.
  (final: prev: {
    terminal-notifier = final.callPackage ./pkgs/terminal-notifier.nix { };
  })

  # mise: install the official prebuilt release binary instead of compiling the
  # Rust source. nixpkgs' mise (and mise's own flake) build from source, and
  # aarch64-darwin mise is NOT in any binary cache (cache.nixos.org / nix-community
  # / FlakeHub all miss it), so a plain `pkgs.mise` means a multi-minute Rust
  # compile on every nixpkgs bump — and the darwin source build additionally fails
  # the OCI setuid test. This is the exact artifact `mise.run` / GitHub releases
  # ship: no compile, no cache dependency. Pinned to aarch64-darwin (this host).
  # Channel-independent: keep regardless of stable vs unstable nixpkgs.
  #
  # Updating is manual (mise self-update can't touch a read-only /nix/store
  # binary). Bump `miseVersion`, then get the new hash with:
  #   nix store prefetch-file --json \
  #     "https://github.com/jdx/mise/releases/download/vNEW/mise-vNEW-macos-arm64.tar.gz" \
  #     | jq -r .hash
  #
  # Removal: drop this overlay once aarch64-darwin mise is reliably cached and the
  # compile stops hurting.
  (final: prev:
    let
      miseVersion = "2026.7.0";
      miseHash = "sha256-I+/hgEbRK5WJXReyvwEBoO+5vxdHZ8V7biyNAZuWQlI=";
    in
    {
      mise = prev.stdenvNoCC.mkDerivation {
        pname = "mise";
        version = miseVersion;
        src = prev.fetchurl {
          url = "https://github.com/jdx/mise/releases/download/v${miseVersion}/mise-v${miseVersion}-macos-arm64.tar.gz";
          hash = miseHash;
        };
        # Prebuilt Mach-O binary — nothing to configure or build. The tarball
        # unpacks to a single `mise/` dir (auto-detected sourceRoot).
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -R bin man share $out/
          runHook postInstall
        '';
        meta = prev.mise.meta // { mainProgram = "mise"; };
      };
    })
]
