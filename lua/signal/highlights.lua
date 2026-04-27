local M = {}

local function apply()
  vim.api.nvim_set_hl(0, "SignalName",        { fg = "#7fc8f8", bold = true,  bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSnippet",     { fg = "#888888",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalTime",        { fg = "#555555",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalUnread",      { fg = "#e06c75", bold = true,  bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSenderOther", { fg = "#7fc8f8", bold = true,  bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSenderSelf",  { fg = "#98c379", bold = true,  bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalMsgBody",     { fg = "#abb2bf",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalGroup",       { fg = "#c678dd",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalLoading",     { fg = "#555555", italic = true, bg = "NONE" })
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("SignalHL", { clear = true }),
    callback = apply,
  })
end

return M
