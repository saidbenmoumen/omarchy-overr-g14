return {
  "catgoose/nvim-colorizer.lua",
  event = "BufReadPre",
  opts = {
    parsers = {
      tailwind = {
        enable = true,
        lsp = true,
      },
      css = true,
    },
  },
}
