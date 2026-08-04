-- Portable-mode save export (#752): with portable.txt beside the game the
-- launcher's Export save must land in the game folder, never in the OS save
-- directory LOVE hands out.  SaveConvert is stubbed so this stays ROM-free;
-- what is under test is only which filesystem SaveFileIO.exportActiveSlot
-- writes through and which root the returned path reports.
--   luajit tests/engine/save_export_portable_bug752.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SEP = package.config:sub(1, 1)
local tmp = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
tmp = tmp:gsub("[/\\]$", "")
local base = tmp .. SEP .. "pokeport752"
if SEP == "\\" then
  os.execute('rmdir /s /q "' .. base .. '" 2>nul')
  os.execute('mkdir "' .. base .. '" 2>nul')
else
  os.execute('rm -rf "' .. base .. '" && mkdir -p "' .. base .. '"')
end
local marker = io.open(base .. SEP .. "portable.txt", "wb")
check(marker ~= nil, "the temp portable folder is writable")
if not marker then T.finish("save_export_portable_bug752") return end
marker:write("portable\n")
marker:close()

-- The love surface portable detection reads: a desktop OS plus a source
-- folder holding the marker (SaveData.gameFolders).  A memfs stands in for
-- the OS save directory so a stray write there is visible in the test rather
-- than silently landing on the real machine.
local strayFiles = {}
love.system = love.system or {}
love.system.getOS = function() return "Linux" end
love.filesystem = {
  getSource = function() return base end,
  getSourceBaseDirectory = function() return base end,
  getSaveDirectory = function() return "/fake/save" end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function(path, content) strayFiles[path] = content return true end,
  remove = function() return true end,
  createDirectory = function() return true end,
}

-- SaveConvert stubbed before SaveFileIO requires it: the codec needs
-- data/generated/ crosswalks, and the byte content is irrelevant here.
package.loaded["src.save_convert.SaveConvert"] = {
  SAVE_SIZE = 32768,
  exportSav = function() return string.rep("\0", 32768) end,
  importSav = function() return nil, "not used here" end,
}

local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("red")
check(SaveData.isPortable(), "portable.txt beside the game turns portable mode on")

local slotId = SaveData.createSlot("red")
check(slotId ~= nil, "a slot registers in the portable folder")
SaveData.setActiveSlot("red", slotId)
check(SaveData.writeSlot("red", slotId, SaveData.newGame()), "the slot writes")

local SaveFileIO = require("src.import.SaveFileIO")
local ok, path = SaveFileIO.exportActiveSlot("red")
eq(ok, true, "exportActiveSlot succeeds in portable mode")
local expected = base .. SEP .. "exports" .. SEP .. "red" .. SEP
  .. "gen1recomp-red-" .. tostring(slotId) .. ".sav"
eq(path, expected, "the reported path is inside the portable game folder")

local f = io.open(expected, "rb")
check(f ~= nil, "the export file exists in the portable exports/ folder")
if f then
  local bytes = f:read("*a")
  f:close()
  eq(#bytes, 32768, "the export is exactly 32768 bytes")
end

for name in pairs(strayFiles) do
  check(not name:find("^exports"),
    "no export leaked into the OS save directory: " .. name)
end

if SEP == "\\" then
  os.execute('rmdir /s /q "' .. base .. '" 2>nul')
else
  os.execute('rm -rf "' .. base .. '"')
end

T.finish("save_export_portable_bug752")
