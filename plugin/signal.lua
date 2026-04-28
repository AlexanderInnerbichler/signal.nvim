if vim.g.signal_loaded then return end
vim.g.signal_loaded = true

vim.api.nvim_create_user_command("Signal", function()
  require("signal").toggle()
end, { desc = "Toggle Signal messenger" })

vim.api.nvim_create_user_command("SignalSetup", function()
  require("signal.setup").run()
end, { desc = "Register a Signal account" })

vim.api.nvim_create_user_command("SignalLink", function()
  require("signal.setup").link()
end, { desc = "Link signal-cli as a secondary device to Signal on phone" })
