local M      = {}
local config = require("signal.config")

local NOTIF_WIDTH  = 55
local NOTIF_HEIGHT = 3

local state = {
  seen_ts    = {},
  unread     = {},
  toasts     = {},
  own_number = nil,
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
    relative  = "editor",
    width     = NOTIF_WIDTH,
    height    = NOTIF_HEIGHT,
    row       = row,
    col       = ui.width - NOTIF_WIDTH - 2,
    style     = "minimal",
    border    = "rounded",
    zindex    = 50,
    title     = " Signal ",
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

local function fmt_ts(ts)
  if not ts or ts == 0 then return "" end
  local t       = math.floor(ts / 1000)
  local now     = os.time()
  local tz_off  = os.time(os.date("*t", now)) - os.time(os.date("!*t", now))
  local today_s = math.floor((now + tz_off) / 86400) * 86400 - tz_off
  if t >= today_s             then return os.date("%H:%M", t)
  elseif t >= today_s - 86400 then return "Yesterday"
  elseif t >= today_s - 6 * 86400 then return os.date("%a", t)
  else return os.date("%d %b", t) end
end

function M.process_messages(messages)
  if type(messages) ~= "table" then return end

  local signal_init = require("signal")
  local main_state  = signal_init.get_state()
  local store       = require("signal.store")

  for _, envelope in ipairs(messages) do
    local dm  = envelope.dataMessage or (envelope.envelope and envelope.envelope.dataMessage)
    local src = envelope.source or (envelope.envelope and envelope.envelope.source)
    local ts  = (dm and dm.timestamp) or envelope.timestamp or 0

    if dm and dm.message and src then
      local last = state.seen_ts[src] or 0
      if ts > last then
        state.seen_ts[src] = ts
        state.unread[src]  = (state.unread[src] or 0) + 1

        local snippet  = dm.message:sub(1, 40)
        local time_str = fmt_ts(ts)
        local name     = src

        for _, c in ipairs(main_state.conversations or {}) do
          if c.id == src then
            name     = c.name
            c.unread = state.unread[src]
            break
          end
        end

        store.append(src, { source = src, message = dm.message, timestamp = ts, is_self = false })

        local thread = require("signal.thread")
        if thread.get_current_conv_id() == src then
          thread.append_message({ source = src, message = dm.message, timestamp = ts })
        end

        show_toast(name .. ": " .. snippet)
        signal_init.update_snippet(src, snippet, time_str)
      end
    end

    -- Incoming reaction
    if dm and dm.reaction and src then
      local r = dm.reaction
      store.add_reaction(src, r.targetTimestamp, r.emoji, src, r.remove or false)
      local thread = require("signal.thread")
      if thread.get_current_conv_id() == src then thread.refresh() end
    end

    -- Incoming remote delete
    if dm and dm.remoteDelete and src then
      store.mark_deleted(src, dm.remoteDelete.targetTimestamp)
      local thread = require("signal.thread")
      if thread.get_current_conv_id() == src then thread.refresh() end
    end

    -- Sent message sync: messages you sent from your phone
    local raw_env = envelope.envelope or envelope
    local sync    = raw_env.syncMessage
    local sm      = sync and sync.sentMessage
    if sm and sm.message then
      local dest_id
      if sm.groupInfo then
        dest_id = sm.groupInfo.groupId
      else
        dest_id = sm.destinationNumber or sm.destination
      end
      local sm_ts = sm.timestamp or 0
      if dest_id and sm_ts > (state.seen_ts[dest_id] or 0) then
        state.seen_ts[dest_id] = sm_ts
        local snippet  = sm.message:sub(1, 40)
        local time_str = fmt_ts(sm_ts)
        store.append(dest_id, {
          source    = state.own_number or "self",
          message   = sm.message,
          timestamp = sm_ts,
          is_self   = true,
        })
        signal_init.update_snippet(dest_id, snippet, time_str)
      end
    end
  end
end

function M.show_sent_toast()
  show_toast("✓ Sent")
end

function M.get_unread(id)
  return state.unread[id] or 0
end

function M.clear_unread(id)
  state.unread[id] = 0
end

function M.setup()
  if config.get().debug then return end

  local ok = config.ready()
  if not ok then return end

  config.resolve_account(function(number)
    if not number then return end
    state.own_number = number
    local daemon = require("signal.daemon")
    daemon.start(number, function(params)
      M.process_messages({ params })
    end)
  end)
end

function M.stop()
  require("signal.daemon").stop()
end

return M
