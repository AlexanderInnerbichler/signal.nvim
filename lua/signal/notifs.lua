local M      = {}
local cli    = require("signal.cli")
local config = require("signal.config")

local NOTIF_WIDTH  = 55
local NOTIF_HEIGHT = 3

local state = {
  timer    = nil,
  seen_ts  = {},
  unread   = {},
  toasts   = {},
}

local function dismiss_toast(toast)
  if toast.timer then
    toast.timer:close()
    toast.timer = nil
  end
  if toast.win and vim.api.nvim_win_is_valid(toast.win) then
    vim.api.nvim_win_close(toast.win, true)
  end
  for i, t in ipairs(state.toasts) do
    if t == toast then
      table.remove(state.toasts, i)
      break
    end
  end
end

local function show_toast(text)
  local ui  = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local row = ui.height - (#state.toasts * (NOTIF_HEIGHT + 1)) - NOTIF_HEIGHT - 2

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].modifiable = true
  local trimmed = text:sub(1, NOTIF_WIDTH - 4)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false,
    { "", "  " .. trimmed })
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width    = NOTIF_WIDTH,
    height   = NOTIF_HEIGHT,
    row      = row,
    col      = ui.width - NOTIF_WIDTH - 2,
    style    = "minimal",
    border   = "rounded",
    zindex   = 50,
    title    = " Signal ",
    title_pos = "center",
  })

  local toast = { buf = buf, win = win, timer = nil }
  table.insert(state.toasts, toast)

  local ttl = config.get().notif_ttl * 1000
  toast.timer = vim.uv.new_timer()
  toast.timer:start(ttl, 0, vim.schedule_wrap(function()
    dismiss_toast(toast)
  end))

  vim.keymap.set("n", "q", function() dismiss_toast(toast) end,
    { buffer = buf, nowait = true, silent = true })
end

local function process_messages(messages)
  if type(messages) ~= "table" then return end

  local signal_init = require("signal")
  local main_state  = signal_init.get_state()

  for _, envelope in ipairs(messages) do
    local dm  = envelope.dataMessage or (envelope.envelope and envelope.envelope.dataMessage)
    local src = envelope.source or (envelope.envelope and envelope.envelope.source)
    local ts  = (dm and dm.timestamp) or envelope.timestamp or 0

    if dm and dm.message and src then
      local last = state.seen_ts[src] or 0
      if ts > last then
        state.seen_ts[src] = ts
        state.unread[src]  = (state.unread[src] or 0) + 1

        local name = src
        for _, c in ipairs(main_state.conversations or {}) do
          if c.id == src then
            name = c.name
            c.snippet = dm.message:sub(1, 40)
            c.unread  = state.unread[src]
            break
          end
        end

        show_toast(name .. ": " .. dm.message:sub(1, 40))

        if main_state.win and vim.api.nvim_win_is_valid(main_state.win) then
          local render = require("signal.init_render")
          if render then render() end
        end
      end
    end
  end
end

function M.get_unread(id)
  return state.unread[id] or 0
end

function M.clear_unread(id)
  state.unread[id] = 0
end

function M.setup()
  if state.timer then
    state.timer:close()
    state.timer = nil
  end

  local ok = config.ready()
  if not ok then return end

  config.resolve_account(function(number)
    if not number then return end
    local interval = config.get().poll_interval * 1000
    state.timer = vim.uv.new_timer()
    state.timer:start(interval, interval, vim.schedule_wrap(function()
      cli.receive(number, function(err, data)
        if err or not data then return end
        process_messages(data)
      end)
    end))
  end)
end

function M.stop()
  if state.timer then
    state.timer:close()
    state.timer = nil
  end
end

return M
