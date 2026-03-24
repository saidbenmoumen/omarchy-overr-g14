-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.relativenumber = false

-- LSP Server to use for TypeScript.
---@type "vtsls" | "tsgo"
vim.g.lazyvim_ts_lsp = "tsgo"

-- Enable the option to require a Prettier config file
-- If no prettier config file is found, the formatter will not be used
vim.g.lazyvim_prettier_needs_config = true

-- Eslint: Set to false to disable auto format
vim.g.lazyvim_eslint_auto_format = false
