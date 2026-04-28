local M = {}
local config = require("signal.config")

local SOCKET_PATH = (os.getenv("XDG_RUNTIME_DIR") or "/run/user/1000") .. "/signal-cli/socket"

local state = {
  pipe      = nil,   -- vim.loop pipe connected to daemon socket
  buf       = "",
  pending   = {},
  id_seq    = 0,
  on_recv   = nil,
  own_proc  = nil,   -- handle if WE spawned the daemon
  connecting = false,
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

local function on_data(err, data)
  if err or not data then return end
  state.buf = state.buf .. data
  while true do
    local nl = state.buf:find("\n")
    if not nl then break end
    local line = state.buf:sub(1, nl - 1)
    state.buf  = state.buf:sub(nl + 1)
    vim.schedule(function() process_line(line) end)
  end
end

local function connect(on_ready)
  local pipe = vim.loop.new_pipe(false)
  pipe:connect(SOCKET_PATH, function(err)
    if err then
      pipe:close()
      if on_ready then on_ready(err) end
      return
    end
    state.pipe = pipe
    pipe:read_start(on_data)
    if on_ready then on_ready(nil) end
  end)
end

local function wait_for_socket(account, on_ready, attempts)
  attempts = attempts or 0
  if attempts > 40 then  -- 20s max
    on_ready("timed out waiting for signal-cli daemon socket")
    return
  end
  local f = io.open(SOCKET_PATH, "r")
  if f then
    f:close()
    vim.defer_fn(function() connect(on_ready) end, 200)
  else
    vim.defer_fn(function() wait_for_socket(account, on_ready, attempts + 1) end, 500)
  end
end

local function spawn_daemon(account, on_ready)
  local stderr = vim.loop.new_pipe(false)
  local proc = vim.loop.spawn(config.get().signal_cmd, {
    args  = { "-a", account, "daemon", "--socket",
              "--ignore-attachments", "--ignore-stories",
              "--receive-mode", "on-start" },
    stdio = { nil, nil, stderr },
  }, vim.schedule_wrap(function()
    state.own_proc = nil
  end))
  stderr:read_start(function() end)  -- drain stderr
  state.own_proc = proc
  wait_for_socket(account, on_ready)
end

function M.call(method, params, callback)
  if not state.pipe then callback("daemon not connected", nil); return end
  state.id_seq = state.id_seq + 1
  local id = state.id_seq
  state.pending[id] = callback
  state.pipe:write(vim.fn.json_encode({
    jsonrpc = "2.0", method = method, id = id,
    params  = params or vim.empty_dict(),
  }) .. "\n")
end

function M.start(account, on_recv)
  if state.pipe or state.connecting then return end
  state.on_recv   = on_recv
  state.connecting = true

  connect(function(err)
    state.connecting = false
    if not err then
      -- Socket already running — just use it; send sync request after brief delay
      vim.defer_fn(function()
        M.call("sendSyncRequest", {}, function() end)
      end, 1000)
      return
    end
    -- No socket — spawn the daemon ourselves
    spawn_daemon(account, function(spawn_err)
      state.connecting = false
      if spawn_err then
        vim.schedule(function()
          vim.notify("signal.nvim: daemon failed: " .. spawn_err, vim.log.levels.WARN)
        end)
        return
      end
      vim.defer_fn(function()
        M.call("sendSyncRequest", {}, function() end)
      end, 2000)
    end)
  end)
end

function M.stop()
  if state.pipe then
    state.pipe:close()
    state.pipe = nil
  end
  if state.own_proc then
    state.own_proc:kill(15)
    state.own_proc = nil
  end
  state.buf = ""; state.pending = {}; state.connecting = false
end

function M.is_running()
  return state.pipe ~= nil
end

return M
