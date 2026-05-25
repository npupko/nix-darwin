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

  # zsh sigsuspend probe fails under autoconf 2.73 / clang gnu23 on macOS
  # Tahoe → falls back to racy pause() path → command substitutions hang
  # forever (visible as "tmux pane stuck with no prompt").
  # Tracking: NixOS/nixpkgs#513543. Master fix 19b2d2ac (2026-04-27).
  # Drop after backport lands on nixpkgs-25.11-darwin.
  (final: prev: {
    zsh = prev.zsh.overrideAttrs (old: {
      preConfigure = (old.preConfigure or "") + ''
        export zsh_cv_sys_sigsuspend=yes
      '';
    });
  })

  # ffmpeg-python checkPhase invokes `ffmpeg -version`; macOS Tahoe sandbox
  # kills the ad-hoc-signed nix-store binary with SIGKILL. Disable tests —
  # transitive dep of gftools → jetbrains-mono → fonts.
  # Drop when nixpkgs marks the test broken on darwin or the sandbox/codesign
  # interaction is fixed upstream.
  (final: prev: {
    python313 = prev.python313.override {
      packageOverrides = pyfinal: pyprev: {
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
]
