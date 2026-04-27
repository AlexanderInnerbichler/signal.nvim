local M      = {}
local config = require("signal.config")

local ns = vim.api.nvim_create_namespace("SignalSetup")

local W = 62
local H = 22

local SEP = "  " .. string.rep("─", W - 6)

local state = {
  buf    = nil,
  win    = nil,
  log    = {},   -- list of {kind, text}
  step   = nil,  -- "phone" | "captcha" | "sms" | "done" | "error"
  number = nil,
  in_input = false,
}

-- ── log kinds ────────────────────────────────────────────────────────────────

local KINDS = {
  info  = { prefix = "  ",   hl = "SignalSetupDim" },
  cmd   = { prefix = "  > ", hl = "SignalSetupCmd" },
  ok    = { prefix = "  ✓ ", hl = "SignalSetupOk"  },
  err   = { prefix = "  ✗ ", hl = "SignalSetupErr" },
  url   = { prefix = "  ↗ ", hl = "SignalSetupUrl" },
  sep   = { prefix = "",     hl = "SignalSetupDim" },
  label = { prefix = "",     hl = "SignalSetupDim" },
  input = { prefix = "",     hl = nil              },
  blank = { prefix = "",     hl = nil              },
}

local FOOTERS = {
  phone   = " <C-s> continue  ·  q cancel ",
  captcha = " <C-s> retry  ·  q cancel ",
  sms     = " <C-s> verify  ·  q cancel ",
  done    = " q close ",
  error   = " q close ",
}

-- ── buffer helpers ────────────────────────────────────────────────────────────

local function set_modifiable(on)
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modifiable = on
  end
end

local function flush()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local was = vim.bo[state.buf].modifiable
  vim.bo[state.buf].modifiable = true

  local lines = { "" }
  local specs = {}
  for i, entry in ipairs(state.log) do
    local kind = KINDS[entry.kind] or KINDS.info
    table.insert(lines, kind.prefix .. (entry.text or ""))
    if kind.hl then
      table.insert(specs, { hl = kind.hl, line = i, col_s = 0, col_e = -1 })
    end
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, s in ipairs(specs) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, s.hl, s.line, s.col_s, s.col_e)
  end

  vim.bo[state.buf].modifiable = was

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { #lines, 0 })
  end
end

local function log(kind, text)
  table.insert(state.log, { kind = kind, text = text })
  flush()
end

local function set_footer(step)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      footer     = FOOTERS[step] or " q close ",
      footer_pos = "center",
    })
  end
end

-- ── input area ────────────────────────────────────────────────────────────────

local function clear_input_lines()
  -- remove last 3 entries (sep, label, input) from state.log
  for _ = 1, 3 do
    if #state.log > 0 then table.remove(state.log) end
  end
end

local function on_submit()
  vim.cmd("stopinsert")
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local all   = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local value = vim.trim(all[#all] or "")

  clear_input_lines()
  set_modifiable(false)
  state.in_input = false
  flush()

  local step = state.step
  if step == "phone" then
    M.handle_phone(value)
  elseif step == "captcha" then
    M.handle_captcha(value)
  elseif step == "sms" then
    M.handle_sms(value)
  end
end

local function show_input(prompt)
  state.in_input = true
  table.insert(state.log, { kind = "sep",   text = SEP })
  table.insert(state.log, { kind = "label", text = "  " .. prompt .. ":" })
  table.insert(state.log, { kind = "input", text = "" })

  set_modifiable(true)
  flush()

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { line_count, 0 })
  end
  vim.cmd("startinsert!")

  -- insert-mode keymaps to constrain the cursor
  local function imap(lhs, rhs)
    vim.keymap.set("i", lhs, rhs, { buffer = state.buf, nowait = true, silent = true })
  end
  imap("<C-s>", on_submit)
  imap("<Up>",  "<Nop>")
  imap("<C-u>", "<Nop>")  -- prevent clearing whole line history
end

-- ── window ────────────────────────────────────────────────────────────────────

local function close()
  vim.cmd("stopinsert")
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win      = nil
  state.buf      = nil
  state.log      = {}
  state.step     = nil
  state.number   = nil
  state.in_input = false
end

local function open_window()
  local ui  = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local row = math.floor((ui.height - H) / 2)
  local col = math.floor((ui.width  - W) / 2)

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden  = "wipe"
  vim.bo[state.buf].buftype    = "nofile"
  vim.bo[state.buf].modifiable = false

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative   = "editor",
    width      = W,
    height     = H,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " Signal Setup ",
    title_pos  = "center",
    footer     = FOOTERS.phone,
    footer_pos = "center",
  })
  vim.wo[state.win].number         = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn     = "no"
  vim.wo[state.win].wrap           = false
  vim.wo[state.win].cursorline     = false
  vim.wo[state.win].foldenable     = false

  local function nmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end
  nmap("q",     close)
  nmap("<Esc>", close)
end

-- ── step handlers ─────────────────────────────────────────────────────────────

local function do_register(number, captcha_token)
  local cmd  = config.get().signal_cmd
  local args = { cmd, "-u", number, "register" }
  if captcha_token then
    vim.list_extend(args, { "--captcha", captcha_token })
  end
  log("cmd", table.concat(args, " "))

  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        log("ok", "SMS sent to " .. number .. ". Check your messages.")
        log("blank", "")
        state.step = "sms"
        set_footer("sms")
        show_input("Verification code")
        return
      end

      local stderr = result.stderr or ""
      if stderr:lower():find("captcha") then
        local url = stderr:match("(https://[^%s]+)")
        log("err", "Captcha required by Signal.")
        if url then
          log("url",  url)
          log("info", "Open the URL in your browser, solve it,")
          log("info", "then copy the token and paste it below.")
        end
        log("blank", "")
        state.step = "captcha"
        set_footer("captcha")
        show_input("Captcha token")
        return
      end

      log("err", stderr ~= "" and stderr or "Registration failed.")
      state.step = "error"
      set_footer("error")
    end)
  end)
end

function M.handle_phone(number)
  if number == "" then
    log("err", "No number entered.")
    state.step = "phone"
    show_input("Phone number (+43…)")
    return
  end
  state.number = number
  log("blank", "")
  do_register(number, nil)
end

function M.handle_captcha(token)
  if token == "" then
    log("err", "No token entered.")
    state.step = "captcha"
    show_input("Captcha token")
    return
  end
  log("blank", "")
  do_register(state.number, token)
end

function M.handle_sms(code)
  if code == "" then
    log("err", "No code entered.")
    state.step = "sms"
    show_input("Verification code")
    return
  end
  local cmd  = config.get().signal_cmd
  local args = { cmd, "-u", state.number, "verify", code }
  log("cmd", table.concat(args, " "))

  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        log("ok",   "Registered successfully!")
        log("info", "You can now close this window and use :Signal")
        state.step = "done"
        set_footer("done")
      else
        local stderr = result.stderr or ""
        log("err",  stderr ~= "" and stderr or "Verification failed.")
        log("info", "Run :SignalSetup to try again.")
        state.step = "error"
        set_footer("error")
      end
    end)
  end)
end

-- ── entry point ───────────────────────────────────────────────────────────────

function M.run()
  local ok, err = config.ready()
  if not ok then
    vim.notify("signal.nvim: " .. err, vim.log.levels.ERROR)
    return
  end

  close()
  open_window()

  log("info",  "Welcome to signal.nvim setup.")
  log("info",  "You will need your phone number")
  log("info",  "and access to your SMS messages.")
  log("blank", "")
  log("cmd",   config.get().signal_cmd .. " --output=json listAccounts")

  config.resolve_account(function(existing)
    if existing then
      log("info", "Already registered as " .. existing .. ".")
      log("info", "Delete the account first to re-register.")
      state.step = "done"
      set_footer("done")
      return
    end
    log("ok",    "No existing account found.")
    log("blank", "")
    state.step = "phone"
    show_input("Phone number (+43…)")
  end)
end

return M
