local M = {}
local config = require("signal.config")

local function socket_path()
  local xdg = os.getenv("XDG_RUNTIME_DIR") or "/run/user/1000"
  return xdg:gsub("/+$", "") .. "/signal-cli/socket"
end

local state = {
  channel    = nil,
  buf        = "",
  pending    = {},
  id_seq     = 0,
  on_recv    = nil,
  own_proc   = nil,
  connecting = false,
  call_queue = {},
}

local function process_line(line)
  if line == "" then return end
  local ok, msg = pcall(vim.fn.json_decode, line)
  if not ok or type(msg) ~= "table" then return end

  if msg.id ~= nil then
    local cb = state.pending[msg.id]
    if cb then
      state.pending[msg.id] = nil
      if msg.error then cb(msg.error.message or "signal-cli error", nil)
      else              cb(nil, msg.result) end
    end
  elseif msg.method == "receive" and state.on_recv then
    state.on_recv(msg.params)
  end
end

-- Neovim channel data: list of strings separated by \n boundaries
local function on_channel_data(_, data, _)
  state.buf = state.buf .. table.concat(data, "\n")
  while true do
    local nl = state.buf:find("\n")
    if not nl then break end
    local line = state.buf:sub(1, nl - 1)
    state.buf  = state.buf:sub(nl + 1)
    vim.schedule(function() process_line(line) end)
  end
end

local function drain_queue()
  local q = state.call_queue
  state.call_queue = {}
  for _, item in ipairs(q) do
    M.call(item.method, item.params, item.callback)
  end
end

local function on_connected()
  state.connecting = false
  drain_queue()
  vim.defer_fn(function()
    M.call("sendSyncRequest", {}, function() end)
  end, 1000)
end

local function connect(on_ready)
  local ok, id = pcall(vim.fn.sockconnect, "pipe", socket_path(), {
    on_data = on_channel_data,
  })
  if not ok or type(id) ~= "number" or id <= 0 then
    if on_ready then on_ready(tostring(id)) end
    return
  end
  state.channel = id
  if on_ready then on_ready(nil) end
end

-- Kill any signal-cli processes except our own daemon (by PID).
-- pkill -f doesn't work on WSL2 (matches process name "java", not cmdline), use pgrep|grep|xargs.
local function kill_competing(own_pid)
  local cmd = own_pid
    and ("pgrep -f signal-cli | grep -v '^" .. own_pid .. "$' | xargs -r kill -9 2>/dev/null")
    or  "pgrep -f signal-cli | xargs -r kill -9 2>/dev/null"
  vim.fn.system(cmd)
end

local function wait_for_socket(account, attempts, own_pid)
  attempts = attempts or 0
  if attempts > 40 then
    state.connecting = false
    vim.schedule(function()
      vim.notify("signal.nvim: timed out waiting for daemon socket", vim.log.levels.WARN)
    end)
    return
  end
  -- Keep killing competing signal-cli processes every 2.5s so they can't
  -- hold the config lock while our daemon is starting up.
  if attempts % 5 == 0 then
    kill_competing(own_pid)
  end
  vim.defer_fn(function()
    connect(function(err)
      if err then
        wait_for_socket(account, attempts + 1, own_pid)
      else
        on_connected()
      end
    end)
  end, 500)
end

local function spawn_daemon(account)
  -- Initial kill before spawning — clears the field so daemon can get the lock.
  kill_competing(nil)

  local stderr = vim.loop.new_pipe(false)
  local proc, pid = vim.loop.spawn(config.get().signal_cmd, {
    args  = { "-a", account, "daemon", "--socket",
              "--ignore-attachments", "--ignore-stories",
              "--receive-mode", "on-start" },
    stdio = { nil, nil, stderr },
  }, vim.schedule_wrap(function()
    state.own_proc = nil
  end))
  stderr:read_start(function() end)
  state.own_proc = proc
  wait_for_socket(account, 0, pid)
end

function M.call(method, params, callback)
  if not state.channel then
    if state.connecting then
      table.insert(state.call_queue, { method = method, params = params, callback = callback })
    else
      callback("daemon not connected", nil)
    end
    return
  end
  state.id_seq = state.id_seq + 1
  local id = state.id_seq
  state.pending[id] = callback
  vim.fn.chansend(state.channel, vim.fn.json_encode({
    jsonrpc = "2.0", method = method, id = id,
    params  = params or vim.empty_dict(),
  }) .. "\n")
end

function M.start(account, on_recv)
  if state.channel or state.connecting then return end
  state.on_recv    = on_recv
  state.connecting = true

  connect(function(err)
    if not err then
      on_connected()
      return
    end
    spawn_daemon(account)
  end)
end

function M.stop()
  if state.channel then
    pcall(vim.fn.chanclose, state.channel)
    state.channel = nil
  end
  if state.own_proc then state.own_proc:kill(15); state.own_proc = nil end
  state.buf = ""; state.pending = {}; state.connecting = false; state.call_queue = {}
end

function M.is_running()
  return state.channel ~= nil
end

return M
