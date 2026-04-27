local M      = {}
local config = require("signal.config")

local ns = vim.api.nvim_create_namespace("SignalSetup")

local W = 60   -- window width
local H = 20   -- total height including input strip

local state = {
  buf       = nil,
  win       = nil,
  input_buf = nil,
  input_win = nil,
  log       = {},
  step      = nil,   -- "phone" | "captcha" | "sms" | "done" | "error"
  number    = nil,
}

-- ── log helpers ──────────────────────────────────────────────────────────────

local LOG_KINDS = {
  info    = { prefix = "  ",   hl = "SignalSetupDim"  },
  cmd     = { prefix = "  > ", hl = "SignalSetupCmd"  },
  ok      = { prefix = "  ✓ ", hl = "SignalSetupOk"   },
  err     = { prefix = "  ✗ ", hl = "SignalSetupErr"  },
  url     = { prefix = "  ↗ ", hl = "SignalSetupUrl"  },
  blank   = { prefix = "",     hl = nil               },
}

local function flush_log()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local lines = { "" }
  local specs = {}
  for i, entry in ipairs(state.log) do
    local kind = LOG_KINDS[entry.kind] or LOG_KINDS.info
    local line = kind.prefix .. (entry.text or "")
    table.insert(lines, line)
    if kind.hl then
      table.insert(specs, { hl = kind.hl, line = i, col_s = 0, col_e = -1 })
    end
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, s in ipairs(specs) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, s.hl, s.line, s.col_s, s.col_e)
  end
  -- scroll to bottom
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { #lines, 0 })
  end
end

local function log(kind, text)
  table.insert(state.log, { kind = kind, text = text })
  flush_log()
end

-- ── window management ────────────────────────────────────────────────────────

local FOOTERS = {
  phone   = " <C-s> continue  ·  q cancel ",
  captcha = " <C-s> retry  ·  q cancel ",
  sms     = " <C-s> verify  ·  q cancel ",
  done    = " q close ",
  error   = " q close ",
}

local function set_footer(step)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      footer     = FOOTERS[step] or " q close ",
      footer_pos = "center",
    })
  end
end

local function close_input()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end
  state.input_win = nil
  state.input_buf = nil
end

local function close()
  close_input()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win       = nil
  state.buf       = nil
  state.log       = {}
  state.step      = nil
  state.number    = nil
end

-- forward declaration
local show_input

local function open_windows()
  local ui  = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local row = math.floor((ui.height - H) / 2)
  local col = math.floor((ui.width  - W) / 2)
  local log_h = H - 4   -- leave room for the input strip below

  -- log buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden  = "wipe"
  vim.bo[state.buf].buftype    = "nofile"
  vim.bo[state.buf].modifiable = false

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative   = "editor",
    width      = W,
    height     = log_h,
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
  vim.wo[state.win].wrap           = true
  vim.wo[state.win].cursorline     = false

  vim.keymap.set("n", "q",     close, { buffer = state.buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = state.buf, nowait = true, silent = true })
end

show_input = function(prompt)
  close_input()

  local ui    = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local row   = math.floor((ui.height - H) / 2)
  local col   = math.floor((ui.width  - W) / 2)
  local log_h = H - 4

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].bufhidden  = "wipe"
  vim.bo[state.input_buf].buftype    = "nofile"
  vim.bo[state.input_buf].filetype   = "text"
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  -- virtual text prompt label
  local input_ns = vim.api.nvim_create_namespace("SignalSetupInput")
  vim.api.nvim_buf_set_extmark(state.input_buf, input_ns, 0, 0, {
    virt_text          = { { prompt .. ": ", "SignalSetupDim" } },
    virt_text_pos      = "inline",
    right_gravity      = false,
  })

  state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
    relative  = "editor",
    width     = W,
    height    = 3,
    row       = row + log_h + 1,   -- flush below log window (inside its border)
    col       = col,
    style     = "minimal",
    border    = { "├", "─", "┤", "│", "╯", "─", "╰", "│" },
    zindex    = 51,
  })
  vim.wo[state.input_win].wrap = false
  vim.cmd("startinsert")

  local function on_submit()
    local line = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1] or ""
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    close_input()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
    -- dispatch based on current step
    if state.step == "phone" then
      require("signal.setup").handle_phone(line)
    elseif state.step == "captcha" then
      require("signal.setup").handle_captcha(line)
    elseif state.step == "sms" then
      require("signal.setup").handle_sms(line)
    end
  end

  local function imap(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = state.input_buf, nowait = true, silent = true })
  end
  imap("n", "<C-s>", on_submit)
  imap("i", "<C-s>", on_submit)
  imap("n", "q",     close)
  imap("n", "<Esc>", close)
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
          log("url", url)
          log("info", "Open the URL, solve the captcha,")
          log("info", "copy the token and paste it below.")
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
    log("err", "No number entered. Try again.")
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
    log("err", "No token entered. Try again.")
    state.step = "captcha"
    show_input("Captcha token")
    return
  end
  log("blank", "")
  do_register(state.number, token)
end

function M.handle_sms(code)
  if code == "" then
    log("err", "No code entered. Try again.")
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
        log("ok", "Registered successfully!")
        log("info", "You can now close this window and use :Signal")
        state.step = "done"
        set_footer("done")
      else
        local stderr = result.stderr or ""
        log("err", stderr ~= "" and stderr or "Verification failed.")
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

  -- reset state for a fresh run
  close()
  state.log = {}

  open_windows()

  log("info", "Welcome to signal.nvim setup.")
  log("info", "You will need your phone number")
  log("info", "and access to your SMS messages.")
  log("blank", "")
  log("cmd",  config.get().signal_cmd .. " --output=json listAccounts")

  config.resolve_account(function(existing)
    if existing then
      log("info", "Already registered as " .. existing .. ".")
      log("info", "Remove the account first to re-register.")
      state.step = "done"
      set_footer("done")
      return
    end

    log("ok", "No existing account found.")
    log("blank", "")
    state.step = "phone"
    show_input("Phone number (+43…)")
  end)
end

return M
