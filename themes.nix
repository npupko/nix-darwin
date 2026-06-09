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
    # Fish has no built-in gruvbox theme (`fish_config theme list` ships nord,
    # catppuccin, etc. — but not gruvbox), so unlike every other tool above we
    # spell out the syntax-highlighting palette as explicit hex. Rendered into
    # `set -g fish_color_*` by fishThemeInit in home.nix. Gruvbox Dark (medium).
    fish.colors = {
      normal = "ebdbb2"; # fg1
      command = "b8bb26"; # bright green
      keyword = "fb4934"; # bright red
      quote = "fabd2f"; # bright yellow  (string literals)
      redirection = "8ec07c"; # bright aqua    (> >> |)
      end = "fe8019"; # bright orange  (; &)
      error = "fb4934"; # bright red
      param = "d5c4a1"; # fg2            (arguments)
      option = "8ec07c"; # bright aqua    (--flags)
      comment = "928374"; # gray
      operator = "d3869b"; # bright purple
      escape = "fe8019"; # bright orange
      autosuggestion = "7c6f64"; # bg4            (subdued)
      selection = "--background=504945";
      search_match = "--background=504945";
      cwd = "b8bb26"; # green
      cwd_root = "fb4934"; # red
      user = "b8bb26"; # green
      host = "83a598"; # bright blue
      host_remote = "8ec07c"; # bright aqua
      status = "fb4934"; # red            (nonzero exit)
      cancel = "fb4934"; # red
      gray = "928374";
      history_current = "--bold";
      valid_path = "--underline";
    };
    fish.pager = {
      progress = "665c54"; # bg3
      prefix = "d3869b --bold"; # purple
      completion = "ebdbb2"; # fg1
      description = "928374"; # gray
      selected_background = "--background=504945";
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
    # See gruvbox-dark.fish above. Gruvbox Light (medium) — faded/neutral hues
    # for legibility on the light background.
    fish.colors = {
      normal = "3c3836"; # fg1 (dark)
      command = "79740e"; # green
      keyword = "9d0006"; # red
      quote = "b57614"; # yellow
      redirection = "427b58"; # aqua
      end = "af3a03"; # orange
      error = "9d0006"; # red
      param = "504945"; # fg2 (dark)
      option = "427b58"; # aqua
      comment = "928374"; # gray
      operator = "8f3f71"; # purple
      escape = "af3a03"; # orange
      autosuggestion = "a89984"; # gray
      selection = "--background=d5c4a1";
      search_match = "--background=d5c4a1";
      cwd = "79740e"; # green
      cwd_root = "9d0006"; # red
      user = "79740e"; # green
      host = "076678"; # blue
      host_remote = "427b58"; # aqua
      status = "9d0006"; # red
      cancel = "9d0006"; # red
      gray = "928374";
      history_current = "--bold";
      valid_path = "--underline";
    };
    fish.pager = {
      progress = "bdae93"; # fg3
      prefix = "8f3f71 --bold"; # purple
      completion = "3c3836"; # fg1
      description = "928374"; # gray
      selected_background = "--background=d5c4a1";
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
