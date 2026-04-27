local M      = {}
local cli    = require("signal.cli")
local config = require("signal.config")

local ns = vim.api.nvim_create_namespace("Signal")

local state = {
  buf            = nil,
  win            = nil,
  conversations  = {},
  is_loading     = false,
  account        = nil,
  line_conv_map  = {},
}

local FOOTER = " <CR> open  ·  r refresh  ·  q close "

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
  vim.api.nvim_win_set_config(state.win, {
    title      = title,
    title_pos  = "center",
    footer     = FOOTER,
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

  local win_width   = vim.api.nvim_win_get_width(state.win)
  local lines       = { "" }
  local specs       = {}
  state.line_conv_map = {}

  for i, c in ipairs(state.conversations) do
    local idx     = i - 1  -- 0-based
    local icon    = c.kind == "group" and "  " or "  "
    local name    = c.name or c.id or "Unknown"
    local snippet = c.snippet or ""
    local badge   = (c.unread and c.unread > 0) and (" [" .. c.unread .. "]") or ""
    local timestr = (c.time or "") .. badge

    local prefix  = "  " .. icon
    local gap     = math.max(1, win_width - #prefix - #name - #timestr - 2)
    local line1   = prefix .. name .. string.rep(" ", gap) .. timestr
    local line2   = "    " .. snippet:sub(1, win_width - 6)

    local name_lnum    = 1 + idx * 3  -- 0-indexed for highlights
    local snippet_lnum = 2 + idx * 3

    table.insert(lines, line1)
    table.insert(lines, line2)
    table.insert(lines, "")

    -- 1-indexed cursor → conv (both name and snippet lines navigate)
    state.line_conv_map[name_lnum + 1]    = c
    state.line_conv_map[snippet_lnum + 1] = c

    -- name highlight
    local name_hl  = c.kind == "group" and "SignalGroup" or "SignalName"
    local name_s   = #prefix
    table.insert(specs, { hl = name_hl, line = name_lnum, col_s = name_s, col_e = name_s + #name })

    -- time highlight
    local time_s = #line1 - #timestr
    local time_e = time_s + #(c.time or "")
    if #(c.time or "") > 0 then
      table.insert(specs, { hl = "SignalTime", line = name_lnum, col_s = time_s, col_e = time_e })
    end
    if badge ~= "" then
      table.insert(specs, { hl = "SignalUnread", line = name_lnum, col_s = time_e, col_e = #line1 })
    end

    -- snippet highlight
    table.insert(specs, { hl = "SignalSnippet", line = snippet_lnum, col_s = 0, col_e = -1 })
  end

  write_buf(lines, specs)
end

function M.register_keymaps()
  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end
  bmap("q",     M.close)
  bmap("<Esc>", M.close)
  bmap("r",     function() M.fetch_and_render() end)
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
end

local DEBUG_CONVS = {
  { id = "+43111000001", name = "Alice",        kind = "contact", snippet = "Hey, how are you?",          time = "12:34", unread = 2 },
  { id = "+43111000002", name = "Bob",          kind = "contact", snippet = "See you tomorrow!",           time = "09:11", unread = 0 },
  { id = "+43111000003", name = "Charlie",      kind = "contact", snippet = "",                            time = "Mon",   unread = 0 },
  { id = "group-abc",   name = "Family Group",  kind = "group",   snippet = "Dinner on Sunday?",           time = "Tue",   unread = 1 },
  { id = "group-xyz",   name = "Work Team",     kind = "group",   snippet = "PR merged — deploying now",   time = "Wed",   unread = 0 },
}

function M.fetch_and_render()
  if config.get().debug then
    state.conversations = vim.deepcopy(DEBUG_CONVS)
    state.is_loading    = false
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
      footer     = FOOTER,
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
