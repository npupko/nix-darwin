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
# Lifecycle: the launchd agent starts at login by default (RunAtLoad=true) and is
# driven by `litellm-up`/`-down`/`-status` — `brew services` in Nix idiom,
# surviving terminal close. KeepAlive=false, so a manual `litellm-down` stays down
# until the next login or `litellm-up` (no auto-restart). A Claude Code
# "ConnectionRefused" means you ran `litellm-down` (or it crashed) — `litellm-up`.
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

    glm = {
      # Cerebras direct: LiteLLM's native cerebras/ provider auto-targets
      # https://api.cerebras.ai/v1 (OpenAI-compatible).
      litellm = {
        model = "cerebras/zai-glm-4.7";
        api_key = "os.environ/CEREBRAS_API_KEY";
      };
      ctx = 131072; # 128K, Cerebras-hosted cap
      caps = "tool_use,streaming";
      label = "GLM 4.7 · Cerebras";
      desc = "Z.ai GLM-4.7 on Cerebras inference (cloud, very fast).";
    };

    gpt-oss = {
      litellm = {
        model = "cerebras/gpt-oss-120b";
        api_key = "os.environ/CEREBRAS_API_KEY";
      };
      ctx = 131000; # Cerebras-hosted cap
      caps = "tool_use,streaming";
      label = "GPT-OSS 120B · Cerebras";
      desc = "OpenAI gpt-oss-120b on Cerebras inference (cloud, very fast).";
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
  #   ANTHROPIC_MODEL                    [used] the active model. `cg` sets this to an
  #                                      alias tier name (default "sonnet", via a
  #                                      preset's `primary`) so /model selects a named
  #                                      slot rather than inventing a "Custom model"
  #                                      entry. May also be a raw gateway model_name or
  #                                      "opusplan" (plan-vs-execute split).
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
  #              really want it) → fills the tiers; becomes the ACTIVE model via
  #              `primary`.                                    [required]
  #   primary    which alias tier ANTHROPIC_MODEL selects: opus|sonnet|haiku|fable.
  #              The active model is whatever that tier holds (default = `main`),
  #              shown as a named slot in /model — not a "Custom model" entry.
  #              [default: "sonnet"]
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
      # ANTHROPIC_MODEL points at the alias TIER that holds `main` (default
      # "sonnet"), not the raw model id — otherwise Claude Code shows the active
      # model as a separate "Custom model" entry instead of selecting the named
      # slot. Routing is identical (the alias resolves to `main`'s model). When
      # `main` is not a registry model (a raw passthrough or "opusplan") it goes
      # in verbatim.
      primary = p.primary or "sonnet";
      mainIsModel = models ? ${mainRef};
      anthropicModel = if mainIsModel then primary else (resolveModel mainRef).id;
    in
    "export ANTHROPIC_MODEL=${lib.escapeShellArg anthropicModel}\n"
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

  # ── Strip-thinking gateway hook ─────────────────────────────────────────────
  # Claude Code (an Anthropic client) replays its assistant `thinking_blocks` on
  # every follow-up turn. LiteLLM carries that field across to the upstream
  # request, but OpenAI-format providers (Cerebras, the LAN openai/ box, …) reject
  # the unknown property with a 400 — and `drop_params` only prunes top-level
  # params, not message content. No Claude Code env nor LiteLLM setting suppresses
  # this (verified: DISABLE_INTERLEAVED_THINKING only toggles the beta header;
  # modify_params/drop_params/additional_drop_params don't touch message content) —
  # so a LiteLLM async_pre_call_hook strips replayed reasoning from messages before
  # the provider call, for ALL models EXCEPT the Anthropic-format ones (kimi), which
  # REQUIRE the blocks. Thinking stays fully ON in Claude Code; the models still
  # reason each turn (server-side), we just stop echoing prior thinking back to a
  # backend that can't parse it. NOTE: LiteLLM resolves the `callbacks` module
  # relative to the config FILE's directory, so the hook is co-located with the
  # generated config.yaml in one store dir (litellmConfigDir below).
  keepThinkingModels = lib.concatStringsSep "," (
    lib.attrNames (
      lib.filterAttrs (_: m: m ? litellm && lib.hasPrefix "anthropic/" m.litellm.model) models
    )
  );
  stripHookPy = pkgs.writeText "strip_thinking.py" ''
    import os
    from litellm.integrations.custom_logger import CustomLogger

    # Anthropic-format models REQUIRE client-replayed thinking blocks (their API
    # rejects an assistant turn that omits them when thinking is enabled). Every
    # other backend is OpenAI-format and rejects the `thinking_blocks` field LiteLLM
    # carries over from the Anthropic request — so we strip replayed reasoning for
    # ALL models EXCEPT these. (Stripping is a safe no-op when no such blocks exist.)
    KEEP_MODELS = {
        m.strip() for m in os.environ.get("KEEP_THINKING_MODELS", "").split(",") if m.strip()
    }

    _THINKING_BLOCK_TYPES = {"thinking", "redacted_thinking"}


    def _scrub(msg):
        if not isinstance(msg, dict):
            return
        # OpenAI-format reasoning artifacts LiteLLM attaches to assistant messages.
        msg.pop("thinking_blocks", None)
        msg.pop("reasoning_content", None)
        # Anthropic-format content blocks (if the hook sees pre-translation data).
        content = msg.get("content")
        if isinstance(content, list):
            msg["content"] = [
                b
                for b in content
                if not (isinstance(b, dict) and b.get("type") in _THINKING_BLOCK_TYPES)
            ]


    class StripThinkingHandler(CustomLogger):
        async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
            model = (data or {}).get("model")
            if model not in KEEP_MODELS:
                for m in data.get("messages") or []:
                    _scrub(m)
            return data


    proxy_handler_instance = StripThinkingHandler()
  '';

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
      callbacks = "strip_thinking.proxy_handler_instance"; # strip replayed thinking_blocks
    };
  };
  configFile = (pkgs.formats.yaml { }).generate "litellm-config.yaml" configData;
  # Co-locate config + hook so LiteLLM's config-dir-relative `callbacks` import
  # resolves `strip_thinking` (the proxy wrapper rewrites PYTHONPATH, so relying on
  # it does not work — see the hook comment above).
  litellmConfigDir = pkgs.runCommandLocal "litellm-config-dir" { } ''
    mkdir -p "$out"
    cp ${configFile} "$out/litellm-config.yaml"
    cp ${stripHookPy} "$out/strip_thinking.py"
  '';

  # ── Start wrapper: source the sops env, then exec litellm ───────────────────
  litellmEnv = config.sops.templates."litellm.env".path;
  startScript = pkgs.writeShellScript "litellm-start" ''
    set -a
    . ${litellmEnv}
    set +a
    # KEEP list names the Anthropic-format models whose thinking_blocks must NOT be
    # stripped (read by strip_thinking.py at import).
    export KEEP_THINKING_MODELS=${lib.escapeShellArg keepThinkingModels}
    exec ${lib.getExe pkgs.litellm} --config ${litellmConfigDir}/litellm-config.yaml --host ${host} --port ${toString port}
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
          # ANTHROPIC_MODEL=sonnet (the alias holding it) so it selects the Sonnet
          # slot instead of appearing as a "Custom model" entry.
          export ANTHROPIC_MODEL=sonnet
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
      export CEREBRAS_API_KEY='${config.sops.placeholder.CEREBRAS_API_KEY}'
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

    # 3) launchd agent — starts at login by default; manual control via
    #    litellm-up/-down. KeepAlive stays false so a `litellm-down` stays down
    #    until the next login or `litellm-up` (no auto-restart fighting you).
    launchd.agents.litellm = {
      enable = true;
      config = {
        ProgramArguments = [ "${startScript}" ];
        RunAtLoad = true; # start at login/agent-load (default-on)
        KeepAlive = false; # a manual `litellm-down` stays down (no auto-restart)
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
