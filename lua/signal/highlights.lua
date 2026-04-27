local M = {}

local function apply()
  -- dashboard
  vim.api.nvim_set_hl(0, "SignalName",          { fg = "#74c7ec", bold = true,   bg = "NONE" })  -- sapphire
  vim.api.nvim_set_hl(0, "SignalGroup",          { fg = "#cba6f7", bold = true,   bg = "NONE" })  -- mauve
  vim.api.nvim_set_hl(0, "SignalPinned",         { fg = "#fab387", bold = true,   bg = "NONE" })  -- peach
  vim.api.nvim_set_hl(0, "SignalUnread",         { fg = "#f38ba8", bold = true,   bg = "NONE" })  -- red
  vim.api.nvim_set_hl(0, "SignalSnippet",        { fg = "#7f849c",                bg = "NONE" })  -- overlay1
  vim.api.nvim_set_hl(0, "SignalTime",           { fg = "#45475a",                bg = "NONE" })  -- surface1
  vim.api.nvim_set_hl(0, "SignalTimeHot",        { fg = "#a6e3a1",                bg = "NONE" })  -- green
  vim.api.nvim_set_hl(0, "SignalTimeWarm",       { fg = "#f9e2af",                bg = "NONE" })  -- yellow
  vim.api.nvim_set_hl(0, "SignalDividerBar",     { fg = "#2a2a3e",                bg = "NONE" })  -- very dim
  vim.api.nvim_set_hl(0, "SignalStripeContact",  { fg = "#2a4a6a",                bg = "NONE" })  -- dark sapphire
  vim.api.nvim_set_hl(0, "SignalStripeGroup",    { fg = "#4a2a6a",                bg = "NONE" })  -- dark mauve
  vim.api.nvim_set_hl(0, "SignalStripePinned",   { fg = "#6a3a1a",                bg = "NONE" })  -- dark peach
  vim.api.nvim_set_hl(0, "SignalLoading",        { fg = "#585b70", italic = true, bg = "NONE" })  -- overlay0

  -- thread
  vim.api.nvim_set_hl(0, "SignalSenderOther",    { fg = "#74c7ec", bold = true,   bg = "NONE" })  -- sapphire
  vim.api.nvim_set_hl(0, "SignalSenderSelf",     { fg = "#a6e3a1", bold = true,   bg = "NONE" })  -- green
  vim.api.nvim_set_hl(0, "SignalMsgBody",        { fg = "#a6adc8",                bg = "NONE" })  -- subtext0
  vim.api.nvim_set_hl(0, "SignalReceiptSent",    { fg = "#45475a",                bg = "NONE" })  -- surface1
  vim.api.nvim_set_hl(0, "SignalReceiptRead",    { fg = "#74c7ec",                bg = "NONE" })  -- sapphire

  -- setup wizard
  vim.api.nvim_set_hl(0, "SignalSetupCmd",       { fg = "#585b70", italic = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupOk",        { fg = "#a6e3a1", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupErr",       { fg = "#f38ba8", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupUrl",       { fg = "#74c7ec",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupDim",       { fg = "#585b70",                bg = "NONE" })
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("SignalHL", { clear = true }),
    callback = apply,
  })
end

return M
