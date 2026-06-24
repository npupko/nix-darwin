# Claude Code alt-provider gateway — a Nix-managed LiteLLM proxy fronted by ONE
# shell-agnostic dispatcher (`cg`). Architecture is two layers:
#
#   models   — the SINGLE SOURCE OF TRUTH: every model defined once (how LiteLLM
#              reaches it, context window, capabilities, picker label).
#   presets  — named session profiles that assign models to Claude Code's slots
#              (main / opus / sonnet / haiku / fable / background / subagent) plus
#              optional knobs (effort, flags, auto-mode, extraEnv). Every model is
#              ALSO a trivial preset, so `cg grok` works with no preset defined.
#
# `cg <name>` resolves: named preset → registry model → passthrough (anything with
# a `/`, e.g. openrouter/… or xai/…) → error. The cascade fills unset slots from
# `main`, EXCEPT `background` which defaults to a cheap cloud model. Nothing routes
# to the LAN box unless a preset names it — `cg qwen` is one option among many, not
# a hidden dependency.
#
# Boundary (do NOT cross): the subscription launchers `c`/`ca`/`cw`/`cwa` use
# Anthropic OAuth, which LiteLLM cannot pass through (litellm#13380), and there is
# no ANTHROPIC_API_KEY in secrets. Those stay DIRECT to Anthropic (accounts.nix).
# This module only fronts API-key alt-providers + the LAN Qwen box.
#
# Lifecycle is manual (Q1): a dormant launchd agent (RunAtLoad=false,
# KeepAlive=false) driven by `litellm-up`/`-down`/`-status` — `brew services` in
# Nix idiom, surviving terminal close. So after a reboot the proxy stays down until
# `litellm-up`; a Claude Code "ConnectionRefused" means the daemon isn't running.
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

  # cheapFast: the cheap always-available CLOUD model every preset's `background`
  # slot (titles, summaries, compaction) defaults to — routed through openrouter/*
  # so it never touches the single LAN GPU. Adjust to taste.
  cheapFast = "openrouter/google/gemini-2.5-flash";

  # ── MODELS REGISTRY (single source of truth) ──────────────────────────────
  # Each model defined ONCE. Fields:
  #   litellm — the LiteLLM model_list entry (how the proxy reaches the backend).
  #             Present ⇒ a dedicated model_list row whose model_name is the attr
  #             key (so ANTHROPIC_MODEL=<key> routes here). Absent ⇒ the model is
  #             reached via the openrouter/* wildcard and `id` IS the model_name
  #             Claude Code must send.
  #   id      — gateway model_name for wildcard-routed models (only when no litellm).
  #   ctx     — context window → LiteLLM model_info.max_input_tokens (so Claude Code
  #             discovery uses the right window instead of its 200K default).
  #   caps    — comma list Claude Code parses for ANTHROPIC_DEFAULT_<TIER>_SUPPORTED_
  #             CAPABILITIES (tool_use,vision,pdf,streaming,interleaved_thinking).
  #   label / desc — picker name + description, auto-derived into the _NAME/
  #             _DESCRIPTION env wherever the model lands in a slot.
  models = {
    kimi = {
      # Moonshot/Kimi coding endpoint is Anthropic-format → a LiteLLM anthropic/
      # provider (LiteLLM appends /v1/messages to api_base).
      litellm = {
        model = "anthropic/kimi-for-coding";
        api_base = "https://api.kimi.com/coding";
        api_key = "os.environ/KIMI_API_KEY";
      };
      ctx = 131072; # 128K — conservative; raise to Kimi's real cap
      caps = "tool_use,streaming";
      label = "Kimi · coding";
      desc = "Moonshot Kimi coding endpoint (Anthropic-native, cloud).";
    };

    grok = {
      # xAI direct: LiteLLM's native xai/ provider auto-targets https://api.x.ai/v1.
      litellm = {
        model = "xai/grok-code-fast-1";
        api_key = "os.environ/XAI_API_KEY";
      };
      ctx = 256000;
      caps = "tool_use,streaming";
      label = "Grok Code Fast · xAI";
      desc = "xAI grok-code-fast-1 via api.x.ai directly (cloud).";
    };

    qwen = {
      # LAN llama-swap/llama.cpp box, OpenAI-compatible at /v1, no auth (LAN-only,
      # api_key a non-empty dummy). NEEDS the GPU box powered on — `cg qwen` only.
      litellm = {
        model = "openai/qwen3.6-27b";
        api_base = "http://192.168.50.60:8080/v1";
        api_key = "dummy";
      };
      ctx = 98304; # 96K context cap (q4-mtp-96k profile)
      caps = "tool_use,streaming";
      label = "Qwen 3.6 27B · local";
      desc = "LAN GPU box (q4-mtp-96k); requires the box powered on.";
    };

    flash = {
      # Wildcard-routed: no dedicated LiteLLM row; `id` is the gateway model_name.
      # This is also the default `background` model (cheapFast).
      id = cheapFast;
      ctx = 1000000;
      caps = "tool_use,streaming";
      label = "Gemini 2.5 Flash";
      desc = "Cheap fast cloud model; the default background/small-fast model.";
    };
  };

  # ── CLAUDE CODE ENV VAR CATALOG (reference for future presets / extraEnv) ──
  # The model-routing & behaviour env the harness reads. [used] = already wired by
  # `cg`/presets; the rest are available knobs (add a preset field, or drop into a
  # preset's `extraEnv = { VAR = "…"; }`). Verified against the installed Claude
  # Code binary (v2.1.187). Keep this in sync when the cascade changes.
  #
  # ROUTING / AUTH
  #   ANTHROPIC_BASE_URL                 [used] point CC at the LiteLLM gateway.
  #   ANTHROPIC_AUTH_TOKEN               [used] bearer token = LITELLM_MASTER_KEY.
  #   ANTHROPIC_API_KEY                  alt auth (x-api-key header); not used here.
  #   CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY  [used] pull the gateway's /v1/models
  #                                      (id, display_name, max_input_tokens, caps)
  #                                      into the /model picker. Requires firstParty
  #                                      provider + a non-anthropic base URL — exactly
  #                                      our setup.
  #   CLAUDE_CODE_USE_GATEWAY            DO NOT SET. Inert here: the provider resolver
  #                                      never reads it. The real "gateway" provider is
  #                                      an enterprise OIDC/JWT login, not an env flag;
  #                                      setting this is a no-op (and would DISABLE the
  #                                      model discovery above if it ever took effect).
  #   _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL  force CC to treat the gateway as real
  #                                      api.anthropic.com (re-enables /feedback, some
  #                                      betas) — but DISABLES gateway model discovery
  #                                      (mutually exclusive). Niche.
  #   CLAUDE_GATEWAY_ALLOW_LOOPBACK / CLAUDE_GATEWAY_LOG_LEVEL  enterprise-gateway OIDC
  #                                      knobs; irrelevant to our base-URL approach.
  #
  # MAIN / TIER MODELS — the slots presets drive
  #   ANTHROPIC_MODEL                    [used] main model: a gateway model_name, or
  #                                      "opusplan" for the plan-vs-execute model split.
  #   ANTHROPIC_SMALL_FAST_MODEL         [used] background work: titles, summaries,
  #                                      auto-compaction (our `background` slot).
  #   ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL  [used] what each /model alias
  #                                      resolves to on the gateway.
  #   …_{NAME,DESCRIPTION,SUPPORTED_CAPABILITIES}  [used] picker label, blurb, and the
  #                                      capability list (comma values: tool_use, vision,
  #                                      pdf, streaming, interleaved_thinking). Take
  #                                      effect on gateways only, not direct anthropic.
  #   ANTHROPIC_CUSTOM_MODEL_OPTION{,_NAME,_DESCRIPTION,_SUPPORTED_CAPABILITIES}  add ONE
  #                                      extra named picker entry without touching the
  #                                      four aliases. Unused.
  #   CLAUDE_CODE_SUBAGENT_MODEL         [used] model for Task/Explore/Plan subagents.
  #                                      "inherit" = track the main model (our default).
  #
  # CONTEXT WINDOW
  #   (per model)  set LiteLLM model_info.max_input_tokens — the `ctx` field above.
  #                CC discovery reads it as the real context window (else it assumes
  #                200K for unknown models). This is the correct per-model lever.
  #   CLAUDE_CODE_MAX_CONTEXT_TOKENS     GLOBAL override, but ONLY honoured when auto-
  #                                      compaction is disabled — blunt; avoid.
  #   CLAUDE_CODE_DISABLE_1M_CONTEXT     kill all 1M-context paths. A model id that
  #                                      contains "[1m]" otherwise forces a 1M window
  #                                      (that is where the picker's "…-pro[1m]" comes
  #                                      from).
  #
  # AUTO MODE — default DISABLED; opt-in per preset
  #   CLAUDE_CODE_ENABLE_AUTO_MODE=1     [preset autoMode] turn auto mode on.
  #   CLAUDE_CODE_AUTO_MODE_MODEL        [preset autoModeModel] the auto-mode WORKER.
  #   CLAUDE_CODE_BG_CLASSIFIER_MODEL    [preset classifier] the SAFETY judge that auto-
  #                                      approves commands. Security boundary — keep it a
  #                                      capable, TRUSTED model; a weak/local model is
  #                                      easier to prompt-inject into approving something
  #                                      destructive.
  #   CLAUDE_CODE_AUTO_MODE_TEMPERATURE / _EXTERNAL_PERMISSIONS / _SIBLING_CONTEXT  finer
  #                                      auto-mode tuning (reach via extraEnv).
  #
  # EFFORT / THINKING
  #   CLAUDE_CODE_EFFORT_LEVEL           [preset effort] low|medium|high|xhigh|max|auto.
  #                                      High effort on a weak/cheap model is slow and
  #                                      wasteful — pin `low` for flash-tier drivers.
  #   CLAUDE_EFFORT                      also read; the global default lives in settings.
  #   MAX_THINKING_TOKENS                extended-thinking token budget.
  #   CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING / CLAUDE_CODE_DISABLE_THINKING  off switches.
  #
  # AUXILIARY MODEL SLOTS — cost levers (route to a cheap model via extraEnv)
  #   CLAUDE_CONTEXT_COLLAPSE_MODEL      model used for context collapse/compaction.
  #   CLAUDE_CONTEXT_COLLAPSE            toggle for the above.
  #
  # PERMISSIONS / BEHAVIOUR
  #   flags (preset)                     [used] claude CLI flags; default
  #                                      --dangerously-skip-permissions (starts in
  #                                      bypassPermissions). --permission-mode
  #                                      plan|acceptEdits|default also valid.
  #   CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1 disable the advisor — it is Anthropic-server-
  #                                      side only and cannot run through this gateway on
  #                                      non-Anthropic models, so it is safe to disable.
  #   NOTE: there is NO env/setting to drop "acceptEdits" from the shift+tab cycle;
  #         settings expose only disableBypassPermissionsMode and disableAutoMode.
  #
  # COST / LIMIT GUARDRAILS (via extraEnv)
  #   CLAUDE_CODE_MAX_OUTPUT_TOKENS, CLAUDE_CODE_MAX_TURNS, CLAUDE_CODE_MAX_RETRIES,
  #   CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC (drop background calls = cut spend).

  # ── PRESETS (named session profiles) ──────────────────────────────────────
  # A preset assigns models to slots and may set knobs. Slot/knob fields (all
  # optional except `main`):
  #   main       model alias (or a raw passthrough string, or "opusplan" if you
  #              really want it) → ANTHROPIC_MODEL.            [required]
  #   opus/sonnet/haiku/fable  model alias → that /model tier. [default: main]
  #   background model alias    → ANTHROPIC_SMALL_FAST_MODEL.  [default: cheapFast]
  #   subagent   model alias or "inherit" → CLAUDE_CODE_SUBAGENT_MODEL. [default: inherit]
  #   effort     low|medium|high|… → CLAUDE_CODE_EFFORT_LEVEL. [default: your global setting]
  #   flags      list of claude CLI flags.   [default: [ "--dangerously-skip-permissions" ]]
  #   autoMode   bool → CLAUDE_CODE_ENABLE_AUTO_MODE=1.        [default: false / disabled]
  #   autoModeModel  model alias → CLAUDE_CODE_AUTO_MODE_MODEL (auto-mode worker).
  #   classifier model alias → CLAUDE_CODE_BG_CLASSIFIER_MODEL (auto-mode SAFETY judge;
  #              keep this a capable, trusted model — it gates command auto-approval).
  #   extraEnv   attrset of VAR = "value" → exported verbatim (escape hatch).
  #   label/desc shown in `cg list` and tab-completion.
  #
  # Every model above is ALSO a trivial preset ({ main = <alias>; }), so you do not
  # restate single-model drivers here. Example multi-slot preset (uncomment/edit):
  #
  #   deep-think = {
  #     main = "grok"; opus = "kimi"; background = "flash";
  #     effort = "high"; subagent = "grok";
  #     label = "Grok drive · Kimi for /model opus";
  #     desc  = "Grok everywhere, Kimi available as the opus tier, high effort.";
  #   };
  #   autorun = {
  #     main = "grok"; autoMode = true; autoModeModel = "grok"; classifier = "kimi";
  #     label = "Grok auto-mode"; desc = "Auto-mode worker=grok, classifier=kimi.";
  #   };
  presets = { };

  # The preset `cg` selects with no argument (a model alias or a `presets` key).
  defaultPreset = "kimi";

  # OpenRouter catch-all: one wildcard so passthrough `cg openrouter/<vendor>/<model>`
  # works on the single OPENROUTER_API_KEY, and wildcard-routed registry models
  # (e.g. `flash`) resolve.
  openrouterWildcard = {
    model_name = "openrouter/*";
    litellm_params = {
      model = "openrouter/*";
      api_key = "os.environ/OPENROUTER_API_KEY";
    };
  };

  # ── resolution helpers ────────────────────────────────────────────────────
  # Resolve a model reference (a `models` alias, or a raw passthrough string) to
  # its gateway id + display metadata.
  resolveModel =
    ref:
    if models ? ${ref} then
      (
        let
          m = models.${ref};
        in
        {
          id = if m ? litellm then ref else m.id;
          caps = m.caps or "";
          label = m.label or ref;
          desc = m.desc or "";
        }
      )
    else
      {
        id = ref;
        caps = "";
        label = ref;
        desc = "passthrough";
      };

  # The four ANTHROPIC_DEFAULT_<TIER>_MODEL{,_NAME,_DESCRIPTION,_SUPPORTED_CAPABILITIES}
  # exports for one alias tier.
  tierExports =
    tier: ref:
    let
      r = resolveModel ref;
      T = lib.toUpper tier;
    in
    "export ANTHROPIC_DEFAULT_${T}_MODEL=${lib.escapeShellArg r.id}\n"
    + "export ANTHROPIC_DEFAULT_${T}_MODEL_NAME=${lib.escapeShellArg r.label}\n"
    + "export ANTHROPIC_DEFAULT_${T}_MODEL_DESCRIPTION=${lib.escapeShellArg r.desc}\n"
    + "export ANTHROPIC_DEFAULT_${T}_MODEL_SUPPORTED_CAPABILITIES=${lib.escapeShellArg r.caps}\n";

  # Expand a (partial) preset into the full block of shell exports — the cascade.
  presetBody =
    name: p:
    let
      mainRef = p.main;
      bgRef = p.background or cheapFast;
      subagent = p.subagent or "inherit";
      subagentId = if subagent == "inherit" then "inherit" else (resolveModel subagent).id;
      effort = p.effort or null;
      flagsList = p.flags or [ "--dangerously-skip-permissions" ];
      autoMode = p.autoMode or false;
      extraEnv = p.extraEnv or { };
    in
    "export ANTHROPIC_MODEL=${lib.escapeShellArg (resolveModel mainRef).id}\n"
    + tierExports "opus" (p.opus or mainRef)
    + tierExports "sonnet" (p.sonnet or mainRef)
    + tierExports "haiku" (p.haiku or mainRef)
    + tierExports "fable" (p.fable or mainRef)
    + "export ANTHROPIC_SMALL_FAST_MODEL=${lib.escapeShellArg (resolveModel bgRef).id}\n"
    + "export CLAUDE_CODE_SUBAGENT_MODEL=${lib.escapeShellArg subagentId}\n"
    + lib.optionalString (
      effort != null
    ) "export CLAUDE_CODE_EFFORT_LEVEL=${lib.escapeShellArg effort}\n"
    + lib.optionalString autoMode (
      "export CLAUDE_CODE_ENABLE_AUTO_MODE=1\n"
      + lib.optionalString (
        p ? autoModeModel
      ) "export CLAUDE_CODE_AUTO_MODE_MODEL=${lib.escapeShellArg (resolveModel p.autoModeModel).id}\n"
      + lib.optionalString (
        p ? classifier
      ) "export CLAUDE_CODE_BG_CLASSIFIER_MODEL=${lib.escapeShellArg (resolveModel p.classifier).id}\n"
    )
    + lib.concatStrings (
      lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") extraEnv
    )
    + "export CG_PRESET=${lib.escapeShellArg name}\n"
    + "FLAGS=(${lib.concatMapStringsSep " " lib.escapeShellArg flagsList})\n";

  # Every model is a trivial preset; named presets add multi-slot ones. A name in
  # BOTH is a build error (matches the repo's "bad name fails the build" ethos).
  modelPresets = lib.mapAttrs (n: _: { main = n; }) models;
  collisions = lib.intersectLists (lib.attrNames models) (lib.attrNames presets);
  allPresets =
    assert lib.assertMsg (
      collisions == [ ]
    ) "cg: preset/model name collision: ${lib.concatStringsSep ", " collisions}";
    modelPresets // presets;

  # One case arm per resolvable target.
  presetArms = lib.concatStrings (
    lib.mapAttrsToList (name: p: "  ${name})\n" + presetBody name p + "    ;;\n") allPresets
  );

  # `cg list` body + tab-completion entries (presets first, then models, then list).
  complEntries =
    (lib.mapAttrsToList (n: p: {
      name = n;
      desc = p.desc or (p.label or "preset");
    }) presets)
    ++ (lib.mapAttrsToList (n: m: {
      name = n;
      desc = m.label or n;
    }) models)
    ++ [
      {
        name = "list";
        desc = "list presets and models";
      }
    ];
  listText =
    "cg targets  (ANTHROPIC_BASE_URL → LiteLLM gateway on ${host}:${toString port})\n\n"
    + "Presets:\n"
    + (
      if presets == { } then
        "  (none defined — add to the presets attrset in claude/providers.nix)\n"
      else
        lib.concatStrings (
          lib.mapAttrsToList (n: p: "  ${n}  —  ${p.desc or (p.label or "preset")}\n") presets
        )
    )
    + "\nModels (each is also a cg target):\n"
    + lib.concatStrings (lib.mapAttrsToList (n: m: "  ${n}  —  ${m.label or n}\n") models)
    + "\nPassthrough:  cg openrouter/<vendor>/<model>   |   cg xai/<model>\n";

  # ── LiteLLM config.yaml (pure store file; os.environ/ placeholders ONLY) ────
  configData = {
    model_list =
      (lib.filter (x: x != null) (
        lib.mapAttrsToList (
          name: m:
          if m ? litellm then
            {
              model_name = name;
              litellm_params = m.litellm;
            }
            // (lib.optionalAttrs (m ? ctx) { model_info.max_input_tokens = m.ctx; })
          else
            null
        ) models
      ))
      ++ [ openrouterWildcard ];
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
    };
    litellm_settings = {
      drop_params = true; # tolerate provider param mismatches; NO fallbacks → fail-fast (Q7)
    };
  };
  configFile = (pkgs.formats.yaml { }).generate "litellm-config.yaml" configData;

  # ── Start wrapper: source the sops env, then exec litellm ───────────────────
  litellmEnv = config.sops.templates."litellm.env".path;
  startScript = pkgs.writeShellScript "litellm-start" ''
    set -a
    . ${litellmEnv}
    set +a
    exec ${lib.getExe pkgs.litellm} --config ${configFile} --host ${host} --port ${toString port}
  '';

  # ── cg dispatcher ───────────────────────────────────────────────────────────
  cgScript = pkgs.writeShellApplication {
    name = "cg";
    text = ''
      # cg [preset|model|passthrough|list] [extra claude args...]
      target="''${1:-}"; [ "$#" -gt 0 ] && shift || true

      export CLAUDE_CODE_TMUX_TRUECOLOR=1
      export ANTHROPIC_BASE_URL="http://${host}:${toString port}"
      export ANTHROPIC_AUTH_TOKEN="''${LITELLM_MASTER_KEY:?cg: LITELLM_MASTER_KEY not in env (interactive sops api-keys not sourced?)}"
      export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1

      case "$target" in
        list|-l|--list) printf '%s' ${lib.escapeShellArg listText}; exit 0 ;;
        ""|default) target=${lib.escapeShellArg defaultPreset} ;;
      esac

      FLAGS=(--dangerously-skip-permissions)

      case "$target" in
      ${presetArms}  */*)
          # passthrough: a raw gateway model name (openrouter/…, xai/…). No metadata.
          export ANTHROPIC_MODEL="$target"
          export ANTHROPIC_DEFAULT_OPUS_MODEL="$target"
          export ANTHROPIC_DEFAULT_SONNET_MODEL="$target"
          export ANTHROPIC_DEFAULT_HAIKU_MODEL="$target"
          export ANTHROPIC_DEFAULT_FABLE_MODEL="$target"
          export ANTHROPIC_SMALL_FAST_MODEL=${lib.escapeShellArg cheapFast}
          export CLAUDE_CODE_SUBAGENT_MODEL=inherit
          export CG_PRESET="passthrough"
          ;;
        *) printf 'cg: unknown target %s — try: cg list\n' "$target" >&2; exit 1 ;;
      esac

      exec claude "''${FLAGS[@]}" "$@"
    '';
  };

  # ── litellm-up / -down / -status (drive the dormant launchd agent) ──────────
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

  # ── Tab completions (single source: complEntries, with descriptions) ────────
  fishCompletion = lib.concatMapStrings (
    e: "complete -c cg -f -a ${lib.escapeShellArg e.name} -d ${lib.escapeShellArg e.desc}\n"
  ) complEntries;
  zshCompletion = ''
    #compdef cg
    local -a _cg_targets
    _cg_targets=(
    ${lib.concatMapStrings (
      e: "  ${lib.escapeShellArg "${e.name}:${lib.replaceStrings [ ":" ] [ "\\:" ] e.desc}"}\n"
    ) complEntries}
    )
    _describe -t targets 'cg target' _cg_targets
  '';
in
{
  config = lib.mkIf cfg.enable {
    # 1) sops: dedicated least-privilege daemon env + the master key secret.
    #    KIMI/XAI/OPENROUTER are declared in home.nix (their placeholders resolve
    #    here); LITELLM_MASTER_KEY is declared below so it auto-joins home.nix's
    #    interactive api-keys templates → `cg` finds it.
    sops.secrets.LITELLM_MASTER_KEY = { }; # value lives in secrets.yaml (added via `ds`)
    sops.templates."litellm.env".content = ''
      export KIMI_API_KEY='${config.sops.placeholder.KIMI_API_KEY}'
      export XAI_API_KEY='${config.sops.placeholder.XAI_API_KEY}'
      export OPENROUTER_API_KEY='${config.sops.placeholder.OPENROUTER_API_KEY}'
      export LITELLM_MASTER_KEY='${config.sops.placeholder.LITELLM_MASTER_KEY}'
    '';

    # 2) Executables on PATH (shell-agnostic).
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
        EnvironmentVariables.PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };

    # 4) Tab-completions for `cg` (fish autoloads; zsh _cg on the cache fpath).
    home.file.".config/fish/completions/cg.fish".text = fishCompletion;
    home.file.".cache/zsh/completions/_cg".text = zshCompletion;
  };
}
