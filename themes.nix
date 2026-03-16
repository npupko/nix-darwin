# Adding a new theme:
# 1. Copy any existing theme block below and update all fields:
#    - Per-tool names: look up each tool's built-in theme name
#      (e.g. ghostty uses "Gruvbox Dark", bat uses "gruvbox-dark")
#    - tmux.accent: a terminal color name (blue, cyan, magenta, etc.)
#    - starship: override branch/dirty; ok/err/duration inherit from defaultStarship
# 2. VERIFY each tool's theme name actually exists — names differ per tool!
#    - ghostty: ls /Applications/Ghostty.app/Contents/Resources/ghostty/themes/
#    - bat:     bat --list-themes
#    - delta:   delta --list-syntax-themes
#    - btop:    ls $(nix eval --raw nixpkgs#btop.outPath)/share/btop/themes/
#    - helix:   ls in helix runtime/themes/
#    - alacritty: ls $(nix eval --raw nixpkgs#alacritty-theme.outPath)/share/alacritty-theme/
#    - zellij:  https://zellij.dev/documentation/theme-list.html
# 3. Add a lazy.nvim plugin spec in ~/.config/nvim/lua/plugins/ui/colorscheme.lua
#    and add the colorscheme name to install.colorscheme in ~/.config/nvim/init.lua
# 4. That's it — theme-switch and flake.nix derive the available list automatically
let
  defaultStarship = {
    ok = "green";
    err = "red";
    duration = "yellow";
  };
in
{
  gruvbox-dark = {
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
  };

  gruvbox-light = {
    alacritty = "gruvbox_light";
    ghostty = "Gruvbox Light";
    bat = "gruvbox-light";
    delta = "gruvbox-light";
    btop = "gruvbox_light";
    zellij = "gruvbox-light";
    helix = "gruvbox_light";
    neovim = "gruvbox-light";
    tmux.accent = "yellow";
    starship = defaultStarship // {
      branch = "purple";
      dirty = "red";
    };
  };

  nord = {
    alacritty = "nord";
    ghostty = "Nord";
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
  };

  catppuccin-latte = {
    alacritty = "catppuccin_latte";
    ghostty = "Catppuccin Latte";
    bat = "Catppuccin Latte";
    delta = "Catppuccin Latte";
    btop = "flat-remix-light"; # btop has no catppuccin — closest light match
    zellij = "catppuccin-latte";
    helix = "catppuccin_latte";
    neovim = "catppuccin-latte";
    tmux.accent = "yellow";
    starship = defaultStarship // {
      branch = "magenta";
      dirty = "yellow";
    };
  };

  catppuccin-mocha = {
    alacritty = "catppuccin_mocha";
    ghostty = "Catppuccin Mocha";
    bat = "Catppuccin Mocha";
    delta = "Catppuccin Mocha";
    btop = "dracula"; # btop has no catppuccin — closest dark match
    zellij = "catppuccin-mocha";
    helix = "catppuccin_mocha";
    neovim = "catppuccin-mocha";
    tmux.accent = "magenta";
    starship = defaultStarship // {
      branch = "magenta";
      dirty = "yellow";
    };
  };
}
