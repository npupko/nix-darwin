# Claude Code → tmux status indicators.
# Shows ONE glyph per Claude pane in the tmux tab, in pane order, space-separated,
# using a five-state vocabulary (gruvbox-neutral palette):
#     · idle = gray #7c6f64 · ✻ thinking = orange #d65d0e · ⊘ approval = yellow #fabd2f
#     · ✓ done = green #98971a · ✗ error = red #cc241d
# The tab name keeps its accent(focused)/dim(rest) color; the glyphs carry the state
# colors. Driven by ~/.claude/settings.json hooks → ~/.local/bin/claude-tmux-status,
# which records per-pane state and rebuilds a per-window @claude_glyphs string.
#
# The GLYPH + COLOR for each state are defined here as @claude_glyph_<state> options
# so all the visuals live in one place; the hook script just maps a pane's state to
# the matching option and joins them. A styled string in a user option is inserted
# verbatim by #{@claude_glyphs} and its embedded #[fg=…] is drawn by the status
# renderer (tmux Formats: #{} expansion vs #[] styles are separate; no #{E:} needed).
#
# This owns the window/pane status FORMATS (they embed the theme accent, so it reads
# `theme`) and pushes them + the glyph options into the shared programs.tmux.extraConfig
# via lib.mkAfter — they are the sole setters of window-status-format /
# pane-border-format, so appending after the home.nix tmux theme block is safe.
#
# Disable it:
#   • instant, no rebuild:  touch ~/.claude/.tmux-status-off  (the hook script checks this)
#   • glyphs off, keep theme:  myConfig.claude.tmuxStatus.enable = false
#   • whole Claude feature:    myConfig.claude.enable = false
{
  config,
  lib,
  themes,
  themeName,
  ...
}:
let
  cfg = config.myConfig.claude;
  theme = themes.${themeName};

  # State palette (gruvbox neutral). Glyph + fg for each of the five states. These
  # become @claude_glyph_<state> options the hook script reads and joins per window.
  states = {
    idle = { glyph = "·"; fg = "#7c6f64"; };
    thinking = { glyph = "✻"; fg = "#d65d0e"; };
    approval = { glyph = "⊘"; fg = "#fabd2f"; };
    done = { glyph = "✓"; fg = "#98971a"; };
    error = { glyph = "✗"; fg = "#cc241d"; };
  };

  # `set -g @claude_glyph_<state> "#[fg=<fg>]<glyph>"` — the styled glyph the script
  # concatenates. The #[fg=…] is applied by the status renderer when #{@claude_glyphs}
  # is expanded into window-status-format.
  glyphOptions = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: s: ''set -g @claude_glyph_${name} "#[fg=${s.fg}]${s.glyph}"'') states
  );

  # Window tab format: appends the per-window glyph string (one glyph per Claude pane).
  # If @claude_glyphs is set, render #[nobold] + a leading space + the glyphs; the fg reset
  # back to the tab-name color (accent when focused, dim otherwise) is emitted AFTER the
  # conditional, then a trailing space.
  #
  # The reset MUST stay outside the #{?…} conditional. tmux's conditional parser splits its
  # branches on commas and does not skip commas inside #[…] style tokens, so an accent style
  # like #[fg=blue,bold] placed inside a branch is cut at its comma — mangling the branch and
  # dropping the trailing space on the focused tab only (its reset has a comma; the dim tab's
  # #[fg=brightblack] does not), which shifts the bar by a column when you switch tabs.
  # Falls back to the plain themed format when glyphs are disabled.
  windowFormats =
    if cfg.tmuxStatus.enable then
      ''
        ${glyphOptions}
        set -g window-status-format "#[fg=brightblack] #I:#W#{?#{@claude_glyphs},#[nobold] #{@claude_glyphs},}#[fg=brightblack] "
        set -g window-status-current-format "#[fg=${theme.tmux.accent},bold] #I:#W#{?#{@claude_glyphs},#[nobold] #{@claude_glyphs},}#[fg=${theme.tmux.accent},bold] "
      ''
    else
      ''
        set -g window-status-format "#[fg=brightblack] #I:#W "
        set -g window-status-current-format "#[fg=${theme.tmux.accent},bold] #I:#W "
      '';

  # Optional: per-pane label on the pane border, tinted from per-pane @claude_pane_status.
  paneBorders = lib.optionalString (cfg.tmuxStatus.enable && cfg.tmuxStatus.paneBorders) ''
    set -g pane-border-status top
    set -g pane-border-format "#{?#{==:#{@claude_pane_status},approval},#[fg=${states.approval.fg}] approval,#{?#{==:#{@claude_pane_status},done},#[fg=${states.done.fg}] done,#{?#{==:#{@claude_pane_status},thinking},#[fg=${states.thinking.fg}] thinking,#{?#{==:#{@claude_pane_status},error},#[fg=${states.error.fg}] error,#{?#{==:#{@claude_pane_status},idle},#[fg=${states.idle.fg}] idle,#[default]}}}}} #{pane_title}"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # Push the Claude status formats after the shared tmux theme block (lib.mkAfter).
    programs.tmux.extraConfig = lib.mkAfter (windowFormats + paneBorders);

    # The hook script that records per-pane state and rebuilds the window glyph string.
    home.file.".local/bin/claude-tmux-status" = {
      source = ../dotfiles/bin/claude-tmux-status;
      executable = true;
    };
  };
}
