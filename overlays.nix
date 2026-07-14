# nixpkgs overlays. Each overlay is a workaround or local override; document
# the reason and removal condition so they can be dropped when no longer needed.
#
# Imported by configuration.nix as
#   nixpkgs.overlays = import ./overlays.nix { inherit inputs; };

{ inputs }:

[
  # bitwarden-desktop: source-built Electron on aarch64-darwin currently
  # breaks via compiler-rt-libc-18.1.8 against libcxx-21 in apple-sdk-26
  # (std::__countl_zero gone → FuzzerFork.cpp fails to compile). Serve from
  # the pinned `nixpkgs-bitwarden` flake input (last known-good rev, see the
  # comment on that input in flake.nix for the full diagnosis).
  #
  # Removal: delete this overlay block AND the `nixpkgs-bitwarden` input in
  # flake.nix once unstable's darwin stdenv chain is healthy again, then run
  # `nix flake lock` to drop the pin from flake.lock.
  #
  # Tracking:
  #   https://github.com/NixOS/nixpkgs/issues/500399  (electron-unwrapped)
  #   https://github.com/NixOS/nixpkgs/issues/348920  (bitwarden-desktop)
  (final: prev: {
    bitwarden-desktop = (import inputs.nixpkgs-bitwarden {
      system = prev.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    }).bitwarden-desktop;
  })

  # python313 package-set fixups for the gftools → jetbrains-mono → fonts tree.
  # Overriding the set busts the binary cache for every package in it, so these
  # all build (and run their checkPhase) locally rather than coming from
  # cache.nixos.org.
  #
  # Keep ALL python313 overrides in this single packageOverrides block: a second
  # `prev.python313.override { packageOverrides = ... }` overlay would replace
  # this argument rather than merge, silently dropping the other fixups.
  (final: prev: {
    python313 = prev.python313.override {
      packageOverrides = pyfinal: pyprev: {
        # ffmpeg-python checkPhase invokes `ffmpeg -version`; macOS Tahoe
        # sandbox kills the ad-hoc-signed nix-store binary with SIGKILL.
        # Drop when nixpkgs marks the test broken on darwin or the
        # sandbox/codesign interaction is fixed upstream.
        ffmpeg-python = pyprev.ffmpeg-python.overridePythonAttrs (_: {
          doCheck = false;
        });
      };
    };
  })

  # direnv `make test-fish` invokes fish; same Tahoe sandbox SIGKILL pattern.
  # Disable checkPhase to skip test-go/test-bash/test-fish/test-zsh entirely.
  (final: prev: {
    direnv = prev.direnv.overrideAttrs (_: {
      doCheck = false;
    });
  })

  # terminal-notifier: cctools-binutils-darwin's classic `ld` crashes with
  # "Trace/BPT trap: 5" (SIGTRAP, exit 133) linking the Ld step, on this
  # nixpkgs pin — a toolchain-wide aarch64-darwin regression (see the
  # `nixpkgs-terminal-notifier` input comment in flake.nix for the full
  # diagnosis and tracking links). Fixed upstream, but not yet on the
  # nixos-unstable channel this flake's main `nixpkgs` input follows — serve
  # from the pinned `nixpkgs-terminal-notifier` input (first known-good rev)
  # instead of re-deriving the same patch locally.
  #
  # Removal: delete this overlay block AND the `nixpkgs-terminal-notifier`
  # input in flake.nix once the main `nixpkgs` input's pin advances past the
  # fix commit, then run `nix flake lock` to drop the pin from flake.lock.
  (final: prev: {
    terminal-notifier = (import inputs.nixpkgs-terminal-notifier {
      system = prev.stdenv.hostPlatform.system;
    }).terminal-notifier;
  })

  # python314 (nixpkgs' current python3/python3Packages default — litellm's
  # by-name package.nix takes `python3Packages` directly, which all-packages.nix
  # aliases straight to `python314Packages = python314.pkgs`, NOT via `python3.pkgs`
  # — so this must override `python314`, not `python3`, to actually reach it)
  # package-set fixup: opentelemetry-exporter-otlp-proto-grpc's test suite
  # asserts a retry backoff completes in "1 second plus wiggle room" (assertAlmostEqual
  # within 1 decimal place). On this machine's build sandbox that occasionally
  # overshoots (~1.16s), failing the whole build nondeterministically. Timing
  # assertion, not a real regression — disable checkPhase.
  #
  # Keep ALL python314 overrides in this single packageOverrides block (same
  # merge-not-replace hazard as the python313 block above).
  #
  # Removal: drop once upstream loosens the timing tolerance or the test is
  # marked flaky on the platform.
  #   https://github.com/open-telemetry/opentelemetry-python/blob/main/exporter/opentelemetry-exporter-otlp-proto-grpc/tests/test_otlp_exporter_mixin.py
  (final: prev: {
    python314 = prev.python314.override {
      packageOverrides = pyfinal: pyprev: {
        # Also missing opentelemetry-sdk from its `dependencies`: the built
        # wheel's Requires-Dist trips pythonRuntimeDepsCheckHook once checkPhase
        # (above) no longer masks it by failing first. Add it back — no
        # circular dependency (opentelemetry-sdk only needs api/semconv/
        # typing-extensions).
        #
        # Removal: drop once nixpkgs' opentelemetry-exporter-otlp-proto-grpc
        # derivation lists opentelemetry-sdk in `dependencies` upstream.
        opentelemetry-exporter-otlp-proto-grpc = pyprev.opentelemetry-exporter-otlp-proto-grpc.overridePythonAttrs (old: {
          doCheck = false;
          dependencies = (old.dependencies or [ ]) ++ [ pyfinal.opentelemetry-sdk ];
        });
      };
    };
  })

  # mise: install the official prebuilt release binary instead of compiling the
  # Rust source. nixpkgs' mise (and mise's own flake) build from source, and
  # aarch64-darwin mise is NOT in any binary cache (cache.nixos.org / nix-community
  # / FlakeHub all miss it), so a plain `pkgs.mise` means a multi-minute Rust
  # compile on every nixpkgs bump — and the darwin source build additionally fails
  # the OCI setuid test. This is the exact artifact `mise.run` / GitHub releases
  # ship: no compile, no cache dependency. Pinned to aarch64-darwin (this host).
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
