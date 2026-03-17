# nix-darwin

My macOS system configuration using [Determinate Nix](https://determinate.systems/) + [nix-darwin](https://github.com/LnL7/nix-darwin) + [Home Manager](https://github.com/nix-community/home-manager).

## What's managed

**System** — Dock, Finder, trackpad, keyboard repeat, Touch ID sudo, file descriptor limits, fonts, Homebrew casks

**Shell** — Zsh with autosuggestions, syntax highlighting, Starship prompt, 100k history

**Dev tools** — Neovim, Helix, Git (delta, GPG signing), tmux, direnv, mise (runtime manager), fzf, fd, ripgrep, eza, bat, zoxide

**Terminal** — Ghostty (primary), Alacritty (fallback)

**Secrets** — [sops-nix](https://github.com/Mic92/sops-nix) with age encryption — API keys decrypted at activation and loaded into shell env

**Themes** — Global theme switching across Ghostty, Alacritty, tmux, Starship, bat, delta, btop, Zellij, Helix, and Neovim:

```
theme-switch catppuccin-mocha   # rebuilds system, reloads tmux
theme-switch                    # shows current + available
```

Available: `gruvbox-dark`, `gruvbox-light`, `nord`, `catppuccin-latte`, `catppuccin-mocha`

## Package strategy

| Layer | What | Why |
|-------|------|-----|
| Nix (stable) | CLI tools, system utilities, fonts | Reproducible, pinned |
| Nix (unstable) | Helix, Neovim | Fast-moving, need latest |
| Homebrew brews | jujutsu, supabase, ollama | macOS-specific or not in nixpkgs |
| Homebrew casks | Ghostty, Docker, Zed, Tailscale | GUI apps |
| Mise | Node, Bun, Rust, npm CLI tools | Language runtimes, always latest |

## Layout

```
flake.nix          # Inputs + system definition
configuration.nix  # macOS system preferences, fonts, Homebrew
home.nix           # User packages, shell, programs, dotfiles
themes.nix         # Theme definitions for all tools
secrets.yaml       # sops-encrypted API keys
dotfiles/          # Static config files (tmux, jj, zellij, scripts)
```

## Usage

```bash
nix develop          # Enter dev shell with `apply` + `sops` commands
apply                # Rebuild and switch (sudo darwin-rebuild switch)
nix flake update     # Update all inputs
```

## Custom scripts

- `tdl` / `tdlm` — tmux dev layouts (editor + AI + terminal panes)
- `tsl` — tmux swarm layout (N panes running same command)
- `gwt` — git worktree helper
- `jjt` / `jwt` — jujutsu workspace helpers
