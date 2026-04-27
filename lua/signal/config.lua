local M = {}

local defaults = {
  phone_number  = "",
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

return M
