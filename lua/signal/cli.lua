local M = {}
local daemon = require("signal.daemon")

function M.list_contacts(_, callback)
  daemon.call("listContacts", {}, callback)
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

return M
