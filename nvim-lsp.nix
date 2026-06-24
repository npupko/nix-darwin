# Language servers consumed by Neovim's native LSP (vim.lsp.enable).
# Kept separate from home.nix so the relationship to the editor is obvious
# and additions/removals don't churn the main package list.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    lua-language-server              # lua_ls
    taplo                            # toml
    svelte-language-server           # svelte
    gopls                            # go
    # marksman (markdown) is in home.nix Editors group — leave there
    #
    # vscode-langservers-extracted (jsonls + html + cssls + eslint) moved to
    # mise — see programs.mise.globalConfig.tools in home.nix. Its nix build
    # pins nodejs 24.15.0, under which the json server's bundled
    # jsonServerMain.js is misclassified as ESM and crashes on startup
    # ("require is not defined in ES module scope"). mise runs it under node
    # "latest" (26.x), which is fine — and node CLI tools belong on mise here
    # anyway (see home.nix header).
  ];
}
