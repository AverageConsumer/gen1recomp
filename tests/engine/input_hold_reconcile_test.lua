-- Held directions must survive lifecycle resets while physically held
-- (#799).  Input state is event-driven, so any Input:reset (focus or
-- visibility flip, joystick add/remove, resume) wipes a hold that never
-- re-fires keypressed afterwards -- on macOS a Bluetooth controller
-- re-enumerating mid-walk fired joystickadded under a held key and parked
-- the player until the direction was released and pressed again.  Game's
-- lifecycle handlers rebuild holds from device ground truth after each
-- reset; only what is physically down comes back, so the swallowed-release
-- hazards the resets guard against stay cleared.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check

local Input = require("src.core.Input")
local Game = require("src.core.Game")

local realIsDown = love.keyboard.isDown
local realJoystick = love.joystick
local function restore()
  love.keyboard.isDown = realIsDown
  love.joystick = realJoystick
end

Input:init()

-- Keyboard: direction still physically held across a spurious pad
-- re-enumeration must keep walking (the #799 report).
love.keyboard.isDown = function(key) return key == "up" end
Input:reset()
Input:keypressed("up")
Input:step()
check(Input:isDown("up"), "up held before joystick re-enumeration")
Game:joystickadded({ getName = function() return "Wireless Controller" end })
check(Input:isDown("up"), "held key survives a spurious joystickadded")

-- Same hold across a focus bounce (another reset source).
Game:focus(false)
check(not Input:isDown("up"), "focus loss still drops the hold")
Game:focus(true)
check(Input:isDown("up"), "held key re-arms on focus regain")

-- A key released while unfocused (keyup swallowed by the OS, the hazard
-- the resets exist for) must NOT come back.
love.keyboard.isDown = function() return false end
Game:focus(false)
Game:focus(true)
check(not Input:isDown("up"), "swallowed release still clears the hold")

-- Controller: held d-pad across a disconnect/reconnect bounce.
local pad = {
  isGamepad = function() return true end,
  isGamepadDown = function(_, button) return button == "dpleft" end,
  getGamepadAxis = function() return 0 end,
}
love.joystick = { getJoysticks = function() return { pad } end }
love.keyboard.isDown = function() return false end
Input:reset()
Input:gamepadpressed(pad, "dpleft")
Input:step()
check(Input:isDown("left"), "d-pad held before reconnect")
Game:joystickremoved(pad)
Game:joystickadded(pad)
check(Input:isDown("left"), "held d-pad survives a reconnect bounce")

-- Held stick across the same bounce (axis ground truth re-derived).
pad.isGamepadDown = function() return false end
pad.getGamepadAxis = function(_, axis) return axis == "leftx" and -0.9 or 0 end
Input:reset()
Input:gamepadaxis(pad, "leftx", -0.9)
Input:step()
check(Input:isDown("left"), "stick held before re-enumeration")
Game:joystickadded(pad)
check(Input:isDown("left"), "held stick survives re-enumeration")

-- A pad that vanished for real reports nothing held: its stale hold must
-- stay cleared (the stuck-flag hazard reset-on-remove guards against).
love.joystick = { getJoysticks = function() return {} end }
Input:reset()
Input:gamepadpressed(pad, "dpleft")
Input:step()
Game:joystickremoved(pad)
check(not Input:isDown("left"), "vanished pad's hold stays cleared")

restore()
T.finish()
