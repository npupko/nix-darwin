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
  themes,
  themeName,
  ...
}:
let
  theme = themes.${themeName};
in
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
    curl
    wget
    doctl

    # Shell & Terminal
    zellij
    ugrep

    # AI Tools
    # aichat
    # argc
    tabby

    # System utilities
    gnupg
    gnused
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
    _1password-cli
    cloudflared
    kubectx

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
    dr = "sudo darwin-rebuild switch";
    duf = "nix flake update --flake /etc/nix-darwin/";
    ngc = "nh clean all --keep 5";
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
        rust = "latest";
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
    autosuggestion = {
      enable = true;
      strategy = [
        "history"
        "completion"
      ];
    };
    syntaxHighlighting.enable = true;

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

        # Git push current branch with force-with-lease
        gpb() {
          git push origin "$(git rev-parse --abbrev-ref HEAD)" --force-with-lease -u
        }

        # OpenAI Codex shell completion
        eval "$(codex completion zsh)"

        # Load API keys from sops-nix secrets
      ''
      + lib.concatMapStrings loadSecret (lib.attrNames config.sops.secrets);
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      command_timeout = 500;
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
    enableZshIntegration = true;
  };

  # FZF (fuzzy finder)
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
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
    ignores = [ ".git/" ".direnv/" ".devenv/" "node_modules/" ".next/" "target/" ];
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
    ignores = [
      ".DS_Store"
      "*.swp"
      "*~"
      ".direnv/"
      ".devenv/"
    ];
    settings = {
      user = {
        name = "Nick Pupko";
        email = "work.pupko@gmail.com";
        signingkey = "B6037B82A01D008B264C633B7E3F4D625B0E9E31";
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
        "shift+enter=text:\\n"
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
    shell = "${pkgs.zsh}/bin/zsh";
    extraConfig = builtins.readFile ./dotfiles/.tmux.conf + ''
      # Theme (generated)
      set -g status-style "bg=default,fg=default"
      set -g status-left "#[fg=black,bg=${theme.tmux.accent},bold] #S #[bg=default] "
      set -g status-right "#[fg=${theme.tmux.accent}]#{?client_prefix,PREFIX ,}#{?window_zoomed_flag,ZOOM ,}#[fg=brightblack]#h "
      set -g window-status-format "#[fg=brightblack] #I:#W "
      set -g window-status-current-format "#[fg=${theme.tmux.accent},bold] #I:#W "
      set -g pane-border-style "fg=brightblack"
      set -g pane-active-border-style "fg=${theme.tmux.accent}"
      set -g message-style "bg=default,fg=${theme.tmux.accent}"
      set -g message-command-style "bg=default,fg=${theme.tmux.accent}"
      set -g mode-style "bg=${theme.tmux.accent},fg=black"
      setw -g clock-mode-colour ${theme.tmux.accent}
    '';
  };

  # Direnv with nix-direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
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
        controlMaster = "auto";
        controlPath = "~/.ssh/control-%C";
        controlPersist = "10m";
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
    ".config/zellij/config.kdl".text =
      builtins.replaceStrings
        [ "@THEME@" ]
        [ theme.zellij ]
        (builtins.readFile ./dotfiles/zellij/config.kdl);
    ".config/theme/current".text = theme.neovim;
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
