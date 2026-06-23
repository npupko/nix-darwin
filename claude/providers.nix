# Claude Code alt-provider gateway — replaces the 9 hand-duplicated per-shell
# `claude-*` wrapper functions (deepseek/xai/zai/qwen/fireworks/kimi/router/
# minimax) with ONE shell-agnostic dispatcher (`cg`) fronting a Nix-managed
# LiteLLM proxy. Single source of truth = the `backends` attrset below; the
# proxy config, the `cg` model map, and the tab-completions are all generated
# from it.
#
# Boundary (do NOT cross): the subscription launchers `c`/`ca`/`cw`/`cwa` use
# Anthropic OAuth, which LiteLLM cannot pass through (litellm#13380), and there
# is no ANTHROPIC_API_KEY in secrets. So those stay DIRECT to Anthropic and live
# in accounts.nix. This module only ever fronts API-key alt-providers + the LAN
# Qwen box. `cg` is a NEW command; it never shadows `c`.
#
# Lifecycle is manual (Q1): the proxy is only useful when the LAN GPU box is
# powered on, which the user does deliberately. A dormant launchd agent
# (RunAtLoad=false, KeepAlive=false) is driven by `litellm-up`/`-down`/`-status`
# — the Nix-idiomatic equivalent of `brew services`, surviving terminal close.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  cfg = config.myConfig.claude;
  homeDir = "/Users/${username}";
  host = "127.0.0.1";
  port = 4000;
  label = "org.nix-community.home.litellm"; # home-manager launchd agent label
  svc = "gui/$(id -u)/${label}"; # launchctl service target ($(id -u) is shell-eval)

  # ── SINGLE SOURCE OF TRUTH ────────────────────────────────────────────────
  # Each backend's attr name IS its LiteLLM model_name and the value `cg` puts in
  # ANTHROPIC_MODEL (the primary slot) — so it's never restated. The fields:
  #   litellm    — the proxy's model_list entry (how LiteLLM reaches the backend).
  #   model_info — optional LiteLLM metadata (e.g. context cap).
  #   aliases    — the `cg <alias>` names that select this backend.
  #   smallFast  — value for ANTHROPIC_SMALL_FAST_MODEL (background: titles,
  #                summaries, auto-compaction).
  #
  # cheapFast: a cheap always-available CLOUD model for background tasks, routed
  # through the openrouter/* catch-all so it never touches the single LAN GPU
  # (which cold-swaps profiles and serves one request at a time). Adjust to taste.
  cheapFast = "openrouter/google/gemini-2.5-flash";

  backends = {
    "local-qwen" = {
      # LAN llama-swap/llama.cpp box, OpenAI-compatible at /v1, no auth (LAN-only,
      # so api_key is a non-empty dummy). `qwen3.6-27b` is a llama-swap alias →
      # the q4-mtp-96k profile (UD-Q4_K_XL + MTP speculative decode, 96K ctx).
      litellm = {
        model = "openai/qwen3.6-27b";
        api_base = "http://192.168.50.60:8080/v1";
        api_key = "dummy";
      };
      model_info.max_input_tokens = 98304; # 96K context cap
      aliases = [
        "qwen"
        "local-qwen"
      ];
      smallFast = cheapFast; # background → cloud, never the GPU (Q7b)
    };

    "kimi" = {
      # Moonshot/Kimi coding endpoint is Anthropic-format (same as the old
      # claude-kimi function's ANTHROPIC_BASE_URL=https://api.kimi.com/coding/),
      # so configure it as a LiteLLM `anthropic/` provider — LiteLLM then speaks
      # the Anthropic protocol to it and appends /v1/messages to api_base.
      litellm = {
        model = "anthropic/kimi-for-coding";
        api_base = "https://api.kimi.com/coding";
        api_key = "os.environ/KIMI_API_KEY";
      };
      aliases = [ "kimi" ];
      smallFast = "kimi";
    };
  };

  # The backend `cg` selects with no argument. Declared here (not hardcoded in the
  # dispatcher) so the default stays a single fact in the source of truth; its
  # value is an attr key of `backends`, so a bad name fails the build.
  defaultBackend = "kimi";

  # OpenRouter catch-all: one wildcard so `cg openrouter/<vendor>/<model>` passes
  # straight through on the single OPENROUTER_API_KEY. Covers the long tail
  # (deepseek, grok, GLM, minimax, …) the old per-provider wrappers hand-wired.
  openrouterWildcard = {
    model_name = "openrouter/*";
    litellm_params = {
      model = "openrouter/*";
      api_key = "os.environ/OPENROUTER_API_KEY";
    };
  };

  # ── LiteLLM config.yaml (pure store file; os.environ/ placeholders ONLY) ────
  # The store is world-readable, so no literal secrets ever land here — LiteLLM
  # resolves os.environ/VAR at runtime from the sourced litellm.env (§ wrapper).
  configData = {
    model_list =
      (lib.mapAttrsToList (
        name: b:
        {
          model_name = name;
          litellm_params = b.litellm;
        }
        // (lib.optionalAttrs (b ? model_info) { inherit (b) model_info; })
      ) backends)
      ++ [ openrouterWildcard ];
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
    };
    litellm_settings = {
      drop_params = true; # tolerate provider param mismatches; NO fallbacks → fail-fast (Q7)
    };
  };
  configFile = (pkgs.formats.yaml { }).generate "litellm-config.yaml" configData;

  # ── Start wrapper: source the sops env, then exec litellm (Q5) ──────────────
  # launchd has no EnvironmentFile (unlike systemd), and secrets must never sit
  # in the plist (world-readable store). So the agent runs this wrapper, which
  # sources the sops-rendered litellm.env and exec's the proxy. The env is
  # dedicated/least-privilege (only LiteLLM's 3 keys) so a daemon env-dump can't
  # leak the user's ~47 other secrets.
  litellmEnv = config.sops.templates."litellm.env".path;
  startScript = pkgs.writeShellScript "litellm-start" ''
    set -a
    . ${litellmEnv}
    set +a
    exec ${lib.getExe pkgs.litellm} --config ${configFile} --host ${host} --port ${toString port}
  '';

  # ── cg dispatcher (one shell-agnostic executable) ───────────────────────────
  # `cg [model] [claude args…]` points Claude Code at the gateway and maps the
  # chosen backend onto Claude Code's primary + small/fast model slots. The case
  # arms are generated from `backends` so adding a backend updates `cg` for free.
  # One case arm per backend; its aliases share the arm via `pat1|pat2)`. The
  # model name is the attr key (`name`), so it's not stored on the backend.
  aliasArms = lib.concatStrings (
    lib.mapAttrsToList (name: b: ''
      ${lib.concatStringsSep "|" b.aliases}) M=${lib.escapeShellArg name}; SF=${lib.escapeShellArg b.smallFast} ;;
    '') backends
  );

  cgScript = pkgs.writeShellApplication {
    name = "cg";
    text = ''
      # cg [model] [extra claude args...]
      model="''${1:-}"; [ "$#" -gt 0 ] && shift || true

      export CLAUDE_CODE_TMUX_TRUECOLOR=1
      export ANTHROPIC_BASE_URL="http://${host}:${toString port}"
      export ANTHROPIC_AUTH_TOKEN="''${LITELLM_MASTER_KEY:?cg: LITELLM_MASTER_KEY not in env (interactive sops api-keys not sourced?)}"
      export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1

      case "$model" in
        ""|default) M=${lib.escapeShellArg defaultBackend}; SF=${
          lib.escapeShellArg backends.${defaultBackend}.smallFast
        } ;;
        ${aliasArms}*) M="$model"; SF="$model" ;;   # pass-through, e.g. openrouter/deepseek/deepseek-chat
      esac
      export ANTHROPIC_MODEL="$M"
      export ANTHROPIC_SMALL_FAST_MODEL="$SF"

      exec claude --dangerously-skip-permissions "$@"
    '';
  };

  # ── litellm-up / -down / -status (drive the dormant launchd agent) ──────────
  # up:     kickstart -k (start, or kill+restart if already up) — fresh boot.
  # down:   kill TERM (NOT bootout) so the agent stays bootstrapped and kickstart
  #         works again; KeepAlive=false means a manual stop stays stopped.
  # status: print the bootstrapped service's state/pid.
  litellmUp = pkgs.writeShellApplication {
    name = "litellm-up";
    text = ''
      launchctl kickstart -k "${svc}"
      printf 'litellm: starting on ${host}:${toString port} (logs: ~/Library/Logs/litellm.log)\n'
    '';
  };
  litellmDown = pkgs.writeShellApplication {
    name = "litellm-down";
    text = ''
      launchctl kill TERM "${svc}" 2>/dev/null || true
      printf 'litellm: stopped\n'
    '';
  };
  litellmStatus = pkgs.writeShellApplication {
    name = "litellm-status";
    text = ''
      launchctl print "${svc}" 2>/dev/null | grep -E "state =|pid =" || echo "litellm: not running"
    '';
  };

  # ── Completion model-name list (single source: the same attrset) ────────────
  complNames = [
    "default"
  ]
  ++ lib.concatLists (lib.mapAttrsToList (_: b: b.aliases) backends)
  ++ [ "openrouter/" ];
  complStr = lib.concatStringsSep " " complNames;
in
{
  config = lib.mkIf cfg.enable {
    # 1) sops: dedicated least-privilege env + the master key secret. Declaring the
    #    secret here auto-includes it in home.nix's api-keys.env/.fish templates
    #    (they iterate lib.attrNames config.sops.secrets), so interactive shells
    #    export LITELLM_MASTER_KEY → `cg` finds it. litellm.env is daemon-only.
    sops.secrets.LITELLM_MASTER_KEY = { }; # value lives in secrets.yaml (added via `ds`)
    sops.templates."litellm.env".content = ''
      export KIMI_API_KEY='${config.sops.placeholder.KIMI_API_KEY}'
      export OPENROUTER_API_KEY='${config.sops.placeholder.OPENROUTER_API_KEY}'
      export LITELLM_MASTER_KEY='${config.sops.placeholder.LITELLM_MASTER_KEY}'
    '';

    # 2) Executables on PATH (shell-agnostic — both fish and zsh get them for free).
    home.packages = [
      cgScript
      litellmUp
      litellmDown
      litellmStatus
    ];

    # 3) Dormant launchd agent (manual control via litellm-up/-down).
    launchd.agents.litellm = {
      enable = true;
      config = {
        ProgramArguments = [ "${startScript}" ];
        RunAtLoad = false; # never auto-start (only useful when the GPU box is on)
        KeepAlive = false; # a manual `litellm-down` stays down
        ProcessType = "Background";
        StandardOutPath = "${homeDir}/Library/Logs/litellm.log";
        StandardErrorPath = "${homeDir}/Library/Logs/litellm.log";
        # launchd agents get a bare PATH; give the wrapper a sane one (mirrors the
        # repo's sops-agent environment.PATH fix) in case litellm shells out.
        EnvironmentVariables.PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };

    # 4) Tab-completions for `cg`, generated from complNames (single source).
    #    fish: a completions file (autoloaded lazily on first `cg <TAB>`).
    #    zsh:  a _cg function on the cache fpath (home.nix prepends it pre-compinit,
    #          mirroring the existing _codex completion).
    home.file.".config/fish/completions/cg.fish".text = ''
      complete -c cg -f -a "${complStr}"
    '';
    home.file.".cache/zsh/completions/_cg".text = ''
      #compdef cg
      compadd ${complStr}
    '';
  };
}
