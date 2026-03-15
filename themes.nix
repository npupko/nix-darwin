# Adding a new theme:
# 1. Copy any existing theme block below and update all fields:
#    - Per-tool names: look up each tool's built-in theme name
#      (e.g. ghostty uses "Gruvbox Dark", bat uses "gruvbox-dark")
#    - tmux.accent: a terminal color name (blue, cyan, magenta, etc.)
#    - starship: override branch/dirty; ok/err/duration inherit from defaultStarship
#    - palette: 16 ANSI colors as hex values
# 2. Add a lazy.nvim plugin spec in ~/.config/nvim/lua/plugins/ui/colorscheme.lua
#    and add the colorscheme name to install.colorscheme in ~/.config/nvim/init.lua
# 3. That's it — theme-switch and flake.nix derive the available list automatically
let
  defaultStarship = {
    ok = "green";
    err = "red";
    duration = "yellow";
  };
in
{
  gruvbox-dark = {
    # Per-tool theme names
    alacritty = "gruvbox_dark";
    ghostty = "Gruvbox Dark";
    bat = "gruvbox-dark";
    delta = "gruvbox-dark";
    btop = "gruvbox_dark_v2";
    zellij = "gruvbox-dark";
    helix = "gruvbox";
    neovim = "gruvbox";
    tmux.accent = "blue";
    starship = defaultStarship // {
      branch = "purple";
      dirty = "red";
    };
    palette = {
      bg = "#282828";
      fg = "#ebdbb2";
      bg1 = "#3c3836";
      selection = "#504945";
      red = "#cc241d";
      green = "#98971a";
      yellow = "#d79921";
      blue = "#458588";
      magenta = "#b16286";
      cyan = "#689d6a";
      white = "#a89984";
      brblack = "#928374";
      brred = "#fb4934";
      brgreen = "#b8bb26";
      bryellow = "#fabd2f";
      brblue = "#83a598";
      brmagenta = "#d3869b";
      brcyan = "#8ec07c";
      brwhite = "#ebdbb2";
    };
  };

  nord = {
    alacritty = "nord";
    ghostty = "nord";
    bat = "Nord";
    delta = "Nord";
    btop = "nord";
    zellij = "nord";
    helix = "nord";
    neovim = "nord";
    tmux.accent = "cyan";
    starship = defaultStarship // {
      branch = "blue";
      dirty = "yellow";
    };
    palette = {
      bg = "#2e3440";
      fg = "#d8dee9";
      bg1 = "#3b4252";
      selection = "#434c5e";
      red = "#bf616a";
      green = "#a3be8c";
      yellow = "#ebcb8b";
      blue = "#5e81ac";
      magenta = "#b48ead";
      cyan = "#88c0d0";
      white = "#e5e9f0";
      brblack = "#4c566a";
      brred = "#bf616a";
      brgreen = "#a3be8c";
      bryellow = "#ebcb8b";
      brblue = "#81a1c1";
      brmagenta = "#b48ead";
      brcyan = "#8fbcbb";
      brwhite = "#eceff4";
    };
  };

  catppuccin-mocha = {
    alacritty = "catppuccin_mocha";
    ghostty = "catppuccin-mocha";
    bat = "Catppuccin Mocha";
    delta = "Catppuccin Mocha";
    btop = "catppuccin_mocha";
    zellij = "catppuccin-mocha";
    helix = "catppuccin_mocha";
    neovim = "catppuccin-mocha";
    tmux.accent = "magenta";
    starship = defaultStarship // {
      branch = "magenta";
      dirty = "yellow";
    };
    palette = {
      bg = "#1e1e2e";
      fg = "#cdd6f4";
      bg1 = "#313244";
      selection = "#45475a";
      red = "#f38ba8";
      green = "#a6e3a1";
      yellow = "#f9e2af";
      blue = "#89b4fa";
      magenta = "#cba6f7";
      cyan = "#94e2d5";
      white = "#bac2de";
      brblack = "#585b70";
      brred = "#f38ba8";
      brgreen = "#a6e3a1";
      bryellow = "#f9e2af";
      brblue = "#89b4fa";
      brmagenta = "#cba6f7";
      brcyan = "#94e2d5";
      brwhite = "#a6adc8";
    };
  };
}
