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
      "zrok"
      "ollama"
      "glow"
      "PeonPing/tap/peon-ping"
      "terminal-notifier"

      # For QMK
      "clang-format"
      "dos2unix"
      "git"
      "hidapi"
      "libusb"
      "make"
      "zstd"
    ];
    casks = [
      "ghostty@tip"
      "docker-desktop"
    ];
  };
}
