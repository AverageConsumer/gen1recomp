package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local name = "src.render.SecondScreen"
local oldModule = package.loaded[name]
local oldFfi = package.loaded.ffi
local oldPreload = package.preload.ffi
local calls = {}
local null = {}

local C = {
  love_android_secondary_ready = function() return 0 end,
  love_android_push_secondary = function(ptr, w, h)
    calls.push = { ptr, w, h }
  end,
  love_android_secondary_enable = function(on) calls.enabled = on end,
  love_android_secondary_detected = function() return 1 end,
  love_android_present_secondary = function(ptr, w, h, background, target)
    calls.present = { ptr, w, h, background, target }
    return 1
  end,
  love_android_poll_secondary_touch = function()
    local event = null
    if not calls.polled then event = "down,12,34" end
    calls.polled = true
    return event
  end,
}
local fakeFfi = {
  C = C,
  NULL = null,
  cdef = function() end,
  load = function() return C end,
  string = function(value) return value end,
}

package.loaded[name] = nil
package.loaded.ffi = nil
package.preload.ffi = function() return fakeFfi end

local SecondScreen = require(name)
local image = { getFFIPointer = function() return "pixels" end }

T.eq(SecondScreen.detected(), true, "companion display detection uses the native extension")
T.eq(SecondScreen.push(image, 160, 144, 0x112233, "handheld"), true,
  "extended push presents through the upstream SecondScreen facade")
T.same(calls.present, { "pixels", 160, 144, 0x112233, "handheld" },
  "extended push preserves frame metadata and target")
T.eq(SecondScreen.pollTouch(), "down,12,34", "companion touch reaches the facade")
T.eq(SecondScreen.pollTouch(), nil, "an empty native touch queue returns nil")
T.eq(SecondScreen.push(image, 160, 144), true, "the original push path still works")
T.same(calls.push, { "pixels", 160, 144 }, "the original push ABI is unchanged")

package.loaded[name] = oldModule
package.loaded.ffi = oldFfi
package.preload.ffi = oldPreload

T.finish("second-screen companion facade")
