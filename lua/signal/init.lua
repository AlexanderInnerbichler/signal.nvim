local M      = {}
local cli    = require("signal.cli")
local config = require("signal.config")

local ns = vim.api.nvim_create_namespace("Signal")

local PIN_FILE = vim.fn.expand("~/.local/share/signal-cli/nvim-pinned.json")

local state = {
  buf            = nil,
  win            = nil,
  conversations  = {},
  is_loading     = false,
  account        = nil,
  line_conv_map  = {},
  filter         = "",
  pinned         = {},
  last_sync      = nil,
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

local function render_list()
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
    write_buf({ "", "  Loading…" }, { { hl = "SignalLoading", line = 1, col_s = 0, col_e = -1 } })
    return
  end

  if #state.conversations == 0 then
    write_buf({
      "",
      "  No conversations yet.",
      "",
      "  Start a chat from your phone —",
      "  it will appear here automatically.",
    }, {
      { hl = "SignalLoading", line = 1, col_s = 0, col_e = -1 },
      { hl = "SignalLoading", line = 3, col_s = 0, col_e = -1 },
      { hl = "SignalLoading", line = 4, col_s = 0, col_e = -1 },
    })
    return
  end

  local win_width     = vim.api.nvim_win_get_width(state.win)
  local lines         = { "" }
  local specs         = {}
  state.line_conv_map = {}

  local function push_divider(label)
    local hl   = label == "Pinned" and "SignalPinned"
      or         label == "Groups" and "SignalGroup"
      or         "SignalName"
    local dot  = "●"
    local head = "  " .. dot .. "  " .. label
    local bar  = string.rep("─", math.max(2, win_width - #head - 3))
    local line = head .. "  " .. bar
    local lnum = #lines

    table.insert(lines, line)
    table.insert(lines, "")

    -- dot colored per section, label same color, trailing bar very dim
    table.insert(specs, { hl = hl,                line = lnum, col_s = 2, col_e = 2 + #dot })
    table.insert(specs, { hl = hl,                line = lnum, col_s = 2 + #dot + 2, col_e = #head })
    table.insert(specs, { hl = "SignalDividerBar", line = lnum, col_s = #head + 2, col_e = -1 })
  end

  local STRIPE = "▌"  -- U+258C, 3 bytes, 1 display col
  local DOT    = "●"  -- U+25CF, 3 bytes, 1 display col
  -- display widths: ▌=1 ●=1 space=1 icon≈4 → 7 total
  local PREFIX_DISPLAY_W = 7

  local function time_hl(timestr)
    if not timestr or timestr == "" then return "SignalTime" end
    if timestr:match("^%d%d?:%d%d") then return "SignalTimeHot"
    elseif timestr:match("^Yesterday")  then return "SignalTimeWarm"
    else return "SignalTime" end
  end

  local function push_conv(c)
    local is_pinned  = state.pinned[c.id]
    local has_unread = c.unread and c.unread > 0
    local icon       = c.kind == "group" and "  " or "  "
    local name       = c.name or c.id or "Unknown"
    local snippet    = c.snippet or ""
    local badge      = has_unread and (" [" .. c.unread .. "]") or ""
    local timestr    = (c.time or "") .. badge

    local prefix = STRIPE .. DOT .. " " .. icon
    local gap    = math.max(1, win_width - PREFIX_DISPLAY_W - #name - #timestr - 2)
    local line1  = prefix .. name .. string.rep(" ", gap) .. timestr
    local line2  = STRIPE .. "      " .. snippet:sub(1, win_width - 9)

    local name_lnum    = #lines
    local snippet_lnum = #lines + 1
    table.insert(lines, line1)
    table.insert(lines, line2)
    table.insert(lines, "")

    state.line_conv_map[name_lnum + 1]    = c
    state.line_conv_map[snippet_lnum + 1] = c

    local stripe_hl = is_pinned and "SignalStripePinned"
      or c.kind == "group" and "SignalStripeGroup"
      or "SignalStripeContact"

    -- unread dot (sits between stripe and icon)
    local dot_hl = has_unread and "SignalUnread" or "SignalDividerBar"
    table.insert(specs, { hl = dot_hl,  line = name_lnum, col_s = #STRIPE, col_e = #STRIPE + #DOT })

    -- icon
    local icon_hl = c.kind == "group" and "SignalGroup" or "SignalName"
    local icon_s  = #STRIPE + #DOT + 1
    table.insert(specs, { hl = icon_hl, line = name_lnum, col_s = icon_s, col_e = icon_s + #icon })

    -- name
    local name_hl = is_pinned and "SignalPinned"
      or c.kind == "group" and "SignalGroup"
      or "SignalName"
    local name_s = #prefix
    table.insert(specs, { hl = name_hl, line = name_lnum, col_s = name_s, col_e = name_s + #name })

    -- timestamp with recency color, then unread badge
    local time_s = #line1 - #timestr
    local time_e = time_s + #(c.time or "")
    if #(c.time or "") > 0 then
      table.insert(specs, { hl = time_hl(c.time), line = name_lnum, col_s = time_s, col_e = time_e })
    end
    if badge ~= "" then
      table.insert(specs, { hl = "SignalUnread", line = name_lnum, col_s = time_e, col_e = #line1 })
    end

    -- snippet first, then stripe overrides col 0 on both lines
    table.insert(specs, { hl = "SignalSnippet", line = snippet_lnum, col_s = 0,       col_e = -1      })
    table.insert(specs, { hl = stripe_hl,       line = snippet_lnum, col_s = 0,       col_e = #STRIPE })
    table.insert(specs, { hl = stripe_hl,       line = name_lnum,    col_s = 0,       col_e = #STRIPE })
  end

  local visible = state.conversations
  if state.filter ~= "" then
    local q = state.filter:lower()
    visible = vim.tbl_filter(function(c)
      return (c.name or ""):lower():find(q, 1, true) ~= nil
    end, visible)
  end

  local pinned   = vim.tbl_filter(function(c) return state.pinned[c.id] end, visible)
  local contacts = vim.tbl_filter(function(c) return c.kind ~= "group" and not state.pinned[c.id] end, visible)
  local groups   = vim.tbl_filter(function(c) return c.kind == "group"  and not state.pinned[c.id] end, visible)

  if #pinned   > 0 then push_divider("Pinned")   for _, c in ipairs(pinned)   do push_conv(c) end end
  if #contacts > 0 then push_divider("Contacts") for _, c in ipairs(contacts) do push_conv(c) end end
  if #groups   > 0 then push_divider("Groups")   for _, c in ipairs(groups)   do push_conv(c) end end

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
    vim.api.nvim_buf_add_highlight(pbuf, ns_p, "SignalName", 1, 5, -1)
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
  render_list()

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
    state.conversations = convs
    state.is_loading    = false
    state.last_sync     = os.time()
    render_list()
  end

  cli.list_contacts(state.account, function(err, data)
    contacts_data = (err or type(data) ~= "table") and {} or data
    contacts_done = true
    try_finish()
  end)

  cli.list_groups(state.account, function(err, data)
    groups_data = (err or type(data) ~= "table") and {} or data
    groups_done = true
    try_finish()
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

function M.setup(opts)
  config.setup(opts)
  require("signal.highlights").setup()
  require("signal.notifs").setup()
end

return M
