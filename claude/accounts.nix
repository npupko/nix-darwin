# Multi-account Claude Code: a second "work" config dir that shares EVERYTHING with
# the live personal ~/.claude except auth. Two accounts exist only to hold two logins;
# config and session state are one unified store.
#
# Auth separation is automatic on macOS: Claude derives the Keychain service name
# from sha256(CLAUDE_CONFIG_DIR), so ~/.claude and ~/.claude-work get independent
# credential slots. We only need to (a) share everything non-auth and (b) launch the
# CLI with CLAUDE_CONFIG_DIR pinned.
#
# Design notes:
#   * Personal (~/.claude) is the default account AND the canonical store — bare
#     `claude`, `c`, `ca`, and the claude-* provider functions are untouched. Work gets
#     explicit `cw` / `cwa` and symlinks its session state back to personal.
#   * .claude.json is NOT symlinked: it co-mingles shareable state (mcpServers,
#     projects, usage) with per-account identity (oauthAccount/userID). We propagate the
#     shareable slices personal->work via activation, preserving work's identity. That's
#     a one-way activation snapshot (no live symlink possible for a mixed-concern file).
#   * home.file + mkOutOfStoreSymlink (see skills.nix header) keeps links live and
#     self-pruning; home.backupFileExtension ("backup", flake.nix) covers any clobber.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  cfg = config.myConfig.claude;
  link = config.lib.file.mkOutOfStoreSymlink; # absolute string, live (see skills.nix header)
  homeDir = "/Users/${username}";
  personal = "${homeDir}/.claude";
  workRel = ".claude-work"; # relative to $HOME (home.file key contract)

  # Everything non-auth. Config is read-mostly. Session state is live read-write but
  # safe to share: transcripts/tasks/plans/file-history/sessions are per-session-id
  # files (one writer each, no clash). history.jsonl is append-shared — a small
  # corruption risk ONLY if `c` and `cw` append at the very same instant. NOT here:
  # .claude.json (identity; see activation) and ephemeral caches/locks/IDE sockets.
  shared = [
    # config
    "settings.json" # env, hooks, statusLine, theme, effortLevel, enabledPlugins
    "keybindings.json"
    "CLAUDE.md"
    "statusline-command.sh"
    "skills" # dir (coexists with skills.nix-managed symlinks under it)
    "agents"
    "commands"
    "plugins"
    # session state (unified store; personal ~/.claude is canonical)
    "projects" # session transcripts (drives --resume / --continue)
    "sessions" # session index/metadata
    "session-env" # per-session env snapshots
    "tasks" # background task state
    "plans" # plan-mode artifacts
    "file-history" # edit/undo history
    "shell-snapshots" # captured shell envs
    "history.jsonl" # prompt-bar history (append-shared; see note above)
  ];
in
{
  config = lib.mkIf cfg.enable {
    # Symlink each shared item from the work dir to the live personal copy.
    home.file = lib.listToAttrs (
      map (n: {
        name = "${workRel}/${n}";
        value.source = link "${personal}/${n}";
      }) shared
    );

    # All four subscription/OAuth launchers (DIRECT to Anthropic, never the gateway):
    #   c / ca   — personal account (~/.claude, the default + canonical store).
    #   cw / cwa — work account: same flags but pin CLAUDE_CONFIG_DIR to ~/.claude-work
    #              (its own Keychain slot; auth derives from sha256(CLAUDE_CONFIG_DIR)).
    # Applies to zsh + fish via home.shellAliases.
    home.shellAliases = {
      c = "CLAUDE_CODE_TMUX_TRUECOLOR=1 claude --dangerously-skip-permissions";
      ca = "CLAUDE_CODE_TMUX_TRUECOLOR=1 claude agents --permission-mode bypassPermissions";
      cw = "CLAUDE_CONFIG_DIR=${homeDir}/.claude-work CLAUDE_CODE_TMUX_TRUECOLOR=1 claude --dangerously-skip-permissions";
      cwa = "CLAUDE_CONFIG_DIR=${homeDir}/.claude-work CLAUDE_CODE_TMUX_TRUECOLOR=1 claude agents --permission-mode bypassPermissions";
    };

    # The work .claude.json holds its own oauthAccount/userID, so it can't be symlinked.
    # Propagate the shareable slices from the personal config (single source of truth) —
    # mcpServers, per-project metadata (trust/allowedTools), and usage stats — while
    # preserving work's identity, and stamp onboarding so `cw` → /login skips the wizard.
    # One-way snapshot: work-side edits to these keys reset to personal's on each rebuild
    # (personal is the daily driver). (Plain-command style matches codexCompletion.)
    home.activation.claudeWorkConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.claude-work"
      src="$HOME/.claude.json"; dst="$HOME/.claude-work/.claude.json"
      share='.mcpServers = ($p[0].mcpServers // {})
        | .projects = ($p[0].projects // {})
        | .skillUsage = ($p[0].skillUsage // {})
        | .pluginUsage = ($p[0].pluginUsage // {})
        | .tipsHistory = ($p[0].tipsHistory // {})
        | .hasCompletedOnboarding = true'
      if [ -f "$src" ]; then
        if [ -f "$dst" ]; then
          ${pkgs.jq}/bin/jq --slurpfile p "$src" "$share" \
            "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"
        else
          ${pkgs.jq}/bin/jq -n --slurpfile p "$src" "{} | $share" > "$dst"
        fi
      fi
    '';
  };
}
