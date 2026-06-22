# =============================================================================
# PACKAGE MANAGEMENT STRATEGY
# =============================================================================
# Nix (home.packages):  CLI tools, system utilities, fonts (nixpkgs unstable)
# Homebrew brews:       macOS-specific, not in nixpkgs, or need latest versions
# Homebrew casks:       GUI applications
# Mise:                 Language runtimes + npm/node CLI tools (always latest)
# Self-managed:         Claude Code (auto-updates via native installer)
# =============================================================================
{
  config,
  pkgs,
  lib,
  inputs,
  username,
  themes,
  themeName,
  ...
}:
let
  theme = themes.${themeName};

  # Render the active theme's fish syntax-highlighting palette into fish script.
  # Fish is the only CLI here without a built-in gruvbox theme, so its palette
  # lives as explicit hex under `theme.fish` (see themes.nix) rather than a named
  # theme reference. Emitted from interactiveShellInit — which fish sources AFTER
  # conf.d/*.fish, so these `set -g` lines override any value set there.
  # Themes without a `fish` attr (nord, catppuccin) fall back to fish defaults.
  fishThemeInit =
    let
      f = theme.fish or null;
    in
    lib.optionalString (f != null) (
      lib.concatStringsSep "\n" (
        (lib.mapAttrsToList (k: v: "set -g fish_color_${k} ${v}") (f.colors or { }))
        ++ (lib.mapAttrsToList (k: v: "set -g fish_pager_color_${k} ${v}") (f.pager or { }))
      )
    );

  # glow's `style` value for the active theme. glamour ships no gruvbox style, so
  # gruvbox themes name a custom JSON (dotfiles/glow/<name>.json) which is resolved
  # to its installed ~/.config path here; any other value (dark/light/…) is passed
  # through verbatim as a glamour built-in style name. glow reads ~/.config/glow/
  # first because XDG_CONFIG_HOME is set (see glow main.go: XDG dir is prepended
  # ahead of macOS ~/Library/Preferences).
  glowStyle =
    let
      name = theme.glow or "auto";
    in
    if builtins.pathExists (./dotfiles/glow + "/${name}.json") then
      "${config.home.homeDirectory}/.config/glow/${name}.json"
    else
      name;

  # Pre-generate starship zsh init at build time. Shell startup sources the
  # store file directly — no subprocess fork per shell (~32ms saved). Cache
  # invalidates automatically when pkgs.starship store path changes.
  starshipInitZsh = pkgs.runCommand "starship-init.zsh" { } ''
    ${lib.getExe pkgs.starship} init zsh > $out
  '';

  # ── Claude Code → tmux status indicators ───────────────────────────────────
  # Appends a state glyph to the tmux tab where a Claude Code hook fires, using
  # the `claude agents` board palette:
  #     ✻ working = coral #da7756 · ⊘ awaiting = amber #fbbf24 · ✓ done = green #16a34a
  # Glyph only — no task title. The tab name keeps its accent(focused)/dim(rest)
  # color; the glyph carries the state color. Driven by ~/.claude/settings.json
  # hooks → ~/.local/bin/claude-tmux-status, which sets a per-window @claude_status
  # (severity-merged across panes: awaiting > working > done).
  #
  # Disable it:
  #   • instant, no rebuild:  touch ~/.claude/.tmux-status-off
  #   • fully:                set enable = false here, then `dr`
  claudeTmuxStatus = {
    enable = true;
    paneBorders = false; # per-pane glyph on the pane border (handy for `tdl` splits)
  };

  # Tab format: appends a single state glyph per @claude_status — the glyph
  # carries the state color, the name keeps accent (focused) / dim (unfocused).
  # No task title. Falls back to the plain format when disabled. Each conditional
  # branch is a comma-free #[fg=…] block, so tmux's style parser stays happy.
  ccWindowFormats =
    if claudeTmuxStatus.enable then
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
  ccPaneBorders = lib.optionalString (claudeTmuxStatus.enable && claudeTmuxStatus.paneBorders) ''
    set -g pane-border-status top
    set -g pane-border-format "#{?#{==:#{@claude_pane_status},waiting},#[fg=#fbbf24] awaiting,#{?#{==:#{@claude_pane_status},done},#[fg=#16a34a] done,#{?#{==:#{@claude_pane_status},active},#[fg=#da7756] working,#[default]}}} #{pane_title}"
  '';
in
{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
    inputs.try.homeModules.default
    ./nvim-lsp.nix
    ./skills.nix
    ./claude-accounts.nix
  ];

  # try: module provides `package` and `path` options; we disable its eager
  # `eval "$(try init …)"` injection (saves ~75ms) because the custom `try()`
  # function below calls the binary directly. Options still resolve since
  # only `config` is gated by `enable`.
  programs.try = {
    enable = false;
    path = "$HOME/Projects/tries";
  };

  home.stateVersion = "26.05";

  # Disable manual generation to avoid builtins.toFile warning (home-manager #7935)
  manual.manpages.enable = false;
  manual.html.enable = false;
  manual.json.enable = false;

  # Packages (review and uncomment as needed)
  home.packages = with pkgs; [
    # Core Dev Tools
    uv
    tilt

    # Editors
    pkgs.helix
    pkgs.neovim
    # markdown-oxide
    marksman

    # Cloud/Infra
    terraform
    opentofu
    awscli2
    kubectl
    google-cloud-sdk
    google-cloud-sql-proxy
    ngrok
    qmk

    # VCS & CLI
    curl
    wget
    doctl
    tree-sitter

    # Shell & Terminal
    zellij
    ugrep
    bfs

    # AI Tools
    # aichat
    # argc
    # tabby # broken: metrics-0.22.3 fails with newer rustc (rust-lang/rust#141402)

    # System utilities
    gnupg
    # gnused
    coreutils
    automake
    bash
    libffi
    postgresql
    pkg-config
    cmake
    ffmpeg
    nh
    devenv
    pinentry_mac
    sops
    age
    _1password-cli
    cloudflared
    kubectx
    bitwarden-desktop
    terminal-notifier

    # Theme switching
    (pkgs.writeShellApplication {
      name = "theme-switch";
      runtimeInputs = [ pkgs.gnused ];
      text =
        let
          availableThemes = builtins.concatStringsSep " " (builtins.attrNames themes);
        in
        ''
          available="${availableThemes}"
          t="''${1:-}"
          if [ -z "$t" ]; then
            current=$(sed -n 's/.*themeName = "\(.*\)";.*# ACTIVE_THEME/\1/p' /etc/nix-darwin/flake.nix)
            echo "Current: $current"
            echo "Available: $available"
            exit 0
          fi
          echo "$available" | tr ' ' '\n' | grep -qx "$t" || { echo "Unknown theme: $t"; exit 1; }
          grep -q '# ACTIVE_THEME' /etc/nix-darwin/flake.nix || { echo "Error: ACTIVE_THEME marker not found in flake.nix" >&2; exit 1; }
          current=$(sed -n 's/.*themeName = "\(.*\)";.*# ACTIVE_THEME/\1/p' /etc/nix-darwin/flake.nix)
          if [ "$current" = "$t" ]; then
            echo "Already on theme: $t"
            exit 0
          fi
          sudo sed -i "s/themeName = \".*\"; # ACTIVE_THEME/themeName = \"$t\"; # ACTIVE_THEME/" /etc/nix-darwin/flake.nix
          echo "Theme set to: $t — rebuilding..."
          sudo darwin-rebuild switch
          # Reload tmux config (if tmux is running)
          tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null || true
          # Ghostty auto-reloads its config on file change
          echo "Theme applied: $t"
        '';
    })

    # Atlas — per-investigation, semantically-zoomable knowledge maps.
    # Thin wrapper over the live source at ~/Projects/npupko/atlas (edits apply
    # immediately). Uses nix's bun, independent of mise; needs `bun install` to
    # have run in the repo so `marked` resolves. Replace with a flake package
    # once Atlas stabilizes (bun build --compile, deps vendored).
    # (pkgs.writeShellApplication {
    #   name = "atlas";
    #   runtimeInputs = [ pkgs.bun ];
    #   text = ''exec bun "$HOME/Projects/npupko/atlas/bin/atlas.ts" "$@"'';
    # })
  ];

  # Session variables
  home.sessionVariables = {
    EDITOR = "nvim";
    JJ_CONFIG = "/Users/${username}/.config/jj/config.toml";
    DEVENV_NIX = "/nix/var/nix/profiles/default";
    STARSHIP_LOG = "error"; # suppress spurious timeout warnings from git commands under system load

    # Aider config (not secrets — just preferences)
    AIDER_DARK_MODE = "true";
    AIDER_CODE_THEME = "gruvbox-dark";

    # API base URLs (not secrets)
    REQUESTY_BASE_URL = "https://router.requesty.ai/v1";

    # Opt out of Determinate Nix telemetry (stops .cache/nix/sentry/ in CWD)
    DETSYS_IDS_TELEMETRY = "disabled";

    # XDG base directories — macOS doesn't set these by default, but most CLI
    # tools (sops, gh, kubectl, jj, nvim, starship, ...) either honor XDG when
    # set or already default to ~/.config. Declare them so every CLI resolves
    # config/cache/data/state in the same XDG-aligned tree as Linux.
    XDG_CONFIG_HOME = "/Users/${username}/.config";
    XDG_CACHE_HOME = "/Users/${username}/.cache";
    XDG_DATA_HOME = "/Users/${username}/.local/share";
    XDG_STATE_HOME = "/Users/${username}/.local/state";
  };

  # PATH additions
  home.sessionPath = [
    "/Users/${username}/.local/bin"
    "/Users/${username}/.claude/local"
    "/Users/${username}/Projects/npupko/utility/target/release"
  ];

  # Shell aliases
  home.shellAliases = {
    v = "nvim";
    be = "bundle exec";
    k = "kubectl";
    zj = "zellij";
    dh = "v /etc/nix-darwin/home.nix";
    dp = "v /etc/nix-darwin/configuration.nix";
    de = "v /etc/nix-darwin";
    dr = "sudo darwin-rebuild switch";
    duf = "nix flake update --flake /etc/nix-darwin/";
    ngc = "nh clean all --keep 5";
    dcd = "cd /etc/nix-darwin/";
    ds = "SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt sops /etc/nix-darwin/secrets.yaml";
    chrome_debug = "open -na \"Google Chrome\" --args --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-debug --no-first-run --no-default-browser-check";
    ghostty = "/Applications/Ghostty.app/Contents/MacOS/ghostty";
    fix-ssh = "launchctl kickstart -k gui/$(id -u)/org.nix-community.home.ssh-agent";
    grep = "ug -G";
    find = "bfs";
    c = "CLAUDE_CODE_TMUX_TRUECOLOR=1 claude --dangerously-skip-permissions";
    ca = "CLAUDE_CODE_TMUX_TRUECOLOR=1 claude agents --permission-mode bypassPermissions";
    cx = "opencode";
    ls = "eza";
    ll = "eza -lh --group-directories-first --icons=auto";
    lla = "eza -lha --group-directories-first --icons=auto";
    lt = "eza --tree --level=2 --long --icons --git";
    lta = "eza --tree --level=2 --long --icons --git -a";
    t = "tmux attach || tmux new -s Work";

    # Directory navigation
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";

    # Git shortcuts
    g = "git";
    gcm = "git commit -m";
    gcam = "git commit -a -m";
    gcad = "git commit -a --amend";

    # FZF + bat
    ff = "fzf --preview 'bat --style=numbers --color=always {}'";

    # Docker
    d = "docker";
  };

  programs.mise = {
    enable = true;
    # package = inputs.mise.packages.${pkgs.system}.default;
    enableZshIntegration = false; # zsh: loaded via zinit turbo (see programs.zsh.initContent)
    enableFishIntegration = true; # fish: native eager `mise activate fish`
    globalConfig = {
      settings = {
        npm = {
          package_manager = "bun";
        };
        trusted_config_paths = [
          "/Users/${username}/Projects"
        ];
        # Disable mise's default ~24h supply-chain release-age delay. It
        # permanently breaks amp/@ampcode/cli (publishes continuously, so no
        # version is ever old enough → "no versions found matching date filter")
        # and emits noisy "newer release ignored" warnings for other fast-moving
        # AI CLIs (qwen-code, pi-coding-agent). We always want latest here.
        minimum_release_age = "0";
      };
      tools = {
        rust = "latest";
        node = "latest";
        bun = "latest";
        "npm:typescript" = "latest";
        "npm:typescript-language-server" = "latest";
        "github:basecamp/fizzy-cli" = "latest";

        # AI CLI tools
        "npm:@google/gemini-cli" = "latest";
        "npm:@openai/codex" = "latest";
        # amp's real package; @sourcegraph/amp's bin path doesn't resolve under mise.
        "npm:@ampcode/cli" = "latest";
        "npm:@qwen-code/qwen-code" = "latest";
        "npm:opencode-ai" = "latest";
        "npm:@musistudio/claude-code-router" = "latest";
        "npm:@earendil-works/pi-coding-agent" = "latest";
        "npm:@playwright/cli" = "latest";
        "cargo:rtk-ai/rtk" = "latest";

        # Dev tools
        "npm:vercel" = "latest";
        "npm:eas-cli" = "latest";

        # Voice-to-text
        "cargo:https://github.com/peteonrails/voxtype" = {
          version = "tag:v0.6.0-rc.2";
          crate = "voxtype";
          features = "gpu-metal";
        };
      };
    };
  };

  # Zsh shell
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    # Run full `compinit` (security audit + dump rebuild) once per day;
    # skip audit with `-C` otherwise. Audit is the expensive part (~50ms);
    # `-C` drops it to ~10ms. Safe on nix-managed fpath (immutable store paths).
    # glob qualifier `(#qN.mh+24)` = regular file, mtime older than 24h, nullglob.
    completionInit = ''
      autoload -U compinit
      if [[ -n $HOME/.zcompdump(#qN.mh+24) ]]; then
        compinit
      else
        compinit -C
      fi
    '';

    autosuggestion = {
      enable = true;
      strategy = [
        "history"
        "completion"
      ];
    };
    syntaxHighlighting.enable = true;

    # Register zinit as an HM zsh plugin. HM sources it at mkOrder 900, before
    # user initContent (1200), so the turbo declarations below can call `zinit`.
    # nixpkgs lays zinit.zsh at share/zinit/ (not <name>.plugin.zsh) so `file`
    # must be set explicitly.
    plugins = [
      {
        name = "zinit";
        src = pkgs.zinit;
        file = "share/zinit/zinit.zsh";
      }
    ];

    history = {
      size = 100000;
      save = 100000;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      share = true;
      extended = true;
    };

    initContent =
      lib.mkMerge [
        # Hand off to fish as the INTERACTIVE shell while zsh stays the LOGIN
        # shell. This is the recommended macOS pattern: making fish the login
        # shell breaks home-manager env/module init on macOS (home-manager#6568)
        # and forces a fragile path_helper PATH workaround. Keeping zsh at the
        # login boundary means the POSIX + nix PATH bootstrap happens in zsh;
        # fish is exec'd NON-login and inherits a correct environment (so no
        # fish-side path_helper fix is needed). Runs first (mkBefore) so the
        # handoff skips zsh's compinit/turbo/prompt setup.
        #   - interactive-only guard (scripts never hand off)
        #   - skip if our parent is already fish, so `zsh` from within fish
        #     drops to a real zsh fallback (no exec loop)
        #   - macOS BSD `ps -o comm=` returns the full path → `*fish` glob
        #     (GNU `ps --format=comm` / procps does not work on Darwin)
        (lib.mkBefore ''
          [[ $- == *i* ]] || return
          if [[ $(ps -o comm= -p $PPID) != *fish ]]; then
            exec ${pkgs.fish}/bin/fish
          fi
        '')

        # Prepend completion cache dir to fpath BEFORE compinit (HM order 570),
        # so compinit autoloads _codex lazily. File is refreshed in activation
        # script, not at shell startup.
        (lib.mkOrder 560 ''
          fpath=($HOME/.cache/zsh/completions $fpath)
        '')

        # Upstream `try init` emits `/usr/bin/env ruby '.../.try-wrapped'`, which
        # resolves to macOS system ruby 2.6 and crashes on `Data.define`
        # (Ruby 3.2+). Redefine the function to call the makeBinaryWrapper
        # `try` binary directly so nix ruby is prefixed onto PATH.
        # Track upstream fix: https://github.com/tobi/try/issues/60
        # (also related: init_snippet hardcodes `/usr/bin/env ruby` in try.rb)
        (lib.mkAfter ''
          try() {
            local out
            out=$(${config.programs.try.package}/bin/try exec --path "${config.programs.try.path}" "$@" 2>/dev/tty)
            if [ $? -eq 0 ]; then
              eval "$out"
            else
              echo "$out"
            fi
          }
        '')

        (''
          # Starship prompt: source pre-generated init (saves fork+parse cost).
          if [[ $TERM != "dumb" ]]; then
            source ${starshipInitZsh}
          fi

          # ---- zinit turbo: defer tool init hooks until after first prompt ----
          # HM sources pkgs.zinit at order 900; this block runs at the default
          # order 1200. Pre-seed ZINIT[BIN_DIR] so zinit doesn't self-install.
          # ZINIT[HOME_DIR] stays on a writable path because turbo plugins (like
          # zdharma-continuum/null) get cloned there on first run.
          # ice flags:
          #   wait'0'   fire immediately after first prompt paints (async)
          #   lucid     suppress "Loaded ..." banner
          #   as"null"  host-only, no plugin code to source
          #   atload    run the eval AFTER the noop host loads (stable env)
          typeset -gA ZINIT
          ZINIT[HOME_DIR]="$HOME/.local/share/zinit"
          ZINIT[BIN_DIR]="${pkgs.zinit}/share/zinit"

          zinit ice wait'0' lucid as"null" atload'eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"'
          zinit light zdharma-continuum/null

          zinit ice wait'0' lucid as"null" atload'eval "$(${pkgs.direnv}/bin/direnv hook zsh)"'
          zinit light zdharma-continuum/null

          zinit ice wait'0' lucid as"null" atload'eval "$(${pkgs.mise}/bin/mise activate zsh)"'
          zinit light zdharma-continuum/null

          zinit ice wait'0' lucid as"null" atload'eval "$(${pkgs.fzf}/bin/fzf --zsh)"'
          zinit light zdharma-continuum/null

          # Handle SIGINT properly to prevent Starship "Exiting because of interrupt signal" spam
        # TRAPINT() {
        #   return $(( 128 + $1 ))
        # }

        # Claude with alternative model providers
        claude-deepseek() {
          ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic \
          ANTHROPIC_AUTH_TOKEN=$DEEPSEEK_API_KEY \
          ANTHROPIC_MODEL=deepseek-chat \
          ANTHROPIC_SMALL_FAST_MODEL=deepseek-chat \
          ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-chat \
          ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-reasoner \
          claude
        }

        claude-xai() {
          ANTHROPIC_BASE_URL=https://api.x.ai/ \
          ANTHROPIC_AUTH_TOKEN=$XAI_API_KEY \
          ANTHROPIC_MODEL=grok-code-fast-1 \
          ANTHROPIC_SMALL_FAST_MODEL=grok-code-fast-1 \
          ANTHROPIC_DEFAULT_SONNET_MODEL=grok-code-fast-1 \
          ANTHROPIC_DEFAULT_OPUS_MODEL=grok-4 \
          claude
        }

        claude-zai() {
          ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
          ANTHROPIC_AUTH_TOKEN=$Z_AI_API_KEY \
          ANTHROPIC_DEFAULT_SONNET_MODEL=GLM-4.7 \
          ANTHROPIC_DEFAULT_OPUS_MODEL=GLM-4.7 \
          ANTHROPIC_DEFAULT_HAIKU_MODEL=GLM-4.5-Air \
          claude
        }

        claude-qwen() {
          ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/api/v2/apps/claude-code-proxy \
          ANTHROPIC_AUTH_TOKEN=$QWEN_API_KEY \
          ANTHROPIC_MODEL=Qwen3-Coder-Plus \
          ANTHROPIC_SMALL_FAST_MODEL=Qwen-Plus \
          ANTHROPIC_DEFAULT_SONNET_MODEL=Qwen3-Coder-Plus \
          ANTHROPIC_DEFAULT_OPUS_MODEL=Qwen3-Max \
          claude
        }

        claude-fireworks() {
          ANTHROPIC_BASE_URL=https://api.fireworks.ai/inference \
          ANTHROPIC_AUTH_TOKEN=$FIREWORKS_API_KEY \
          ANTHROPIC_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
          ANTHROPIC_SMALL_FAST_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
          ANTHROPIC_DEFAULT_SONNET_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
          ANTHROPIC_DEFAULT_HAIKU_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
          ANTHROPIC_DEFAULT_OPUS_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
          claude
        }

        claude-kimi() {
          ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic \
          ANTHROPIC_AUTH_TOKEN=$MOONSHOT_API_KEY \
          ANTHROPIC_MODEL=kimi-k2-turbo-preview \
          ANTHROPIC_SMALL_FAST_MODEL=kimi-k2-turbo-preview \
          ANTHROPIC_DEFAULT_SONNET_MODEL=kimi-k2-turbo-preview \
          ANTHROPIC_DEFAULT_OPUS_MODEL=kimi-k2-turbo-preview \
          claude
        }

        claude-router() {
          ANTHROPIC_BASE_URL=http://127.0.0.1:8080 \
          claude
        }

        cproxy() {
          local u p url
          u=$(jq -sRr @uri <<<"$PROXY_USER")
          p=$(jq -sRr @uri <<<"$PROXY_PASS")
          url="https://$u:$p@$PROXY_HOST:$PROXY_PORT"
          CLAUDE_CODE_TMUX_TRUECOLOR=1 \
          HTTPS_PROXY="$url" \
            NO_PROXY="localhost,127.0.0.1,::1" \
            claude --dangerously-skip-permissions "$@"
        }

        claude-minimax() {
          ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic \
          CLAUDE_CODE_TMUX_TRUECOLOR=1 \
          ANTHROPIC_AUTH_TOKEN=$MINIMAX_API_KEY \
          ANTHROPIC_MODEL=MiniMax-M2.7 \
          ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 \
          ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 \
          ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 \
          ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 \
          API_TIMEOUT_MS=3000000 \
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
          CLAUDE_CODE_TELEMETRY=0 \
          claude --dangerously-skip-permissions
        }

        # Edit fuzzy-found file
        eff() { ''$EDITOR "''$(ff)"; }

        # Omarchy tmux dev layouts
        # tdl: 3-pane layout — editor (left), AI (right 30%), terminal (bottom 15%)
        # Usage: tdl <cx|claude|codex> [<second_ai>]
        tdl() {
          [[ -z ''$1 ]] && { echo "Usage: tdl <cx|claude|codex|other_ai> [<second_ai>]"; return 1; }
          [[ -z ''$TMUX ]] && { echo "You must start tmux to use tdl."; return 1; }

          local current_dir="''$PWD"
          local editor_pane ai_pane ai2_pane
          local ai="''$1"
          local ai2="''$2"

          editor_pane="''$TMUX_PANE"
          tmux rename-window -t "''$editor_pane" "''$(basename "''$current_dir")"
          tmux split-window -v -p 15 -t "''$editor_pane" -c "''$current_dir"
          ai_pane=''$(tmux split-window -h -p 30 -t "''$editor_pane" -c "''$current_dir" -P -F '#{pane_id}')
          if [[ -n ''$ai2 ]]; then
            ai2_pane=''$(tmux split-window -v -t "''$ai_pane" -c "''$current_dir" -P -F '#{pane_id}')
            tmux send-keys -t "''$ai2_pane" "''$ai2" C-m
          fi
          tmux send-keys -t "''$ai_pane" "''$ai" C-m
          tmux send-keys -t "''$editor_pane" "''$EDITOR ." C-m
          tmux select-pane -t "''$editor_pane"
        }

        # tdlm: one tdl window per subdirectory (monorepo mode)
        # Usage: tdlm <cx|claude|codex> [<second_ai>]
        tdlm() {
          [[ -z ''$1 ]] && { echo "Usage: tdlm <cx|claude|codex|other_ai> [<second_ai>]"; return 1; }
          [[ -z ''$TMUX ]] && { echo "You must start tmux to use tdlm."; return 1; }

          local ai="''$1"
          local ai2="''$2"
          local base_dir="''$PWD"
          local first=true

          tmux rename-session "''$(basename "''$base_dir" | tr '.:' '--')"

          for dir in "''$base_dir"/*/; do
            [[ -d ''$dir ]] || continue
            local dirpath="''${dir%/}"
            if ''$first; then
              tmux send-keys -t "''$TMUX_PANE" "cd '''$dirpath' && tdl ''$ai ''$ai2" C-m
              first=false
            else
              local pane_id=''$(tmux new-window -c "''$dirpath" -P -F '#{pane_id}')
              tmux send-keys -t "''$pane_id" "tdl ''$ai ''$ai2" C-m
            fi
          done
        }

        # tsl: swarm layout — N panes tiled, all running the same command
        # Usage: tsl <pane_count> <command>
        tsl() {
          [[ -z ''$1 || -z ''$2 ]] && { echo "Usage: tsl <pane_count> <command>"; return 1; }
          [[ -z ''$TMUX ]] && { echo "You must start tmux to use tsl."; return 1; }

          local count="''$1"
          local cmd="''$2"
          local current_dir="''$PWD"
          local -a panes

          tmux rename-window -t "''$TMUX_PANE" "''$(basename "''$current_dir")"
          panes+=("''$TMUX_PANE")
          while (( ''${#panes[@]} < count )); do
            local new_pane
            local split_target="''${panes[-1]}"
            new_pane=''$(tmux split-window -h -t "''$split_target" -c "''$current_dir" -P -F '#{pane_id}')
            panes+=("''$new_pane")
            tmux select-layout -t "''${panes[0]}" tiled
          done
          for pane in "''${panes[@]}"; do
            tmux send-keys -t "''$pane" "''$cmd" C-m
          done
          tmux select-pane -t "''${panes[0]}"
        }

        # Git push current branch with force-with-lease
        gpb() {
          git push origin "$(git rev-parse --abbrev-ref HEAD)" --force-with-lease -u
        }

        # Load API keys from sops-nix (single rendered dotenv, ~140ms saved vs per-key cat loop)
        [[ -o interactive && -f "${config.sops.templates."api-keys.env".path}" ]] && \
          source "${config.sops.templates."api-keys.env".path}"
        '')
      ];
  };

  # ===========================================================================
  # Fish — primary interactive shell (zsh above is kept as a working fallback).
  # System-level fish (configuration.nix) installs the binary and wires nixpkgs
  # vendor completions; this block is the per-user config. The default login
  # shell is switched with a one-time `chsh -s /run/current-system/sw/bin/fish`
  # (nix-darwin cannot set the macOS login shell declaratively).
  #
  # No zinit-style turbo here: fish has no native deferral and doesn't need it
  # (bare fish ~10ms; all hooks eager ~100ms — vs zsh's ~2000ms compinit that
  # turbo targeted). Integrations load eagerly via each program's
  # enableFishIntegration (default true once fish is enabled), except starship
  # which we pre-generate (see starshipInitFish) and source directly.
  # ===========================================================================
  programs.fish = {
    enable = true;

    # Skip man-page-derived completion generation for every home.packages entry
    # (pulls in python3 and forces programs.man.generateCaches → slow rebuilds).
    # fish built-ins + nixpkgs vendor completions already cover our tools.
    generateCompletions = false;

    # Git shortcuts as abbreviations: expand inline to the real command on the
    # command line (history stores the expansion). The other 23 aliases carry
    # over from home.shellAliases automatically (home-manager mirrors them).
    shellAbbrs = {
      g = "git";
      gcm = "git commit -m";
      gcam = "git commit -a -m";
      gcad = "git commit -a --amend";
    };

    # Drop those 4 from fish's auto-populated alias set so they don't duplicate
    # the abbreviations above. zsh keeps them as aliases (home.shellAliases is
    # untouched). home-manager assigns programs.fish.shellAliases directly, so
    # mkForce is required to override.
    shellAliases = lib.mkForce (
      removeAttrs config.home.shellAliases [
        "g"
        "gcm"
        "gcam"
        "gcad"
      ]
    );

    # No loginShellInit: fish is launched NON-login from zsh (see programs.zsh
    # initContent), so macOS path_helper (__fish_macos_set_env) never runs and
    # fish inherits zsh's already-correct nix PATH — no PATH workaround needed.

    # Runs inside `status is-interactive` (home-manager wraps it).
    interactiveShellInit = ''
      # Disable the default "Welcome to fish…" greeting. home-manager has no
      # dedicated option; the documented way is to set the variable empty (the
      # default fish_greeting function does `test -n "$fish_greeting"; and echo`,
      # so an empty value prints nothing — verified, no leftover blank line).
      set -g fish_greeting

      # Syntax-highlighting palette for the active theme (gruvbox). The
      # documented way to theme fish from config is `set -g fish_color_*` here;
      # fish sources config.fish after conf.d, so this overrides the legacy
      # ~/.config/fish/conf.d/fish_frozen_theme.fish if it ever reappears.
      ${fishThemeInit}

      # Load API keys from sops-nix (fish-syntax template — sourced natively).
      test -f "${config.sops.templates."api-keys.fish".path}"; and source "${config.sops.templates."api-keys.fish".path}"
    '';

    # Custom functions (autoloaded lazily from ~/.config/fish/functions/).
    # Each body is fish_indent-validated at build time, so a syntax error here
    # fails `darwin-rebuild` rather than producing a broken shell.
    functions = {
      # ---- Claude with alternative model providers ----
      # fish ≥3.2 supports the `VAR=val cmd` prefix; fish is 4.7.1 here.
      claude-deepseek = ''
        ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic \
        ANTHROPIC_AUTH_TOKEN=$DEEPSEEK_API_KEY \
        ANTHROPIC_MODEL=deepseek-chat \
        ANTHROPIC_SMALL_FAST_MODEL=deepseek-chat \
        ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-chat \
        ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-reasoner \
        claude
      '';

      claude-xai = ''
        ANTHROPIC_BASE_URL=https://api.x.ai/ \
        ANTHROPIC_AUTH_TOKEN=$XAI_API_KEY \
        ANTHROPIC_MODEL=grok-code-fast-1 \
        ANTHROPIC_SMALL_FAST_MODEL=grok-code-fast-1 \
        ANTHROPIC_DEFAULT_SONNET_MODEL=grok-code-fast-1 \
        ANTHROPIC_DEFAULT_OPUS_MODEL=grok-4 \
        claude
      '';

      claude-zai = ''
        ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
        ANTHROPIC_AUTH_TOKEN=$Z_AI_API_KEY \
        ANTHROPIC_DEFAULT_SONNET_MODEL=GLM-4.7 \
        ANTHROPIC_DEFAULT_OPUS_MODEL=GLM-4.7 \
        ANTHROPIC_DEFAULT_HAIKU_MODEL=GLM-4.5-Air \
        claude
      '';

      claude-qwen = ''
        ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/api/v2/apps/claude-code-proxy \
        ANTHROPIC_AUTH_TOKEN=$QWEN_API_KEY \
        ANTHROPIC_MODEL=Qwen3-Coder-Plus \
        ANTHROPIC_SMALL_FAST_MODEL=Qwen-Plus \
        ANTHROPIC_DEFAULT_SONNET_MODEL=Qwen3-Coder-Plus \
        ANTHROPIC_DEFAULT_OPUS_MODEL=Qwen3-Max \
        claude
      '';

      claude-fireworks = ''
        ANTHROPIC_BASE_URL=https://api.fireworks.ai/inference \
        ANTHROPIC_AUTH_TOKEN=$FIREWORKS_API_KEY \
        ANTHROPIC_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
        ANTHROPIC_SMALL_FAST_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
        ANTHROPIC_DEFAULT_SONNET_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
        ANTHROPIC_DEFAULT_HAIKU_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
        ANTHROPIC_DEFAULT_OPUS_MODEL=accounts/fireworks/routers/kimi-k2p5-turbo \
        claude
      '';

      claude-kimi = ''
        ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic \
        ANTHROPIC_AUTH_TOKEN=$MOONSHOT_API_KEY \
        ANTHROPIC_MODEL=kimi-k2-turbo-preview \
        ANTHROPIC_SMALL_FAST_MODEL=kimi-k2-turbo-preview \
        ANTHROPIC_DEFAULT_SONNET_MODEL=kimi-k2-turbo-preview \
        ANTHROPIC_DEFAULT_OPUS_MODEL=kimi-k2-turbo-preview \
        claude
      '';

      claude-router = ''
        ANTHROPIC_BASE_URL=http://127.0.0.1:8080 \
        claude
      '';

      claude-minimax = ''
        ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic \
        CLAUDE_CODE_TMUX_TRUECOLOR=1 \
        ANTHROPIC_AUTH_TOKEN=$MINIMAX_API_KEY \
        ANTHROPIC_MODEL=MiniMax-M2.7 \
        ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 \
        ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 \
        ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 \
        ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 \
        API_TIMEOUT_MS=3000000 \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        CLAUDE_CODE_TELEMETRY=0 \
        claude --dangerously-skip-permissions
      '';

      # Claude through the corporate HTTPS proxy. Here-string `<<<` → pipe;
      # keep jq @uri (RFC-3986) for credential encoding rather than fish's
      # string escape --style=url (char set not byte-equivalent).
      cproxy = ''
        set -l u (printf %s "$PROXY_USER" | jq -sRr @uri)
        set -l p (printf %s "$PROXY_PASS" | jq -sRr @uri)
        set -l url "https://$u:$p@$PROXY_HOST:$PROXY_PORT"
        CLAUDE_CODE_TMUX_TRUECOLOR=1 \
        HTTPS_PROXY="$url" \
        NO_PROXY="localhost,127.0.0.1,::1" \
        claude --dangerously-skip-permissions $argv
      '';

      # Edit fuzzy-found file (ff alias carries over from home.shellAliases).
      eff = ''$EDITOR (ff)'';

      # Git push current branch with force-with-lease.
      gpb = ''git push origin (git rev-parse --abbrev-ref HEAD) --force-with-lease -u'';

      # Omarchy tmux dev layouts.
      # tdl: 3-pane layout — editor (left), AI (right 30%), terminal (bottom 15%).
      # Usage: tdl <cx|claude|codex> [<second_ai>]
      tdl = ''
        if test -z "$argv[1]"
            echo "Usage: tdl <cx|claude|codex|other_ai> [<second_ai>]"
            return 1
        end
        if not set -q TMUX
            echo "You must start tmux to use tdl."
            return 1
        end

        set -l current_dir $PWD
        set -l ai $argv[1]
        set -l ai2 $argv[2]

        set -l editor_pane $TMUX_PANE
        tmux rename-window -t "$editor_pane" (basename "$current_dir")
        tmux split-window -v -p 15 -t "$editor_pane" -c "$current_dir"
        set -l ai_pane (tmux split-window -h -p 30 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
        if test -n "$ai2"
            set -l ai2_pane (tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')
            tmux send-keys -t "$ai2_pane" "$ai2" C-m
        end
        tmux send-keys -t "$ai_pane" "$ai" C-m
        tmux send-keys -t "$editor_pane" "$EDITOR ." C-m
        tmux select-pane -t "$editor_pane"
      '';

      # tdlm: one tdl window per subdirectory (monorepo mode).
      # Usage: tdlm <cx|claude|codex> [<second_ai>]
      tdlm = ''
        if test -z "$argv[1]"
            echo "Usage: tdlm <cx|claude|codex|other_ai> [<second_ai>]"
            return 1
        end
        if not set -q TMUX
            echo "You must start tmux to use tdlm."
            return 1
        end

        set -l ai $argv[1]
        set -l ai2 $argv[2]
        set -l base_dir $PWD
        set -l first true

        tmux rename-session (basename "$base_dir" | tr '.:' '--')

        for dir in $base_dir/*/
            test -d "$dir"; or continue
            set -l dirpath (string trim --right --chars=/ "$dir")
            if test "$first" = true
                tmux send-keys -t "$TMUX_PANE" "cd '$dirpath' && tdl $ai $ai2" C-m
                set first false
            else
                set -l pane_id (tmux new-window -c "$dirpath" -P -F '#{pane_id}')
                tmux send-keys -t "$pane_id" "tdl $ai $ai2" C-m
            end
        end
      '';

      # tsl: swarm layout — N panes tiled, all running the same command.
      # Usage: tsl <pane_count> <command>
      tsl = ''
        if test -z "$argv[1]" -o -z "$argv[2]"
            echo "Usage: tsl <pane_count> <command>"
            return 1
        end
        if not set -q TMUX
            echo "You must start tmux to use tsl."
            return 1
        end

        set -l count $argv[1]
        set -l cmd $argv[2]
        set -l current_dir $PWD
        set -l panes

        tmux rename-window -t "$TMUX_PANE" (basename "$current_dir")
        set -a panes $TMUX_PANE
        while test (count $panes) -lt $count
            set -l split_target $panes[-1]
            set -l new_pane (tmux split-window -h -t "$split_target" -c "$current_dir" -P -F '#{pane_id}')
            set -a panes $new_pane
            tmux select-layout -t $panes[1] tiled
        end
        for pane in $panes
            tmux send-keys -t "$pane" "$cmd" C-m
        end
        tmux select-pane -t $panes[1]
      '';

      # try: call the makeBinaryWrapper binary directly so nix ruby is used (not
      # macOS system ruby 2.6, which crashes on Data.define); `try init` instead
      # hardcodes `/usr/bin/env ruby`. Otherwise this is exactly what `try init`
      # emits for fish. The `| string collect` + `$pipestatus[1]` are
      # load-bearing: `try exec` prints a MULTI-LINE `mkdir -p …` + `cd …` script
      # when creating a new dir, so its output must stay a SINGLE string. A bare
      # `(...)` capture splits on newlines and `eval` then space-joins the parts
      # into `mkdir -p … cd …` — which makes a junk `cd/` dir and never cd's (the
      # "new folders don't work" bug). `string collect` keeps it one string;
      # pipestatus[1] is try's exit (plain $status would be string collect's).
      try = ''
        set -l out (${config.programs.try.package}/bin/try exec --path "${config.programs.try.path}" $argv 2>/dev/tty | string collect)
        if test $pipestatus[1] -eq 0
            eval $out
        else
            echo $out
        end
      '';
    };
  };

  # SSH control socket directory: 0700 perms (sshd refuses sockets in
  # group/world-writable dirs), and sweep any sockets whose master process is
  # gone so the "ControlSocket … already exists, disabling multiplexing"
  # warning self-heals on each rebuild. Also migrate sockets from the old
  # ~/.ssh/control-* layout.
  home.activation.sshSockets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.ssh/sockets"
    chmod 700 "$HOME/.ssh/sockets"
    rm -f "$HOME"/.ssh/control-*
    for sock in "$HOME"/.ssh/sockets/*; do
      [ -S "$sock" ] || continue
      /usr/sbin/lsof -- "$sock" >/dev/null 2>&1 || rm -f "$sock"
    done
  '';

  # Regenerate codex zsh completion only when mise shim changes.
  # File lands in ~/.cache/zsh/completions and is picked up by compinit via
  # fpath (see programs.zsh.initContent mkOrder 560 above).
  home.activation.codexCompletion = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    shim="$HOME/.local/share/mise/shims/codex"
    out="$HOME/.cache/zsh/completions/_codex"
    if [ -x "$shim" ] && { [ ! -f "$out" ] || [ "$shim" -nt "$out" ]; }; then
      mkdir -p "$(dirname "$out")"
      "$shim" completion zsh > "$out"
    fi
  '';

  # Same for fish — lands in ~/.config/fish/completions/, which fish autoloads.
  # Pass `fish` explicitly (codex has defaulted to bash without it: codex#3009).
  home.activation.codexCompletionFish = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    shim="$HOME/.local/share/mise/shims/codex"
    out="$HOME/.config/fish/completions/codex.fish"
    if [ -x "$shim" ] && { [ ! -f "$out" ] || [ "$shim" -nt "$out" ]; }; then
      mkdir -p "$(dirname "$out")"
      "$shim" completion fish > "$out"
    fi
  '';

  # Bash shell (minimal — zsh is primary)
  programs.bash = {
    enable = true;
    initExtra = ''
      export VOLTA_HOME="$HOME/.volta"
      export PATH="$VOLTA_HOME/bin:$PATH"
      export PATH="$PATH:$HOME/.maestro/bin"
    '';
  };

  # Starship prompt. zsh integration disabled — we source the pre-generated init
  # file (starshipInitZsh) directly to avoid the per-shell `starship init` fork.
  # fish uses the official `starship init fish | source` integration: upstream
  # keeps the two-stage `--print-full-init | psub` init (starship#2637, still
  # open), so it forks starship twice per shell (~15-30ms) — acceptable here.
  programs.starship = {
    enable = true;
    enableZshIntegration = false;
    enableFishIntegration = true;
    settings = {
      command_timeout = 200;
      add_newline = false;
      format = "$directory$git_branch$git_state$git_status$cmd_duration$line_break$character";
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
      git_branch = {
        format = "[$branch]($style) ";
        style = "bold ${theme.starship.branch}";
      };
      git_status = {
        format = "[$all_status$ahead_behind]($style) ";
        style = "bold ${theme.starship.dirty}";
      };
      character = {
        success_symbol = "[❯](bold ${theme.starship.ok})";
        error_symbol = "[❯](bold ${theme.starship.err})";
      };
      cmd_duration = {
        min_time = 2000;
        format = "[$duration]($style) ";
        style = "bold ${theme.starship.duration}";
      };
    };
  };

  # Zoxide (smart cd)
  programs.zoxide = {
    enable = true;
    enableZshIntegration = false; # zsh: loaded via zinit turbo
    enableFishIntegration = true; # fish: native eager init (--on-variable PWD)
  };

  # FZF (fuzzy finder)
  programs.fzf = {
    enable = true;
    enableZshIntegration = false; # zsh: loaded via zinit turbo
    enableFishIntegration = true; # fish: built-in `fzf --fish` (CTRL-T/R, ALT-C)
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
    ];
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetOptions = [ "--preview 'bat --style=numbers --color=always --line-range :500 {}'" ];
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
    changeDirWidgetOptions = [ "--preview 'eza --tree --level=2 --icons --color=always {}'" ];
  };

  # Fd (modern find)
  programs.fd = {
    enable = true;
    hidden = true;
    ignores = [
      ".git/"
      ".direnv/"
      ".devenv/"
      "node_modules/"
      ".next/"
      "target/"
    ];
  };

  # Ripgrep (modern grep)
  programs.ripgrep = {
    enable = true;
    arguments = [
      "--smart-case"
      "--hidden"
      "--glob=!.git/"
      "--glob=!.direnv/"
      "--glob=!.devenv/"
      "--glob=!node_modules/"
    ];
  };

  # Git
  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = "openpgp";
    ignores = [
      # System / editor
      ".DS_Store"
      "*.swp"
      "*~"

      # Nix / devenv
      ".direnv/"
      ".devenv*"
      "devenv*"
      "devenv.lock"
      "devenv.local.nix"
      ".envrc"
      "shell.nix"

      # Node
      "node_modules/"

      # Environment
      ".env.local"
      ".env.production"
      ".env.preview"
      "*.local.*"

      # AI tools
      ".aider*"
      ".mcp.json*"
      ".cursor/"
      ".kilocode/"
      ".roo/"
      ".rooignore"
      ".roomodes"
      ".serena/"
      ".opencode/"
      "opencode.json"
      "forge.yaml"
      "context_portal/"
      "memory-bank/"
      ".memory-bank/"
      ".taskmaster/"
      "plans"
      "projectBrief.md"
      "tmp_code_*"

      # Ruby
      ".ruby-gemset"
      ".gems"
      ".yardoc/"
      ".solargraph.yml"
      ".irb_history"
      ".irbrc"

      # Misc project
      "/tags/"
      ".graphqlconfig"
      ".doc"
      "doc"
      ".duderc.yml"
      "docker-compose.override.yml"
      "local/"
      "coverage/"
      ".ignore"
      ".ripgreprc"
      "mise.local.toml"
      "*_cache*.json"
    ];
    settings = {
      user = {
        name = "Nick Pupko";
        email = "work.pupko@gmail.com";
        # Signing subkey of primary B16BCB35D0D578EBA7F30282D8F94441802E8AE2.
        # Primary is Certify-only and lives in 1Password (offline-primary
        # pattern); only the signing subkey's secret is on this laptop.
        # Trailing `!` forces gpg to use exactly this subkey (no fallback).
        # Renews 2027-05-25; pull primary from 1Password to mint a new subkey.
        signingkey = "81A700F2DD12DA8D!";
      };
      commit = {
        gpgsign = true;
        verbose = true;
      };
      gpg.program = "gpg";
      tag.gpgSign = true;
      init.defaultBranch = "main";
      pull.rebase = true;
      push = {
        autoSetupRemote = true;
        default = "current";
        followTags = true;
        useForceIfIncludes = true;
      };
      rebase = {
        autoSquash = true;
        autoStash = true;
        updateRefs = true;
        missingCommitsCheck = "error";
      };
      merge.conflictstyle = "zdiff3";
      mergetool = {
        path = "nvim";
        keepBackup = false;
      };
      diff = {
        algorithm = "histogram";
        colorMoved = "plain";
        mnemonicPrefix = true;
        renames = true;
      };
      color.ui = "auto";
      rerere = {
        enabled = true;
        autoUpdate = true;
      };
      column.ui = "auto";
      branch.sort = "-committerdate";
      tag.sort = "version:refname";
      help.autocorrect = "prompt";
      fetch = {
        prune = true;
        pruneTags = true;
        writeCommitGraph = true;
      };
      transfer.fsckObjects = true;
      github.user = "npupko";
      coderabbit.machineId = "cli/7a1cbaf57305471189ef9d0275574e79";
      # Performance (git 2.37+)
      feature.manyFiles = true;
      core.fsmonitor = true;
      core.untrackedCache = true;
      checkout.workers = 0;
      alias = {
        st = "status -sb";
        co = "checkout";
        ci = "commit";
        br = "branch";
        lg = "log --oneline --graph --decorate --all";
        amend = "commit --amend --no-edit";
        update = "commit --amend --no-edit";
      };
    };
  };

  # Delta (git diff pager)
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
      syntax-theme = theme.delta;
    };
  };

  # Ghostty terminal (installed via Homebrew cask)
  programs.ghostty = {
    enable = true;
    package = null;
    enableZshIntegration = true;
    enableFishIntegration = true;
    installBatSyntax = false;
    settings = {
      font-size = 13;
      font-thicken = true;
      theme = theme.ghostty;
      bell-features = "title,attention,audio,system";
      font-family = [
        "JetBrains Mono"
        "Fira Code"
        "Symbols Nerd Font Mono"
        "STIX Two Math"
        "Noto Sans Symbols 2"
        "Apple Color Emoji"
      ];
      clipboard-paste-protection = false;
      desktop-notifications = true;
      window-decoration = true;
      background-opacity = 1;
      background-blur-radius = 0;
      cursor-style = "block";
      shell-integration-features = "no-cursor";
      adjust-cell-height = "20%";
      adjust-cursor-height = "20%";
      macos-option-as-alt = "left";
      keybind = [
        "global:cmd+grave_accent=toggle_quick_terminal"
        # "shift+enter=text:\\n"
        "super+r=reload_config"
      ];
      window-save-state = "always";
      mouse-scroll-multiplier = 0.95;
      tab-inherit-working-directory = true;
      split-inherit-working-directory = true;
      notify-on-command-finish = "unfocused";
      notify-on-command-finish-action = "notify";
      notify-on-command-finish-after = "30s";
    };
  };

  # Eza (modern ls)
  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
    git = true;
    extraOptions = [
      "--group-directories-first"
      "--header"
    ];
  };

  # Bat (modern cat)
  programs.bat = {
    enable = true;
    config = {
      theme = theme.bat;
      style = "numbers,changes,header";
    };
  };

  # Alacritty terminal
  programs.alacritty = {
    enable = true;
    theme = theme.alacritty;
    settings = {
      env.TERM = "xterm-256color";
      terminal.osc52 = "CopyPaste";
      bell.command = {
        program = "osascript";
        args = [
          "-e"
          ''display notification "Task complete" with title "Alacritty"''
        ];
      };
      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Italic";
        };
        size = 13;
        offset.y = 4;
      };
      window = {
        decorations = "Full";
        option_as_alt = "OnlyLeft";
      };
      keyboard.bindings = [
        {
          key = "Return";
          mods = "Shift";
          chars = "\\x1b\\r";
        }
      ];
    };
  };

  # Btop (system monitor)
  programs.btop = {
    enable = true;
    settings = {
      color_theme = theme.btop;
      theme_background = false;
      vim_keys = true;
    };
  };

  # GitHub CLI
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      editor = "nvim";
    };
    gitCredentialHelper.enable = true;
  };

  # Tmux
  programs.tmux = {
    enable = true;
    prefix = "C-a";
    escapeTime = 0;
    historyLimit = 50000;
    mouse = true;
    focusEvents = true;
    baseIndex = 1;
    terminal = "xterm-ghostty";
    # plugins = with pkgs; [
    #   {
    #     plugin = tmuxPlugins.gruvbox;
    #     extraConfig = "set -g @tmux-gruvbox 'dark'";
    #   }
    # ];
    # zsh is the login shell; its initContent execs fish. tmux panes therefore
    # launch zsh (which hands off to fish), keeping one uniform path to fish.
    shell = "${pkgs.zsh}/bin/zsh";
    extraConfig = builtins.readFile ./dotfiles/.tmux.conf + ''

      # Theme (generated)
      set -g status-style "bg=default,fg=default"
      set -g status-left "#[fg=black,bg=${theme.tmux.accent},bold] #S #[bg=default] "
      set -g status-right "#{E:@voxtype} #[fg=${theme.tmux.accent}]#{?pane_in_mode,COPY ,}#{?client_prefix,PREFIX ,}#{?window_zoomed_flag,ZOOM ,}#[fg=brightblack]#h "
      ${ccWindowFormats}
      set -g pane-border-style "fg=brightblack"
      set -g pane-active-border-style "fg=${theme.tmux.accent}"
      ${ccPaneBorders}
      set -g message-style "bg=default,fg=${theme.tmux.accent}"
      set -g message-command-style "bg=default,fg=${theme.tmux.accent}"
      set -g mode-style "bg=${theme.tmux.accent},fg=black"
      # set -g extended-keys on
      set -s extended-keys on
      set -s extended-keys-format csi-u
      # set -as terminal-features 'xterm*:extkeys'

      setw -g clock-mode-colour ${theme.tmux.accent}
      unbind -T root MouseDrag1Border
    '';
  };

  # Direnv with nix-direnv
  programs.direnv = {
    enable = true;
    enableZshIntegration = false; # zsh: loaded via zinit turbo
    enableFishIntegration = true; # fish: native `direnv hook fish` (silent/nix-direnv are shell-agnostic)
    nix-direnv.enable = true;
    silent = true;
  };

  # SSH agent (auto-start via launchd on macOS)
  services.ssh-agent = {
    enable = true;
  };

  # SSH client configuration
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "*" = {
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
        SetEnv = { TERM = "xterm-256color"; };
        ControlMaster = "auto";
        # %C = SHA1(%l%h%p%r). Subdir (0700, see home.activation.sshSockets)
        # keeps ~/.ssh/ uncluttered; ~/.ssh/ (not /tmp) because anyone who can
        # read/write a live control socket can hijack the session without
        # re-auth, so the path must not be publicly accessible.
        ControlPath = "~/.ssh/sockets/%C";
        ControlPersist = "10m";
      };
      "bitbucket-fleetrover" = {
        HostName = "bitbucket.org";
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519_fleetrover";
        IdentitiesOnly = true;
        WarnWeakCrypto = "no";
      };
    };
  };

  # sops-nix secrets configuration (using age - recommended for macOS).
  # Format kept as yaml: sops-nix only supports per-key extract on yaml/json
  # (dotenv/ini return whole file per secret — unusable with `sops.placeholder`).
  sops = {
    defaultSopsFile = ./secrets.yaml;

    # Fix PATH for launchd agent to find getconf (needed for DARWIN_USER_TEMP_DIR)
    environment.PATH = lib.mkForce "/usr/bin:/bin:/usr/sbin:/sbin";

    # Use dedicated age key file
    age.keyFile = "/Users/${username}/.config/sops/age/keys.txt";

    # Consolidated dotenv file rendered at activation — single file shell sources
    # once at startup instead of one `cat` per key. Values single-quoted (safe:
    # current values contain no single quotes). Used by zsh/bash.
    templates."api-keys.env".content = lib.concatMapStrings (name: ''
      export ${name}='${config.sops.placeholder.${name}}'
    '') (lib.attrNames config.sops.secrets);

    # Same secrets, fish syntax — fish cannot source the bash-style file above.
    # Sourced from programs.fish.interactiveShellInit. Same single-quote safety.
    templates."api-keys.fish".content = lib.concatMapStrings (name: ''
      set -gx ${name} '${config.sops.placeholder.${name}}'
    '') (lib.attrNames config.sops.secrets);

    # Individual secrets - each becomes a file
    secrets = lib.genAttrs [
      # AI/LLM providers
      "OPENAI_API_KEY"
      "DEEPSEEK_API_KEY"
      "XAI_API_KEY"
      "QWEN_API_KEY"
      "MOONSHOT_API_KEY"
      "Z_AI_API_KEY"
      "MINIMAX_API_KEY"
      "GEMINI_API_KEY"
      "CEREBRAS_API_KEY"

      # AI routing & proxying
      "OPENROUTER_API_KEY"
      "TMUXAI_OPENROUTER_API_KEY"
      "COPILOT_PROXY_URL"
      "REF_API_KEY"
      "REQUESTY_API_KEY"
      "WANDB_API_KEY"

      # Search & research
      "TAVILY_API_KEY"
      "BRAVE_API_KEY"
      "FIRECRAWL_API_KEY"
      "VOYAGE_API_KEY"
      "COHERE_API_KEY"

      # Dev tools & services
      "GITHUB_READ_ONLY_PAT"
      "LINEAR_API_KEY"
      "SENTRY_API_KEY"
      "HF_TOKEN"
      "HARVEST_TOKEN"
      "TRELLO_API_KEY"
      "TRELLO_API_TOKEN"
      "ONKERNEL_API_KEY"

      # Other APIs
      "GOOGLE_PLACES_API_KEY"
      "ELEVENLABS_API_KEY"
      "CIVITAI_API_KEY"
      "FIREWORKS_API_KEY"
      "PARALLEL_API_KEY"
      "STITCH_API_KEY"

      # Corporate HTTPS proxy
      "PROXY_HOST"
      "PROXY_PORT"
      "PROXY_USER"
      "PROXY_PASS"

      "SOLIDTIME_PI5_API_KEY"
    ] (_: { });
  };

  # Dotfiles
  home.file = {
    ".config/jj/config.toml".source = ./dotfiles/jj/config.toml;
    ".config/zellij/config.kdl".text = builtins.replaceStrings [ "@THEME@" ] [ theme.zellij ] (
      builtins.readFile ./dotfiles/zellij/config.kdl
    );
    ".config/theme/current".text = theme.neovim;
    # glow: custom gruvbox glamour styles + config pointing at the active one.
    # Both JSONs are always installed so glowStyle resolves regardless of theme.
    ".config/glow/gruvbox-dark.json".source = ./dotfiles/glow/gruvbox-dark.json;
    ".config/glow/gruvbox-light.json".source = ./dotfiles/glow/gruvbox-light.json;
    ".config/glow/glow.yml".text = ''
      style: "${glowStyle}"
    '';
    ".aider.conf.yml".source = ./dotfiles/aider.conf.yml;
    ".local/bin/workspace-up" = {
      source = ./dotfiles/bin/workspace-up;
      executable = true;
    };
    ".local/bin/workspace-down" = {
      source = ./dotfiles/bin/workspace-down;
      executable = true;
    };
    ".local/bin/voxtype-tmux" = {
      source = ./dotfiles/bin/voxtype-tmux;
      executable = true;
    };
    ".local/bin/claude-tmux-status" = {
      source = ./dotfiles/bin/claude-tmux-status;
      executable = true;
    };
  };
}
