package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("UWP native picker")
local check = S.check

local Platform = require("src.core.Platform")
local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
local saved = {
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  getPickedFile = love.system.getPickedFile,
  getPickError = love.system.getPickError,
  remove = os.remove,
}

love.system.getOS = function() return "UWP" end
love.system.pickFile = function() return true end
love.system.getPickedFile = function()
  love.system.getPickedFile = function() return nil end
  return [[C:\LocalState\picked_mod.zip]]
end
love.system.getPickError = function() return nil end

local removedPath
os.remove = function(path)
  removedPath = path
  return true
end

Platform._resetForTests()
local importer = RomImporter.new(function() end, { launcher = true })
importer.pickerPendingKind = "mod"
importer._installMod = function(self, source)
  self.installedPath = source
  self.modNotice = { ok = true, text = "Installed test-mod" }
end
importer:update(0)

check(importer.installedPath == [[C:\LocalState\picked_mod.zip]],
  "passes the picked path to the mod installer")
check(removedPath == [[C:\LocalState\picked_mod.zip]],
  "removes the temporary copy after installation")

love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.system.getPickedFile = saved.getPickedFile
love.system.getPickError = saved.getPickError
os.remove = saved.remove
Platform._resetForTests()

S.finish()
