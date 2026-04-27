local M      = {}
local config = require("signal.config")

local function signal_cmd()
  return config.get().signal_cmd
end

local function do_verify(number)
  vim.ui.input({ prompt = "SMS verification code: " }, function(code)
    if not code or code == "" then
      vim.notify("signal.nvim: setup cancelled", vim.log.levels.INFO)
      return
    end
    vim.system(
      { signal_cmd(), "-u", number, "verify", code },
      { text = true },
      function(result)
        vim.schedule(function()
          if result.code == 0 then
            vim.notify(
              "signal.nvim: registered! You can now use :Signal",
              vim.log.levels.INFO
            )
          else
            local stderr = result.stderr or ""
            vim.notify(
              "signal.nvim: verification failed: " .. stderr .. "\nRun :SignalSetup to try again.",
              vim.log.levels.ERROR
            )
          end
        end)
      end
    )
  end)
end

local function do_register(number, captcha_token)
  local args = { signal_cmd(), "-u", number, "register" }
  if captcha_token then
    vim.list_extend(args, { "--captcha", captcha_token })
  end

  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify("signal.nvim: SMS sent to " .. number, vim.log.levels.INFO)
        do_verify(number)
        return
      end

      local stderr = result.stderr or ""

      -- Signal requires a captcha for this registration
      if stderr:lower():find("captcha") then
        local url = stderr:match("(https://[^%s]+)")
        local msg = "Signal requires a captcha.\nOpen this URL in your browser, solve it, then paste the token below.\n"
        if url then
          msg = msg .. "URL: " .. url .. "\n"
        end
        vim.notify(msg, vim.log.levels.WARN)
        vim.ui.input({ prompt = "Captcha token: " }, function(token)
          if not token or token == "" then
            vim.notify("signal.nvim: setup cancelled", vim.log.levels.INFO)
            return
          end
          do_register(number, token)
        end)
        return
      end

      vim.notify("signal.nvim: registration failed: " .. stderr, vim.log.levels.ERROR)
    end)
  end)
end

function M.run()
  local ok, err = config.ready()
  if not ok then
    vim.notify("signal.nvim: " .. err, vim.log.levels.ERROR)
    return
  end

  config.resolve_account(function(existing)
    if existing then
      vim.notify(
        "signal.nvim: already registered as " .. existing .. "\nDelete the account first if you want to re-register.",
        vim.log.levels.INFO
      )
      return
    end

    vim.ui.input({ prompt = "Phone number (e.g. +43123456789): " }, function(number)
      if not number or number == "" then
        vim.notify("signal.nvim: setup cancelled", vim.log.levels.INFO)
        return
      end
      do_register(number, nil)
    end)
  end)
end

return M
