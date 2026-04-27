local M = {}

local defaults = {
  phone_number  = vim.env.SIGNAL_PHONE_NUMBER or "",
  poll_interval = 30,
  notif_ttl     = 5,
  window_width  = 0.9,
  signal_cmd    = "signal-cli",
}

local _config = vim.deepcopy(defaults)

function M.setup(opts)
  _config = vim.tbl_deep_extend("force", defaults, opts or {})
end

function M.get()
  return _config
end

function M.ready()
  local cfg = _config
  if not cfg.phone_number or cfg.phone_number == "" then
    return false, "SIGNAL_PHONE_NUMBER not set — add 'export SIGNAL_PHONE_NUMBER=+43...' to your shell profile"
  end
  if vim.fn.executable(cfg.signal_cmd) == 0 then
    return false, "signal-cli not found — see :checkhealth signal"
  end
  return true, nil
end

return M
