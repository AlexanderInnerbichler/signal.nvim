local M      = {}
local cli    = require("signal.cli")
local config = require("signal.config")

local ns = vim.api.nvim_create_namespace("Signal")

local PIN_FILE   = vim.fn.expand("~/.local/share/signal-cli/nvim-pinned.json")
local CONV_CACHE = vim.fn.expand("~/.local/share/signal-cli/nvim-convs.json")

local conv_cache_data = nil  -- lazy-loaded; { ts = unix, convs = [...] }

local function load_conv_cache()
  if conv_cache_data then return conv_cache_data end
  local f = io.open(CONV_CACHE, "r")
  if not f then conv_cache_data = { ts = 0, convs = {} }; return conv_cache_data end
  local raw = f:read("*a"); f:close()
  local ok, d = pcall(vim.fn.json_decode, raw)
  conv_cache_data = (ok and type(d) == "table") and d or { ts = 0, convs = {} }
  return conv_cache_data
end

local function save_conv_cache(convs)
  if not convs or #convs == 0 then return end
  conv_cache_data = { ts = os.time(), convs = convs }
  local ok, enc = pcall(vim.fn.json_encode, conv_cache_data)
  if not ok then return end
  local f = io.open(CONV_CACHE, "w")
  if f then f:write(enc); f:close() end
end

local SPINNER = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" }

local SPRITE_FRAMES = {
  -- 1: neutral stand
  { " ▄████▄ ", " ▐████▌ ", "▌ ████ ▐", "  █  █  ", " ▄█  █▄ " },
  -- 2: bob down (▀ = bent knee)
  { " ▄████▄ ", " ▐████▌ ", "▌ ████ ▐", "  ▀  ▀  ", "  █  █  " },
  -- 3: neutral (return from bob)
  { " ▄████▄ ", " ▐████▌ ", "▌ ████ ▐", "  █  █  ", " ▄█  █▄ " },
  -- 4: look left (head shifted left)
  { "▄████▄  ", " ▐████▌ ", "▌ ████ ▐", "  █  █  ", " ▄█  █▄ " },
  -- 5: look right (head shifted right)
  { "  ▄████▄", " ▐████▌ ", "▌ ████ ▐", "  █  █  ", " ▄█  █▄ " },
  -- 6: walk A — left arm in, right leg forward
  { " ▄████▄ ", " ▐████▌ ", "  ████ ▐", "▌ █  █  ", " ▄█   ▄█" },
  -- 7: walk B — mid stride, feet together
  { " ▄████▄ ", " ▐████▌ ", "▌ ████ ▐", "  ██    ", " ▄██▄   " },
  -- 8: walk C — right arm in, left leg forward
  { " ▄████▄ ", " ▐████▌ ", "▌ ████  ", "  █  █ ▐", "▄█   █▄ " },
  -- 9: walk D — mid stride other side
  { " ▄████▄ ", " ▐████▌ ", "▌ ████ ▐", "    ██  ", "   ▄██▄ " },
  -- 10: wave prep (right arm at shoulder)
  { " ▄████▄ ", " ▐████▌▌", "▌ ████  ", "  █  █  ", " ▄█  █▄ " },
  -- 11: wave high (arm at head level)
  { " ▄████▄▌", " ▐████▌ ", "▌ ████  ", "  █  █  ", " ▄█  █▄ " },
  -- 12: wave mid (▀ = hand waving)
  { " ▄████▄ ", " ▐████▌▀", "▌ ████  ", "  █  █  ", " ▄█  █▄ " },
  -- 13: groove — left arm raised
  { "▌▄████▄ ", " ▐████▌▐", "  ████  ", "  █  █  ", " ▄█  █▄ " },
  -- 14: groove — both arms raised (flanking head)
  { "▌▄████▄▐", "  ████  ", "  ████  ", "  █  █  ", " ▄█  █▄ " },
  -- 15: groove — right arm raised
  { " ▄████▄▐", "▌▐████▌ ", "  ████  ", "  █  █  ", " ▄█  █▄ " },
  -- 16: groove — crouch with arms flared
  { " ▄████▄ ", "▌▐████▌▐", "  ████  ", "  ▀  ▀  ", "  █  █  " },
  -- 17: jump pose (arms up + knees bent)
  { "▌▄████▄▐", "  ████  ", "  ████  ", "  ▀  ▀  ", " ▄█  █▄ " },
  -- 18: shuffle right (legs spread right)
  { " ▄████▄ ", " ▐████▌ ", "▌ ████ ▐", " █   █  ", "▄█   █▄ " },
  -- 19: shuffle left (legs spread left)
  { " ▄████▄ ", " ▐████▌ ", "▌ ████ ▐", "  █   █ ", " ▄█   █▄" },
  -- 20: shuffle together (feet close)
  { " ▄████▄ ", " ▐████▌ ", "▌ ████ ▐", "  ████  ", " ▄████▄ " },
}

local SEQ_IDLE = {
  1, 1, 2, 1, 3, 4, 3, 5, 3,
  6, 7, 8, 9, 7, 6, 7, 8, 9, 7,
  1, 1, 10, 11, 12, 11, 12, 11, 10, 1,
}
local SEQ_DANCE_A = {   -- groove: arms pump, knees bob
  1, 16, 13, 14, 15, 14, 13, 16, 17, 16, 17, 16, 1, 1,
}
local SEQ_DANCE_B = {   -- shuffle: feet slide
  1, 18, 20, 19, 20, 18, 20, 19, 20, 1, 1,
}
local SEQ_EXCITED = {   -- unread reactive: rapid bounce + arm flash
  2, 17, 2, 17, 14, 1, 14, 1, 16, 13, 16, 15, 2, 1,
}
local SPRITE_SEQ_FULL = {}
for _, s in ipairs({ SEQ_IDLE, SEQ_DANCE_A, SEQ_IDLE, SEQ_DANCE_B }) do
  for _, v in ipairs(s) do table.insert(SPRITE_SEQ_FULL, v) end
end

local state = {
  buf            = nil,
  win            = nil,
  conversations  = {},
  is_loading     = false,
  auth_error     = false,
  account        = nil,
  line_conv_map  = {},
  pinned         = {},
  last_sync      = nil,
  spinner_timer  = nil,
  spinner_frame  = 1,
  profile        = nil,
  sprite_frame   = 1,
  sprite_seq_pos = 1,
  sprite_timer   = nil,
  in_list        = false,
  status_msg     = nil,
}

local function avatar_chars(c)
  local name  = c.name or c.id or "?"
  local parts = vim.split(name, " ", { plain = true, trimempty = true })
  if #parts >= 2 then
    return (parts[1]:sub(1, 1) .. parts[2]:sub(1, 1)):upper()
  end
  return name:sub(1, 1):upper() .. " "
end

local function avatar_hl(c)
  local key = c.id or c.name or ""
  local n   = 0
  for i = 1, #key do n = n + string.byte(key, i) end
  return "SignalAvatar" .. (n % 8 + 1)
end

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
  local base = " <CR> open  ·  n new  ·  r refresh"
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
  if state.is_loading or state.status_msg then return end
  if state.spinner_timer then
    state.spinner_timer:stop()
    state.spinner_timer:close()
    state.spinner_timer = nil
  end
end

local function paint_sprite_row(row_str, row_idx, line_ln)
  local segs = {}
  local pos = 1
  while pos <= #row_str do
    local b    = row_str:byte(pos)
    local clen = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    local ch   = row_str:sub(pos, pos + clen - 1)
    local cs   = pos + 1
    local ce   = pos + clen + 1
    local hl
    if row_idx == 0 then
      if ch ~= " " then hl = "SignalSpriteSkin" end
    elseif row_idx == 1 then
      if ch == "▐" or ch == "▌" then hl = "SignalSpriteSkin"
      elseif ch ~= " "           then hl = "SignalSpriteBody" end
    elseif row_idx == 2 then
      if ch == "▌" or ch == "▐" then hl = "SignalSpriteSkin"
      elseif ch ~= " "           then hl = "SignalSpriteBody" end
    elseif row_idx == 3 then
      if ch ~= " " then hl = "SignalSpriteLeg" end
    elseif row_idx == 4 then
      if ch ~= " " then hl = "SignalSpriteShoe" end
    end
    if hl then
      table.insert(segs, { hl = hl, line = line_ln, col_s = cs, col_e = ce })
    end
    pos = pos + clen
  end
  return segs
end

local function active_seq()
  for _, c in ipairs(state.conversations) do
    if (c.unread or 0) > 0 then return SEQ_EXCITED end
  end
  return SPRITE_SEQ_FULL
end

local function start_sprite_anim()
  if state.sprite_timer then return end
  state.sprite_timer = vim.uv.new_timer()
  state.sprite_timer:start(120, 120, vim.schedule_wrap(function()
    if not is_valid() or not state.in_list then return end
    local seq = active_seq()
    state.sprite_seq_pos = (state.sprite_seq_pos % #seq) + 1
    state.sprite_frame   = seq[state.sprite_seq_pos]
    render_list()
  end))
end

local function stop_sprite_anim()
  if state.sprite_timer then
    state.sprite_timer:stop()
    state.sprite_timer:close()
    state.sprite_timer = nil
  end
end

local function time_greeting()
  local h = tonumber(os.date("%H"))
  if h < 5  then return "Good night \xe2\x9c\xa6"
  elseif h < 12 then return "Good morning \xe2\x9c\xa6"
  elseif h < 17 then return "Good afternoon \xe2\x9c\xa6"
  elseif h < 21 then return "Good evening \xe2\x9c\xa6"
  else               return "Good night \xe2\x9c\xa6"
  end
end

local function date_line()
  return os.date("%A, %d %b")
end

render_list = function()
  if not is_valid() then return end
  if not state.in_list then return end

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
    footer     = make_footer(),
    footer_pos = "center",
  })

  local win_width     = vim.api.nvim_win_get_width(state.win)
  local lines         = { "" }
  local specs         = {}
  state.line_conv_map = {}

  -- Animated sprite header (always visible, even while loading or on auth error)
  if state.account then
    local prof   = state.profile or {}
    local name   = (prof.name and prof.name ~= "") and prof.name or state.account
    local about  = (prof.about and prof.about ~= "") and prof.about or nil
    local fr     = SPRITE_FRAMES[state.sprite_frame or 1]
    local gap    = "   "

    -- row 0: head + name
    local row0 = fr[1]; local pre0 = "  " .. row0 .. gap
    local ln0  = #lines
    table.insert(lines, pre0 .. name)
    table.insert(specs, { hl = "SignalHeaderBg", line = ln0, col_s = 0, col_e = -1 })
    for _, s in ipairs(paint_sprite_row(row0, 0, ln0)) do table.insert(specs, s) end
    table.insert(specs, { hl = "SignalName", line = ln0, col_s = #pre0, col_e = -1 })

    -- row 1: torso top + time greeting
    local row1 = fr[2]; local pre1 = "  " .. row1 .. gap
    local ln1  = #lines
    table.insert(lines, pre1 .. time_greeting())
    table.insert(specs, { hl = "SignalHeaderBg", line = ln1, col_s = 0, col_e = -1 })
    for _, s in ipairs(paint_sprite_row(row1, 1, ln1)) do table.insert(specs, s) end
    table.insert(specs, { hl = "SignalTimeHot", line = ln1, col_s = #pre1, col_e = -1 })

    -- row 2: arms + about (if set) or current date
    local row2    = fr[3]; local pre2 = "  " .. row2
    local side    = about or date_line()
    local side_hl = about and "SignalProfileAbout" or "SignalTimeWarm"
    local ln2     = #lines
    table.insert(lines, pre2 .. gap .. side)
    table.insert(specs, { hl = "SignalHeaderBg", line = ln2, col_s = 0, col_e = -1 })
    for _, s in ipairs(paint_sprite_row(row2, 2, ln2)) do table.insert(specs, s) end
    table.insert(specs, { hl = side_hl, line = ln2, col_s = #pre2 + #gap, col_e = -1 })

    -- row 3: legs
    local row3 = fr[4]; local ln3 = #lines
    table.insert(lines, "  " .. row3)
    table.insert(specs, { hl = "SignalHeaderBg", line = ln3, col_s = 0, col_e = -1 })
    for _, s in ipairs(paint_sprite_row(row3, 3, ln3)) do table.insert(specs, s) end

    -- row 4: feet
    local row4 = fr[5]; local ln4 = #lines
    table.insert(lines, "  " .. row4)
    table.insert(specs, { hl = "SignalHeaderBg", line = ln4, col_s = 0, col_e = -1 })
    for _, s in ipairs(paint_sprite_row(row4, 4, ln4)) do table.insert(specs, s) end

    -- decorative floor separator
    local sep_ln = #lines
    table.insert(lines, "  " .. string.rep("▀", math.max(2, win_width - 4)))
    table.insert(specs, { hl = "SignalHeaderBg",   line = sep_ln, col_s = 0, col_e = -1 })
    table.insert(specs, { hl = "SignalSpriteBody",  line = sep_ln, col_s = 0, col_e = -1 })
    table.insert(lines, "")
  end

  local status_ln = #lines
  if state.is_loading then
    local frame = SPINNER[state.spinner_frame] or "⠋"
    table.insert(lines, "  " .. frame .. "  Syncing contacts…")
    table.insert(specs, { hl = "SignalLoading", line = status_ln, col_s = 0, col_e = -1 })
    table.insert(lines, "")
  elseif state.auth_error then
    table.insert(lines, "  ✗  Not linked to Signal.")
    table.insert(specs, { hl = "SignalSetupErr", line = status_ln, col_s = 0, col_e = -1 })
    table.insert(lines, "")
    local ln2 = #lines
    table.insert(lines, "  Run :SignalSetup to reconnect.")
    table.insert(specs, { hl = "SignalLoading", line = ln2, col_s = 0, col_e = -1 })
    table.insert(lines, "")
    write_buf(lines, specs)
    return
  elseif state.status_msg then
    local frame = SPINNER[state.spinner_frame] or "⠋"
    table.insert(lines, "  " .. frame .. "  " .. state.status_msg)
    table.insert(specs, { hl = "SignalLoading", line = status_ln, col_s = 0, col_e = -1 })
    table.insert(lines, "")
  else
    local sync_str = state.last_sync
      and ("synced " .. os.date("%H:%M", state.last_sync))
      or  "not yet synced"
    table.insert(lines, "  ●  Online · " .. sync_str)
    table.insert(specs, { hl = "SignalUnread",  line = status_ln, col_s = 2, col_e = 3 })
    table.insert(specs, { hl = "SignalLoading", line = status_ln, col_s = 5, col_e = -1 })
    table.insert(lines, "")
  end

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
    local av         = c.note_to_self and "Me" or avatar_chars(c)
    local name       = c.name or c.id or "Unknown"
    local snippet    = c.snippet or ""
    local badge      = has_unread and (" " .. c.unread) or ""
    local timestr    = (c.time or "") .. badge

    -- "● " is 4 bytes (3-byte UTF-8 + space); "  " is 2 bytes — track for correct col offsets
    local dot     = has_unread and "● " or "  "
    local dot_len = #dot
    local prefix  = dot .. av
    local gap     = math.max(1, win_width - 6 - #name - #timestr - 2)
    local line1   = prefix .. " " .. name .. string.rep(" ", gap) .. timestr
    local line2   = "     " .. snippet:sub(1, win_width - 8)

    local name_lnum    = #lines
    local snippet_lnum = #lines + 1
    table.insert(lines, line1)
    table.insert(lines, line2)

    state.line_conv_map[name_lnum + 1]    = c
    state.line_conv_map[snippet_lnum + 1] = c

    -- unread dot
    if has_unread then
      table.insert(specs, { hl = "SignalUnreadDot", line = name_lnum, col_s = 0, col_e = dot_len })
    end

    -- avatar badge
    local av_hl = c.note_to_self and "SignalAvatarSelf" or avatar_hl(c)
    table.insert(specs, { hl = av_hl, line = name_lnum, col_s = dot_len, col_e = dot_len + #av })

    -- name: bright when unread, dim when read
    local name_hl = (c.note_to_self or is_pinned) and "SignalPinned"
      or (has_unread and (c.kind == "group" and "SignalGroup" or "SignalName"))
      or (c.kind == "group" and "SignalGroupDim" or "SignalNameDim")
    local name_s = dot_len + #av + 1
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

  -- Note to Self is always rendered first, outside the normal section flow
  local note_self = nil
  visible = vim.tbl_filter(function(c)
    if c.note_to_self then note_self = c; return false end
    return true
  end, visible)

  local pinned   = vim.tbl_filter(function(c) return  state.pinned[c.id] end, visible)
  local unpinned = vim.tbl_filter(function(c) return not state.pinned[c.id] end, visible)
  local chats    = vim.tbl_filter(function(c) return c.snippet ~= nil and c.snippet ~= "" end, unpinned)
  local contacts = vim.tbl_filter(function(c) return c.snippet == nil  or c.snippet == "" end, unpinned)

  local by_recency = function(a, b) return (a.last_ts or 0) > (b.last_ts or 0) end
  table.sort(pinned, by_recency)
  table.sort(chats,  by_recency)

  if not note_self and #pinned == 0 and #chats == 0 and #contacts == 0 then
    write_buf({ "", "  No conversations yet.", "",
      "  Link your device and start chatting from your phone." }, {
      { hl = "SignalLoading", line = 1, col_s = 0, col_e = -1 },
      { hl = "SignalLoading", line = 3, col_s = 0, col_e = -1 },
    })
    return
  end

  if note_self then
    push_conv(note_self)
    push_gap()
  end

  if #pinned > 0 then
    push_label("Pinned")
    for _, c in ipairs(pinned) do push_conv(c) end
  end

  if #chats > 0 then
    if #pinned > 0 then push_gap() end
    for _, c in ipairs(chats) do push_conv(c) end
  elseif #pinned == 0 then
    -- No message history yet (linked device limitation) — show contacts as fallback
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
  bmap("<Esc>", M.close)
  bmap("r",     function() M.fetch_and_render() end)
  bmap("<CR>",  function()
    if not is_valid() then return end
    local cur  = vim.api.nvim_win_get_cursor(state.win)[1]
    local conv = state.line_conv_map[cur]
    if conv then
      state.in_list = false
      local unread_before = conv.unread or 0
      require("signal.notifs").clear_unread(conv.id)
      conv.unread = 0
      require("signal.thread").open(conv, state.account, state.buf, state.win, unread_before)
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
  bmap("n", function()
    if state.is_loading then
      vim.notify("signal.nvim: contacts are still loading, please wait…", vim.log.levels.INFO)
      return
    end
    local items = {}
    for _, c in ipairs(state.conversations) do
      if not c.note_to_self then
        table.insert(items, c)
      end
    end
    if #items == 0 then
      vim.notify(
        "signal.nvim: no contacts found — if you just linked this device, contacts may still be syncing from your phone",
        vim.log.levels.WARN
      )
      return
    end
    table.sort(items, function(a, b)
      return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    vim.ui.select(items, {
      prompt = "New chat: ",
      format_item = function(c)
        local icon = c.kind == "group" and "  " or "  "
        return icon .. (c.name or c.id)
      end,
    }, function(conv)
      if not conv then return end
      state.in_list = false
      local unread_before = conv.unread or 0
      require("signal.notifs").clear_unread(conv.id)
      conv.unread = 0
      require("signal.thread").open(conv, state.account, state.buf, state.win, unread_before)
    end)
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
    state.profile       = { name = "You (debug mode)", about = nil }
    state.is_loading    = false
    state.last_sync     = os.time()
    render_list()
    return
  end

  state.auth_error = false

  -- Fetch own profile (fire-and-forget; updates header when it arrives)
  cli.get_profile(state.account, function(err, prof)
    if not err and type(prof) == "table" then
      local given  = prof.givenName or ""
      local family = prof.familyName or ""
      local name   = vim.trim(given .. (family ~= "" and (" " .. family) or ""))
      state.profile = {
        name  = name ~= "" and name or nil,
        about = (prof.about and prof.about ~= "") and prof.about or nil,
      }
      render_list()
    end
  end)

  -- Show cached conversations instantly (sub-50ms); skip spinner if cache is warm
  local cache = load_conv_cache()
  if #(cache.convs) > 0 then
    state.conversations = vim.deepcopy(cache.convs)
    state.is_loading    = false
    render_list()
  else
    state.is_loading = true
    start_spinner()
  end

  -- Background refresh: always updates contacts/groups/snippets in background
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
        if c.number ~= state.account then  -- exclude self from contact list
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
      -- Note to Self is always first
      if state.account then
        table.insert(convs, 1, {
          id           = state.account,
          name         = "Note to Self",
          kind         = "contact",
          note_to_self = true,
          snippet      = "",
          time         = "",
          unread       = require("signal.notifs").get_unread(state.account),
        })
      end

      local snippet_map = {}
      for _, c in ipairs(state.conversations) do
        if c.snippet and c.snippet ~= "" then
          snippet_map[c.id] = { snippet = c.snippet, time = c.time, last_ts = c.last_ts }
        end
      end
      for _, c in ipairs(cache.convs) do
        if not snippet_map[c.id] and c.snippet and c.snippet ~= "" then
          snippet_map[c.id] = { snippet = c.snippet, time = c.time, last_ts = c.last_ts }
        end
      end
      for _, c in ipairs(convs) do
        local s = snippet_map[c.id]
        if s then c.snippet = s.snippet; c.time = s.time; c.last_ts = s.last_ts end
      end

      state.conversations = convs
      stop_spinner()
      state.is_loading = false
      state.last_sync  = os.time()
      save_conv_cache(convs)
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

  do_list()
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
  state.in_list = true
  for _, c in ipairs(state.conversations) do
    c.unread = require("signal.notifs").get_unread(c.id)
  end
  M.register_keymaps()
  render_list()
end

function M.close()
  state.in_list = false
  stop_sprite_anim()
  stop_spinner()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

function M.open()
  state.auth_error = false
  state.pinned = load_pins()
  if config.get().debug then
    state.account = "+43000000000"
    open_win()
    state.in_list = true
    start_sprite_anim()
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
    state.in_list = true
    start_sprite_anim()
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

function M.set_status(msg)
  state.status_msg = msg
  if msg and not state.spinner_timer then start_spinner() end
  if state.in_list then render_list() end
end

function M.clear_status()
  state.status_msg = nil
  stop_spinner()
  if state.in_list then render_list() end
end

function M.render_list()
  render_list()
end

-- called by notifs when a new message updates a conversation
function M.update_snippet(id, snippet, time_str, ts)
  for _, c in ipairs(state.conversations) do
    if c.id == id then
      c.snippet = snippet
      c.time    = time_str or c.time
      c.last_ts = ts or c.last_ts
      break
    end
  end
  save_conv_cache(state.conversations)
  render_list()
end

function M.unread_count()
  local notifs = require("signal.notifs")
  local total = 0
  for _, conv in ipairs(state.conversations) do
    total = total + notifs.get_unread(conv.id)
  end
  return total
end

function M.setup(opts)
  config.setup(opts)
  package.loaded["signal.highlights"] = nil
  require("signal.highlights").setup()
  package.loaded["signal.notifs"] = nil
  require("signal.notifs").setup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group    = vim.api.nvim_create_augroup("SignalDaemon", { clear = true }),
    callback = function() require("signal.daemon").stop() end,
  })
end

return M
