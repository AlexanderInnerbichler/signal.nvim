local M = {}
local daemon = require("signal.daemon")

function M.list_contacts(_, callback)
  daemon.call("listContacts", {}, callback)
end

function M.get_profile(account, callback)
  daemon.call("getProfile", { recipient = account }, callback)
end

function M.list_groups(_, callback)
  daemon.call("listGroups", {}, callback)
end


function M.send(_, recipient, body, is_group, callback)
  local params = { message = body }
  if is_group then params.groupId = recipient
  else             params.recipient = { recipient } end
  daemon.call("send", params, callback)
end

function M.send_reaction(_, recipient, is_group, emoji, target_author, target_ts, remove, callback)
  local params = {
    emoji           = emoji,
    targetAuthor    = target_author,
    targetTimestamp = target_ts,
    remove          = remove or false,
  }
  if is_group then params.groupId = recipient
  else             params.recipient = { recipient } end
  daemon.call("sendReaction", params, callback or function() end)
end

function M.remote_delete(_, recipient, is_group, target_ts, callback)
  local params = { targetTimestamp = target_ts }
  if is_group then params.groupId = recipient
  else             params.recipient = { recipient } end
  daemon.call("remoteDeleteForAll", params, callback or function() end)
end

return M
