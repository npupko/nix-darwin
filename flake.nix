{
  description = "nix-darwin configuration with Determinate Nix";

  inputs = {
    # nixos-unstable: rolling unstable channel. Hydra builds the full job set,
    # so cache hit rate is high. Bump to nixpkgs-26.05-darwin after May 2026
    # release if/when stability matters more than freshness.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pinned older nixpkgs for bitwarden-desktop only. On unstable, source-built
    # Electron on aarch64-darwin currently fails: compiler-rt-libc-18.1.8 source
    # is compiled against libcxx-21.1.6+apple-sdk-26.4 headers, where
    # std::__countl_zero changed → 11 errors in FuzzerFork.cpp. Rev daf6dc4
    # (25.05 channel, 2025-10-27) is the last lock state where this machine
    # built the package locally; the overlay in overlays.nix swaps just
    # bitwarden-desktop to come from here.
    #
    # Removal: when both upstream issues are fixed on nixos-unstable and a
    # plain `nix build .#darwinConfigurations.m1.config.system.build.toplevel`
    # no longer pulls compiler-rt-libc into the closure, delete this input
    # AND the matching overlay block in overlays.nix.
    #
    # Tracking:
    #   https://github.com/NixOS/nixpkgs/issues/500399  (electron-unwrapped)
    #   https://github.com/NixOS/nixpkgs/issues/348920  (bitwarden-desktop)
    nixpkgs-bitwarden.url = "github:NixOS/nixpkgs/daf6dc47aa4b44791372d6139ab7b25269184d55";

    # Pinned newer nixpkgs for terminal-notifier only. A hardening flag added to
    # nixpkgs' ld64 around 2026-06-29 makes cctools-binutils-darwin's classic
    # `ld` crash ("Trace/BPT trap: 5", exit 133) linking terminal-notifier on
    # aarch64-darwin (also broke starship/R/caffeine/gtk4/etc. in the same
    # window — NixOS/nixpkgs#536363). Fixed upstream in nixpkgs#541326 (forces
    # the link step onto lld), merged to master 2026-07-13 as commit
    # ca912fdb11d1cb083bfcdef0c0ba5c530b3ca784 — but nixos-unstable's branch
    # tip is still e7a3ca8 (2026-07-11, Hydra hasn't advanced the channel past
    # it yet), so the main `nixpkgs` input can't pick it up via a plain
    # `nix flake update`. Pin straight to the fix commit instead of
    # reimplementing the same patch locally; the overlay in overlays.nix swaps
    # just terminal-notifier to come from here.
    #
    # Removal: once the main `nixpkgs` input's nixos-unstable pin advances past
    # ca912fdb11d1cb083bfcdef0c0ba5c530b3ca784, delete this input AND the
    # matching overlay block in overlays.nix.
    #
    # Tracking:
    #   https://github.com/NixOS/nixpkgs/pull/536365  (ld64: disable hardening again — the real fix, unmerged)
    #   https://github.com/NixOS/nixpkgs/pull/541326  (terminal-notifier: fix darwin build)
    nixpkgs-terminal-notifier.url = "github:NixOS/nixpkgs/ca912fdb11d1cb083bfcdef0c0ba5c530b3ca784";

    nix-darwin = {
      # TEMPORARY: pointed at the PR #1819 fork branch, NOT upstream master.
      # Current nixpkgs' nixos-render-docs removed `--toc-depth`, but nix-darwin
      # master's manual builder (doc/manual/default.nix) still passes it, so
      # darwin-manual-html (and the darwin-uninstaller's nested system) hard-fails
      # on any rebuild. PR #1819 switches `--toc-depth`/`--chunk-toc-depth` ->
      # `--sidebar-depth`, which fixes both. It was open + mergeable but not merged
      # as of 2026-07-06, so we ride the branch to stay buildable while keeping
      # nixpkgs fresh (no pin-back, no local patch).
      # Pinned to the exact commit (not the branch) so a blanket `nix flake update`
      # can't pull a force-pushed change; verified diff vs upstream master = this
      # single one-line change and nothing else (ahead_by=1, one file, GPG-signed).
      # REVERT once #1819 merges: set url back to `github:nix-darwin/nix-darwin/master`
      # (or the merge commit) and `nix flake lock`.
      #   https://github.com/nix-darwin/nix-darwin/pull/1819
      #   https://github.com/nix-darwin/nix-darwin/issues/1817
      url = "github:p42software/nix-darwin/ebaac1f1e5cbb10ea5e9815bb1f69e53164f8b9b";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    try = {
      url = "github:tobi/try";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    let
      username = "random";
      system = "aarch64-darwin";
      hostname = "m1";
      themes = import ./themes.nix;
      themeName = "gruvbox-dark"; # ACTIVE_THEME
    in
    {
      darwinConfigurations.${hostname} = inputs.nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit inputs username;
        };
        modules = [
          # Determinate Nix module
          inputs.determinate.darwinModules.default

          # Custom Determinate Nix settings written to /etc/nix/nix.custom.conf.
          # Determinate's darwin module owns nix configuration; do NOT also set
          # nix.enable = false (redundant since 3.15.2). build-time-fetch-tree
          # and parallel-eval are default in Determinate 3.13+.
          {
            determinateNix.customSettings = {
              extra-substituters = [
                "https://nix-community.cachix.org"
                "https://devenv.cachix.org"
                # FlakeHub Cache — caches *our own* builds, so an unavoidable source
                # compile (e.g. a package not yet on cache.nixos.org at a fresh
                # aarch64-darwin nixpkgs pin) only happens once: re-runs and other
                # machines substitute it instead of recompiling. The Determinate
                # installer already lists this in trusted-substituters but NOT in the
                # queried `substituters` set, so nix never actually hit it — adding it
                # here turns it on.
                #
                # No keys needed here: the installer writes the full cache.flakehub.com
                # signing-key set (rotated/sharded, currently -3…-10) into
                # /etc/nix/nix.conf and keeps it current; nix trusts the union of all
                # config files, so duplicating them here would only rot on rotation.
                #
                # Requires auth (JWT, not anonymous): run `sudo determinate-nixd login`
                # once to write /nix/var/determinate/netrc, else builds emit cache
                # auth warnings.
                "https://cache.flakehub.com"
              ];
              extra-trusted-public-keys = [
                "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
              ];
              trusted-users = [
                "root"
                username
              ];
              # Allow mprocs to use pbcopy on macOS (for devenv).
              # Determinate Nix 3.21 doesn't register an `extra-` variant for this
              # setting (it warns "unknown setting"), so set the full list directly:
              # the darwin defaults plus pbcopy. Keep the defaults in sync if they
              # change — `nix config show allowed-impure-host-deps` prints the base set.
              allowed-impure-host-deps = [
                "/System/Library"
                "/bin/sh"
                "/dev"
                "/usr/lib"
                "/usr/bin/pbcopy"
              ];

              # Build parallelism — tuned for M1 Max, 10 cores, 32GB RAM.
              # max-jobs=4 fits 4 concurrent heavy builds (Rust/LLVM/Haskell
              # each spike to ~8GB). cores=0 lets each job use all 10 cores;
              # the kernel time-shares fairly, no contention concern.
              max-jobs = 4;
              cores = 0;
              auto-optimise-store = true;

              # Network — defaults (16/25) are conservative. Faster downloads
              # from cache.nixos.org/FlakeHub when bandwidth permits.
              max-substitution-jobs = 32;
              http-connections = 50;

              # Don't bail on first failed build — surface all errors per run.
              keep-going = true;
            };
          }

          # Main configuration
          ./configuration.nix

          # Home Manager module
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "backup";
              extraSpecialArgs = {
                inherit inputs username themes themeName;
              };
              users.${username} = import ./home.nix;
            };
          }
        ];
      };

      # Development shell with helper scripts
      devShells.${system}.default =
        let
          pkgs = import inputs.nixpkgs { inherit system; };
        in
        pkgs.mkShellNoCC {
          packages = with pkgs; [
            (writeShellApplication {
              name = "apply";
              runtimeInputs = [ inputs.nix-darwin.packages.${system}.darwin-rebuild ];
              text = ''
                sudo darwin-rebuild switch --flake .
              '';
            })
            sops
            ssh-to-age
            self.formatter.${system}
          ];
        };

      formatter.${system} = inputs.nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
    };
}
