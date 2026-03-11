{
  description = "nix-darwin configuration with Determinate Nix";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

    nix-darwin = {
      url = "https://flakehub.com/f/nix-darwin/nix-darwin/0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mise = {
      url = "github:jdx/mise";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    let
      username = "random";
      system = "aarch64-darwin";
      hostname = "m1";
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

          # Nix configuration for Determinate
          {
            # Let Determinate Nix handle Nix configuration
            nix.enable = false;

            # Custom Determinate Nix settings written to /etc/nix/nix.custom.conf
            determinateNix.customSettings = {
              # Enables parallel evaluation (set to 1 to disable)
              # eval-cores = 0;
              extra-experimental-features = [
                "build-time-fetch-tree" # Enables build-time flake inputs
                "parallel-eval" # Enables parallel evaluation
              ];
              extra-substituters = https://devenv.cachix.org;
              extra-trusted-public-keys = devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=;
              trusted-users = [
                "root"
                username
              ];
              # Allow mprocs to use pbcopy on macOS (for devenv)
              extra-allowed-impure-host-deps = "/usr/bin/pbcopy";
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
                inherit inputs username;
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
