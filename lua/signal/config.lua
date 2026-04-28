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

function M.is_auth_error(err)
  if not err then return false end
  local low = err:lower()
  return low:find("notlinked")     ~= nil
    or   low:find("not linked")    ~= nil
    or   low:find("notregistered") ~= nil
    or   low:find("not registered") ~= nil
end

function M.invalidate_cache()
  os.remove(M.ACCOUNT_CACHE)
end

local function list_accounts(cmd, callback)
  vim.system({ cmd, "--output=json", "listAccounts" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 or not result.stdout or result.stdout == "" then
        callback(nil)
        return
      end
      local ok, data = pcall(vim.fn.json_decode, result.stdout)
      callback((ok and type(data) == "table") and data or nil)
    end)
  end)
end

function M.resolve_account(callback)
  local cmd = _config.signal_cmd
  local f   = io.open(M.ACCOUNT_CACHE, "r")
  if f then
    local num = vim.trim(f:read("*a") or "")
    f:close()
    if num:match("^%+%d+$") then
      callback(num)
      return
    end
  end
  -- Cache miss only — spawn listAccounts once to find the account
  list_accounts(cmd, function(accounts)
    local num = accounts and accounts[1] and accounts[1].number
    if num then
      local wf = io.open(M.ACCOUNT_CACHE, "w")
      if wf then wf:write(num); wf:close() end
      callback(num)
    else
      callback(nil)
    end
  end)
end

return M
