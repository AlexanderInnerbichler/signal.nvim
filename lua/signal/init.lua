local M      = {}
local cli    = require("signal.cli")
local config = require("signal.config")

local ns = vim.api.nvim_create_namespace("Signal")

local state = {
  buf           = nil,
  win           = nil,
  conversations = {},
  is_loading    = false,
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

  vim.api.nvim_win_set_config(state.win, {
    title      = " Signal ",
    title_pos  = "center",
    footer     = FOOTER,
    footer_pos = "center",
  })

  if state.is_loading then
    write_buf({ "", "  Loading…" }, { { hl = "SignalLoading", line = 1, col_s = 0, col_e = -1 } })
    return
  end

  if #state.conversations == 0 then
    write_buf({ "", "  No conversations found." }, {})
    return
  end

  local lines = { "" }
  local specs = {}

  for i, c in ipairs(state.conversations) do
    local lnum        = i
    local name        = c.name or c.id or "Unknown"
    local snippet     = c.snippet or ""
    local time        = c.time or ""
    local badge       = (c.unread and c.unread > 0) and ("[" .. c.unread .. "]") or ""
    local icon        = c.kind == "group" and "  " or "  "
    local name_width  = 18
    local snip_width  = 30

    local name_padded = name:sub(1, name_width)
    name_padded = name_padded .. string.rep(" ", math.max(0, name_width - #name_padded))
    local snip_padded = snippet:sub(1, snip_width)
    snip_padded = snip_padded .. string.rep(" ", math.max(0, snip_width - #snip_padded))

    local line = icon .. name_padded .. "  " .. snip_padded .. "  " .. time
    if badge ~= "" then line = line .. "  " .. badge end
    table.insert(lines, line)

    local icon_len   = #icon
    local snip_start = icon_len + name_width + 2
    local time_start = snip_start + #snip_padded + 2

    table.insert(specs, { hl = (c.kind == "group") and "SignalGroup" or "SignalName",
      line = lnum, col_s = icon_len, col_e = icon_len + #name_padded })
    table.insert(specs, { hl = "SignalSnippet",
      line = lnum, col_s = snip_start, col_e = snip_start + #snip_padded })
    table.insert(specs, { hl = "SignalTime",
      line = lnum, col_s = time_start, col_e = time_start + #time })
    if badge ~= "" then
      local badge_start = time_start + #time + 2
      table.insert(specs, { hl = "SignalUnread",
        line = lnum, col_s = badge_start, col_e = badge_start + #badge })
    end
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
    local conv = state.conversations[cur - 1]
    if conv then
      require("signal.notifs").clear_unread(conv.id)
      conv.unread = 0
      require("signal.thread").open(conv, state.buf, state.win)
    end
  end)
end

function M.fetch_and_render()
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

  cli.list_contacts(function(err, data)
    contacts_data = (err or type(data) ~= "table") and {} or data
    contacts_done = true
    try_finish()
  end)

  cli.list_groups(function(err, data)
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
  local ok, err = config.ready()
  if not ok then
    vim.notify("signal.nvim: " .. err, vim.log.levels.WARN)
    return
  end
  open_win()
  M.register_keymaps()
  M.fetch_and_render()
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
