--   luajit tests/engine/stick_rebind_isolation_test.lua
-- Tests for analog stick rebind isolation, default neutrality of RS,
-- D-pad preservation, and virtual source eviction across applyBindings.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Input = require("src.core.Input")
local pad = { isGamepad = function() return true end }

-- =========================================================================
-- 1. Default state: LS moves, RS is neutral, D-Pad moves
-- =========================================================================
Input:init()
Input:reset()

Input:gamepadpressed(pad, "dpup")
Input:step()
check(Input:wasPressed("up"), "default: D-pad presses up")
check(Input:isDown("up"), "default: D-pad holds up")
Input:gamepadreleased(pad, "dpup")
Input:step()
check(not Input:isDown("up"), "default: D-pad release releases up")

Input:reset()
Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(Input:wasPressed("up"), "default: LS presses up")
check(Input:isDown("up"), "default: LS holds up")
Input:gamepadaxis(pad, "lefty", 0)
Input:step()
check(not Input:isDown("up"), "default: centering LS releases up")

Input:reset()
Input:gamepadaxis(pad, "righty", -0.9)
Input:step()
check(not Input:wasPressed("up"), "default: RS is neutral and does NOT press up")
check(not Input:isDown("up"), "default: RS is neutral and does NOT hold up")
Input:gamepadaxis(pad, "righty", 0)

-- =========================================================================
-- 2. D-Pad vs Analog trap: remapping D-Pad or face buttons does NOT kill LS
-- =========================================================================
Input:init()
Input:applyBindings({
  up = { pad = "dpup" },
  down = { pad = "y" },
})
Input:reset()

Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(Input:wasPressed("up"), "D-pad rebind: LS still moves up")
check(Input:isDown("up"), "D-pad rebind: LS holds up")
Input:gamepadaxis(pad, "lefty", 0)

Input:reset()
Input:gamepadaxis(pad, "lefty", 0.9)
Input:step()
check(Input:wasPressed("down"), "face-button rebind for DOWN: LS still moves down")
check(Input:isDown("down"), "face-button rebind for DOWN: LS holds down")
Input:gamepadaxis(pad, "lefty", 0)

Input:reset()
Input:gamepadaxis(pad, "righty", -0.9)
Input:step()
check(not Input:isDown("up"), "D-pad rebind: RS remains neutral")
Input:gamepadaxis(pad, "righty", 0)

-- =========================================================================
-- 3. Movement bound explicitly to LS: LS moves, RS remains neutral
-- =========================================================================
Input:init()
Input:applyBindings({
  up = { pad = "leftstick_up" },
  down = { pad = "leftstick_down" },
  left = { pad = "leftstick_left" },
  right = { pad = "leftstick_right" },
})
Input:reset()

Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(Input:wasPressed("up"), "LS bound: LS presses up")
Input:gamepadaxis(pad, "lefty", 0)

Input:reset()
Input:gamepadaxis(pad, "righty", -0.9)
Input:step()
check(not Input:wasPressed("up"), "LS bound: RS does NOT press up")
check(not Input:isDown("up"), "LS bound: RS is neutral")
Input:gamepadaxis(pad, "righty", 0)

-- =========================================================================
-- 4. Movement bound explicitly to RS: RS moves, LS is suppressed
-- =========================================================================
Input:init()
Input:applyBindings({
  up = { pad = "rightstick_up" },
  down = { pad = "rsdown" },
})
Input:reset()

Input:gamepadaxis(pad, "righty", -0.9)
Input:step()
check(Input:wasPressed("up"), "RS bound: RS presses up")
check(Input:isDown("up"), "RS bound: RS holds up")
Input:gamepadaxis(pad, "righty", 0)

Input:reset()
Input:gamepadaxis(pad, "righty", 0.9)
Input:step()
check(Input:wasPressed("down"), "RS bound (alias): RS down presses down")
check(Input:isDown("down"), "RS bound (alias): RS down holds down")
Input:gamepadaxis(pad, "righty", 0)

Input:reset()
Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(not Input:wasPressed("up"), "RS bound: LS up is suppressed")
check(not Input:isDown("up"), "RS bound: LS up is not held")
Input:gamepadaxis(pad, "lefty", 0)

Input:reset()
Input:gamepadaxis(pad, "lefty", 0.9)
Input:step()
check(not Input:wasPressed("down"), "RS bound: LS down is suppressed")
check(not Input:isDown("down"), "RS bound: LS down is not held")
Input:gamepadaxis(pad, "lefty", 0)

-- Note: horizontal directions were NOT bound to RS, so LS left/right still works!
Input:reset()
Input:gamepadaxis(pad, "leftx", -0.9)
Input:step()
check(Input:wasPressed("left"), "RS bound only for vertical: LS horizontal left still works")
Input:gamepadaxis(pad, "leftx", 0)

-- =========================================================================
-- 5. Left stick bound to an arbitrary action (e.g. A / Confirm)
-- =========================================================================
Input:init()
Input:applyBindings({
  a = { pad = "leftstick_up" },
})
Input:reset()

Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(Input:wasPressed("a"), "LS up bound to A: presses A")
check(not Input:wasPressed("up"), "LS up bound to A: does NOT press up")
Input:gamepadaxis(pad, "lefty", 0)

-- Short alias test (lsup bound to B)
Input:init()
Input:applyBindings({
  b = { pad = "lsup" },
})
Input:reset()

Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(Input:wasPressed("b"), "LS up alias bound to B: presses B")
check(not Input:wasPressed("up"), "LS up alias bound to B: does NOT press up")
Input:gamepadaxis(pad, "lefty", 0)

-- =========================================================================
-- 6. Right stick bound to an arbitrary action (e.g. A / Confirm)
-- =========================================================================
Input:init()
Input:applyBindings({
  a = { pad = "rightstick_up" },
})
Input:reset()

Input:gamepadaxis(pad, "righty", -0.9)
Input:step()
check(Input:wasPressed("a"), "RS up bound to A: presses A")
check(not Input:wasPressed("up"), "RS up bound to A: does NOT press up")
Input:gamepadaxis(pad, "righty", 0)

-- Left stick should still move up
Input:reset()
Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(Input:wasPressed("up"), "RS up bound to A: LS up still moves up")
Input:gamepadaxis(pad, "lefty", 0)

-- =========================================================================
-- 7. Symmetrical virtual stick source eviction across applyBindings
-- =========================================================================
Input:init()
Input:reset()

-- Tilt stick up and confirm it is held
Input:gamepadaxis(pad, "lefty", -0.9)
Input:step()
check(Input:isDown("up"), "stick tilted up holds up")

-- While stick is still tilted, swap bindings (like exiting the CONTROLS menu)
Input:applyBindings({
  up = { pad = "rightstick_up" },
})
Input:step()
check(not Input:isDown("up"), "applyBindings evicted virtual stick source: UP is no longer held")
eq(Input.stickDir, nil, "applyBindings reset stickDir to nil")
eq(Input.rightStickDir, nil, "applyBindings reset rightStickDir to nil")

Input:init()
T.finish("stick_rebind_isolation_test")
