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

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
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
              ];
              extra-trusted-public-keys = [
                "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
              ];
              trusted-users = [
                "root"
                username
              ];
              # Allow mprocs to use pbcopy on macOS (for devenv)
              extra-allowed-impure-host-deps = "/usr/bin/pbcopy";

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
