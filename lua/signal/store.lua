local M = {}

local MSG_DIR = vim.fn.expand("~/.local/share/signal-cli/nvim-messages")
local MAX_MSGS = 200

local function ensure_dir()
  vim.fn.mkdir(MSG_DIR, "p")
end

function M.path(conv_id)
  local safe = tostring(conv_id):gsub("[^%w%+%-]", "_")
  return MSG_DIR .. "/" .. safe .. ".json"
end

function M.load(conv_id)
  local f = io.open(M.path(conv_id), "r")
  if not f then return {} end
  local raw = f:read("*a"); f:close()
  local ok, data = pcall(vim.fn.json_decode, raw)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

function M.append(conv_id, msg)
  ensure_dir()
  local msgs = M.load(conv_id)
  -- deduplicate by timestamp + source
  for _, m in ipairs(msgs) do
    if m.timestamp == msg.timestamp and m.source == msg.source then return end
  end
  table.insert(msgs, msg)
  table.sort(msgs, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)
  if #msgs > MAX_MSGS then
    msgs = vim.list_slice(msgs, #msgs - MAX_MSGS + 1, #msgs)
  end
  local ok, enc = pcall(vim.fn.json_encode, msgs)
  if not ok then return end
  local f = io.open(M.path(conv_id), "w")
  if f then f:write(enc); f:close() end
end

local function save_msgs(conv_id, msgs)
  local ok, enc = pcall(vim.fn.json_encode, msgs)
  if not ok then return end
  local f = io.open(M.path(conv_id), "w")
  if f then f:write(enc); f:close() end
end

function M.add_reaction(conv_id, target_ts, emoji, author, remove)
  local msgs = M.load(conv_id)
  for _, m in ipairs(msgs) do
    if m.timestamp == target_ts then
      m.reactions = m.reactions or {}
      m.reactions[emoji] = m.reactions[emoji] or {}
      if remove then
        for i = #m.reactions[emoji], 1, -1 do
          if m.reactions[emoji][i] == author then table.remove(m.reactions[emoji], i); break end
        end
        if #m.reactions[emoji] == 0 then m.reactions[emoji] = nil end
      else
        local found = false
        for _, a in ipairs(m.reactions[emoji]) do
          if a == author then found = true; break end
        end
        if not found then table.insert(m.reactions[emoji], author) end
      end
      break
    end
  end
  save_msgs(conv_id, msgs)
end

function M.mark_deleted(conv_id, timestamp)
  local msgs = M.load(conv_id)
  for _, m in ipairs(msgs) do
    if m.timestamp == timestamp then
      m.deleted = true
      m.message = ""
      break
    end
  end
  save_msgs(conv_id, msgs)
end

return M
