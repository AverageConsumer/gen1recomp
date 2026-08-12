package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Game2 = require("src.core.Game2")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")

local savedHooks = Runtime.hooks
local hooks = Hooks.new()
Runtime.hooks = hooks

local received
hooks:wrap("render.output_enabled", function() return true end, 0, "test")
hooks:wrap("render.output", function(_, context)
  received = context
  return true
end, 0, "test")

local canvas = love.graphics.newCanvas(640, 480)
local game = setmetatable({
  frameFit = function() return 3, 80, 24, 1, 480, 432 end,
  presentCanvas = function() return canvas end,
  drawScene = function() end,
  drawHud = function() end,
}, Game2)

Game2.draw(game)

T.check(received ~= nil, "Gold raises render.output for an enabled subscriber")
T.eq(received and received.canvas, canvas,
  "Gold hands render.output the finished present canvas")
T.eq(received and received.generation, 2,
  "Gold identifies the output context without changing Gen 1")
T.eq(received and received.gameX, 80, "Gold output carries the fitted game X")
T.eq(received and received.gameY, 24, "Gold output carries the fitted game Y")
T.eq(received and received.gameWidth, 480,
  "Gold output carries the fitted game width")
T.eq(received and received.gameHeight, 432,
  "Gold output carries the fitted game height")

Runtime.hooks = savedHooks
T.finish("gen2 render output seam")
