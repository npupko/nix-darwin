# Claude Code alt-provider gateway — a Nix-managed LiteLLM proxy fronted by ONE
# shell-agnostic dispatcher (`cg`). Architecture is two layers:
#
#   models   — the SINGLE SOURCE OF TRUTH: every curated model defined once (how
#              LiteLLM reaches it — ONE deployment or a load-balance GROUP of
#              several — plus context window, capabilities, picker label).
#   presets  — named session profiles that assign models to Claude Code's slots
#              (main / opus / sonnet / haiku / fable / background / subagent) plus
#              optional knobs (effort, flags, auto-mode, extraEnv). Every model is
#              ALSO a trivial preset, so `cg free` works with no preset defined.
#
# `cg` resolves INTENT first, then names:
#   cg            → cg free (the default).
#   cg free       → the quality-ranked FREE chain. The router serves the best tier
#                   that isn't rate-limited and FAILS OVER automatically when a
#                   provider throttles (LiteLLM fallbacks + cooldown). The active
#                   model may change between turns — that is the point.
#   cg lan        → the LAN GPU box (Qwen3.6-27B). HARD-FAILS if the box is off
#                   (no silent cloud fallback).
#   cg <provider> → an interactive fzf picker of that provider's LIVE catalog
#                   (cerebras|groq|cloudflare|openrouter|xai), with a real quota
#                   gauge where the provider exposes rate-limit headers.
#   cg <provider>/<model>  → direct passthrough to any model the provider lists
#                   (drift-proof, via per-provider wildcards). No metadata.
#   cg status     → live catalogs + quota gauges + cooldown note.
#   cg <preset>   → a named preset (none defined by default).
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

  # Cloudflare Workers AI. The account ID is NOT secret (it scopes the api_base);
  # the key lives in sops. The NATIVE litellm `cloudflare/` provider DROPS `tools`
  # (verified — useless for agentic Claude Code), so Cloudflare is wired as an
  # OpenAI-compatible backend via this `/ai/v1` endpoint, which DOES return real
  # tool calls (live-tested). See the gpt-oss group + kimi-k2.7-code + the
  # cloudflare/* wildcard below.
  cfAcct = "0e9bd7514f96c40b78dd0719b2d609b4";
  cfBase = "https://api.cloudflare.com/client/v4/accounts/${cfAcct}/ai/v1";

  # LiteLLM 1.89.0's Anthropic-passthrough streaming adapter drops the FIRST token
  # of every content block on a block transition (e.g. reasoning→answer): it emits
  # content_block_start then re-queues the trigger chunk's delta ONLY for tool_use
  # (input_json_delta), discarding it for text/thinking on the false assumption that
  # "content_block_start carries the information" (true for tool_use, whose start
  # has the name/id; FALSE for text, whose start is text:""). Every reasoning model
  # in the free chain (GLM-4.7, Qwen3.6, gpt-oss) hit this — the visible answer lost
  # its opening token ("Hello there" → "there"). The patch broadens that re-queue to
  # also emit a text_delta/thinking_delta carrying content. Pure-Python, so only
  # litellm rebuilds; tool calls (already correct) are unaffected.
  #
  # ── REMOVE THIS PATCH WHEN BUMPING litellm ──────────────────────────────────
  # This is BerriAI/litellm#30014, now CLOSED/fixed upstream — the accepted fix
  # (tracked via #30043) is the same behavior this patch implements: "ensure the
  # first non-empty text delta is never dropped". It is NOT in 1.89.0; it landed in
  # a later release (likely 1.89.1–1.89.3 or 1.90.x — exact version unconfirmed).
  # So on the next litellm bump: drop ./litellm-streaming-firsttoken.patch + this
  # override, restart the daemon, and re-run the repro — a streaming `cg free`
  # request must keep its leading token ("Hello there friend", not "there friend").
  # If the patch then fails to apply (upstream touched these lines), that's the
  # signal the fix is in: delete it. Keep it only while pinned to 1.89.0.
  litellmPkg = pkgs.litellm.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./litellm-streaming-firsttoken.patch ];
  });

  # ── MODELS REGISTRY (single source of truth) ──────────────────────────────
  # Each curated model defined ONCE. Fields:
  #   litellm — the LiteLLM deployment(s). EITHER a single attrset (one backend)
  #             OR a LIST of attrsets (a load-balance GROUP — several backends
  #             sharing this model_name; the router picks a live one and cools
  #             down throttled ones). Each deployment is a litellm_params block;
  #             it may carry `tpm`/`rpm` (the provider's MEASURED free-tier limit)
  #             so the router pre-skips a deployment whose budget can't fit the
  #             request. Present ⇒ a model_list row (or rows) whose model_name is
  #             the attr key, so ANTHROPIC_MODEL=<key> routes here. Absent ⇒ the
  #             model is reached via a wildcard and `id` IS the model_name.
  #   id      — gateway model_name for wildcard-routed models (only when no litellm).
  #   ctx     — context window → LiteLLM model_info.max_input_tokens (so Claude Code
  #             discovery uses the right window instead of its 200K default).
  #   caps    — comma list Claude Code parses for ANTHROPIC_DEFAULT_<TIER>_SUPPORTED_
  #             CAPABILITIES (tool_use,vision,pdf,streaming,interleaved_thinking).
  #   label / desc — picker name + description, auto-derived into the _NAME/
  #             _DESCRIPTION env wherever the model lands in a slot.
  #
  # Curated entries exist for: the FREE-chain members (their metadata matters to
  # Claude Code), the synthetic `free` driver, the LAN `qwen`, and `kimi`
  # (Anthropic-format, special). EVERYTHING ELSE is reached via the per-provider
  # wildcards (`cg groq/<model>`) or the picker — drift-proof, but no metadata
  # (Claude Code then assumes a 200K window).
  models = {
    # ── synthetic FREE driver ────────────────────────────────────────────────
    # `free`'s PRIMARY deployment is tier-1's backend (GLM-4.7 on Cerebras); the
    # rest of the chain hangs off it via router_settings.fallbacks (see below).
    # A DEDICATED model_name (not fallbacks bolted onto `zai-glm-4.7`) keeps the
    # chain isolated to the mode: picking GLM-4.7 directly does NOT drag the chain.
    free = {
      litellm = {
        model = "cerebras/zai-glm-4.7";
        api_key = "os.environ/CEREBRAS_API_KEY";
        rpm = 5; # Cerebras free tier: MEASURED 5 requests/minute (shared bucket)
        tpm = 30000; # …and 30000 tokens/minute
      };
      ctx = 131072;
      caps = "tool_use,streaming";
      label = "Free · best available";
      desc = "Quality-ranked free chain; fails over automatically when a tier throttles.";
    };

    # ── FREE-chain tiers (each ALSO directly selectable by name) ──────────────
    # Tier 1 — GLM-4.7 on Cerebras. Best agentic-coding fit (interleaved + turn-
    # level tool-call reasoning; SWE-bench Verified 73.8%).
    "zai-glm-4.7" = {
      litellm = {
        model = "cerebras/zai-glm-4.7";
        api_key = "os.environ/CEREBRAS_API_KEY";
        rpm = 5;
        tpm = 30000;
      };
      ctx = 131072;
      caps = "tool_use,streaming";
      label = "GLM 4.7 · Cerebras";
      desc = "Z.ai GLM-4.7 on Cerebras inference (free tier; 5 rpm / 30k tpm).";
    };

    # Tier 2 — Qwen3.6-27B on Groq. Highest CONFIRMED SWE-Verified of the set
    # (77.2%); a reasoning model (emits `reasoning`, finish_reason tool_calls).
    # Different provider bucket than tier 1 so they don't compete for quota.
    "qwen3.6-27b" = {
      litellm = {
        model = "groq/qwen/qwen3.6-27b";
        api_key = "os.environ/GROQ_API_KEY";
        tpm = 8000; # Groq free tier: MEASURED 8000 tokens/minute
      };
      ctx = 131072;
      caps = "tool_use,streaming";
      label = "Qwen 3.6 27B · Groq";
      desc = "Qwen3.6-27B on Groq inference (free tier; 8k tpm; reasoning model).";
    };

    # Tier 3 — gpt-oss-120b as a 3-DEPLOYMENT load-balance group on three
    # INDEPENDENT free accounts. The router picks a live one and cools down the
    # throttled ones — maximum resilience for the workhorse tier at zero quality
    # cost.
    #
    # NOTE: a Cloudflare Workers AI leg (`openai/@cf/openai/gpt-oss-120b`) and a
    # dedicated Cloudflare Kimi-K2.7-Code tier were in the original plan, but
    # Cloudflare's `…/ai/v1` OpenAI-compat gateway currently REJECTS tool-calling
    # for its sglang-backed models: the backend requires nested OpenAI tools
    # (`tools[].function.name`), yet the gateway validator rejects any request
    # carrying a nested `function` object — so NO payload satisfies both layers
    # (verified live 2026-06). Shipping a tool-deaf leg is worse than omitting it:
    # a hard 400 from a chain member can abort failover instead of routing around
    # it. Re-add the Cloudflare leg + a `kimi-k2.7-code` tier once Cloudflare fixes
    # this (the cloudflare/* wildcard + picker below already prove the catalog and
    # api_base wiring). The obvious future tier-1 upgrade is GLM-5.2 via Z.ai (a
    # new provider + key — out of scope for now).
    "gpt-oss" = {
      litellm = [
        {
          model = "groq/openai/gpt-oss-120b";
          api_key = "os.environ/GROQ_API_KEY";
          tpm = 8000;
        }
        {
          model = "cerebras/gpt-oss-120b";
          api_key = "os.environ/CEREBRAS_API_KEY";
          rpm = 5;
          tpm = 30000;
        }
        {
          model = "openrouter/openai/gpt-oss-120b:free";
          api_key = "os.environ/OPENROUTER_API_KEY";
        }
      ];
      ctx = 131072;
      caps = "tool_use,streaming";
      label = "GPT-OSS 120B · 3-provider group";
      desc = "gpt-oss-120b load-balanced across Groq/Cerebras/OpenRouter.";
    };

    # Tier 4 — deep backstop only. 1M context, but heavily rate-limited (~20 rpm).
    "qwen3-coder" = {
      litellm = {
        model = "openrouter/qwen/qwen3-coder:free";
        api_key = "os.environ/OPENROUTER_API_KEY";
      };
      ctx = 1000000;
      caps = "tool_use,streaming";
      label = "Qwen3-Coder · OpenRouter (free)";
      desc = "1M-context backstop; heavily rate-limited — last resort only.";
    };

    # ── LAN box ───────────────────────────────────────────────────────────────
    # OpenAI-compatible llama-swap/llama.cpp box, no auth (LAN-only, api_key a
    # non-empty dummy). NEEDS the GPU box powered on — reached only via `cg lan`,
    # which probes it first and HARD-FAILS if it's off (no cloud fallback).
    qwen = {
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

    # ── Anthropic-format escape hatch ──────────────────────────────────────────
    # Moonshot/Kimi coding endpoint is Anthropic-format → a LiteLLM anthropic/
    # provider (LiteLLM appends /v1/messages to api_base). The ONLY model whose
    # replayed thinking_blocks are KEPT (the strip hook skips anthropic/ models).
    kimi = {
      litellm = {
        model = "anthropic/kimi-for-coding";
        api_base = "https://api.kimi.com/coding";
        api_key = "os.environ/KIMI_API_KEY";
      };
      ctx = 131072;
      caps = "tool_use,streaming";
      label = "Kimi · coding";
      desc = "Moonshot Kimi coding endpoint (Anthropic-native, cloud).";
    };
  };

  # The FREE fallback chain: when `free` (tier 1) throttles, the router tries each
  # of these model_names in order, skipping cooled-down / over-budget deployments.
  # Order = quality-ranked, top tiers on DIFFERENT provider buckets (decision 3).
  freeFallback = [
    "qwen3.6-27b"
    "gpt-oss"
    "qwen3-coder"
  ];

  # Providers that expose a live catalog (and, for the metered two, a quota gauge)
  # to the `cg <provider>` picker and `cg status`.
  providerNames = [
    "cerebras"
    "groq"
    "cloudflare"
    "openrouter"
    "xai"
  ];

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
  #     main = "zai-glm-4.7"; opus = "kimi"; background = "gpt-oss";
  #     effort = "high"; subagent = "zai-glm-4.7";
  #     label = "GLM drive · Kimi for /model opus";
  #     desc  = "GLM everywhere, Kimi available as the opus tier, high effort.";
  #   };
  presets = { };

  # The preset `cg` selects with no argument: the resilient FREE chain.
  defaultPreset = "free";

  # ── per-provider wildcards (drift-proof reach) ─────────────────────────────
  # One catch-all row per provider so `cg <provider>/<model>` works on the single
  # stored key with NO Nix edit when a vendor adds a model. These rows ALSO
  # participate in fallbacks. Trade-off: wildcard-routed models carry no metadata
  # (Claude Code assumes a 200K window) — that's why curated entries still exist
  # for the models that matter. Cloudflare is special: the native cloudflare/
  # provider drops `tools`, so its wildcard targets openai/* against cfBase (the
  # OpenAI-compat endpoint that DOES return tool calls).
  providerWildcard = prefix: keyEnv: {
    model_name = "${prefix}/*";
    litellm_params = {
      model = "${prefix}/*";
      api_key = "os.environ/${keyEnv}";
    };
  };
  wildcards = [
    (providerWildcard "openrouter" "OPENROUTER_API_KEY")
    (providerWildcard "groq" "GROQ_API_KEY")
    (providerWildcard "cerebras" "CEREBRAS_API_KEY")
    (providerWildcard "xai" "XAI_API_KEY")
    {
      # cloudflare/<@cf/vendor/model> → openai/<@cf/vendor/model> against cfBase.
      # (Verified: litellm rewrites `cloudflare/*`→`openai/*` keeping the suffix.)
      model_name = "cloudflare/*";
      litellm_params = {
        model = "openai/*";
        api_base = cfBase;
        api_key = "os.environ/CLOUDFLARE_WORKERS_AI_API_KEY";
      };
    }
  ];

  # ── resolution helpers ────────────────────────────────────────────────────
  # A model's deployments, normalized to a list (single attrset or list both ok).
  deploymentsOf = m: if lib.isList m.litellm then m.litellm else [ m.litellm ];

  # Resolve a model reference (a `models` alias, or a raw passthrough string) to
  # its gateway id + display metadata. Shape of `litellm` (single vs group) is
  # irrelevant here — the gateway id is always the attr key.
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

  # One case arm per resolvable preset/model target.
  presetArms = lib.concatStrings (
    lib.mapAttrsToList (name: p: "  ${name})\n" + presetBody name p + "    ;;\n") allPresets
  );

  # `cg list` body + tab-completion entries (intent modes, presets, models, list).
  modeEntries = [
    {
      name = "lan";
      desc = "LAN GPU box (Qwen3.6-27B); hard-fails if the box is off";
    }
    {
      name = "status";
      desc = "live provider catalogs + quota gauges";
    }
  ]
  ++ (map (p: {
    name = p;
    desc = "pick a ${p} model (live catalog${
      if p == "groq" || p == "cerebras" then " + quota gauge" else ""
    })";
  }) providerNames);
  complEntries =
    modeEntries
    ++ (lib.mapAttrsToList (n: p: {
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
        desc = "list modes, presets and models";
      }
    ];
  listText =
    "cg targets  (ANTHROPIC_BASE_URL → LiteLLM gateway on ${host}:${toString port})\n\n"
    + "Intent modes:\n"
    + "  free      —  quality-ranked FREE chain, auto-failover (the default: bare cg)\n"
    + "  lan       —  LAN GPU box (Qwen3.6-27B); hard-fails if the box is off\n"
    + "  status    —  live provider catalogs + quota gauges\n"
    + "  ${lib.concatStringsSep " / " providerNames}\n"
    + "            —  interactive fzf picker of the provider's LIVE model catalog\n\n"
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
    + "\nPassthrough:  cg ${lib.concatMapStringsSep "/<model>  |  cg " (p: p) providerNames}/<model>\n";

  # ── Strip-thinking gateway hook ─────────────────────────────────────────────
  # Claude Code (an Anthropic client) replays its assistant `thinking_blocks` on
  # every follow-up turn. LiteLLM carries that field across to the upstream
  # request, but OpenAI-format providers (Cerebras, Groq, Cloudflare openai-compat,
  # the LAN openai/ box, …) reject the unknown property with a 400 — and
  # `drop_params` only prunes top-level params, not message content. No Claude Code
  # env nor LiteLLM setting suppresses this (verified: DISABLE_INTERLEAVED_THINKING
  # only toggles the beta header; modify_params/drop_params/additional_drop_params
  # don't touch message content) — so a LiteLLM async_pre_call_hook strips replayed
  # reasoning from messages before the provider call, for ALL models EXCEPT the
  # Anthropic-format ones (kimi), which REQUIRE the blocks. Thinking stays fully ON
  # in Claude Code; the models still reason each turn (server-side), we just stop
  # echoing prior thinking back to a backend that can't parse it. Reasoning models
  # (Qwen3.6-27B emits `reasoning`) are handled the same way. NOTE: LiteLLM resolves
  # the `callbacks` module relative to the config FILE's directory, so the hook is
  # co-located with the generated config.yaml in one store dir (litellmConfigDir).
  keepThinkingModels = lib.concatStringsSep "," (
    lib.attrNames (
      lib.filterAttrs (
        _: m: m ? litellm && lib.any (d: lib.hasPrefix "anthropic/" d.model) (deploymentsOf m)
      ) models
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
    # Each curated model expands to one model_list row per deployment (a group →
    # several rows sharing the model_name). tpm/rpm ride inside litellm_params
    # (where the router's pre-call check reads them). Wildcards appended last.
    model_list =
      (lib.concatMap (
        name:
        let
          m = models.${name};
        in
        if m ? litellm then
          map (
            dep:
            {
              model_name = name;
              litellm_params = dep;
            }
            // (lib.optionalAttrs (m ? ctx) { model_info.max_input_tokens = m.ctx; })
          ) (deploymentsOf m)
        else
          [ ]
      ) (lib.attrNames models))
      ++ wildcards;
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
    };
    litellm_settings = {
      drop_params = true; # tolerate provider param mismatches
      callbacks = "strip_thinking.proxy_handler_instance"; # strip replayed thinking_blocks
    };
    # Router behaviour. These are Router.__init__ args and MUST live under
    # router_settings — `cooldown_time` and `enable_pre_call_checks` are read ONLY
    # from the Router constructor (not the litellm module globals), so placing them
    # in litellm_settings would silently no-op (verified in litellm 1.89.0).
    router_settings = {
      enable_pre_call_checks = true; # pre-skip a deployment whose tpm/rpm can't fit the request
      num_retries = 2; # retry a failed call (across other healthy deployments)
      cooldown_time = 60; # bench a throttled deployment for 60s — matches the per-minute reset
      # Quality-ranked FREE chain: `free` (tier-1 GLM) → tier-2 → … Each entry is a
      # model_name; the router skips cooled-down / over-budget deployments.
      fallbacks = [ { free = freeFallback; } ];
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
    exec ${lib.getExe litellmPkg} --config ${litellmConfigDir}/litellm-config.yaml --host ${host} --port ${toString port}
  '';

  # ── cg dispatcher ───────────────────────────────────────────────────────────
  cgScript = pkgs.writeShellApplication {
    name = "cg";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.fzf
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
    ];
    text = ''
      # cg [free|lan|status|<provider>|<provider>/<model>|preset|model|list] [claude args...]
      gw="http://${host}:${toString port}"

      export CLAUDE_CODE_TMUX_TRUECOLOR=1
      export ANTHROPIC_BASE_URL="$gw"
      export ANTHROPIC_AUTH_TOKEN="''${LITELLM_MASTER_KEY:?cg: LITELLM_MASTER_KEY not in env (interactive sops api-keys not sourced?)}"
      export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1

      # ── live provider catalog / quota helpers (picker + status) ─────────────
      # Print a provider's live model ids, one per line (empty/best-effort on any
      # failure — missing key, offline, 403).
      _cg_catalog() {
        local prov="$1" url key json
        case "$prov" in
          groq)       url="https://api.groq.com/openai/v1/models";  key="''${GROQ_API_KEY:-}" ;;
          cerebras)   url="https://api.cerebras.ai/v1/models";      key="''${CEREBRAS_API_KEY:-}" ;;
          openrouter) url="https://openrouter.ai/api/v1/models";    key="''${OPENROUTER_API_KEY:-}" ;;
          xai)        url="https://api.x.ai/v1/models";             key="''${XAI_API_KEY:-}" ;;
          cloudflare) url="https://api.cloudflare.com/client/v4/accounts/${cfAcct}/ai/models/search?task=Text+Generation&per_page=100"; key="''${CLOUDFLARE_WORKERS_AI_API_KEY:-}" ;;
          *) return 1 ;;
        esac
        json=$(curl -sS --max-time 8 -H "Authorization: Bearer $key" "$url" 2>/dev/null) || return 0
        case "$prov" in
          cloudflare) printf '%s' "$json" | jq -r '.result[]?.name // empty' 2>/dev/null || true ;;
          *)          printf '%s' "$json" | jq -r '.data[]?.id // empty'    2>/dev/null || true ;;
        esac
      }

      # Pull a single header value (case-insensitive) from a dumped header blob.
      _cg_hv() { printf '%s\n' "$1" | grep -i "^$2:" | tail -1 | tr -d '\r' | sed 's/^[^:]*:[[:space:]]*//'; }

      # Print a one-line quota gauge. Only Groq & Cerebras emit usable rate-limit
      # headers; everyone else degrades honestly to a reachability note.
      _cg_gauge() {
        local prov="$1" url key model body hdrs
        case "$prov" in
          groq)     url="https://api.groq.com/openai/v1/chat/completions"; key="''${GROQ_API_KEY:-}" ;;
          cerebras) url="https://api.cerebras.ai/v1/chat/completions";     key="''${CEREBRAS_API_KEY:-}" ;;
          *) printf 'quota: n/a (no rate-limit headers)'; return 0 ;;
        esac
        # Probe with a CHAT model — skip audio/embedding/image/etc ids that would
        # 400 a chat completion and leave the gauge blank.
        model=$(_cg_catalog "$prov" | grep -ivE 'whisper|tts|embedding|guard|playai|moderation|dall-e|image|sora|realtime|transcribe|audio' | head -1)
        [ -n "$model" ] || model=$(_cg_catalog "$prov" | head -1)
        [ -n "$model" ] || { printf 'quota: n/a'; return 0; }
        body=$(printf '{"model":"%s","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' "$model")
        hdrs=$(curl -sS --max-time 8 -D - -o /dev/null -H "Authorization: Bearer $key" -H "Content-Type: application/json" -d "$body" "$url" 2>/dev/null) || { printf 'quota: n/a'; return 0; }
        if [ "$prov" = groq ]; then
          local lim rem
          lim=$(_cg_hv "$hdrs" x-ratelimit-limit-tokens)
          rem=$(_cg_hv "$hdrs" x-ratelimit-remaining-tokens)
          if [ -n "$lim" ]; then printf 'TPM %s/%s remaining' "''${rem:-?}" "$lim"; else printf 'quota: n/a'; fi
        else
          local lr rr lt rt
          lr=$(_cg_hv "$hdrs" x-ratelimit-limit-requests-minute);  rr=$(_cg_hv "$hdrs" x-ratelimit-remaining-requests-minute)
          lt=$(_cg_hv "$hdrs" x-ratelimit-limit-tokens-minute);    rt=$(_cg_hv "$hdrs" x-ratelimit-remaining-tokens-minute)
          if [ -n "$lr" ] || [ -n "$lt" ]; then
            printf 'req-min %s/%s · tok-min %s/%s' "''${rr:-?}" "''${lr:-?}" "''${rt:-?}" "''${lt:-?}"
          else printf 'quota: n/a'; fi
        fi
      }

      # Interactive picker: fetch the live catalog, show fzf with a quota gauge in
      # the header, echo the chosen passthrough target ("<provider>/<model>").
      _cg_pick() {
        local prov="$1" cat gauge sel
        cat=$(_cg_catalog "$prov") || true
        if [ -z "$cat" ]; then
          printf 'cg: no live catalog for %s (key missing, 403, or unreachable)\n' "$prov" >&2
          return 1
        fi
        gauge=$(_cg_gauge "$prov")
        sel=$(printf '%s\n' "$cat" | LC_ALL=C sort -u | fzf \
          --prompt="$prov> " \
          --header="$prov — $gauge   (Enter launches · Esc cancels)" \
          --height=80% --reverse --no-multi) || return 1
        [ -n "$sel" ] || return 1
        printf '%s/%s' "$prov" "$sel"
      }

      target="''${1:-}"; [ "$#" -gt 0 ] && shift || true

      # ── intent modes resolved BEFORE name resolution ────────────────────────
      case "$target" in
        list|-l|--list) printf '%s' ${lib.escapeShellArg listText}; exit 0 ;;
        ""|default|free) target=${lib.escapeShellArg defaultPreset} ;;
        status)
          printf 'litellm gateway %s/health/liveliness → ' "$gw"
          curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$gw/health/liveliness" || printf 'unreachable\n'
          printf '\nConfigured gateway model_names (/v1/models):\n'
          # Curated names have no "/"; wildcards end in "/*". Drop the hundreds of
          # wildcard-ENUMERATED "<provider>/<model>" rows litellm also reports.
          curl -s --max-time 5 -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" "$gw/v1/models" \
            | jq -r '.data[]?.id | select(test("^[^/]+$") or test("/\\*$"))' 2>/dev/null | sed 's/^/  /' || true
          printf '\nLive provider catalogs + quota:\n'
          for p in ${lib.concatStringsSep " " providerNames}; do
            n=$(_cg_catalog "$p" | grep -c . || true)
            printf '  %-11s %s models · %s\n' "$p" "''${n:-0}" "$(_cg_gauge "$p")"
          done
          printf '\nNote: litellm ${pkgs.litellm.version} exposes NO cooldown-list endpoint — a\n'
          printf 'benched deployment is only visible in ~/Library/Logs/litellm.log\n'
          printf '(grep for "cooldown" / "Retried"). /health pings reachability, not quota.\n'
          exit 0
          ;;
        lan)
          # Hard-fail if the LAN GPU box is off — NO silent cloud fallback.
          if ! curl -sf -o /dev/null --max-time 3 "${models.qwen.litellm.api_base}/models"; then
            printf 'cg lan: LAN GPU box at ${models.qwen.litellm.api_base} is unreachable — power it on (no cloud fallback).\n' >&2
            exit 1
          fi
          target="qwen"
          ;;
        cerebras|groq|cloudflare|openrouter|xai)
          target=$(_cg_pick "$target") || { printf 'cg: nothing selected\n' >&2; exit 1; }
          ;;
      esac

      FLAGS=(--dangerously-skip-permissions)

      # ── name resolution: preset/model → passthrough → error ─────────────────
      case "$target" in
      ${presetArms}  */*)
          # passthrough: a raw gateway model name (groq/…, cerebras/…, xai/…,
          # cloudflare/@cf/…, openrouter/…). No metadata. ANTHROPIC_MODEL=sonnet
          # (the alias holding it) so it selects the Sonnet slot instead of
          # appearing as a "Custom model" entry.
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
    #    KIMI/XAI/CEREBRAS/GROQ/OPENROUTER/CLOUDFLARE are declared in home.nix
    #    (their placeholders resolve here); LITELLM_MASTER_KEY is declared below so
    #    it auto-joins home.nix's interactive api-keys templates → `cg` finds it.
    sops.secrets.LITELLM_MASTER_KEY = { }; # value lives in secrets.yaml (added via `ds`)
    sops.templates."litellm.env".content = ''
      export KIMI_API_KEY='${config.sops.placeholder.KIMI_API_KEY}'
      export XAI_API_KEY='${config.sops.placeholder.XAI_API_KEY}'
      export CEREBRAS_API_KEY='${config.sops.placeholder.CEREBRAS_API_KEY}'
      export GROQ_API_KEY='${config.sops.placeholder.GROQ_API_KEY}'
      export OPENROUTER_API_KEY='${config.sops.placeholder.OPENROUTER_API_KEY}'
      export CLOUDFLARE_WORKERS_AI_API_KEY='${config.sops.placeholder.CLOUDFLARE_WORKERS_AI_API_KEY}'
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
