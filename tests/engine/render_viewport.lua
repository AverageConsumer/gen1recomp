package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local savedHooks = Runtime.hooks
local hooks = Hooks.new()
Runtime.hooks = hooks

local Viewport = require("src.render.GameViewport")
local SafeArea = require("src.core.SafeArea")
local TouchControls = require("src.core.TouchControls")

Viewport.begin(1)
assert(not Viewport.active(), "vanilla frame must not allocate a viewport")
local w, h = Viewport.dimensions()
assert(w == 640 and h == 576, "vanilla dimensions must stay unchanged")

hooks:wrap("render.viewport", function(next, ctx)
  local full = next(ctx)
  assert(full.width == 640 and full.height == 576,
    "viewport hook receives OS-independent window geometry")
  return { x = 320, y = 12, width = 320, height = 288 }
end, 0, "fixture")

local presented
hooks:wrap("render.window", function(next, game, ctx)
  presented = ctx
  return next(game, ctx)
end, 0, "fixture")

Viewport.begin(2)
assert(Viewport.active(), "a reserved rectangle creates a game target")
w, h = Viewport.dimensions()
assert(w == 320 and h == 288, "game renders against reserved dimensions")
Viewport.target().getPixelDimensions = function() return 737, 664 end
local pw, ph = Viewport.pixelDimensions()
assert(pw == 737 and ph == 664,
  "captured rendering uses the target's real high-DPI pixel dimensions")
local x, y, inside = Viewport.toLocal(400, 100)
assert(x == 80 and y == 88 and inside,
  "window pointers expose viewport-local coordinates")
local _, _, outside = Viewport.toLocal(20, 20)
assert(not outside, "reserved companion space is outside the game viewport")
local _, _, localW, localH = SafeArea.rect()
local _, _, windowW, windowH = SafeArea.windowRect()
assert(localW == 320 and localH == 288,
  "game chrome may still use viewport-local safe geometry")
assert(windowW == 640 and windowH == 576,
  "OS chrome can retain the full-window safe geometry")
TouchControls:init()
local controls = TouchControls:layout()
assert(controls.dpad.cx < 160 and controls.a.cx > 480,
  "touch controls stay laid out across the full OS window")
local function source(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("*a")
  file:close()
  return text
end
for _, path in ipairs({ "src/core/Game.lua", "src/core/Game2.lua" }) do
  local text = source(path)
  local finish = assert(text:find("GameViewport.finish(self)", 1, true))
  local controlsDraw = assert(text:find("TouchControls:draw()", finish, true))
  assert(controlsDraw > finish,
    path .. " draws touch controls after final window composition")
end
Viewport.setTarget()
assert(love.graphics.getCanvas() == Viewport.target(),
  "game rendering is redirected into the viewport canvas")
Viewport.finish({})
assert(presented and presented.x == 320 and presented.y == 12
  and presented.width == 320 and presented.height == 288
  and presented.windowWidth == 640 and presented.windowHeight == 576
  and presented.generation == 2,
  "window composition receives game and host geometry")
assert(love.graphics.getCanvas() == nil,
  "window composition restores the OS render target")
Viewport.reset()
assert(not Viewport.active(),
  "viewport geometry cannot leak into the launcher after presentation")

hooks.chains["render.viewport"] = nil
hooks:wrap("render.viewport", function(next, ctx)
  local full = next(ctx)
  full.capture = true
  return full
end, 0, "capture-fixture")
Viewport.begin(1)
assert(Viewport.active() and Viewport.dimensions() == 640,
  "a full-window capture allocates a final composition target")
presented = nil
Viewport.setTarget()
Viewport.finish({})
assert(presented and presented.width == 640 and presented.height == 576,
  "a full-window capture reaches final window composition")
Viewport.reset()

Runtime.hooks = savedHooks
print("render viewport: ok")
