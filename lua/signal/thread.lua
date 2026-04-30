local M      = {}
local cli    = require("signal.cli")
local config = require("signal.config")
local store  = require("signal.store")

local ns = vim.api.nvim_create_namespace("SignalThread")

local REACTIONS = { "👍", "❤️", "😂", "😮", "😢", "😡", "🔥", "✅", "👎" }

local state = {
  conversation   = nil,
  account        = nil,
  messages       = {},
  buf            = nil,
  win            = nil,
  input_buf      = nil,
  input_win      = nil,
  is_loading     = false,
  line_msg_map   = {},
  unread_at_open = 0,
}

local function avatar_char(name_or_id)
  local name  = name_or_id or "?"
  local parts = vim.split(name, " ", { plain = true, trimempty = true })
  if #parts >= 2 then
    return (parts[1]:sub(1, 1) .. parts[2]:sub(1, 1)):upper()
  end
  return name:sub(1, 1):upper()
end

local function avatar_hl(id_or_name)
  local key = id_or_name or ""
  local n   = 0
  for i = 1, #key do n = n + string.byte(key, i) end
  return "SignalAvatar" .. (n % 8 + 1)
end

local function write_buf(lines, specs)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, s in ipairs(specs or {}) do
    if s.hl_eol then
      vim.api.nvim_buf_set_extmark(state.buf, ns, s.line, s.col_s, {
        hl_group = s.hl,
        end_col  = s.col_e >= 0 and s.col_e or nil,
        hl_eol   = true,
      })
    else
      vim.api.nvim_buf_add_highlight(state.buf, ns, s.hl, s.line, s.col_s, s.col_e)
    end
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
      footer     = " s compose  ·  gr reply  ·  ra react  ·  rd delete  ·  q back ",
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

  -- first_unread_idx: index of the first unread message (for "New messages" separator)
  local unread_count     = state.unread_at_open or 0
  local first_unread_idx = (unread_count > 0 and unread_count < #state.messages)
    and (#state.messages - unread_count + 1) or nil

  -- pre-compute which messages show a header (message grouping)
  local show_headers = {}
  do
    local prev_sk = nil
    local prev_d  = nil
    for i, msg in ipairs(state.messages) do
      local sk = msg.source or "unknown"
      local d  = day_label(msg.timestamp or 0)
      if d ~= prev_d or i == first_unread_idx then prev_sk = nil end
      show_headers[i] = (sk ~= prev_sk)
      prev_sk = sk
      prev_d  = d
    end
  end

  for i, msg in ipairs(state.messages) do
    local is_self  = msg.source == state.account
    local sender   = is_self and "You" or (conv and conv.name or msg.source or "?")
    local time_str = format_ts(msg.timestamp)
    local body     = msg.message or ""
    local attach   = msg.attachments and "📎 " or ""
    local indent   = is_self and "        " or "    "

    -- date separator
    local this_day = day_label(msg.timestamp or 0)
    if this_day ~= prev_day then
      prev_day     = this_day
      local label  = this_day
      local pad    = win_w - #label - 8
      local bar    = string.rep("─", math.max(2, math.floor(pad / 2)))
      local div_ln = #lines
      table.insert(lines, "  " .. bar .. "  " .. label .. "  " .. bar)
      table.insert(specs, { hl = "SignalTime", line = div_ln, col_s = 0, col_e = -1 })
    end

    -- "New messages" separator
    if i == first_unread_idx then
      local label  = "New messages"
      local pad    = win_w - #label - 8
      local bar    = string.rep("─", math.max(2, math.floor(pad / 2)))
      local sep_ln = #lines
      table.insert(lines, "  " .. bar .. "  " .. label .. "  " .. bar)
      table.insert(specs, { hl = "SignalUnread", line = sep_ln, col_s = 0, col_e = -1 })
    end

    local receipt_glyph, receipt_hl = "", nil
    if is_self and not msg.deleted then
      if msg.status == "read" then
        receipt_glyph = "  ✓✓"
        receipt_hl    = "SignalReceiptRead"
      elseif msg.status == "delivered" then
        receipt_glyph = "  ✓✓"
        receipt_hl    = "SignalReceiptSent"
      elseif msg.status == "sent" then
        receipt_glyph = "  ✓"
        receipt_hl    = "SignalReceiptSent"
      elseif msg.status == "sending" then
        receipt_glyph = "  ⌛"
        receipt_hl    = "SignalLoading"
      elseif msg.status == "error" then
        receipt_glyph = "  ✗"
        receipt_hl    = "SignalSetupErr"
      end
    end

    local av_key  = is_self and "self" or (msg.source or sender)
    local av      = is_self and "Me" or avatar_char(sender)
    local av_hl_g = is_self and "SignalAvatarSelf" or avatar_hl(av_key)

    -- header (skipped for consecutive messages from same sender)
    if show_headers[i] then
      local header_ln   = #lines
      local header_line = "  " .. av .. " " .. sender .. "  " .. time_str .. receipt_glyph
      table.insert(lines, header_line)
      if is_self then
        table.insert(specs, { hl = "SignalMsgSelfBg", line = header_ln, col_s = 0, col_e = -1, hl_eol = true })
      end
      table.insert(specs, { hl = av_hl_g, line = header_ln, col_s = 2, col_e = 2 + #av })
      table.insert(specs, {
        hl = is_self and "SignalSenderSelf" or "SignalSenderOther",
        line = header_ln, col_s = 2 + #av + 1, col_e = 2 + #av + 1 + #sender,
      })
      local time_s = 2 + #av + 1 + #sender + 2
      local time_e = time_s + #time_str
      table.insert(specs, { hl = "SignalTime", line = header_ln, col_s = time_s, col_e = time_e })
      if receipt_hl then
        table.insert(specs, { hl = receipt_hl, line = header_ln, col_s = time_e, col_e = -1 })
      end
      state.line_msg_map[header_ln + 1] = msg
    end

    -- quote block
    if msg.quote and type(msg.quote) == "table" then
      local q_author_id   = msg.quote.author
      local q_author_name = q_author_id
      local conv_list = require("signal").get_state().conversations or {}
      for _, c in ipairs(conv_list) do
        if c.id == q_author_id then q_author_name = c.name; break end
      end
      if q_author_id == state.account then q_author_name = "You" end
      local q_author_hl = q_author_id == state.account and "SignalSenderSelf" or avatar_hl(q_author_id)
      local q_text   = (msg.quote.text or ""):match("([^\n]*)")
      local q_prefix = indent .. "\xe2\x94\x86 "
      local ql       = #lines
      table.insert(lines, q_prefix .. q_author_name .. ": " .. q_text:sub(1, win_w - #q_prefix - #q_author_name - 4))
      table.insert(specs, { hl = "SignalQuoteBg",  line = ql, col_s = 0,          col_e = -1,                          hl_eol = true })
      table.insert(specs, { hl = q_author_hl,      line = ql, col_s = #q_prefix,  col_e = #q_prefix + #q_author_name })
    end

    if msg.deleted then
      local del_ln = #lines
      table.insert(lines, indent .. "This message was deleted")
      table.insert(specs, { hl = "SignalTime", line = del_ln, col_s = #indent, col_e = -1 })
      state.line_msg_map[del_ln + 1] = msg
    else
      local body_lines = vim.split(body, "\n", { plain = true })
      for bi, bline in ipairs(body_lines) do
        local body_ln = #lines
        local prefix  = bi == 1 and (indent .. attach) or indent
        table.insert(lines, prefix .. bline)
        if is_self then
          table.insert(specs, { hl = "SignalMsgSelfBg", line = body_ln, col_s = 0,       col_e = -1, hl_eol = true })
        else
          table.insert(specs, { hl = "SignalMsgBody",   line = body_ln, col_s = #indent, col_e = -1 })
        end
        state.line_msg_map[body_ln + 1] = msg
      end

      if msg.reactions then
        local parts = {}
        for emoji, authors in pairs(msg.reactions) do
          if type(authors) == "table" and #authors > 0 then
            table.insert(parts, emoji .. " " .. #authors)
          end
        end
        if #parts > 0 then
          local rl = #lines
          table.insert(lines, indent .. table.concat(parts, "  "))
          table.insert(specs, { hl = "SignalReaction", line = rl, col_s = #indent, col_e = -1 })
          state.line_msg_map[rl + 1] = msg
        end
      end
    end

    -- blank line only before messages that start a new group (or after the last message)
    if i == #state.messages or show_headers[i + 1] then
      table.insert(lines, "")
    end
  end

  write_buf(lines, specs)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local last_msg_line = #lines
    while last_msg_line > 1 and not state.line_msg_map[last_msg_line] do
      last_msg_line = last_msg_line - 1
    end
    vim.api.nvim_win_set_cursor(state.win, { last_msg_line, 0 })
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
    zindex     = 250,
  })
  vim.wo[state.input_win].wrap      = true
  vim.wo[state.input_win].linebreak = true
  vim.cmd("startinsert!")

  local function do_send()
    local all_lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    local reply_lines = quoted_msg and vim.list_slice(all_lines, 2) or all_lines
    local body = table.concat(reply_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    local quote = quoted_msg and {
      id     = quoted_msg.timestamp,
      author = (quoted_msg.source and quoted_msg.source ~= vim.NIL)
        and quoted_msg.source
        or state.account,
      text   = quoted_msg.message or "",
    } or nil
    close_input()
    if body == "" or not conv then return end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end

    local pending_msg = {
      source    = state.account,
      message   = body,
      timestamp = os.time() * 1000,
      status    = "sending",
      _pending  = true,
      quote     = quote and { author = quote.author, text = quote.text } or nil,
    }
    table.insert(state.messages, pending_msg)
    render()

    if config.get().debug then
      local thread = DEBUG_THREADS[conv.id] or {}
      table.insert(thread, { source = state.account, message = body, timestamp = now_ms(), status = "sent" })
      DEBUG_THREADS[conv.id] = thread
      pending_msg._pending = nil
      pending_msg.status   = "sent"
      render()
      return
    end
    cli.send(state.account, conv.id, body, conv.kind == "group", function(err, result)
      for _, m in ipairs(state.messages) do
        if m._pending then
          m._pending = nil
          if err then
            m.status = "error"
            vim.notify("signal.nvim: send failed: " .. err, vim.log.levels.ERROR)
          else
            local srv_ts = type(result) == "table" and result.timestamp
            if srv_ts then m.timestamp = srv_ts end
            m.status = "sent"
            store.append(conv.id, m)
            require("signal").update_snippet(conv.id, body:sub(1, 40), os.date("%H:%M"))
          end
          break
        end
      end
      render()
    end, quote)
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
  bmap("ra", function()
    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
    local cur = vim.api.nvim_win_get_cursor(state.win)[1]
    local msg = state.line_msg_map[cur]
    if not msg or msg.deleted then return end
    vim.ui.select(REACTIONS, { prompt = "React:" }, function(emoji)
      if not emoji then return end
      local conv = state.conversation
      cli.send_reaction(state.account, conv.id, conv.kind == "group",
        emoji, msg.source, msg.timestamp, false,
        function(err)
          if err then
            vim.notify("signal.nvim: reaction failed: " .. err, vim.log.levels.ERROR)
          end
        end)
      store.add_reaction(conv.id, msg.timestamp, emoji, state.account, false)
      msg.reactions = msg.reactions or {}
      msg.reactions[emoji] = msg.reactions[emoji] or {}
      for _, a in ipairs(msg.reactions[emoji]) do
        if a == state.account then render(); return end
      end
      table.insert(msg.reactions[emoji], state.account)
      render()
    end)
  end)
  bmap("rd", function()
    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
    local cur = vim.api.nvim_win_get_cursor(state.win)[1]
    local msg = state.line_msg_map[cur]
    if not msg or msg.source ~= state.account or msg.deleted then return end
    vim.ui.input({ prompt = "Delete for everyone? (y/N): " }, function(answer)
      if answer ~= "y" then return end
      local conv = state.conversation
      cli.remote_delete(state.account, conv.id, conv.kind == "group", msg.timestamp,
        function(err)
          if err then
            vim.notify("signal.nvim: delete failed: " .. err, vim.log.levels.ERROR)
          else
            store.mark_deleted(conv.id, msg.timestamp)
            M.refresh()
          end
        end)
    end)
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

  state.is_loading = false
  state.messages   = require("signal.store").load(conv.id)
  render()
end

function M.open(conversation, account, buf, win, unread_at_open)
  state.conversation   = conversation
  state.account        = account
  state.buf            = buf
  state.win            = win
  state.messages       = {}
  state.line_msg_map   = {}
  state.unread_at_open = unread_at_open or 0
  register_keymaps()
  M.refresh()
end

return M
