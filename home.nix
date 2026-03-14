# =============================================================================
# PACKAGE MANAGEMENT STRATEGY
# =============================================================================
# Nix (home.packages):  CLI tools, system utilities, fonts, stable software
# Nix (pkgs-unstable):  Fast-moving tools where nixpkgs-stable is too old
# Homebrew brews:       macOS-specific, not in nixpkgs, or need latest versions
# Homebrew casks:       GUI applications
# Mise:                 Language runtimes + npm/node CLI tools (always latest)
# Self-managed:         Claude Code (auto-updates via native installer)
# =============================================================================
{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  username,
  ...
}:
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  home.stateVersion = "24.11";

  # Disable manual generation to avoid builtins.toFile warning (home-manager #7935)
  manual.manpages.enable = false;
  manual.html.enable = false;
  manual.json.enable = false;

  # Packages (review and uncomment as needed)
  home.packages = with pkgs; [
    # Core Dev Tools
    uv
    eza
    bat

    # Editors
    pkgs-unstable.helix
    pkgs-unstable.neovim
    markdown-oxide

    # Cloud/Infra
    terraform
    opentofu
    awscli2
    kubectl
    ngrok

    # VCS & CLI
    gh
    git-lfs
    delta
    fd
    ripgrep
    curl
    wget
    htop
    doctl

    # Shell & Terminal
    zellij
    ugrep

    # AI Tools
    # aichat
    # argc
    tabby

    # Fonts
    jetbrains-mono
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    fira-code

    # System utilities
    gnupg
    gnused
    coreutils
    automake
    bash
    libffi
    postgresql
    pkg-config
    ffmpeg
    nh
    devenv
    pinentry_mac
    sops
    _1password-cli
    cloudflared
    kubectx
  ];

  # Session variables
  home.sessionVariables = {
    EDITOR = "nvim";
    JJ_CONFIG = "/Users/${username}/.config/jj/config.toml";
    SOPS_AGE_KEY_FILE = "/Users/${username}/.config/sops/age/keys.txt";
    DEVENV_NIX = "/nix/var/nix/profiles/default";
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
    dr = "ulimit -n 10240 && sudo darwin-rebuild switch";
    du = "ulimit -n 10240 && nix flake update --flake /etc/nix-darwin/";
    dcd = "cd /etc/nix-darwin/";
    chrome_debug = "open -na \"Google Chrome\" --args --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-debug --no-first-run --no-default-browser-check";
    ghostty = "/Applications/Ghostty.app/Contents/MacOS/ghostty";
    fix-ssh = "launchctl kickstart -k gui/$(id -u)/org.nix-community.home.ssh-agent";
    grep = "ug";
    c = "claude --dangerously-skip-permissions";
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

    # Claude with alternative model providers
    # claude-deepseek = "ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic ANTHROPIC_AUTH_TOKEN=\${DEEPSEEK_API_KEY} ANTHROPIC_MODEL=deepseek-chat ANTHROPIC_SMALL_FAST_MODEL=deepseek-chat ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-chat ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-reasoner claude";
    # claude-xai = "ANTHROPIC_BASE_URL=https://api.x.ai/ ANTHROPIC_AUTH_TOKEN=\${XAI_API_KEY} ANTHROPIC_MODEL=grok-code-fast-1 ANTHROPIC_SMALL_FAST_MODEL=grok-code-fast-1 ANTHROPIC_DEFAULT_SONNET_MODEL=grok-code-fast-1 ANTHROPIC_DEFAULT_OPUS_MODEL=grok-4 claude";
    # claude-zai = "ANTHROPIC_AUTH_TOKEN=\${Z_AI_API_KEY} ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic ANTHROPIC_MODEL=GLM-4.6 ANTHROPIC_SMALL_FAST_MODEL=GLM-4.6-Air claude";
    # claude-qwen = "ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/api/v2/apps/claude-code-proxy ANTHROPIC_AUTH_TOKEN=\${QWEN_API_KEY} ANTHROPIC_MODEL=Qwen3-Coder-Plus ANTHROPIC_SMALL_FAST_MODEL=Qwen-Plus ANTHROPIC_DEFAULT_SONNET_MODEL=Qwen3-Coder-Plus ANTHROPIC_DEFAULT_OPUS_MODEL=Qwen3-Max claude";
    # claude-kimi = "ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic ANTHROPIC_AUTH_TOKEN=\${MOONSHOT_API_KEY} ANTHROPIC_MODEL=kimi-k2-turbo-preview ANTHROPIC_DEFAULT_SONNET_MODEL=kimi-k2-turbo-preview ANTHROPIC_DEFAULT_OPUS_MODEL=kimi-k2-turbo-preview ANTHROPIC_SMALL_FAST_MODEL=kimi-k2-turbo-preview claude";
    # claude-router = "ANTHROPIC_BASE_URL=http://127.0.0.1:8080 claude";
    # claude-minimax = "ANTHROPIC_AUTH_TOKEN=\${MINIMAX_API_KEY} ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic ANTHROPIC_MODEL=MiniMax-M2 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2 API_TIMEOUT_MS=3000000 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude";
  };

  programs.mise = {
    enable = true;
    # package = inputs.mise.packages.${pkgs.system}.default;
    enableZshIntegration = true;
    globalConfig = {
      settings = {
        npm = {
          package_manager = "bun";
        };
      };
      tools = {
        node = "latest";
        bun = "latest";
        "npm:typescript" = "latest";
        "npm:typescript-language-server" = "latest";

        # AI CLI tools
        "npm:@google/gemini-cli" = "latest";
        "npm:@openai/codex" = "latest";
        "npm:@sourcegraph/amp" = "latest";
        "npm:@qwen-code/qwen-code" = "latest";
        "npm:opencode-ai" = "latest";
        "npm:@musistudio/claude-code-router" = "latest";

        # Dev tools
        "npm:vercel" = "latest";
        "npm:eas-cli" = "latest";
      };
    };
  };

  # Zsh shell
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      strategy = [
        "history"
        "completion"
      ];
    };
    syntaxHighlighting.enable = true;

    initContent =
      let
        loadSecret = name: ''
          if [[ -f "${config.sops.secrets.${name}.path}" ]]; then
            export ${name}="$(cat "${config.sops.secrets.${name}.path}")"
          fi
        '';
      in
      ''
        # Handle SIGINT properly to prevent Starship "Exiting because of interrupt signal" spam
        # TRAPINT() {
        #   return $(( 128 + $1 ))
        # }

        # Initialize try.rb for project shortcuts
        eval "$($HOME/.local/try.rb init $HOME/Projects/tries)"

        # Initialize jjt for jujutsu workspaces
        eval "$($HOME/.local/bin/jjt init $HOME/src/workspaces)"

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

        claude-minimax() {
          ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic \
          ANTHROPIC_AUTH_TOKEN=$MINIMAX_API_KEY \
          ANTHROPIC_MODEL=MiniMax-M2 \
          ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2 \
          ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2 \
          ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2 \
          ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2 \
          API_TIMEOUT_MS=3000000 \
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
          claude
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

        # Load API keys from sops-nix secrets
      ''
      + lib.concatMapStrings loadSecret (lib.attrNames config.sops.secrets);
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_state$git_status$cmd_duration$line_break$character";
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
      git_branch = {
        format = "[$branch]($style) ";
        style = "bold purple";
      };
      git_status = {
        format = "[$all_status$ahead_behind]($style) ";
        style = "bold red";
      };
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
      cmd_duration = {
        min_time = 2000;
        format = "[$duration]($style) ";
        style = "bold yellow";
      };
    };
  };

  # Zoxide (smart cd)
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # FZF (fuzzy finder)
  programs.fzf.enable = true;

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
    shell = "${pkgs.zsh}/bin/zsh";
    extraConfig = builtins.readFile ./dotfiles/.tmux.conf;
  };

  # Direnv with nix-direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # SSH agent (auto-start via launchd on macOS)
  services.ssh-agent = {
    enable = true;
    enableZshIntegration = true;
  };

  # SSH client configuration
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        extraOptions = {
          AddKeysToAgent = "yes";
          UseKeychain = "yes";
          SetEnv = "TERM=xterm-256color";
        };
      };
      "bitbucket-fleetrover" = {
        hostname = "bitbucket.org";
        user = "git";
        identityFile = "~/.ssh/id_ed25519_fleetrover";
        identitiesOnly = true;
        extraOptions = {
          WarnWeakCrypto = "no";
        };
      };
    };
  };

  # sops-nix secrets configuration (using age - recommended for macOS)
  sops = {
    defaultSopsFile = ./secrets.yaml;

    # Fix PATH for launchd agent to find getconf (needed for DARWIN_USER_TEMP_DIR)
    environment.PATH = lib.mkForce "/usr/bin:/bin:/usr/sbin:/sbin";

    # Use dedicated age key file
    age.keyFile = "/Users/${username}/.config/sops/age/keys.txt";

    # Individual secrets - each becomes a file
    secrets = {
      COPILOT_PROXY_URL = { };
      XAI_API_KEY = { };
      TMUXAI_OPENROUTER_API_KEY = { };
      AIDER_DARK_MODE = { };
      AIDER_CODE_THEME = { };
      OPENROUTER_API_KEY = { };
      REF_API_KEY = { };
      GITHUB_READ_ONLY_PAT = { };
      DEEPSEEK_API_KEY = { };
      MOONSHOT_API_KEY = { };
      QWEN_API_KEY = { };
      Z_AI_API_KEY = { };
      TAVILY_API_KEY = { };
      CEREBRAS_API_KEY = { };
      HARVEST_TOKEN = { };
      HF_TOKEN = { };
      MINIMAX_API_KEY = { };
      OPENAI_API_KEY = { };
      SENTRY_API_KEY = { };
      BRAVE_API_KEY = { };
      GEMINI_API_KEY = { };
      NEW_OPENAI_API_KEY = { };
      GOOGLE_PLACES_API_KEY = { };
      REQUESTY_API_KEY = { };
      REQUESTY_BASE_URL = { };
      LINEAR_API_KEY = { };
      ELEVENLABS_API_KEY = { };
    };
  };

  # Dotfiles
  home.file = {
    ".config/jj/config.toml".source = ./dotfiles/jj/config.toml;
    ".config/zellij/config.kdl".source = ./dotfiles/zellij/config.kdl;
    ".aider.conf.yml".source = ./dotfiles/aider.conf.yml;
    ".local/bin/gwt" = {
      source = ./dotfiles/bin/gwt;
      executable = true;
    };
    ".local/bin/jwt" = {
      source = ./dotfiles/bin/jwt;
      executable = true;
    };
    ".local/bin/jjt" = {
      source = ./dotfiles/bin/jjt;
      executable = true;
    };
    ".local/bin/workspace-up" = {
      source = ./dotfiles/bin/workspace-up;
      executable = true;
    };
    ".local/bin/workspace-down" = {
      source = ./dotfiles/bin/workspace-down;
      executable = true;
    };
  };
}
