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
    # Fish has no built-in gruvbox theme, so its syntax-highlighting palette is
    # spelled out as explicit hex here. Per user preference fish uses the softer
    # gruvbox-material palette (sainnhe/gruvbox-material), not classic gruvbox —
    # adopted verbatim from dmitriyb/dot config/themes/gruvbox/fish.theme:
    #   https://github.com/dmitriyb/dot/blob/HEAD/config/themes/gruvbox/fish.theme
    # Rendered into `set -g fish_color_*` by fishThemeInit in home.nix.
    fish.colors = {
      normal = "d4be98";
      command = "7daea3"; # teal
      keyword = "d3869b"; # purple
      quote = "d8a657"; # yellow
      redirection = "d4be98";
      end = "d65d0e"; # orange
      error = "ea6962"; # red
      param = "a9b665"; # green
      comment = "928374"; # gray
      operator = "89b482"; # aqua
      escape = "d3869b"; # purple
      autosuggestion = "928374"; # gray
      selection = "--background=3c3836";
      search_match = "--background=504945";
      cwd = "7daea3"; # teal
      user = "89b482"; # aqua
      host = "a9b665"; # green
      host_remote = "d8a657"; # yellow
      status = "ea6962"; # red
      cancel = "ea6962"; # red
      valid_path = "--underline";
    };
    fish.pager = {
      progress = "928374";
      prefix = "7daea3";
      completion = "d4be98";
      description = "928374";
      selected_background = "--background=3c3836";
      selected_prefix = "7daea3";
      selected_completion = "d4be98";
      selected_description = "928374";
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
    # See gruvbox-dark.fish above — gruvbox-material light, adopted verbatim from
    # jasonlong/dotfiles fish/themes/gruvbox_material_light.theme:
    #   https://github.com/jasonlong/dotfiles/blob/HEAD/fish/themes/gruvbox_material_light.theme
    fish.colors = {
      normal = "654735";
      command = "6c782e"; # green
      keyword = "945e80"; # purple
      quote = "4c7a5d"; # aqua
      redirection = "45707a"; # blue
      end = "c35e0a"; # orange
      error = "c14a4a"; # red
      param = "654735";
      comment = "928374"; # gray
      operator = "45707a"; # blue
      escape = "4c7a5d"; # aqua
      autosuggestion = "a89984"; # gray
      selection = "--background=ebdbb2 --foreground=654735";
      search_match = "--background=b47109 --foreground=fbf1c7";
      cwd = "b47109"; # yellow
      cwd_root = "c14a4a"; # red
      user = "4c7a5d"; # aqua
      host = "6c782e"; # green
      host_remote = "b47109"; # yellow
      status = "c14a4a"; # red
      cancel = "c14a4a"; # red
    };
    fish.pager = {
      progress = "fbf1c7 --background=6c782e";
      prefix = "6c782e --bold";
      completion = "654735";
      description = "928374";
      selected_background = "--background=ebdbb2";
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
