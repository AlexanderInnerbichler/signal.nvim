local M = {}

function M.check()
  vim.health.start("signal.nvim")

  local config = require("signal.config")
  local cmd    = config.get().signal_cmd

  -- signal-cli binary
  if vim.fn.executable(cmd) == 1 then
    vim.health.ok("signal-cli found: " .. cmd)
  else
    vim.health.error(
      "signal-cli not found at '" .. cmd .. "'\n" ..
      "Download from: https://github.com/AsamK/signal-cli/releases\n" ..
      "Java 17–21 required (Java 25+ not yet supported by signal-cli)"
    )
    return
  end

  -- Java
  if vim.fn.executable("java") == 1 then
    vim.health.ok("Java found")
  else
    vim.health.warn("java not found in PATH — signal-cli may fail")
  end

  -- registered account
  local result = vim.system(
    { cmd, "--output=json", "listAccounts" },
    { text = true, timeout = 8000 }
  ):wait()

  if result.code ~= 0 then
    vim.health.warn(
      "signal-cli listAccounts failed — run :SignalSetup to register\n" ..
      (result.stderr or "")
    )
    return
  end

  local ok, data = pcall(vim.fn.json_decode, result.stdout or "")
  if ok and type(data) == "table" and data[1] and data[1].number then
    vim.health.ok("account registered: " .. data[1].number)
  else
    vim.health.warn("no account registered — run :SignalSetup")
  end
end

return M
