--   luajit tests/engine/sdl_controller_support_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Input = require("src.core.Input")
local GamepadMap = require("src.core.GamepadMap")
local BindingsMenu = require("src.ui.BindingsMenu")
local Game = require("src.core.Game")

local pad = { isGamepad = function() return true end }

local function newGame()
  local game = { save = { options = {} }, data = {}, wroteOptions = 0 }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = Input
  function game:writeOptions() self.wroteOptions = self.wroteOptions + 1 end
  function game:_cycleSpeed(dir) self.cycledSpeed = (self.cycledSpeed or 0) + dir end
  return game
end

Input:init()

Input:reset()
Input:gamepadaxis(pad, "leftx", -0.9)
Input:step()
check(Input:wasPressed("left"), "left stick left presses left")
check(Input:isDown("left"), "left stick left holds left")

Input:gamepadaxis(pad, "leftx", 0)
check(not Input:isDown("left"), "centering left stick releases left")

Input:reset()
Input:gamepadaxis(pad, "lefty", -0.8)
Input:step()
check(Input:wasPressed("up"), "left stick up presses up")
check(Input:isDown("up"), "left stick up holds up")

Input:gamepadaxis(pad, "lefty", 0)
check(not Input:isDown("up"), "centering left stick releases up")

Input:reset()
Input:gamepadaxis(pad, "rightx", 0.9)
Input:step()
check(not Input:wasPressed("right"), "right stick right is unmapped by default")
check(not Input:isDown("right"), "right stick right does not hold right by default")

Input:gamepadaxis(pad, "rightx", 0)

Input:reset()
Input:gamepadaxis(pad, "righty", 0.8)
Input:step()
check(not Input:wasPressed("down"), "right stick down is unmapped by default")
check(not Input:isDown("down"), "right stick down does not hold down by default")

Input:gamepadaxis(pad, "righty", 0)

Input:reset()
Input:gamepadaxis(pad, "lefty", -0.4)
check(not Input:isDown("up"), "lefty -0.4 is below STICK_ON (0.5), does not trigger")

Input:gamepadaxis(pad, "lefty", -0.7)
check(Input:isDown("up"), "lefty -0.7 triggers up")

Input:gamepadaxis(pad, "lefty", -0.4)
check(Input:isDown("up"), "lefty -0.4 stays held above STICK_OFF (0.3)")

Input:gamepadaxis(pad, "lefty", -0.2)
check(not Input:isDown("up"), "lefty -0.2 drops below STICK_OFF (0.3), releases up")

Input:reset()
Input:gamepadaxis(pad, "leftx", 0.9)
Input:step()
check(Input:isDown("right"), "stick tilted right")
check(not Input:isDown("down"), "down not held")

Input:gamepadaxis(pad, "lefty", 0.95)
Input:step()
check(not Input:isDown("right"), "rolling to down releases right")
check(Input:isDown("down"), "and presses down")

Input:gamepadaxis(pad, "leftx", 0)
Input:gamepadaxis(pad, "lefty", 0)
check(not Input:isDown("down"), "centering releases down")

Input:reset()
Input:gamepadpressed(pad, "dpup")
Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(Input:isDown("up"), "both D-pad and stick hold up")

Input:gamepadreleased(pad, "dpup")
check(Input:isDown("up"), "releasing D-pad still keeps up held via stick")

Input:gamepadaxis(pad, "lefty", 0)
check(not Input:isDown("up"), "releasing stick finally clears up")

Input:reset()
local name, phase = Input:triggerAxis("triggerleft", 0.3)
check(phase == nil, "trigger at 0.3 is below threshold")

name, phase = Input:triggerAxis("triggerleft", 0.6)
eq(phase, "pressed", "trigger at 0.6 fires pressed")

name, phase = Input:triggerAxis("triggerleft", 0.3)
check(phase == nil, "trigger releasing to 0.3 stays held (hysteresis)")

name, phase = Input:triggerAxis("triggerleft", 0.1)
eq(phase, "released", "trigger dropping to 0.1 fires released")

local game = newGame()
local bm = BindingsMenu.new(game)
game.stack:push(bm)

bm.index = 5
bm.onChoose(bm.items[5])
check(bm.capture == bm.items[5], "A row capture armed")

bm:onGamepadPressed("triggerright")
check(game.save.options.bindings == nil, "pending trigger release")
bm:onGamepadReleased("triggerright")

local bindings = game.save.options.bindings
eq(bindings.a.pad, "triggerright", "triggerright stored on row A")
eq(bm.items[5].right, "Z/R2", "row A displays Z/R2")

Input:applyBindings(bindings)
Input:reset()
Input:gamepadaxis(pad, "triggerright", 0.8)
Input:step()
check(Input:isDown("a"), "pulling R2 presses A")
Input:gamepadaxis(pad, "triggerright", 0)
check(not Input:isDown("a"), "releasing R2 releases A")

bm.index = 1
bm.onChoose(bm.items[1])
bm:onGamepadPressed("leftstick_up")
bm:onGamepadReleased("leftstick_up")

eq(bindings.up.pad, "leftstick_up", "leftstick_up stored on row UP")
eq(bm.items[1].right, "UP/LS-UP", "row UP displays UP/LS-UP")

bm.index = 2
bm.onChoose(bm.items[2])
bm:onGamepadPressed("rightstick_down")
bm:onGamepadReleased("rightstick_down")

eq(bindings.down.pad, "rightstick_down", "rightstick_down stored on row DOWN")
eq(bm.items[2].right, "DOWN/RS-DN", "row DOWN displays DOWN/RS-DN")

bm.index = 10
bm.onChoose(bm.items[10])
bm:onGamepadPressed("rightstick")
bm:onGamepadReleased("rightstick")

eq(bindings.speedUp.pad, "rightstick", "rightstick stored on SPEED +")
eq(bm.items[10].right, "1/RS", "row SPEED + displays 1/RS")

Input:applyBindings(bindings)
eq(Input:padAction("rightstick"), "speedUp", "rightstick triggers speedUp action")

bm.index = 9
bm.onChoose(bm.items[9])
bm:onGamepadPressed("triggerleft")
bm:onGamepadReleased("triggerleft")

eq(bindings.speedDown.pad, "triggerleft", "triggerleft stored on SPEED -")
eq(bm.items[9].right, "0/L2", "row SPEED - displays 0/L2")
Input:applyBindings(bindings)
eq(Input:padAction("triggerleft"), "speedDown", "triggerleft triggers speedDown action")

local gameInstance = setmetatable(newGame(), { __index = Game })
local bm2 = BindingsMenu.new(gameInstance)
gameInstance.stack:push(bm2)

bm2.index = 6
bm2.onChoose(bm2.items[6])
check(bm2.capture == bm2.items[6], "Row B capture armed")

Game.gamepadaxis(gameInstance, pad, "rightx", -0.8)
check(bm2.pending ~= nil and bm2.pending.value == "rightstick_left",
  "Game:gamepadaxis routes stick tilt into capture as rightstick_left")

Game.gamepadaxis(gameInstance, pad, "rightx", 0)
check(bm2.capture == nil, "centering stick completes capture")
eq(gameInstance.save.options.bindings.b.pad, "rightstick_left", "Row B bound to rightstick_left")
eq(bm2.items[6].right, "X/RS-LT", "Row B displays X/RS-LT")

local bm3 = BindingsMenu.new(game)
game.stack:push(bm3)

bm3.index = 5
bm3.onChoose(bm3.items[5])
bm3:onGamepadPressed("leftstick")
bm3:onGamepadReleased("leftstick")
eq(bm3.items[5].right, "Z/LS", "Row A bound to leftstick shows Z/LS")

bm3.index = 6
bm3.onChoose(bm3.items[6])
bm3:onGamepadPressed("x")
bm3:onGamepadReleased("x")
eq(bm3.items[6].right, "X/X", "Row B bound to x shows X/X")

bm3.index = 7
bm3.onChoose(bm3.items[7])
bm3:onGamepadPressed("guide")
bm3:onGamepadReleased("guide")
eq(bm3.items[7].right, "ESC/GUIDE", "Row START bound to guide shows ESC/GUIDE")

bm3.index = 8
bm3.onChoose(bm3.items[8])
bm3:onGamepadPressed("touchpad")
bm3:onGamepadReleased("touchpad")
eq(bm3.items[8].right, "TAB/PAD", "Row SELECT bound to touchpad shows TAB/PAD")

bm3.index = 5
bm3.onSelectKey(bm3.items[5])
eq(bm3.items[5].right, "Z/A", "clearing row A restores default Z/A")

game.save.options.bindings = {
  a = { pad = "leftstick" },
  b = { pad = "rightstick_up" },
  up = { pad = "triggerright" },
}
bm3.confirmReset(bm3)
local confirmBox = game.stack:top()
check(confirmBox ~= nil, "confirm reset dialog pushed")
if confirmBox and confirmBox.onChoose then confirmBox.onChoose(true) end
check(game.save.options.bindings == nil, "reset all cleared options.bindings")

local Game2 = require("src.core.Game2")
local Game3 = require("src.core.Game3")

local g2 = setmetatable(newGame(), { __index = Game2 })
local bmG2 = BindingsMenu.new(g2)
g2.stack:push(bmG2)
bmG2.index = 5
bmG2.onChoose(bmG2.items[5])
Game2.gamepadaxis(g2, pad, "lefty", -0.9)
check(bmG2.pending ~= nil and bmG2.pending.value == "leftstick_up",
  "Game2:gamepadaxis routes stick tilt into menu capture")
Game2.gamepadaxis(g2, pad, "lefty", 0)
check(bmG2.capture == nil, "Game2 stick release completes capture")
eq(bmG2.items[5].right, "Z/LS-UP", "Game2 row A displays Z/LS-UP")

local g3 = setmetatable(newGame(), { __index = Game3 })
g3.input = Input
Input:reset()
Input:armCapture()
Game3.gamepadaxis(g3, pad, "righty", 0.9)
local capEvents = Input:takeCaptureEvents()
check(capEvents ~= nil and #capEvents > 0, "Game3:gamepadaxis records captureEvents")
check(capEvents[1].kind == "pad" and capEvents[1].phase == "pressed" and capEvents[1].value == "rightstick_down",
  "Game3 capture event is rightstick_down pressed")
Game3.gamepadaxis(g3, pad, "righty", 0)
local relEvents = Input:takeCaptureEvents()
check(relEvents ~= nil and #relEvents > 0 and relEvents[1].phase == "released" and relEvents[1].value == "rightstick_down",
  "Game3 capture event is rightstick_down released")
Input:disarmCapture()

local mockPad = {
  isGamepad = function() return true end,
  isGamepadDown = function(_, b) return false end,
  getGamepadAxis = function(_, axis)
    if axis == "triggerleft" then return 0.9 end
    if axis == "lefty" then return -0.9 end
    return 0
  end,
}

Input:init()
Input:applyBindings({
  speedDown = { pad = "triggerleft" },
  up = { pad = "leftstick_up" },
})

Input:reconcile()
Input:gamepadaxis(mockPad, "triggerleft", 0.9)
Input:gamepadaxis(mockPad, "lefty", -0.9)
Input:step()
check(Input:isDown("up"), "reconciled stick axis holds up")

Input:init()
T.finish("sdl_controller_support_test")
