return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      -- Extend existing formatters
      opts.formatters_by_ft = opts.formatters_by_ft or {}

      -- Default for all languages: try biome first, fallback to prettier
      -- opts.formatters_by_ft["html"] = { "biome" }

      return opts
    end,
  },
}
