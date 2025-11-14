return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      -- Extend existing formatters
      opts.formatters_by_ft = opts.formatters_by_ft or {}

      -- Default for all languages: try biome first, fallback to prettier
      opts.formatters_by_ft = {
        lua = { "stylua" },
        ["javascript"] = { "biome-check" },
        ["javascriptreact"] = { "biome-check" },
        ["typescript"] = { "biome-check" },
        ["typescriptreact"] = { "biome-check" },
        ["json"] = { "biome-check" },
        ["css"] = { "biome-check" },
      }

      return opts
    end,
  },
}
