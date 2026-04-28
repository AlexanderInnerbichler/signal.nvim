local M = {}

local function apply()
  -- dashboard
  vim.api.nvim_set_hl(0, "SignalName",          { fg = "#e2e8f0", bold = true,   bg = "NONE" })  -- unread contact (near-white)
  vim.api.nvim_set_hl(0, "SignalNameDim",        { fg = "#64748b",                bg = "NONE" })  -- read contact (slate)
  vim.api.nvim_set_hl(0, "SignalGroup",          { fg = "#818cf8", bold = true,   bg = "NONE" })  -- unread group (indigo)
  vim.api.nvim_set_hl(0, "SignalGroupDim",       { fg = "#374151",                bg = "NONE" })  -- read group (dim)
  vim.api.nvim_set_hl(0, "SignalPinned",         { fg = "#f59e0b", bold = true,   bg = "NONE" })  -- pinned (amber)
  vim.api.nvim_set_hl(0, "SignalUnread",         { fg = "#22c55e", bold = true,   bg = "NONE" })  -- unread badge (green)
  vim.api.nvim_set_hl(0, "SignalUnreadDot",      { fg = "#22c55e",                bg = "NONE" })  -- ● left-edge indicator
  vim.api.nvim_set_hl(0, "SignalSnippet",        { fg = "#475569",                bg = "NONE" })  -- last message preview
  vim.api.nvim_set_hl(0, "SignalTime",           { fg = "#334155",                bg = "NONE" })  -- old timestamp
  vim.api.nvim_set_hl(0, "SignalTimeHot",        { fg = "#38bdf8",                bg = "NONE" })  -- today (sky blue)
  vim.api.nvim_set_hl(0, "SignalTimeWarm",       { fg = "#a78bfa",                bg = "NONE" })  -- yesterday (violet)
  vim.api.nvim_set_hl(0, "SignalDividerBar",     { fg = "#1e293b",                bg = "NONE" })  -- thread date separators
  vim.api.nvim_set_hl(0, "SignalSectionLabel",   { fg = "#475569",                bg = "NONE" })  -- section header (PINNED)
  vim.api.nvim_set_hl(0, "SignalLoading",        { fg = "#64748b", italic = true, bg = "NONE" })

  -- thread
  vim.api.nvim_set_hl(0, "SignalSenderOther",    { fg = "#60a5fa", bold = true,   bg = "NONE" })  -- blue
  vim.api.nvim_set_hl(0, "SignalSenderSelf",     { fg = "#34d399", bold = true,   bg = "NONE" })  -- emerald
  vim.api.nvim_set_hl(0, "SignalMsgBody",        { fg = "#94a3b8",                bg = "NONE" })  -- readable body
  vim.api.nvim_set_hl(0, "SignalReceiptSent",    { fg = "#334155",                bg = "NONE" })  -- dim
  vim.api.nvim_set_hl(0, "SignalReceiptRead",    { fg = "#60a5fa",                bg = "NONE" })  -- blue (matches sender)
  vim.api.nvim_set_hl(0, "SignalReaction",       { fg = "#a78bfa",                bg = "NONE" })  -- violet
  vim.api.nvim_set_hl(0, "SignalSprite",         { fg = "#818cf8", bold = true,   bg = "NONE" })  -- indigo

  -- setup wizard
  vim.api.nvim_set_hl(0, "SignalSetupCmd",       { fg = "#64748b", italic = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupOk",        { fg = "#34d399", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupErr",       { fg = "#f87171", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupUrl",       { fg = "#60a5fa",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "SignalSetupDim",       { fg = "#475569",                bg = "NONE" })
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("SignalHL", { clear = true }),
    callback = apply,
  })
end

return M
