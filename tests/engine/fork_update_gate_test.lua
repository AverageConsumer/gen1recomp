-- The Kanto Android fork publishes APK-only releases.  Its bundled host must
-- neither advertise upstream payloads nor chainload one left in save data.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("Kanto fork update gate")
local eq = S.eq

local started = false
package.loaded["src.update.Check"] = {
  start = function() started = true end,
  state = function() return { status = "idle" } end,
}

love.system.getOS = function() return "Android" end
love.filesystem.isFused = function() return true end

package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
local importer = require("src.import.RomImporter").new(
  function() end, { launcher = true })

eq(require("src.core.Version").selfUpdate, false,
  "fork declares host self-updates disabled")
eq(importer.Check, nil, "launcher hides the upstream host updater")
eq(started, false, "launcher never starts an upstream release check")
eq(require("src.update.Boot").run(), false,
  "boot ignores downloaded upstream payloads")

package.loaded["src.update.Check"] = nil
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
