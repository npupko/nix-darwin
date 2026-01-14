{
  config,
  pkgs,
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
    nodejs_24
    rustup
    bun
    uv
    volta

    # Editors
    helix
    neovim
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
    cocoapods
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
    "/Users/${username}/.volta/bin"
    "/Users/${username}/.local/bin"
    "/Users/${username}/.claude/local"
    "/Users/${username}/.bun/bin"
    "/Users/${username}/.cargo/bin"
    "/Users/${username}/Projects/npupko/utility/target/release"
  ];

  # Shell aliases
  home.shellAliases = {
    v = "nvim";
    be = "bundle exec";
    k = "kubectl";
    zj = "zellij";
    dp = "v /etc/nix-darwin/home.nix";
    de = "v /etc/nix-darwin";
    dr = "sudo darwin-rebuild switch";
    du = "nix flake update --flake /etc/nix-darwin/";
    dcd = "cd /etc/nix-darwin/";
    chrome_debug = "open -na \"Google Chrome\" --args --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-debug --no-first-run --no-default-browser-check";
    cm = "claude-monitor --timezone Europe/Minsk --plan max5";
    ghostty = "/Applications/Ghostty.app/Contents/MacOS/ghostty";
    fix-ssh = "launchctl kickstart -k gui/$(id -u)/org.nix-community.home.ssh-agent";

    # Claude with alternative model providers
    # claude-deepseek = "ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic ANTHROPIC_AUTH_TOKEN=\${DEEPSEEK_API_KEY} ANTHROPIC_MODEL=deepseek-chat ANTHROPIC_SMALL_FAST_MODEL=deepseek-chat ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-chat ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-reasoner claude";
    # claude-xai = "ANTHROPIC_BASE_URL=https://api.x.ai/ ANTHROPIC_AUTH_TOKEN=\${XAI_API_KEY} ANTHROPIC_MODEL=grok-code-fast-1 ANTHROPIC_SMALL_FAST_MODEL=grok-code-fast-1 ANTHROPIC_DEFAULT_SONNET_MODEL=grok-code-fast-1 ANTHROPIC_DEFAULT_OPUS_MODEL=grok-4 claude";
    # claude-zai = "ANTHROPIC_AUTH_TOKEN=\${Z_AI_API_KEY} ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic ANTHROPIC_MODEL=GLM-4.6 ANTHROPIC_SMALL_FAST_MODEL=GLM-4.6-Air claude";
    # claude-qwen = "ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/api/v2/apps/claude-code-proxy ANTHROPIC_AUTH_TOKEN=\${QWEN_API_KEY} ANTHROPIC_MODEL=Qwen3-Coder-Plus ANTHROPIC_SMALL_FAST_MODEL=Qwen-Plus ANTHROPIC_DEFAULT_SONNET_MODEL=Qwen3-Coder-Plus ANTHROPIC_DEFAULT_OPUS_MODEL=Qwen3-Max claude";
    # claude-kimi = "ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic ANTHROPIC_AUTH_TOKEN=\${MOONSHOT_API_KEY} ANTHROPIC_MODEL=kimi-k2-turbo-preview ANTHROPIC_DEFAULT_SONNET_MODEL=kimi-k2-turbo-preview ANTHROPIC_DEFAULT_OPUS_MODEL=kimi-k2-turbo-preview ANTHROPIC_SMALL_FAST_MODEL=kimi-k2-turbo-preview claude";
    # claude-router = "ANTHROPIC_BASE_URL=http://127.0.0.1:8080 claude";
    # claude-minimax = "ANTHROPIC_AUTH_TOKEN=\${MINIMAX_API_KEY} ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic ANTHROPIC_MODEL=MiniMax-M2 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2 API_TIMEOUT_MS=3000000 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude";
  };

  # Zsh shell
  programs.zsh = {
    enable = true;

    initContent =
      let
        loadSecret = name: ''
          if [[ -f "${config.sops.secrets.${name}.path}" ]]; then
            export ${name}="$(cat "${config.sops.secrets.${name}.path}")"
          fi
        '';
      in
      ''
        # Initialize mise
        eval "$($HOME/.local/bin/mise activate zsh)"

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

        # Load API keys from sops-nix secrets
      '' + lib.concatMapStrings loadSecret (lib.attrNames config.sops.secrets);
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
    plugins = with pkgs; [
      {
        plugin = tmuxPlugins.gruvbox;
        extraConfig = "set -g @tmux-gruvbox 'dark'";
      }
    ];
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

  # sops-nix secrets configuration (using age - recommended for macOS)
  sops = {
    defaultSopsFile = ./secrets.yaml;

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
