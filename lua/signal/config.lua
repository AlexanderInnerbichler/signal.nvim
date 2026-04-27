local M = {}

M.ACCOUNT_CACHE = vim.fn.expand("~/.local/share/signal-cli/nvim-account")

local defaults = {
  poll_interval = 30,
  notif_ttl     = 5,
  window_width  = 0.9,
  signal_cmd    = "signal-cli",
  debug         = false,
}

local _config = vim.deepcopy(defaults)

function M.setup(opts)
  _config = vim.tbl_deep_extend("force", defaults, opts or {})
end

function M.get()
  return _config
end

function M.ready()
  if vim.fn.executable(_config.signal_cmd) == 0 then
    return false, "signal-cli not found — run :SignalSetup or see :checkhealth signal"
  end
  return true, nil
end

function M.resolve_account(callback)
  -- fast path: use cached number written after last successful verify
  local f = io.open(M.ACCOUNT_CACHE, "r")
  if f then
    local num = vim.trim(f:read("*a") or "")
    f:close()
    if num ~= "" then
      callback(num)
      return
    end
  end

  -- slow path: ask signal-cli
  local cmd = _config.signal_cmd
  vim.system({ cmd, "--output=json", "listAccounts" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 or not result.stdout or result.stdout == "" then
        callback(nil)
        return
      end
      local ok, data = pcall(vim.fn.json_decode, result.stdout)
      if ok and type(data) == "table" and data[1] and data[1].number then
        callback(data[1].number)
      else
        callback(nil)
      end
    end)
  end)
end

return M
