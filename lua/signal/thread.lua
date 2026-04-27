local M   = {}
local cli = require("signal.cli")

local ns = vim.api.nvim_create_namespace("SignalThread")

local state = {
  conversation = nil,
  account      = nil,
  messages     = {},
  buf          = nil,
  win          = nil,
  input_buf    = nil,
  input_win    = nil,
  is_loading   = false,
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

local function ts_to_hhmm(ts)
  if not ts or ts == 0 then return "" end
  return os.date("%H:%M", math.floor(ts / 1000))
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local conv = state.conversation
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      title      = " " .. (conv and conv.name or "Thread") .. " ",
      title_pos  = "center",
      footer     = " s compose  ·  r refresh  ·  q back ",
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

  local lines = { "" }
  local specs = {}
  local phone = config.get().phone_number

  for _, msg in ipairs(state.messages) do
    local is_self  = msg.source == state.account
    local sender   = is_self and "You" or (conv and conv.name or msg.source or "?")
    local time_str = ts_to_hhmm(msg.timestamp)
    local body     = msg.message or ""

    local header_ln = #lines
    table.insert(lines, "  " .. sender .. "  " .. time_str)
    table.insert(specs, {
      hl = is_self and "SignalSenderSelf" or "SignalSenderOther",
      line = header_ln, col_s = 2, col_e = 2 + #sender,
    })
    table.insert(specs, {
      hl = "SignalTime",
      line = header_ln, col_s = 2 + #sender + 2, col_e = -1,
    })

    for _, bline in ipairs(vim.split(body, "\n", { plain = true })) do
      local body_ln = #lines
      table.insert(lines, "    " .. bline)
      table.insert(specs, { hl = "SignalMsgBody", line = body_ln, col_s = 4, col_e = -1 })
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

local function open_input()
  close_input()

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype   = "nofile"
  vim.bo[state.input_buf].bufhidden = "wipe"
  vim.bo[state.input_buf].filetype  = "text"
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  local ui   = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local w    = math.floor(ui.width * 0.60)
  local h    = 8
  local conv = state.conversation

  state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
    relative   = "editor",
    width      = w,
    height     = h,
    row        = math.floor((ui.height - h) / 2),
    col        = math.floor((ui.width  - w) / 2),
    style      = "minimal",
    border     = "rounded",
    title      = " Send to " .. (conv and conv.name or "?") .. " ",
    title_pos  = "center",
    footer     = " <C-s> send  ·  q / <Esc> cancel ",
    footer_pos = "center",
  })
  vim.wo[state.input_win].wrap      = true
  vim.wo[state.input_win].linebreak = true
  vim.cmd("startinsert")

  local function do_send()
    local all_lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    local body = table.concat(all_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    close_input()
    if body == "" or not conv then return end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
    cli.send(state.account, conv.id, body, conv.kind == "group", function(err)
      if err then
        vim.notify("signal.nvim: send failed: " .. err, vim.log.levels.ERROR)
      else
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
  bmap("s", open_input)
  bmap("r", M.refresh)
end

function M.refresh()
  state.is_loading = true
  render()
  cli.receive(state.account, function(err, data)
    if err then
      vim.notify("signal.nvim: receive error: " .. err, vim.log.levels.WARN)
      state.is_loading = false
      render()
      return
    end
    local msgs = {}
    if type(data) == "table" then
      for _, envelope in ipairs(data) do
        local dm  = envelope.dataMessage
          or (envelope.envelope and envelope.envelope.dataMessage)
        local src = envelope.source
          or (envelope.envelope and envelope.envelope.source)
        if dm and dm.message then
          table.insert(msgs, {
            source    = src,
            message   = dm.message,
            timestamp = dm.timestamp or envelope.timestamp or 0,
          })
        end
      end
    end
    table.sort(msgs, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)
    state.messages   = msgs
    state.is_loading = false
    render()
  end)
end

function M.open(conversation, account, buf, win)
  state.conversation = conversation
  state.account      = account
  state.buf          = buf
  state.win          = win
  state.messages     = {}
  register_keymaps()
  M.refresh()
end

return M
