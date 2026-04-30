# nixpkgs overlays. Each overlay is a workaround or local override; document
# the reason and removal condition so they can be dropped when no longer needed.
#
# Imported by configuration.nix as
#   nixpkgs.overlays = import ./overlays.nix { inherit inputs; };
# `inputs` is unused today but keeping the parameter avoids churn when an
# overlay later needs a flake input (custom package from another flake, etc.).

{ inputs ? null }:

[
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
