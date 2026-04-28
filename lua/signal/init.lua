local M      = {}
local cli    = require("signal.cli")
local config = require("signal.config")

local ns = vim.api.nvim_create_namespace("Signal")

local PIN_FILE      = vim.fn.expand("~/.local/share/signal-cli/nvim-pinned.json")
local SNIPPET_CACHE = vim.fn.expand("~/.local/share/signal-cli/nvim-snippets.json")

local snippet_cache = nil  -- lazy-loaded; persists for the session

local function get_snippet_cache()
  if snippet_cache then return snippet_cache end
  local f = io.open(SNIPPET_CACHE, "r")
  if not f then snippet_cache = {}; return snippet_cache end
  local raw = f:read("*a"); f:close()
  local ok, data = pcall(vim.fn.json_decode, raw)
  snippet_cache = (ok and type(data) == "table") and data or {}
  return snippet_cache
end

local function flush_snippet_cache()
  if not snippet_cache then return end
  local ok, enc = pcall(vim.fn.json_encode, snippet_cache)
  if not ok then return end
  local f = io.open(SNIPPET_CACHE, "w")
  if f then f:write(enc); f:close() end
end

local SPINNER = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" }

local state = {
  buf            = nil,
  win            = nil,
  conversations  = {},
  is_loading     = false,
  auth_error     = false,
  account        = nil,
  line_conv_map  = {},
  filter         = "",
  pinned         = {},
  last_sync      = nil,
  spinner_timer  = nil,
  spinner_frame  = 1,
}

local function load_pins()
  local f = io.open(PIN_FILE, "r")
  if not f then return {} end
  local raw = f:read("*a")
  f:close()
  local ok, data = pcall(vim.fn.json_decode, raw)
  if ok and type(data) == "table" then return data end
  return {}
end

local function save_pins(set)
  local ok, encoded = pcall(vim.fn.json_encode, set)
  if not ok then return end
  local f = io.open(PIN_FILE, "w")
  if f then f:write(encoded) f:close() end
end

local function make_footer()
  local base = " <CR> open  ·  /  filter  ·  r refresh"
  local sync = state.last_sync and ("  ·  synced " .. os.date("%H:%M", state.last_sync)) or ""
  return base .. sync .. "  ·  q close "
end

local function is_valid()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
    and state.win and vim.api.nvim_win_is_valid(state.win)
end

local function write_buf(lines, hl_specs)
  if not is_valid() then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, s in ipairs(hl_specs or {}) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, s.hl, s.line, s.col_s, s.col_e)
  end
end

local render_list  -- forward declaration for spinner callback

local function start_spinner()
  if state.spinner_timer then return end
  state.spinner_frame = 1
  state.spinner_timer = vim.uv.new_timer()
  state.spinner_timer:start(0, 80, vim.schedule_wrap(function()
    if not is_valid() then return end
    state.spinner_frame = (state.spinner_frame % #SPINNER) + 1
    render_list()
  end))
end

local function stop_spinner()
  if state.spinner_timer then
    state.spinner_timer:stop()
    state.spinner_timer:close()
    state.spinner_timer = nil
  end
end

render_list = function()
  if not is_valid() then return end

  local total_unread = 0
  for _, c in ipairs(state.conversations) do
    total_unread = total_unread + (c.unread or 0)
  end
  local title = total_unread > 0
    and (" Signal [" .. total_unread .. "] ")
    or  " Signal "
  local footer = state.filter ~= ""
    and (" / " .. state.filter .. "  ·  <Esc> clear ")
    or  make_footer()
  vim.api.nvim_win_set_config(state.win, {
    title      = title,
    title_pos  = "center",
    footer     = footer,
    footer_pos = "center",
  })

  if state.is_loading then
    local frame = SPINNER[state.spinner_frame] or "⠋"
    write_buf({ "", "  " .. frame .. "  Syncing…" },
      { { hl = "SignalLoading", line = 1, col_s = 0, col_e = -1 } })
    return
  end

  if state.auth_error then
    write_buf({
      "",
      "  Not linked to Signal.",
      "",
      "  Run :SignalSetup to reconnect.",
    }, {
      { hl = "SignalLoading", line = 1, col_s = 0, col_e = -1 },
      { hl = "SignalLoading", line = 3, col_s = 0, col_e = -1 },
    })
    return
  end

  local win_width     = vim.api.nvim_win_get_width(state.win)
  local lines         = { "" }
  local specs         = {}
  state.line_conv_map = {}

  local function push_label(label)
    local lnum = #lines
    table.insert(lines, "  " .. label:upper())
    table.insert(lines, "")
    table.insert(specs, { hl = "SignalSectionLabel", line = lnum, col_s = 0, col_e = -1 })
  end

  local function push_gap()
    table.insert(lines, "")
  end

  local function time_hl(timestr)
    if not timestr or timestr == "" then return "SignalTime" end
    if timestr:match("^%d%d?:%d%d")   then return "SignalTimeHot"
    elseif timestr:match("^Yesterday") then return "SignalTimeWarm"
    else return "SignalTime" end
  end

  local function push_conv(c)
    local is_pinned  = state.pinned[c.id]
    local has_unread = c.unread and c.unread > 0
    local icon       = c.kind == "group" and "  " or "  "
    local name       = c.name or c.id or "Unknown"
    local snippet    = c.snippet or ""
    local badge      = has_unread and (" " .. c.unread) or ""
    local timestr    = (c.time or "") .. badge

    -- col 0-1: green dot for unread, blank otherwise; then icon
    local dot    = has_unread and "● " or "  "
    local prefix = dot .. icon
    local gap    = math.max(1, win_width - 6 - #name - #timestr - 2)
    local line1  = prefix .. name .. string.rep(" ", gap) .. timestr
    local line2  = "  " .. icon .. " " .. snippet:sub(1, win_width - 8)

    local name_lnum    = #lines
    local snippet_lnum = #lines + 1
    table.insert(lines, line1)
    table.insert(lines, line2)

    state.line_conv_map[name_lnum + 1]    = c
    state.line_conv_map[snippet_lnum + 1] = c

    -- unread dot
    if has_unread then
      table.insert(specs, { hl = "SignalUnreadDot", line = name_lnum, col_s = 0, col_e = 2 })
    end

    -- icon: dim, type-specific
    local icon_hl = c.kind == "group" and "SignalGroupDim" or "SignalNameDim"
    table.insert(specs, { hl = icon_hl, line = name_lnum, col_s = 2, col_e = 2 + #icon })

    -- name: bright when unread, dim when read
    local name_hl = is_pinned and "SignalPinned"
      or (has_unread and (c.kind == "group" and "SignalGroup" or "SignalName"))
      or (c.kind == "group" and "SignalGroupDim" or "SignalNameDim")
    local name_s = #prefix
    table.insert(specs, { hl = name_hl, line = name_lnum, col_s = name_s, col_e = name_s + #name })

    -- timestamp (recency-tinted) + badge
    local time_s = #line1 - #timestr
    local time_e = time_s + #(c.time or "")
    if #(c.time or "") > 0 then
      table.insert(specs, { hl = time_hl(c.time), line = name_lnum, col_s = time_s, col_e = time_e })
    end
    if badge ~= "" then
      table.insert(specs, { hl = "SignalUnread", line = name_lnum, col_s = time_e, col_e = #line1 })
    end
    table.insert(specs, { hl = "SignalSnippet", line = snippet_lnum, col_s = 0, col_e = -1 })
  end

  local visible = state.conversations

  if state.filter ~= "" then
    local q = state.filter:lower()
    visible = vim.tbl_filter(function(c)
      return (c.name or ""):lower():find(q, 1, true) ~= nil
    end, visible)
  end

  local pinned   = vim.tbl_filter(function(c) return  state.pinned[c.id] end, visible)
  local unpinned = vim.tbl_filter(function(c) return not state.pinned[c.id] end, visible)
  local chats    = vim.tbl_filter(function(c) return c.snippet ~= nil and c.snippet ~= "" end, unpinned)
  local contacts = vim.tbl_filter(function(c) return c.snippet == nil  or c.snippet == "" end, unpinned)

  if #pinned == 0 and #chats == 0 and #contacts == 0 then
    write_buf({ "", "  No conversations yet.", "",
      "  Link your device and start chatting from your phone." }, {
      { hl = "SignalLoading", line = 1, col_s = 0, col_e = -1 },
      { hl = "SignalLoading", line = 3, col_s = 0, col_e = -1 },
    })
    return
  end

  if #pinned > 0 then
    push_label("Pinned")
    for _, c in ipairs(pinned) do push_conv(c) end
  end
  if #chats > 0 then
    if #pinned > 0 then push_gap() end
    for _, c in ipairs(chats) do push_conv(c) end
  end
  if #contacts > 0 then
    if #chats > 0 or #pinned > 0 then push_gap() end
    push_label("Contacts")
    for _, c in ipairs(contacts) do push_conv(c) end
  end

  write_buf(lines, specs)
end

function M.show_profile(conv)
  local W, H = 48, 10
  local ui   = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[pbuf].bufhidden  = "wipe"
  vim.bo[pbuf].buftype    = "nofile"
  vim.bo[pbuf].modifiable = false

  local pwin = vim.api.nvim_open_win(pbuf, true, {
    relative   = "editor",
    width      = W,
    height     = H,
    row        = math.floor((ui.height - H) / 2),
    col        = math.floor((ui.width  - W) / 2),
    style      = "minimal",
    border     = "rounded",
    title      = " Profile ",
    title_pos  = "center",
    footer     = " q close ",
    footer_pos = "center",
  })
  vim.wo[pwin].number         = false
  vim.wo[pwin].relativenumber = false
  vim.wo[pwin].signcolumn     = "no"

  local function close_profile()
    if vim.api.nvim_win_is_valid(pwin) then
      vim.api.nvim_win_close(pwin, true)
    end
  end
  vim.keymap.set("n", "q",     close_profile, { buffer = pbuf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close_profile, { buffer = pbuf, nowait = true, silent = true })

  local ns_p = vim.api.nvim_create_namespace("SignalProfile")

  local function render_profile(name, number, kind, about)
    local icon = kind == "group" and "󰀼" or "󰀄"
    local sep  = string.rep("─", W - 4)
    local lns  = {
      "",
      "  " .. icon .. "  " .. name,
      "  " .. sep,
      "",
    }
    if kind ~= "group" and number then
      table.insert(lns, "  Number    " .. number)
    end
    table.insert(lns, "  Type      " .. (kind == "group" and "Group" or "Contact"))
    if kind == "group" then
      table.insert(lns, "  ID        " .. (conv.id or ""))
    end
    if about and about ~= "" then
      table.insert(lns, "  About     " .. about)
    end

    vim.bo[pbuf].modifiable = true
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lns)
    vim.bo[pbuf].modifiable = false
    vim.api.nvim_buf_clear_namespace(pbuf, ns_p, 0, -1)
    vim.api.nvim_buf_add_highlight(pbuf, ns_p, "SignalName", 1, 2, -1)
    vim.api.nvim_buf_add_highlight(pbuf, ns_p, "SignalTime", 2, 0, -1)
  end

  if config.get().debug then
    render_profile(conv.name or conv.id, conv.id, conv.kind)
    return
  end

  if conv.kind == "group" then
    render_profile(conv.name or conv.id, nil, "group")
    return
  end

  local cmd  = config.get().signal_cmd
  local args = { cmd, "-a", state.account, "listContacts", "--output=json" }
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(pwin) then return end
      local name, number, about = conv.name or conv.id, conv.id, nil
      if result.code == 0 and result.stdout and result.stdout ~= "" then
        local ok, data = pcall(vim.fn.json_decode, result.stdout)
        if ok and type(data) == "table" then
          for _, c in ipairs(data) do
            if c.number == conv.id then
              name   = (c.name and c.name ~= "") and c.name or name
              number = c.number or number
              about  = c.profile and c.profile.about or nil
              break
            end
          end
        end
      end
      render_profile(name, number, "contact", about)
    end)
  end)
end

function M.register_keymaps()
  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end
  bmap("q",     M.close)
  bmap("<Esc>", function()
    if state.filter ~= "" then
      state.filter = ""
      render_list()
    else
      M.close()
    end
  end)
  bmap("r",     function() M.fetch_and_render() end)
  bmap("/",     function()
    local q = vim.fn.input("/")
    state.filter = vim.trim(q)
    render_list()
  end)
  bmap("<CR>",  function()
    if not is_valid() then return end
    local cur  = vim.api.nvim_win_get_cursor(state.win)[1]
    local conv = state.line_conv_map[cur]
    if conv then
      require("signal.notifs").clear_unread(conv.id)
      conv.unread = 0
      require("signal.thread").open(conv, state.account, state.buf, state.win)
    end
  end)
  bmap("p", function()
    if not is_valid() then return end
    local cur  = vim.api.nvim_win_get_cursor(state.win)[1]
    local conv = state.line_conv_map[cur]
    if conv then M.show_profile(conv) end
  end)
  bmap("P", function()
    if not is_valid() then return end
    local cur  = vim.api.nvim_win_get_cursor(state.win)[1]
    local conv = state.line_conv_map[cur]
    if not conv then return end
    if state.pinned[conv.id] then
      state.pinned[conv.id] = nil
    else
      state.pinned[conv.id] = true
    end
    save_pins(state.pinned)
    render_list()
  end)
end

local DEBUG_CONVS = {
  { id = "+43111000001", name = "Alice",          kind = "contact", snippet = "Hey, how are you?",            time = "12:34", unread = 2 },
  { id = "+43111000002", name = "Bob",            kind = "contact", snippet = "See you tomorrow!",             time = "09:11", unread = 0 },
  { id = "+43111000003", name = "Charlie",        kind = "contact", snippet = "Sounds good 👍",               time = "Mon",   unread = 0 },
  { id = "+43111000004", name = "Mia",            kind = "contact", snippet = "Can you call me later?",        time = "11:52", unread = 3 },
  { id = "+43111000005", name = "David",          kind = "contact", snippet = "Thanks for the help!",          time = "Tue",   unread = 0 },
  { id = "+43111000006", name = "Sophie",         kind = "contact", snippet = "Running 10 min late, sorry",    time = "08:30", unread = 1 },
  { id = "+43111000007", name = "Lukas",          kind = "contact", snippet = "",                              time = "Sun",   unread = 0 },
  { id = "group-abc",   name = "Family Group",    kind = "group",   snippet = "Dinner on Sunday?",             time = "Tue",   unread = 1 },
  { id = "group-xyz",   name = "Work Team",       kind = "group",   snippet = "PR merged — deploying now",     time = "Wed",   unread = 0 },
  { id = "group-def",   name = "Team Sprint",     kind = "group",   snippet = "Retro is at 15:00 tomorrow",    time = "10:05", unread = 4 },
  { id = "group-ghi",   name = "Climbing Crew",   kind = "group",   snippet = "New route opened at Kletterhalle", time = "Sat", unread = 0 },
}

function M.fetch_and_render()
  if config.get().debug then
    state.conversations = vim.deepcopy(DEBUG_CONVS)
    state.is_loading    = false
    state.last_sync     = os.time()
    render_list()
    return
  end

  state.is_loading = true
  state.auth_error = false
  start_spinner()

  local auth_handled = false

  local function handle_auth_error(err)
    if auth_handled then return end
    auth_handled = true
    config.invalidate_cache()
    stop_spinner()
    state.is_loading = false
    state.auth_error = true
    render_list()
    vim.notify("signal.nvim: not linked — run :SignalSetup to reconnect\n" .. (err or ""), vim.log.levels.WARN)
  end

  local function do_list()
    local contacts_done, groups_done = false, false
    local contacts_data, groups_data

    local function try_finish()
      if not contacts_done or not groups_done then return end
      local convs = {}
      for _, c in ipairs(contacts_data or {}) do
        local name = (c.name and c.name ~= "") and c.name or c.number or "Unknown"
        table.insert(convs, {
          id      = c.number,
          name    = name,
          kind    = "contact",
          snippet = "",
          time    = "",
          unread  = require("signal.notifs").get_unread(c.number),
        })
      end
      for _, g in ipairs(groups_data or {}) do
        table.insert(convs, {
          id      = g.id,
          name    = g.name or "Group",
          kind    = "group",
          snippet = "",
          time    = "",
          unread  = require("signal.notifs").get_unread(g.id),
        })
      end
      -- restore snippets from persistent cache (local file, no network)
      local cache = get_snippet_cache()
      for _, c in ipairs(convs) do
        local cached = cache[c.id]
        if cached and cached.snippet and cached.snippet ~= "" then
          c.snippet = cached.snippet
          c.time    = cached.time or ""
        end
      end
      state.conversations = convs
      stop_spinner()
      state.is_loading    = false
      state.last_sync     = os.time()
      render_list()
    end

    cli.list_contacts(state.account, function(err, data)
      if auth_handled then return end
      if err and config.is_auth_error(err) then handle_auth_error(err) return end
      if err then vim.notify("signal.nvim: listContacts: " .. err, vim.log.levels.WARN) end
      contacts_data = (err or type(data) ~= "table") and {} or data
      contacts_done = true
      try_finish()
    end)

    cli.list_groups(state.account, function(err, data)
      if auth_handled then return end
      if err and config.is_auth_error(err) then handle_auth_error(err) return end
      if err then vim.notify("signal.nvim: listGroups: " .. err, vim.log.levels.WARN) end
      groups_data = (err or type(data) ~= "table") and {} or data
      groups_done = true
      try_finish()
    end)
  end

  -- list conversations immediately (reads local DB — no network wait)
  do_list()

  -- receive in background to pull new messages; process_messages updates snippets
  cli.receive(state.account, function(err, messages)
    if auth_handled then return end
    if err and config.is_auth_error(err) then handle_auth_error(err) return end
    require("signal.notifs").process_messages(messages)
  end)
end

local function open_win()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden  = "hide"
    vim.bo[state.buf].buftype    = "nofile"
    vim.bo[state.buf].modifiable = false
  end

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * config.get().window_width)
  local height = math.floor(ui.height * 0.88)
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    state.win = vim.api.nvim_open_win(state.buf, true, {
      relative   = "editor",
      width      = width,
      height     = height,
      row        = row,
      col        = col,
      style      = "minimal",
      border     = "rounded",
      title      = " Signal ",
      title_pos  = "center",
      footer     = make_footer(),
      footer_pos = "center",
    })
    vim.wo[state.win].number         = false
    vim.wo[state.win].relativenumber = false
    vim.wo[state.win].signcolumn     = "no"
    vim.wo[state.win].cursorline     = true
    vim.wo[state.win].wrap           = false
    vim.wo[state.win].foldenable     = false
  end
end

function M.return_to_list()
  state.filter = ""
  for _, c in ipairs(state.conversations) do
    c.unread = require("signal.notifs").get_unread(c.id)
  end
  M.register_keymaps()
  render_list()
end

function M.close()
  stop_spinner()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

function M.open()
  state.pinned = load_pins()
  if config.get().debug then
    state.account = "+43000000000"
    open_win()
    M.register_keymaps()
    M.fetch_and_render()
    return
  end
  local ok, err = config.ready()
  if not ok then
    vim.notify("signal.nvim: " .. err, vim.log.levels.WARN)
    return
  end
  config.resolve_account(function(number)
    if not number then
      vim.notify("signal.nvim: no account registered — run :SignalSetup", vim.log.levels.WARN)
      return
    end
    state.account = number
    open_win()
    M.register_keymaps()
    M.fetch_and_render()
  end)
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

function M.get_state()
  return state
end

function M.render_list()
  render_list()
end

-- called by notifs when a new message updates a conversation
function M.update_snippet(id, snippet, time_str)
  for _, c in ipairs(state.conversations) do
    if c.id == id then
      c.snippet = snippet
      c.time    = time_str or c.time
      break
    end
  end
  local cache = get_snippet_cache()
  cache[id] = { snippet = snippet, time = time_str or "" }
  flush_snippet_cache()
  render_list()
end

function M.setup(opts)
  config.setup(opts)
  package.loaded["signal.highlights"] = nil
  require("signal.highlights").setup()
  package.loaded["signal.notifs"] = nil
  require("signal.notifs").setup()
end

return M
