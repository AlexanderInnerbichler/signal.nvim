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
  account    = nil,
}

local connect, spawn_daemon

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
  if #data == 0 or (#data == 1 and data[1] == "") then
    state.channel = nil
    for id, cb in pairs(state.pending) do
      state.pending[id] = nil
      cb("daemon disconnected", nil)
    end
    if state.account and not state.connecting then
      state.connecting = true
      vim.defer_fn(function()
        connect(function(err)
          if not err then on_connected()
          else          spawn_daemon(state.account) end
        end)
      end, 1000)
    end
    return
  end
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

connect = function(on_ready)
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

-- Kill signal-cli daemon JVM processes except our own (by PID).
-- Read /proc directly to avoid shell self-matching with pgrep -f.
local function kill_competing(own_pid)
  local pids = vim.fn.systemlist("pgrep java 2>/dev/null")
  for _, s in ipairs(pids) do
    local pid = tonumber(vim.trim(s))
    if pid and pid ~= own_pid then
      local f = io.open("/proc/" .. pid .. "/cmdline", "r")
      if f then
        local cmdline = f:read("*a"):gsub("%z", " ")
        f:close()
        if cmdline:find("signal%-cli") and cmdline:find("daemon") then
          vim.fn.system("kill -9 " .. pid .. " 2>/dev/null")
        end
      end
    end
  end
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

spawn_daemon = function(account)
  kill_competing(nil)
  os.remove(socket_path())  -- remove stale socket so new daemon can bind

  local stderr = vim.loop.new_pipe(false)
  local proc, pid = vim.loop.spawn(config.get().signal_cmd, {
    args   = { "-a", account, "daemon", "--socket",
               "--ignore-attachments", "--ignore-stories",
               "--receive-mode", "on-start" },
    stdio  = { nil, nil, stderr },
    detach = true,
  }, vim.schedule_wrap(function()
    state.own_proc = nil
  end))
  stderr:read_start(function() end)
  stderr:unref()
  proc:unref()
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
  local p = (params == nil or (type(params) == "table" and not next(params)))
    and vim.empty_dict() or params
  vim.fn.chansend(state.channel, vim.fn.json_encode({
    jsonrpc = "2.0", method = method, id = id,
    params  = p,
  }) .. "\n")
end

function M.start(account, on_recv)
  if state.channel or state.connecting then return end
  state.on_recv    = on_recv
  state.account    = account
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
  state.account = nil  -- prevent EOF handler from reconnecting on intentional close
  if state.channel then
    pcall(vim.fn.chanclose, state.channel)
    state.channel = nil
  end
  state.own_proc = nil
  state.buf = ""; state.pending = {}; state.connecting = false; state.call_queue = {}
end

function M.is_running()
  return state.channel ~= nil
end

return M
