local M = {}

local function apply()
  -- dashboard — dark & moody, cool blues/teals
  vim.api.nvim_set_hl(0, "SignalName",          { fg = "#7aaec4",                bg = "NONE" })  -- unread contact (muted steel blue)
  vim.api.nvim_set_hl(0, "SignalNameDim",        { fg = "#2e4252",                bg = "NONE" })  -- read contact (dark)
  vim.api.nvim_set_hl(0, "SignalGroup",          { fg = "#6aaaa6",                bg = "NONE" })  -- unread group (muted teal)
  vim.api.nvim_set_hl(0, "SignalGroupDim",       { fg = "#263c3a",                bg = "NONE" })  -- read group (very dark)
  vim.api.nvim_set_hl(0, "SignalPinned",         { fg = "#78a898",                bg = "NONE" })  -- cool sage
  vim.api.nvim_set_hl(0, "SignalUnread",         { fg = "#5a8ea8",                bg = "NONE" })  -- badge [N]
  vim.api.nvim_set_hl(0, "SignalSnippet",        { fg = "#3e4a5a",                bg = "NONE" })  -- barely-there snippet
  vim.api.nvim_set_hl(0, "SignalTime",           { fg = "#283040",                bg = "NONE" })  -- near-invisible time
  vim.api.nvim_set_hl(0, "SignalTimeHot",        { fg = "#3e6070",                bg = "NONE" })  -- dim blue (today)
  vim.api.nvim_set_hl(0, "SignalTimeWarm",       { fg = "#344e5c",                bg = "NONE" })  -- slightly dimmer (yesterday)
  vim.api.nvim_set_hl(0, "SignalDividerBar",     { fg = "#181e28",                bg = "NONE" })  -- near-black rule
  vim.api.nvim_set_hl(0, "SignalSectionLabel",   { fg = "#2e4252",                bg = "NONE" })  -- dim section text
  vim.api.nvim_set_hl(0, "SignalLoading",        { fg = "#3e4a5a", italic = true, bg = "NONE" })

  -- thread
  vim.api.nvim_set_hl(0, "SignalSenderOther",    { fg = "#7aaec4", bold = true,   bg = "NONE" })  -- steel blue
  vim.api.nvim_set_hl(0, "SignalSenderSelf",     { fg = "#5a8878", bold = true,   bg = "NONE" })  -- muted teal-green
  vim.api.nvim_set_hl(0, "SignalMsgBody",        { fg = "#4a5668",                bg = "NONE" })  -- dim body
  vim.api.nvim_set_hl(0, "SignalReceiptSent",    { fg = "#283040",                bg = "NONE" })  -- invisible
  vim.api.nvim_set_hl(0, "SignalReceiptRead",    { fg = "#4a7898",                bg = "NONE" })  -- muted blue

  -- setup wizard
  vim.api.nvim_set_hl(0, "SignalSetupCmd",       { fg = "#3e4a5a", italic = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupOk",        { fg = "#5a8878", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupErr",       { fg = "#805868", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupUrl",       { fg = "#5a8ea8",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupDim",       { fg = "#3e4a5a",                bg = "NONE" })
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("SignalHL", { clear = true }),
    callback = apply,
  })
end

return M
