-- #781: Linux launcher mouse-dead behind the pad cursor.  Reproduces the
-- X11 multi-monitor failure mode (polled love.mouse.getPosition frozen on
-- desktop-virtual coords, so the motion yield in _updatePadCursor never
-- fires) and asserts a host-forwarded mousepressed reclaims the pointer.
-- Self-contained: `luajit tests/rom_importer_cursor_bug781_test.lua`.
-- Should eventually merge into tests/rom_importer_cursor_test.lua (dofile'd
-- by tests/run_tests.lua).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer pad cursor #781")
local eq = S.eq

local RomImporter = require("src.import.RomImporter")

-- Bare importer with just the pad-cursor state new() would build; isNX
-- false keeps _updatePadCursor on the desktop path (polled motion yield),
-- _flex nil keeps the right-stick branch out of LauncherView.
local function makeImporter()
  return setmetatable({
    android = false,
    isNX = false,
    _flex = nil,
    _padCursor = { x = 320, y = 260 },
    _padCursorActive = false,
    _padAxis = { leftx = 0, lefty = 0, righty = 0 },
    _padDir = {},
    _padInited = true,
  }, RomImporter)
end

-- Failure mode: SDL's polled mouse state stuck on coordinates outside the
-- window (primary display away from desktop 0,0).  Successive samples are
-- identical, so the motion yield sees zero delta and never releases the
-- pad cursor no matter how much the real mouse moves.
local ri = makeImporter()
love.mouse.getPosition = function() return 2960, 4130 end
ri._padCursorActive = true
ri:_updatePadCursor(1 / 60)  -- seeds _lastMouseX/_lastMouseY
ri:_updatePadCursor(1 / 60)
ri:_updatePadCursor(1 / 60)
eq(ri._padCursorActive, true,
  "frozen polled coords starve the motion yield (the #781 trap)")

-- The fix: the host-forwarded real press must win the pointer back, same
-- contract as PadCursor.yieldToPointer in the overlay hosts.  This is the
-- half that un-gates LauncherView.update's click minting.
ri:mousepressed(10, 10, 1)
eq(ri._padCursorActive, false,
  "mousepressed reclaims the pointer even when the yield is starved (#781)")

-- A reclaimed pointer must stay reclaimed: the next pad-cursor tick with
-- still-frozen polled coords may not re-arm it by itself.
ri:_updatePadCursor(1 / 60)
eq(ri._padCursorActive, false,
  "an idle pad tick does not re-steal the pointer after reclaim")

-- Regression guard for the healthy desktop path: when polled coords do
-- move (window-relative, single monitor), the existing motion yield still
-- releases the pad cursor without needing a click.
local ri2 = makeImporter()
local px = 100
love.mouse.getPosition = function() return px, 100 end
ri2._padCursorActive = true
ri2:_updatePadCursor(1 / 60)
px = 140
ri2:_updatePadCursor(1 / 60)
eq(ri2._padCursorActive, false,
  "real mouse motion still yields the pad cursor on sane polled coords")

S.finish()
