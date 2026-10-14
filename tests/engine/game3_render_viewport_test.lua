package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")
local Game3 = require("src.core.Game3")
local Display = require("src.core.game3.display")
local Viewport = require("src.render.GameViewport")
local Renderer = require("src.render.Renderer")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local G = love.graphics

local hooks = Hooks.new()
Runtime.hooks = hooks
local width, height, requested, phase
local viewportCalls, windowCalls, hudCalls, controlsCalls, fieldDraws
local lastBarsTarget, presented
G.getDimensions = function() return width, height end
G.getPixelDimensions = G.getDimensions
G.getWidth = function() return width end
G.getHeight = function() return height end
G.rectangle = function() lastBarsTarget = G.getCanvas() end
Renderer:setUISize(240, 160)

hooks:wrap("render.viewport", function(next, ctx)
  viewportCalls = viewportCalls + 1
  assert(ctx.generation == 3 and ctx.width == width and ctx.height == height,
    "Gen 3 requests its viewport using the full OS window dimensions")
  return requested or next(ctx)
end, 0, "fixture")
hooks:wrap("render.window", function(next, game, ctx)
  windowCalls = windowCalls + 1
  presented = ctx
  assert(G.getCanvas() == nil, "final composition targets the OS window")
  return next(game, ctx)
end, 0, "fixture")
hooks:wrap("render.hud", function(next, game, ctx)
  hudCalls = hudCalls + 1
  local w, h = Viewport.dimensions()
  assert(ctx.width == w and ctx.height == h, "HUD receives the game viewport dimensions")
  assert(G.getCanvas() == Viewport.target(), "HUD is drawn before final window composition")
  return next(game, ctx)
end, 0, "fixture")

local function noop() end
require("src.ui.game3.boot").draw = noop
require("src.ui.game3.quest_log").draw = noop
require("src.ui.game3.help_system").isOpen = function() return false end
require("src.core.game3.battle").isActive = function() return false end
local Oam = require("src.core.game3.oam")
Oam.resetFrame, Oam.animateSprites, Oam.buildOamBuffer, Oam.flush = noop, noop, noop, noop
require("src.core.game3.bg").hasVisible = function() return false end
require("src.core.game3.field_view").draw = function() fieldDraws = fieldDraws + 1 end
Display.setUiRenderer(noop)
require("src.core.game3.runtime").isActive = function() return phase ~= "inactive" end

local function planes(game, w, h)
  local rw, rh = Viewport.dimensions()
  assert(w == rw and h == rh, "native presentation receives the reserved dimensions")
  Viewport.setTarget()
  if width == 1080 and requested and requested.height == 1236 then
    assert(Renderer:fitScale() == 4,
      "portrait GBA presentation fits at 960x640 instead of shrinking a full-window frame")
  end
  return true
end
local cases = 0
for _, size in ipairs({ { 1080, 2424 }, { 1280, 720 } }) do
  width, height = size[1], size[2]
  local regions = {
    { x = 0, y = 0, width = width, height = width == 1080 and 1236 or 450, capture = true },
    { x = 0, y = 0, width = math.floor(width * 0.65), height = height, capture = true },
    { x = 400, y = 200, width = 240, height = 216, capture = true },
    { x = 0, y = 0, width = width, height = height, capture = true },
    { x = 0, y = 0, width = width, height = height },
    false,
  }
  for _, region in ipairs(regions) do
    requested = region or nil
    for _, kind in ipairs({ "boot", "quest_log", "field", "arena", "inactive", "boot-flat", "field-flat" }) do
      phase = kind
      Viewport.reset()
      G.setCanvas()
      viewportCalls, windowCalls, hudCalls, controlsCalls, fieldDraws = 0, 0, 0, 0, 0
      lastBarsTarget, presented = nil, nil
      Display.planesBroken = kind == "field-flat"
      Display.presentUi = kind == "boot-flat" and function() return false end or planes
      Display.present = kind == "field-flat" and Display.presentFlat or planes
      local game = setmetatable({
        generation = 3, phase = kind:match("^(%w+)"), boot = {}, session = { map = "fixture" },
        arena = { draw = function(_, w, h)
          local rw, rh = Viewport.dimensions()
          assert(w == rw and h == rh and G.getCanvas() == Viewport.target(),
            "arena rendering stays inside the reserved viewport")
        end },
        touchControls = { draw = function()
          controlsCalls = controlsCalls + 1
          assert(G.getCanvas() == nil, "touch controls draw after viewport presentation")
          local w, h = G.getDimensions()
          assert(w == width and h == height, "touch controls retain the full OS window")
        end },
      }, { __index = Game3 })
      if kind == "inactive" then game.phase = "field" end
      game:draw()
      local label = width .. "x" .. height .. "/" .. kind
      assert(viewportCalls == 1, label .. ": request the viewport exactly once")
      assert(hudCalls == 1 and controlsCalls == 1, label .. ": draw HUD and controls exactly once")
      assert(windowCalls == (Viewport.active() and 1 or 0), label .. ": compose the viewport exactly once")
      if presented then
        assert(presented.generation == 3 and presented.width == requested.width
          and presented.height == requested.height and presented.x == requested.x
          and presented.y == requested.y, label .. ": preserve viewport size and origin")
      end
      if kind == "field-flat" then
        assert(fieldDraws == 1 and lastBarsTarget == Viewport.target(),
          label .. ": fallback draws the game once into the reserved target")
      end
      cases = cases + 1
    end
  end
end
Viewport.reset()
print("game3 render viewport: " .. cases .. " cases passed")
