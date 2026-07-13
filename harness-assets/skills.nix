# Cross-harness agent skills — data instance of myConfig.harnessAssets.
#
# Canonical source of truth: a flat git repo at ~/Projects/npupko/skills, one
# folder per skill (<repo>/<skill>/SKILL.md). This instance symlinks each enabled
# skill into the directories the harnesses discover (see ../harness-assets for the
# generic fan-out mechanism):
#   - ~/.agents/skills  -> read by pi AND Codex (Agent Skills USER scope)
#   - ~/.claude/skills   -> read by Claude Code (alongside its native skills)
#
# Registry contract (per item):
#   key    = skill folder name (matches <repo>/<skill>/ and its SKILL.md `name`).
#   to     = OPTIONAL farm list; omit to link into ALL farms.
#              to = [ "claude" ];  -> Claude only (NOT pi/Codex)
#              to = [ "agents" ];  -> pi + Codex only (NOT Claude)
#   status = OPTIONAL informational label (e.g. "experimental"); has NO effect
#            on linking — purely a human marker. "Promote" = delete it.
# Delete a whole line to unlink that skill everywhere (home.file self-prunes).
{ username, ... }:
{
  myConfig.harnessAssets.skills = {
    # Absolute string on purpose — kept live-editable / out of the nix store.
    src = "/Users/${username}/Projects/npupko/skills";

    # Farm directories, RELATIVE to $HOME (the home.file key contract).
    targets = {
      agents = ".agents/skills"; # pi + Codex
      claude = ".claude/skills"; # Claude Code (coexists with native skills)
    };

    items = {
      angles = { };
      # atlas = { };
      brainstorming = {
        to = [ "claude" ]; # from obra/superpowers; Claude-only per request
      };
      breakdown = { };
      caveman = { };
      eventstorming = { };
      grill-me = { };
      humanize = { };
      image-gen = { };
      mise-bootstrap = { };
      okf = { }; # author/validate/consume Open Knowledge Format bundles; cross-harness
      process-book = { };
      prototype = { };
      solidtime-pi5 = { }; # self-hosted Solidtime operator; useful on pi + Codex + Claude
      system-design = { };
      tdd = { };
      to-my-style = { };
      to-prd = { };
      tradeoffs = { };
      walkthrough = { };
      zoom-out = { };
      skill-creator = {
        to = [ "agents" ]; # pi + Codex only; Claude has its own native skill-creator
      };
      playground = {
        status = "experimental";
      };
      playwright-cli = {
        status = "experimental";
      };
      skillify = {
        status = "experimental";
      };
      websitify = {
        status = "experimental";
      };

      # Migrated from ~/.claude/skills (were Claude-only). Kept Claude-only to
      # preserve behavior — several lean on Claude-specific tooling (the `Agent`
      # tool, `disable-model-invocation`, `allowed-tools`, `model:`). Drop the
      # `to` line on any you want shared to pi + Codex as well.
      animate-image = {
        to = [ "claude" ]; # fal.ai Wan image-to-video; sibling of image-gen
      };
      develop = {
        to = [ "claude" ];
      };
      ensure = {
        to = [ "claude" ];
      };
      mini-ensure = {
        to = [ "claude" ]; # lean variant of ensure, kept beside it
      };
      handoff = {
        to = [ "claude" ];
      };
      to-plan = {
        to = [ "claude" ]; # uses Claude plan mode (EnterPlanMode/ExitPlanMode + plan file)
      };
      prove-it = {
        to = [ "claude" ];
      };
      team = {
        to = [ "claude" ];
      };
      test-stand = {
        to = [ "claude" ];
      };
      poka-yoke = {
        to = [ "claude" ]; # mistake-proofing build mode; disable-model-invocation + model: + Agent verifier
      };

      retro = {
        to = [ "claude" ]; # AskUserQuestion + Claude transcript mining; meaningless on pi/Codex
      };

      prune-comments = {
        to = [ "claude" ]; # manual /prune-comments only; allowed-tools + disable-model-invocation
      };

      parallel-deep-research = {
        to = [ "claude" ]; # parallel-cli deep research; user-invocable + allowed-tools, Claude-only
      };
    };
  };
}
