local M      = {}
local cli    = require("signal.cli")
local config = require("signal.config")

local ns = vim.api.nvim_create_namespace("SignalThread")

local state = {
  conversation  = nil,
  account       = nil,
  messages      = {},
  buf           = nil,
  win           = nil,
  input_buf     = nil,
  input_win     = nil,
  is_loading    = false,
  line_msg_map  = {},
}

local function write_buf(lines, specs)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, s in ipairs(specs or {}) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, s.hl, s.line, s.col_s, s.col_e)
  end
end

local function format_ts(ts)
  if not ts or ts == 0 then return "" end
  local t        = math.floor(ts / 1000)
  local now      = os.time()
  local day_secs = 86400
  local tz_off   = os.time(os.date("*t", now)) - os.time(os.date("!*t", now))
  local today_s  = math.floor((now + tz_off) / day_secs) * day_secs - tz_off
  if t >= today_s then
    return os.date("%H:%M", t)
  elseif t >= today_s - day_secs then
    return "Yesterday " .. os.date("%H:%M", t)
  elseif t >= today_s - 6 * day_secs then
    return os.date("%a %H:%M", t)
  else
    return os.date("%d %b", t)
  end
end

local function day_label(ts)
  if not ts or ts == 0 then return "Unknown" end
  local t       = math.floor(ts / 1000)
  local now     = os.time()
  local tz_off  = os.time(os.date("*t", now)) - os.time(os.date("!*t", now))
  local today_s = math.floor((now + tz_off) / 86400) * 86400 - tz_off
  if t >= today_s             then return "Today"
  elseif t >= today_s - 86400 then return "Yesterday"
  elseif t >= today_s - 6 * 86400 then return os.date("%A", t)
  else return os.date("%d %b %Y", t) end
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local conv = state.conversation
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      title      = " " .. (conv and conv.name or "Thread") .. " ",
      title_pos  = "center",
      footer     = " s compose  ·  gr reply  ·  r refresh  ·  q back ",
      footer_pos = "center",
    })
  end

  if state.is_loading then
    write_buf({ "", "  Loading…" }, { { hl = "SignalLoading", line = 1, col_s = 0, col_e = -1 } })
    return
  end

  if #state.messages == 0 then
    write_buf({ "", "  No messages yet. Press s to compose." }, {})
    return
  end

  local win_w = state.win and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_width(state.win) or 80

  local lines = { "" }
  local specs = {}
  state.line_msg_map = {}

  local prev_day = nil

  for _, msg in ipairs(state.messages) do
    local is_self  = msg.source == state.account
    local sender   = is_self and "You" or (conv and conv.name or msg.source or "?")
    local time_str = format_ts(msg.timestamp)
    local body     = msg.message or ""
    local attach   = msg.attachments and "📎 " or ""

    -- date separator
    local this_day = day_label(msg.timestamp or 0)
    if this_day ~= prev_day then
      prev_day       = this_day
      local label    = this_day
      local pad      = win_w - #label - 8
      local bar      = string.rep("─", math.max(2, math.floor(pad / 2)))
      local div_ln   = #lines
      table.insert(lines, "  " .. bar .. "  " .. label .. "  " .. bar)
      table.insert(specs, { hl = "SignalTime", line = div_ln, col_s = 0, col_e = -1 })
    end

    local receipt_glyph, receipt_hl = "", nil
    if is_self then
      if msg.status == "read" then
        receipt_glyph = "  ✓✓"
        receipt_hl    = "SignalReceiptRead"
      elseif msg.status == "delivered" then
        receipt_glyph = "  ✓✓"
        receipt_hl    = "SignalReceiptSent"
      elseif msg.status == "sent" then
        receipt_glyph = "  ✓"
        receipt_hl    = "SignalReceiptSent"
      end
    end

    local header_ln   = #lines
    local header_line = "  " .. sender .. "  " .. time_str .. receipt_glyph
    table.insert(lines, header_line)
    table.insert(specs, {
      hl = is_self and "SignalSenderSelf" or "SignalSenderOther",
      line = header_ln, col_s = 2, col_e = 2 + #sender,
    })
    local time_s = 2 + #sender + 2
    local time_e = time_s + #time_str
    table.insert(specs, { hl = "SignalTime", line = header_ln, col_s = time_s, col_e = time_e })
    if receipt_hl then
      table.insert(specs, { hl = receipt_hl, line = header_ln, col_s = time_e, col_e = -1 })
    end
    state.line_msg_map[header_ln + 1] = msg

    local body_lines = vim.split(body, "\n", { plain = true })
    for bi, bline in ipairs(body_lines) do
      local body_ln = #lines
      local prefix  = bi == 1 and ("    " .. attach) or "    "
      table.insert(lines, prefix .. bline)
      table.insert(specs, { hl = "SignalMsgBody", line = body_ln, col_s = 4, col_e = -1 })
      state.line_msg_map[body_ln + 1] = msg
    end
    table.insert(lines, "")
  end

  write_buf(lines, specs)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { #lines, 0 })
  end
end

local function close_input()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end
  state.input_win = nil
  state.input_buf = nil
end

local function open_input(quoted_msg)
  close_input()

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype   = "nofile"
  vim.bo[state.input_buf].bufhidden = "wipe"
  vim.bo[state.input_buf].filetype  = "text"

  local conv = state.conversation

  if quoted_msg then
    local qsender  = quoted_msg.source == state.account
      and "You"
      or (conv and conv.name or quoted_msg.source or "?")
    local qbody    = (quoted_msg.message or ""):match("([^\n]*)")
    vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false,
      { "> " .. qsender .. ": " .. qbody, "" })
  else
    vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
  end

  local ui  = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local w   = math.floor(ui.width * 0.60)
  local h   = 8
  local ttl = quoted_msg
    and (" Reply to " .. (conv and conv.name or "?") .. " ")
    or  (" Send to "  .. (conv and conv.name or "?") .. " ")

  state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
    relative   = "editor",
    width      = w,
    height     = h,
    row        = math.floor((ui.height - h) / 2),
    col        = math.floor((ui.width  - w) / 2),
    style      = "minimal",
    border     = "rounded",
    title      = ttl,
    title_pos  = "center",
    footer     = " <C-s> send  ·  q / <Esc> cancel ",
    footer_pos = "center",
  })
  vim.wo[state.input_win].wrap      = true
  vim.wo[state.input_win].linebreak = true
  vim.cmd("startinsert!")

  local function do_send()
    local all_lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    local body = table.concat(all_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    close_input()
    if body == "" or not conv then return end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
    if config.get().debug then
      local thread = DEBUG_THREADS[conv.id] or {}
      table.insert(thread, { source = state.account, message = body, timestamp = now_ms(), status = "sent" })
      DEBUG_THREADS[conv.id] = thread
      require("signal.notifs").show_sent_toast()
      M.refresh()
      return
    end
    cli.send(state.account, conv.id, body, conv.kind == "group", function(err)
      if err then
        vim.notify("signal.nvim: send failed: " .. err, vim.log.levels.ERROR)
      else
        require("signal.notifs").show_sent_toast()
        M.refresh()
      end
    end)
  end

  local function imap(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = state.input_buf, nowait = true, silent = true })
  end
  imap("n", "<C-s>", do_send)
  imap("i", "<C-s>", do_send)
  imap("n", "q",     close_input)
  imap("n", "<Esc>", close_input)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = state.input_buf,
    once     = true,
    callback = function()
      state.input_buf = nil
      state.input_win = nil
    end,
  })
end

local function register_keymaps()
  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end
  bmap("q",     function()
    close_input()
    require("signal").return_to_list()
  end)
  bmap("<Esc>", function()
    close_input()
    require("signal").return_to_list()
  end)
  bmap("s",    function() open_input() end)
  bmap("r",    M.refresh)
  bmap("p",    function()
    if state.conversation then
      require("signal").show_profile(state.conversation)
    end
  end)
  bmap("gr",   function()
    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
    local cur = vim.api.nvim_win_get_cursor(state.win)[1]
    local msg = state.line_msg_map[cur]
    if msg then open_input(msg) end
  end)
end

local function now_ms() return os.time() * 1000 end
local function ago_ms(minutes) return (os.time() - minutes * 60) * 1000 end

local DEBUG_THREADS = {
  ["+43111000001"] = {  -- Alice
    { source = "+43111000001", message = "Hey! Are you free this weekend?",       timestamp = ago_ms(120) },
    { source = "+43000000000", message = "Yeah, what did you have in mind?",       timestamp = ago_ms(118), status = "read" },
    { source = "+43111000001", message = "Maybe hiking? The weather looks great.", timestamp = ago_ms(115), attachments = true },
    { source = "+43000000000", message = "I'm in! Saturday or Sunday?",            timestamp = ago_ms(110), status = "read" },
    { source = "+43111000001", message = "Saturday works. Let's say 10am?",        timestamp = ago_ms(90)  },
    { source = "+43000000000", message = "Perfect, see you then!",                 timestamp = ago_ms(88),  status = "read" },
    { source = "+43111000001", message = "Hey, how are you?",                      timestamp = ago_ms(5)   },
  },
  ["+43111000002"] = {  -- Bob
    { source = "+43000000000", message = "Did you get the deploy done?",           timestamp = ago_ms(60), status = "read" },
    { source = "+43111000002", message = "Almost, ran into a migration issue.",     timestamp = ago_ms(55) },
    { source = "+43000000000", message = "Need help?",                             timestamp = ago_ms(54), status = "delivered" },
    { source = "+43111000002", message = "Nah got it. See you tomorrow!",           timestamp = ago_ms(10) },
  },
  ["+43111000003"] = {  -- Charlie (no recent messages)
    { source = "+43111000003", message = "Talk later?",                            timestamp = ago_ms(2880) },
    { source = "+43000000000", message = "Sure, ping me anytime.",                 timestamp = ago_ms(2870) },
  },
  ["group-abc"] = {  -- Family Group
    { source = "+43111000001", message = "Who's coming Sunday?",                   timestamp = ago_ms(200) },
    { source = "+43111000002", message = "We'll be there 👍",                      timestamp = ago_ms(195) },
    { source = "+43000000000", message = "Same, bringing dessert.",                timestamp = ago_ms(190), status = "read" },
    { source = "+43111000001", message = "Dinner on Sunday?",                      timestamp = ago_ms(30)  },
  },
  ["group-xyz"] = {  -- Work Team
    { source = "+43111000002", message = "PR is up, needs review.",                timestamp = ago_ms(300) },
    { source = "+43000000000", message = "On it.",                                 timestamp = ago_ms(295), status = "read" },
    { source = "+43111000002", message = "PR merged — deploying now",              timestamp = ago_ms(10)  },
  },
  ["+43111000004"] = {  -- Mia
    { source = "+43000000000", message = "Hey, what's up?",                        timestamp = ago_ms(80)  },
    { source = "+43111000004", message = "Not much, busy day.",                     timestamp = ago_ms(75)  },
    { source = "+43111000004", message = "Can you call me later?",                  timestamp = ago_ms(12)  },
    { source = "+43111000004", message = "It's important.",                         timestamp = ago_ms(11)  },
    { source = "+43111000004", message = "Like, really important.",                 timestamp = ago_ms(3)   },
  },
  ["+43111000005"] = {  -- David
    { source = "+43000000000", message = "Do you know how to fix this webpack issue?", timestamp = ago_ms(1440) },
    { source = "+43111000005", message = "Yeah, try clearing node_modules.",         timestamp = ago_ms(1435) },
    { source = "+43000000000", message = "That worked, legend!",                    timestamp = ago_ms(1430) },
    { source = "+43111000005", message = "Thanks for the help!",                    timestamp = ago_ms(1428) },
  },
  ["+43111000006"] = {  -- Sophie
    { source = "+43111000006", message = "Running 10 min late, sorry",              timestamp = ago_ms(25)  },
    { source = "+43000000000", message = "No worries, I'll grab a coffee",          timestamp = ago_ms(23)  },
  },
  ["+43111000007"] = {  -- Lukas (no recent)
    { source = "+43111000007", message = "Good game yesterday",                     timestamp = ago_ms(5760) },
    { source = "+43000000000", message = "Yeah was fun, rematch soon?",             timestamp = ago_ms(5758) },
  },
  ["group-def"] = {  -- Team Sprint
    { source = "+43111000002", message = "Sprint planning in 10",                   timestamp = ago_ms(600) },
    { source = "+43111000005", message = "On my way",                               timestamp = ago_ms(595) },
    { source = "+43000000000", message = "Same",                                    timestamp = ago_ms(594) },
    { source = "+43111000002", message = "Velocity was 42 points this sprint 🎉",   timestamp = ago_ms(60)  },
    { source = "+43111000005", message = "Retro is at 15:00 tomorrow",              timestamp = ago_ms(15)  },
  },
  ["group-ghi"] = {  -- Climbing Crew
    { source = "+43111000003", message = "Anyone up for bouldering Saturday?",      timestamp = ago_ms(2880) },
    { source = "+43000000000", message = "I'm in!",                                 timestamp = ago_ms(2875) },
    { source = "+43111000006", message = "Me too",                                  timestamp = ago_ms(2870) },
    { source = "+43111000003", message = "New route opened at Kletterhalle",        timestamp = ago_ms(120)  },
  },
}

local function parse_msg(item, account)
  local env  = item.envelope or item
  local dm   = env.dataMessage
  local sync = env.syncMessage
  local src  = env.source

  if dm and dm.message then
    return {
      source      = src,
      message     = dm.message,
      timestamp   = dm.timestamp or env.timestamp or 0,
      attachments = dm.attachments and #dm.attachments > 0,
    }
  end

  if sync and sync.sentMessage and sync.sentMessage.message then
    local sm = sync.sentMessage
    return {
      source      = account,
      message     = sm.message,
      timestamp   = sm.timestamp or 0,
      attachments = sm.attachments and #sm.attachments > 0,
      status      = "sent",
    }
  end
end

function M.get_current_conv_id()
  return state.conversation and state.conversation.id
end

function M.append_message(msg)
  if not state.conversation then return end
  local ts = msg.timestamp or 0
  for _, m in ipairs(state.messages) do
    if m.timestamp == ts and m.source == msg.source then return end
  end
  table.insert(state.messages, msg)
  table.sort(state.messages, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)
  render()
end

function M.refresh()
  if config.get().debug then
    local conv_id = state.conversation and state.conversation.id
    local msgs = DEBUG_THREADS[conv_id] or {}
    state.messages   = msgs
    state.is_loading = false
    if state.conversation and #msgs > 0 then
      local last = msgs[#msgs]
      local icon = last.attachments and "📎 " or ""
      state.conversation.snippet = icon .. (last.message or "")
    end
    render()
    return
  end

  local conv = state.conversation
  if not conv then return end

  state.is_loading = true
  render()

  cli.list_messages(state.account, conv.id, function(err, data)
    vim.schedule(function()
      if err then
        -- listMessages unavailable (signal-cli 0.14.x) — show in-memory messages
        -- (populated by notifs.append_message when new messages arrive)
        state.is_loading = false
        render()
        return
      end
      local msgs = {}
      if type(data) == "table" then
        for _, item in ipairs(data) do
          local msg = parse_msg(item, state.account)
          if msg then table.insert(msgs, msg) end
        end
      end
      table.sort(msgs, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)
      state.messages   = msgs
      state.is_loading = false
      render()
    end)
  end)
end

function M.open(conversation, account, buf, win)
  state.conversation = conversation
  state.account      = account
  state.buf          = buf
  state.win          = win
  state.messages     = {}
  state.line_msg_map = {}
  register_keymaps()
  M.refresh()
end

return M
