# Language servers consumed by Neovim's native LSP (vim.lsp.enable).
# Kept separate from home.nix so the relationship to the editor is obvious
# and additions/removals don't churn the main package list.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    lua-language-server              # lua_ls
    vscode-langservers-extracted     # jsonls + html + cssls + eslint
    taplo                            # toml
    nodePackages.svelte-language-server  # svelte
    gopls                            # go
    # marksman (markdown) is in home.nix Editors group — leave there
  ];
}
