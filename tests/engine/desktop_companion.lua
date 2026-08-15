package.path = "./?.lua;./?/init.lua;" .. package.path

local clock, quit = 1, false
local sent, queue, draws = {}, {}, 0
local peer = {
  send = function(_, data) sent[#sent + 1] = data end,
  disconnect_now = function() end,
}
local host = {
  connect = function() return peer end,
  service = function()
    if #queue == 0 then return nil end
    return table.remove(queue, 1)
  end,
}
local rendered = {
  setFilter = function() end, replacePixels = function() end,
  release = function() end,
}
love = {
  timer = { getTime = function() return clock end },
  data = { decompress = function(_, _, value) return value end },
  image = { newImageData = function(w, h, format, raw)
    assert(w == 1 and h == 1 and format == "rgba8" and raw == "rgba")
    return {}
  end },
  graphics = {
    newImage = function() return rendered end,
    getDimensions = function() return 100, 100 end,
    clear = function() end, setColor = function() end,
    draw = function() draws = draws + 1 end,
  },
  event = { quit = function() quit = true end },
}
package.preload.enet = function()
  return { host_create = function() return host end }
end

require("src.render.DesktopCompanion").install({ port = 50000, token = "token" })
queue[#queue + 1] = { type = "connect" }
love.update()
assert(sent[#sent] == "Htoken", "companion authenticates after connecting")
queue[#queue + 1] = {
  type = "receive", data = "Ftoken\n1,1,0,auto\nrgba",
}
love.update()
love.draw()
assert(draws == 1, "companion draws a received frame")
love.mousepressed(50, 50, 1)
love.mousereleased(50, 50, 1)
assert(sent[#sent - 1] == "Itoken\ndown,0,0"
  and sent[#sent] == "Itoken\nup,0,0", "mouse input maps back to source pixels")
queue[#queue + 1] = { type = "receive", data = "Qtoken" }
love.update()
assert(quit, "parent can close the companion")
print("desktop companion: ok")
