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
        callback(nil, ok and decoded or result.stdout)
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

local function base_args(number)
  return { config.get().signal_cmd, "-a", number, "--output=json" }
end

function M.receive(number, callback)
  local args = vim.list_extend(base_args(number), { "receive", "--ignore-attachments" })
  M.run(args, callback)
end

function M.list_contacts(number, callback)
  M.run(vim.list_extend(base_args(number), { "listContacts" }), callback)
end

function M.list_groups(number, callback)
  M.run(vim.list_extend(base_args(number), { "listGroups" }), callback)
end

function M.list_messages(number, conversation_id, callback)
  local args = vim.list_extend(base_args(number), { "listMessages", "--conversation-id", conversation_id })
  M.run(args, callback)
end

function M.send(number, recipient, body, is_group, callback)
  local args = { config.get().signal_cmd, "-a", number, "send", "-m", body }
  vim.list_extend(args, is_group and { "-g", recipient } or { "-n", recipient })
  M.run(args, callback)
end

return M
