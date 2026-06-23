# Claude Code feature module. One cohesive, toggleable home-manager feature that
# owns EVERYTHING Claude-Code-specific, split into focused files:
#   * accounts.nix   — subscription/OAuth launchers (personal c/ca, work cw/cwa).
#                      DIRECT to Anthropic; never fronted by a gateway.
#   * providers.nix  — the LiteLLM gateway (`cl`) for API-key alt-providers + local Qwen.
#   * tmux.nix        — the Claude→tmux status-glyph integration (window/pane formats
#                      pushed into programs.tmux + the claude-tmux-status hook script).
#
# Subscription OAuth auth cannot pass through LiteLLM (litellm#13380) and no
# ANTHROPIC_API_KEY exists, so the subscription launchers stay direct (accounts.nix)
# and only the alt-providers go through the gateway (providers.nix).
#
# A single `myConfig.claude.enable` (default true) gates the whole feature; the
# submodules read it via `config.myConfig.claude`. `imports` stays unconditional —
# only `config` is gated — because branching `imports` on `config` is illegal.
{ lib, ... }:
{
  imports = [
    ./accounts.nix
    ./providers.nix
    ./tmux.nix
  ];

  options.myConfig.claude = {
    enable = lib.mkEnableOption "Claude Code integration (launchers, LiteLLM gateway, tmux status)" // {
      default = true;
    };

    tmuxStatus = {
      enable = lib.mkEnableOption "Claude Code → tmux status glyphs" // {
        default = true;
      };
      paneBorders = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Also render the Claude state glyph on the pane border (handy for `tdl` splits).";
      };
    };
  };
}
