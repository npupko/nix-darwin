# Claude Code → tmux status indicators.
# Appends a state glyph to the tmux tab where a Claude Code hook fires, using the
# `claude agents` board palette:
#     ✻ working = coral #da7756 · ⊘ awaiting = amber #fbbf24 · ✓ done = green #16a34a
# Glyph only — no task title. The tab name keeps its accent(focused)/dim(rest)
# color; the glyph carries the state color. Driven by ~/.claude/settings.json
# hooks → ~/.local/bin/claude-tmux-status, which sets a per-window @claude_status
# (severity-merged across panes: awaiting > working > done).
#
# This owns the window/pane status FORMATS (they embed the theme accent, so it
# reads `theme`) and pushes them into the shared programs.tmux.extraConfig via
# lib.mkAfter — they are the sole setters of window-status-format /
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

  # Window tab format: appends a single state glyph per @claude_status — the glyph
  # carries the state color, the name keeps accent (focused) / dim (unfocused). No
  # task title. Falls back to the plain themed format when glyphs are disabled. Each
  # conditional branch is a comma-free #[fg=…] block, so tmux's style parser stays happy.
  windowFormats =
    if cfg.tmuxStatus.enable then
      ''
        set -g window-status-format "#[fg=brightblack] #I:#W#{?#{==:#{@claude_status},waiting}, #[fg=#fbbf24]⊘,#{?#{==:#{@claude_status},done}, #[fg=#16a34a]✓,#{?#{==:#{@claude_status},active}, #[fg=#da7756]✻,}}}#[fg=brightblack] "
        set -g window-status-current-format "#[fg=${theme.tmux.accent},bold] #I:#W#{?#{==:#{@claude_status},waiting}, #[fg=#fbbf24]⊘,#{?#{==:#{@claude_status},done}, #[fg=#16a34a]✓,#{?#{==:#{@claude_status},active}, #[fg=#da7756]✻,}}}#[fg=${theme.tmux.accent},bold] "
      ''
    else
      ''
        set -g window-status-format "#[fg=brightblack] #I:#W "
        set -g window-status-current-format "#[fg=${theme.tmux.accent},bold] #I:#W "
      '';

  # Optional: per-pane label on the pane border, tinted from per-pane @claude_pane_status.
  paneBorders = lib.optionalString (cfg.tmuxStatus.enable && cfg.tmuxStatus.paneBorders) ''
    set -g pane-border-status top
    set -g pane-border-format "#{?#{==:#{@claude_pane_status},waiting},#[fg=#fbbf24] awaiting,#{?#{==:#{@claude_pane_status},done},#[fg=#16a34a] done,#{?#{==:#{@claude_pane_status},active},#[fg=#da7756] working,#[default]}}} #{pane_title}"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # Push the Claude status formats after the shared tmux theme block (lib.mkAfter).
    programs.tmux.extraConfig = lib.mkAfter (windowFormats + paneBorders);

    # The hook script that severity-merges per-pane state into @claude_status.
    home.file.".local/bin/claude-tmux-status" = {
      source = ../dotfiles/bin/claude-tmux-status;
      executable = true;
    };
  };
}
