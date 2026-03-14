{
  pkgs,
  username,
  ...
}:
{
  system.stateVersion = 5;
  system.primaryUser = username;
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  # Enable Touch ID for sudo (including inside tmux)
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;

  # Zsh shell (adds to /etc/shells)
  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # User configuration
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
    };
  };

  # System-level fonts
  fonts.packages = with pkgs; [
    jetbrains-mono
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    fira-code
    stix-two
    noto-fonts-symbols
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
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap"; # Remove unlisted packages
    };
    taps = [
      # "alvinunreal/tmuxai"
      "supabase/tap"
    ];
    brews = [
      "tmuxai"
      "jujutsu"
      "transmission"
      "libyaml"
      "supabase"
      "ollama"
      "glow"
    ];
    casks = [
      "ghostty@tip"
      "docker-desktop"
      "tailscale-app"
      "zed"
      "droid"
      "cursor-cli"
    ];
  };
}
