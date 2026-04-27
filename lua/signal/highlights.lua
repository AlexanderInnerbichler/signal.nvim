local M = {}

local function apply()
  vim.api.nvim_set_hl(0, "SignalName",        { fg = "#7fc8f8", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSnippet",     { fg = "#9a9a9a",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalTime",        { fg = "#4a4e5a",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalUnread",      { fg = "#e06c75", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSenderOther", { fg = "#7fc8f8", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSenderSelf",  { fg = "#98c379", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalMsgBody",     { fg = "#abb2bf",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalGroup",       { fg = "#c678dd",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalPinned",      { fg = "#e5c07b", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalDividerBar",  { fg = "#2e3138",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalLoading",     { fg = "#555555", italic = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupCmd",   { fg = "#555555", italic = true,  bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupOk",    { fg = "#98c379", bold = true,    bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupErr",   { fg = "#e06c75", bold = true,    bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupUrl",   { fg = "#7fc8f8",                 bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupDim",   { fg = "#555555",                 bg = "NONE" })
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("SignalHL", { clear = true }),
    callback = apply,
  })
end

return M
