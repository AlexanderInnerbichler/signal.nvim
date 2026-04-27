local M = {}

local function apply()
  -- dashboard
  vim.api.nvim_set_hl(0, "SignalName",          { fg = "#e8a060", bold = true,   bg = "NONE" })  -- amber
  vim.api.nvim_set_hl(0, "SignalGroup",          { fg = "#d4769c", bold = true,   bg = "NONE" })  -- dusty rose
  vim.api.nvim_set_hl(0, "SignalPinned",         { fg = "#f0c060", bold = true,   bg = "NONE" })  -- warm gold
  vim.api.nvim_set_hl(0, "SignalUnread",         { fg = "#ff6e6e", bold = true,   bg = "NONE" })  -- coral
  vim.api.nvim_set_hl(0, "SignalSnippet",        { fg = "#6a5a4a",                bg = "NONE" })  -- warm dim
  vim.api.nvim_set_hl(0, "SignalTime",           { fg = "#4a3e32",                bg = "NONE" })  -- dark warm brown
  vim.api.nvim_set_hl(0, "SignalTimeHot",        { fg = "#f0b060",                bg = "NONE" })  -- bright amber glow
  vim.api.nvim_set_hl(0, "SignalTimeWarm",       { fg = "#c07840",                bg = "NONE" })  -- deep orange
  vim.api.nvim_set_hl(0, "SignalDividerBar",     { fg = "#2a1e14",                bg = "NONE" })  -- near-black warm
  vim.api.nvim_set_hl(0, "SignalStripeContact",  { fg = "#5a2808",                bg = "NONE" })  -- dark rust
  vim.api.nvim_set_hl(0, "SignalStripeGroup",    { fg = "#5a1830",                bg = "NONE" })  -- dark rose
  vim.api.nvim_set_hl(0, "SignalStripePinned",   { fg = "#5a4008",                bg = "NONE" })  -- dark gold
  vim.api.nvim_set_hl(0, "SignalLoading",        { fg = "#5a4e3e", italic = true, bg = "NONE" })  -- warm muted

  -- thread
  vim.api.nvim_set_hl(0, "SignalSenderOther",    { fg = "#e8a060", bold = true,   bg = "NONE" })  -- amber
  vim.api.nvim_set_hl(0, "SignalSenderSelf",     { fg = "#8ac880", bold = true,   bg = "NONE" })  -- sage green
  vim.api.nvim_set_hl(0, "SignalMsgBody",        { fg = "#b09a80",                bg = "NONE" })  -- warm tan
  vim.api.nvim_set_hl(0, "SignalReceiptSent",    { fg = "#4a3e32",                bg = "NONE" })  -- dim warm
  vim.api.nvim_set_hl(0, "SignalReceiptRead",    { fg = "#e8a060",                bg = "NONE" })  -- amber glow

  -- setup wizard
  vim.api.nvim_set_hl(0, "SignalSetupCmd",       { fg = "#5a4e3e", italic = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupOk",        { fg = "#8ac880", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupErr",       { fg = "#ff6e6e", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupUrl",       { fg = "#e8a060",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupDim",       { fg = "#5a4e3e",                bg = "NONE" })
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("SignalHL", { clear = true }),
    callback = apply,
  })
end

return M
