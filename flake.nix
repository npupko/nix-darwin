{
  description = "nix-darwin configuration with Determinate Nix";

  inputs = {
    # nixpkgs-26.05-darwin: the stable macOS release branch, fully built by
    # Hydra for aarch64-darwin → near-total binary-cache hit rate (no local
    # source compiles for plumbing) and no periodic breakage from riding
    # master's tip. Fast-moving tools live in mise (home.nix) / Homebrew
    # (configuration.nix), so stable costs nothing in freshness for what Nix
    # manages here.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # nix-darwin now ships release branches that must match the nixpkgs release
    # (master = unstable/26.11, nix-darwin-YY.MM = nixpkgs-YY.MM-darwin). Using a
    # mismatched pair is a hard assert (eval-config.nix), not a warning — so track
    # nix-darwin-26.05 alongside nixpkgs-26.05-darwin. The old p42software fork
    # (for the --toc-depth manual-build break) is obsolete: fixed upstream and the
    # release branch carries the fix.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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
