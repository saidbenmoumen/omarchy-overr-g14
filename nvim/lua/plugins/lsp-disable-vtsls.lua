-- TEMP: disable vtsls since tsgo is the active TS LSP (set in options.lua).
-- Having both running causes duplicate inlay hints and 'col out of range' crashes.
-- TODO: remove this file once LazyVim releases a version after v15.14.0,
-- which properly handles vim.g.lazyvim_ts_lsp = "tsgo" (commit 9029d928).
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        vtsls = {
          enabled = false,
        },
      },
    },
  },
}
