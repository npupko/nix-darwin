{
  pkgs,
  inputs,
  username,
  ...
}:
{
  system.stateVersion = 5;
  system.primaryUser = username;
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = import ./overlays.nix { inherit inputs; };

  # GC: Determinate handles automatically via disk-pressure heuristics
  # (target 30GB free, urgent <5%). Override via /etc/determinate/config.json
  # `garbageCollector.strategy`. Manual cleanup via `ngc` alias (home.nix).
  # Source: https://manual.determinate.systems/package-management/garbage-collection.html

  # Enable Touch ID for sudo (including inside tmux)
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;

  # Zsh shell (adds to /etc/shells). Disable the module's own compinit/prompt
  # init — home-manager already runs compinit at mkOrder 570 and we use
  # starship. The duplicate /etc/zshrc compinit alone costs ~2000ms per shell.
  # Kept as a fully-working fallback now that fish is the daily driver.
  programs.zsh = {
    enable = true;
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
  };

  # Fish shell, system level. Installs fish to /run/current-system/sw/bin and
  # wires nixpkgs vendor completions/functions (vendor_completions.d etc.) onto
  # fish's search path via pathsToLink. The per-user fish config lives in
  # home.nix (programs.fish). fish is NOT the login shell — zsh is, and it
  # execs fish for interactive sessions (home-manager#6568: fish-as-login-shell
  # breaks HM env/module init on macOS). So fish is intentionally NOT in
  # /etc/shells.
  programs.fish.enable = true;

  # zsh is the login shell (registered in /etc/shells so `chsh` accepts the
  # nix-managed zsh).
  environment.shells = [ pkgs.zsh ];

  # User configuration. NOTE: `shell` is a no-op on macOS (nix-darwin can't set
  # the login shell here); the real switch is `chsh`. zsh is the login shell.
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    shell = pkgs.zsh;
  };

  # Hostname
  networking.hostName = "m1";
  networking.computerName = "m1";

  # macOS system preferences
  system.defaults = {
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.4;
      tilesize = 48;
      magnification = false;
      show-recents = false;
      minimize-to-application = true;
      mru-spaces = false;
      orientation = "bottom";
      showhidden = true;
    };
    finder = {
      AppleShowAllExtensions = true;
      QuitMenuItem = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
      _FXSortFoldersFirst = true;
      FXDefaultSearchScope = "SCcf";
      FXPreferredViewStyle = "Nlsv";
      FXEnableExtensionChangeWarning = false;
    };
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleInterfaceStyleSwitchesAutomatically = true;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      "com.apple.swipescrolldirection" = true;
      AppleShowAllFiles = true;
      _HIHideMenuBar = false;
    };
    trackpad = {
      Clicking = false;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = false;
    };
    screencapture = {
      location = "/Users/random/Screenshots";
      type = "png";
      disable-shadow = true;
    };
    loginwindow.GuestEnabled = false;
    menuExtraClock.Show24Hour = true;
    CustomUserPreferences = {
      NSGlobalDomain.ApplePressAndHoldEnabled = false;
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      # Allow Nix store binaries (ad-hoc signed) to access the local network.
      # macOS Sequoia+ Local Network Privacy blocks them because tmux detaches
      # from the terminal (Ghostty), so macOS can't trace a "responsible code"
      # back to a signed app. Whitelisting the subnet bypasses the check.
      # See: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
      "com.apple.network.local-network" = {
        "Allowed Wi Fi Local Network Addresses" = [ "192.168.50.0/24" ];
        "Allowed Ethernet Local Network Addresses" = [ "192.168.50.0/24" ];
      };
    };
  };

  # System-level fonts
  fonts.packages = with pkgs; [
    jetbrains-mono
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    fira-code
    stix-two
    noto-fonts
  ];

  # Raise macOS file descriptor limits (default 256 is too low for Nix)
  launchd.daemons.limit-maxfiles = {
    serviceConfig = {
      Label = "limit.maxfiles";
      ProgramArguments = [
        "launchctl"
        "limit"
        "maxfiles"
        "65536"
        "524288"
      ];
      RunAtLoad = true;
    };
  };

  # Homebrew (managed by nix-darwin)
  homebrew = {
    enable = true;
    # Inject `eval "$(/opt/homebrew/bin/brew shellenv zsh)"` into /etc/zshrc so
    # brew + its bins land on PATH (also sets HOMEBREW_PREFIX, MANPATH, INFOPATH).
    # Restores the line that lived in a hand-written ~/.zprofile until home-manager
    # took over that file (backed up to ~/.zprofile.backup on 2026-03-18).
    enableZshIntegration = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap"; # Remove unlisted packages
      # Homebrew >=5.1.14 gates non-interactive `--cleanup` behind explicit
      # consent (--force/--force-cleanup/$HOMEBREW_ASK) after brew#22395 made
      # cleanup more destructive. Drop once nix-darwin#1774 lands.
      extraFlags = [ "--force-cleanup" ];
    };
    taps = [
      # "alvinunreal/tmuxai"
      "supabase/tap"
    ];
    brews = [
      "tmuxai"
      "jj"
      "transmission"
      "libyaml"
      "supabase"
      "ollama"
      "glow"
    ];
    casks = [
      "ghostty@tip"
      "docker-desktop"
      # "orbstack"
      "tailscale-app"
      "zed"
      "droid"
      "cursor-cli"
    ];
  };
}
