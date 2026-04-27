local M = {}
local config = require("signal.config")

local MAX_CONCURRENT = 4
local in_flight      = 0
local queue          = {}

local function dispatch(args, callback)
  in_flight = in_flight + 1
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      in_flight = in_flight - 1
      if #queue > 0 then
        local job = table.remove(queue, 1)
        dispatch(job.args, job.callback)
      end
      if result.code ~= 0 then
        callback(result.stderr or "signal-cli error", nil)
        return
      end
      if result.stdout and result.stdout ~= "" then
        local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
        if ok then
          callback(nil, decoded)
        else
          callback(nil, result.stdout)
        end
      else
        callback(nil, nil)
      end
    end)
  end)
end

function M.run(args, callback)
  if in_flight < MAX_CONCURRENT then
    dispatch(args, callback)
  else
    table.insert(queue, { args = args, callback = callback })
  end
end

function M.base_args()
  local cfg = config.get()
  return { cfg.signal_cmd, "-u", cfg.phone_number, "--output=json" }
end

function M.receive(callback)
  local args = vim.list_extend(vim.list_slice(M.base_args()), { "receive", "--ignore-attachments" })
  M.run(args, callback)
end

function M.list_contacts(callback)
  local args = vim.list_extend(vim.list_slice(M.base_args()), { "listContacts" })
  M.run(args, callback)
end

function M.list_groups(callback)
  local args = vim.list_extend(vim.list_slice(M.base_args()), { "listGroups" })
  M.run(args, callback)
end

function M.send(recipient, body, is_group, callback)
  local cfg  = config.get()
  local args = { cfg.signal_cmd, "-u", cfg.phone_number, "send", "-m", body }
  if is_group then
    vim.list_extend(args, { "-g", recipient })
  else
    vim.list_extend(args, { "-n", recipient })
  end
  M.run(args, callback)
end

return M
