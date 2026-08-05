-- SafeArea.rect unit sanity (#810): the iOS build reported the portrait
-- safe rect in framebuffer PIXELS while love.graphics works in DPI-scaled
-- units, and the old clamp kept the inflated top inset -- the launcher
-- started a band down the screen and left the top of it black.  A rect
-- that cannot fit the unit window is converted back to units with
-- per-axis ratios (the axes can disagree, #208).  No pokered cite: the
-- launcher is port-only chrome.
--   luajit tests/engine/safe_area_units_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local SafeArea = require("src.core.SafeArea")

local oldDims = love.graphics.getDimensions
local oldPix = love.graphics.getPixelDimensions
local oldSafe = love.window.getSafeArea

local function frame(uw, uh, pw, ph, sx, sy, sw, sh)
  love.graphics.getDimensions = function() return uw, uh end
  love.graphics.getPixelDimensions = function() return pw, ph end
  love.window.getSafeArea = function() return sx, sy, sw, sh end
  return SafeArea.rect()
end

-- a pixel-based rect on a 3x portrait phone comes back in units (#810)
local x, y, w, h = frame(375, 812, 1125, 2436, 0, 132, 1125, 2232)
eq(x, 0, "pixel-unit safe x rescales")
eq(y, 44, "pixel-unit top inset rescales to the real notch")
eq(w, 375, "pixel-unit safe width rescales")
eq(h, 744, "pixel-unit safe height rescales")

-- a correct unit rect passes through untouched
x, y, w, h = frame(375, 812, 1125, 2436, 0, 44, 375, 734)
eq(y, 44, "a unit rect keeps its top inset")
eq(h, 734, "a unit rect keeps its height")

-- dpi 1: no rescale, the oversized rect still clamps to the window
x, y, w, h = frame(640, 576, 640, 576, 0, 100, 900, 900)
eq(y, 100, "no rescale when units are pixels")
eq(w, 640, "width clamps to the drawable window")
eq(h, 476, "height clamps to the drawable window")

love.graphics.getDimensions = oldDims
love.graphics.getPixelDimensions = oldPix
love.window.getSafeArea = oldSafe

T.finish("safe area units")
