# Multi-account Claude Code: a second "work" config dir that shares config with the
# live personal ~/.claude but authenticates separately.
#
# Auth separation is automatic on macOS: Claude derives the Keychain service name
# from sha256(CLAUDE_CONFIG_DIR), so ~/.claude and ~/.claude-work get independent
# credential slots. We only need to (a) share the non-auth config and (b) launch the
# CLI with CLAUDE_CONFIG_DIR pinned.
#
# Design notes:
#   * Personal (~/.claude) is the default account — bare `claude`, `c`, `ca`, and the
#     claude-* provider functions are untouched. Work gets explicit `cw` / `cwa`.
#   * .claude.json is NOT symlinked: it mixes shareable mcpServers with per-account
#     oauthAccount/projects. We propagate only mcpServers (+ onboarding) via activation.
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
  link = config.lib.file.mkOutOfStoreSymlink; # absolute string, live (see skills.nix header)
  homeDir = "/Users/${username}";
  personal = "${homeDir}/.claude";
  workRel = ".claude-work"; # relative to $HOME (home.file key contract)

  # Safe to share: read-mostly, or contain no auth. NOT here: .claude.json
  # (oauthAccount/projects) and history/sessions — those stay per-account.
  shared = [
    "settings.json" # env, hooks, statusLine, theme, effortLevel, enabledPlugins
    "keybindings.json"
    "CLAUDE.md"
    "statusline-command.sh"
    "skills" # dir (coexists with skills.nix-managed symlinks under it)
    "agents"
    "commands"
    "plugins"
  ];
in
{
  # Symlink each shared item from the work dir to the live personal copy.
  home.file = lib.listToAttrs (
    map (n: {
      name = "${workRel}/${n}";
      value.source = link "${personal}/${n}";
    }) shared
  );

  # cw / cwa: working account. Same flags as c / ca, but pin CLAUDE_CONFIG_DIR so the
  # CLI uses ~/.claude-work (its own Keychain slot). Applies to zsh + fish.
  home.shellAliases = {
    cw = "CLAUDE_CONFIG_DIR=${homeDir}/.claude-work CLAUDE_CODE_TMUX_TRUECOLOR=1 claude --dangerously-skip-permissions";
    cwa = "CLAUDE_CONFIG_DIR=${homeDir}/.claude-work CLAUDE_CODE_TMUX_TRUECOLOR=1 claude agents --permission-mode bypassPermissions";
  };

  # The work .claude.json holds its own oauthAccount/projects, so it can't be
  # symlinked. Propagate just the user-scoped mcpServers from the personal config
  # (single source of truth) and stamp onboarding so `cw` → /login skips the wizard.
  # Idempotent; touches only two keys. (Plain-command style matches codexCompletion.)
  home.activation.claudeWorkConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.claude-work"
    src="$HOME/.claude.json"; dst="$HOME/.claude-work/.claude.json"
    if [ -f "$src" ]; then
      if [ -f "$dst" ]; then
        ${pkgs.jq}/bin/jq --slurpfile p "$src" \
          '.mcpServers = ($p[0].mcpServers // {}) | .hasCompletedOnboarding = true' \
          "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"
      else
        ${pkgs.jq}/bin/jq -n --slurpfile p "$src" \
          '{hasCompletedOnboarding: true, mcpServers: ($p[0].mcpServers // {})}' > "$dst"
      fi
    fi
  '';
}
