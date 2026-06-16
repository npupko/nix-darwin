# Cross-harness agent skills.
#
# Canonical source of truth: a flat git repo at ~/Projects/npupko/skills, one
# folder per skill (<repo>/<skill>/SKILL.md). This module symlinks each enabled
# skill into the directories the three harnesses discover:
#   - ~/.agents/skills  -> read by pi AND Codex (Agent Skills USER scope)
#   - ~/.claude/skills   -> read by Claude Code (alongside its native skills)
#
# Design notes:
#   * home.file (not an activation script): home-manager auto-prunes links it no
#     longer manages and is dry-run/build-correct. A hand-rolled `ln` loop is
#     neither, and activation scripts ignore DRY_RUN under nix-darwin (hm#7344).
#   * mkOutOfStoreSymlink takes an ABSOLUTE STRING, never a `./path` literal or
#     `toString ./path` — a literal would copy the (large) repo into the nix
#     store and point the link at /nix/store instead of the live dir (hm#2660).
#     The string path keeps content out of the store and live-editable.
#   * The repo is NOT read with builtins.readDir (impure in flakes + store copy);
#     the skill set is enumerated explicitly in `skills` below.
{
  config,
  lib,
  username,
  ...
}:
let
  # Absolute string on purpose (see header).
  repo = "/Users/${username}/Projects/npupko/skills";

  # Farm directories, RELATIVE to $HOME (that is the home.file key contract).
  farms = {
    agents = ".agents/skills"; # pi + Codex
    claude = ".claude/skills"; # Claude Code (coexists with native skills)
  };
  allFarms = lib.attrNames farms;

  # ===== Single source of truth: per-skill / per-harness registry ============
  # key    = skill folder name (matches <repo>/<skill>/ and its SKILL.md `name`).
  # to     = OPTIONAL farm list; omit to link into ALL farms.
  #            to = [ "claude" ];  -> Claude only (NOT pi/Codex)
  #            to = [ "agents" ];  -> pi + Codex only (NOT Claude)
  # status = OPTIONAL informational label (e.g. "experimental"); has NO effect
  #          on linking — purely a human marker. "Promote" = delete it.
  # Delete a whole line to unlink that skill everywhere (home.file self-prunes).
  skills = {
    angles = { };
    # atlas = { };
    breakdown = { };
    caveman = { };
    eventstorming = { };
    grill-me = { };
    humanize = { };
    image-gen = { };
    mise-bootstrap = { };
    process-book = { };
    prototype = { };
    solidtime-pi5 = { }; # self-hosted Solidtime operator; useful on pi + Codex + Claude
    stop-slop = { };
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
    develop = {
      to = [ "claude" ];
    };
    ensure = {
      to = [ "claude" ];
    };
    handoff = {
      to = [ "claude" ];
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

    retro = {
      to = [ "claude" ]; # AskUserQuestion + Claude transcript mining; meaningless on pi/Codex
    };
  };

  # Expand the registry -> one home.file entry per (skill x target farm).
  # `status` is intentionally unused here (informational only).
  entries = lib.concatLists (
    lib.mapAttrsToList (
      name: s:
      map (f: {
        name = "${farms.${f}}/${name}";
        value.source = config.lib.file.mkOutOfStoreSymlink "${repo}/${name}";
      }) (s.to or allFarms)
    ) skills
  );
in
{
  home.file = lib.listToAttrs entries;
}
