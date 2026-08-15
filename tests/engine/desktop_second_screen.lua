package.path = "./?.lua;./?/init.lua;" .. package.path

local clock = 1
love = {
  timer = { getTime = function() return clock end },
  data = {
    hash = function() return "digest" end,
    encode = function() return "0123456789abcdef0123456789abcdef" end,
    compress = function(_, _, value) return value end,
  },
}

local sent, spawned, queue = {}, nil, {}
local peer = {
  send = function(_, data, channel, flag)
    sent[#sent + 1] = { data = data, channel = channel, flag = flag }
  end,
  disconnect_now = function() end,
}
local host = {
  service = function()
    if #queue == 0 then return nil end
    return table.remove(queue, 1)
  end,
  destroy = function() end,
}

package.loaded["src.core.Platform"] = { canSpawnProcess = function() return true end }
package.loaded["src.core.HostShell"] = {
  spawnSelfDetached = function(args) spawned = args return true end,
}
package.preload.enet = function()
  return { host_create = function() return host end }
end

local Screen = require("src.render.DesktopScreen")
assert(Screen.usable(), "desktop backend is available on process-capable LOVE")
Screen.setEnabled(true)
assert(spawned and spawned[1]:match("^%-%-display%-companion=%d+,[%w]+$"),
  "enabling launches one companion of this app")
local token = spawned[1]:match(",([%w]+)$")
queue[#queue + 1] = { type = "receive", peer = peer, data = "H" .. token }
assert(Screen.detected(), "a token-authenticated companion becomes detected")

local pixels = { getString = function() return "rgba" end }
assert(Screen.push(pixels, 1, 1, 0x102030, "auto"),
  "a connected companion accepts a frame")
assert(sent[#sent].data:find("^F" .. token .. "\n1,1,1056816,auto\nrgba"),
  "frame metadata and pixels stay in one loopback packet")

queue[#queue + 1] = {
  type = "receive", peer = peer, data = "I" .. token .. "\ndown,3,4",
}
assert(Screen.pollTouch() == "down,3,4", "companion input returns to the mod")
Screen.setEnabled(false)
assert(sent[#sent].data == "Q" .. token, "disabling closes the companion")
print("desktop second screen: ok")
