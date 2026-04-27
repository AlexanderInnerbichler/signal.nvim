local M = {}

function M.check()
  vim.health.start("signal.nvim")

  local config = require("signal.config").get()

  -- Java
  local java = vim.fn.executable("java")
  if java == 1 then
    vim.health.ok("Java found")
  else
    vim.health.error("Java not found — install Java 17+: sudo apt install default-jre")
  end

  -- signal-cli
  local cmd = config.signal_cmd or "signal-cli"
  if vim.fn.executable(cmd) == 1 then
    vim.health.ok("signal-cli found: " .. cmd)
  else
    vim.health.error(
      "signal-cli not found at '" .. cmd .. "'\n" ..
      "Download from: https://github.com/AsamK/signal-cli/releases\n" ..
      "Or set signal_cmd in setup()"
    )
  end

  -- phone_number
  if config.phone_number and config.phone_number ~= "" then
    vim.health.ok("phone_number set")
  else
    vim.health.error(
      "SIGNAL_PHONE_NUMBER not set\n" ..
      "Add to your shell profile: export SIGNAL_PHONE_NUMBER='+43...'"
    )
    return
  end

  -- connectivity check
  local result = vim.system(
    { cmd, "-u", config.phone_number, "--output=json", "listContacts" },
    { text = true, timeout = 8000 }
  ):wait()

  if result.code == 0 then
    vim.health.ok("signal-cli connection successful")
  else
    vim.health.warn(
      "signal-cli test call failed (may need registration)\n" ..
      (result.stderr or "")
    )
  end
end

return M
