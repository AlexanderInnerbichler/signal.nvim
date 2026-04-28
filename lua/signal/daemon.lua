local M = {}
local config = require("signal.config")

local state = {
  proc    = nil,
  stdin   = nil,
  stdout  = nil,
  buf     = "",
  pending = {},
  id_seq  = 0,
  on_recv = nil,
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

local function on_stdout(err, data)
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

function M.call(method, params, callback)
  if not state.proc then callback("daemon not running", nil); return end
  state.id_seq = state.id_seq + 1
  local id = state.id_seq
  state.pending[id] = callback
  state.stdin:write(vim.fn.json_encode({
    jsonrpc = "2.0", method = method, id = id,
    params  = params or vim.empty_dict(),
  }) .. "\n")
end

function M.start(account, on_recv)
  if state.proc then return end
  state.on_recv = on_recv
  local si = vim.loop.new_pipe(false)
  local so = vim.loop.new_pipe(false)
  local se = vim.loop.new_pipe(false)
  state.proc = vim.loop.spawn(config.get().signal_cmd, {
    args  = { "-a", account, "--output=json",
              "jsonRpc", "--ignore-attachments", "--ignore-stories",
              "--receive-mode", "on-start" },
    stdio = { si, so, se },
  }, vim.schedule_wrap(function()
    state.proc = nil; state.stdin = nil; state.stdout = nil
  end))
  state.stdin  = si
  state.stdout = so
  so:read_start(on_stdout)
  se:read_start(function() end)
end

function M.stop()
  if state.proc then state.proc:kill(15) end
  state.proc = nil; state.stdin = nil; state.stdout = nil
  state.buf = ""; state.pending = {}
end

function M.is_running() return state.proc ~= nil end

return M
