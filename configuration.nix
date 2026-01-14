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

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # Fish shell (adds to /etc/shells)
  programs.fish.enable = true;
  environment.shells = [ pkgs.fish ];

  # User configuration
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
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
    ];
    casks = [
      "ghostty"
      "claude-code"
      "docker-desktop"
    ];
  };
}
