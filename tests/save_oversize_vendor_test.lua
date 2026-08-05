-- Independent-oracle test for the oversize-save import path in
-- src/import/SaveFileIO.lua (importToSlot force/truncate when a .sav exceeds
-- 32768 bytes with a valid main-data checksum -- i.e. a cartridge save padded
-- with an emulator RTC footer).
--
-- The fixture is built by the VENDOR codec (tools/save_convert/vendor/
-- gen1lib.lua, a PKHeX-derived Gen1 .sav<->JSON codec): the bytes GenSave
-- later imports were never produced by GenSave.  The post-truncation export is
-- then re-parsed by that SAME vendor codec -- a second source independent of
-- GenSave -- confirming the forced truncation drops only the footer.
--
-- Runs under stock Lua 5.3/5.4/5.5 (gen1lib needs native bitwise operators and
-- cannot even be parsed by LuaJIT); GenSave gets a `bit` shim backed by those
-- operators, exactly like tools/save_convert/crosscheck.lua.
--   lua tests/save_oversize_vendor_test.lua
--
-- The luajit side of this policy lives in save_file_io_tests.lua; this file is
-- the out-of-band vendor oracle (see save_convert_tests.lua for the same
-- split).  It lives OUTSIDE tests/engine/ on purpose: tier_runner globs that
-- directory under luajit, which cannot parse gen1lib.  scripts/test.sh runs it
-- as its own lua5.4 tier when that interpreter is available.

package.path = "./?.lua;./?/init.lua;" .. package.path

-- `bit` shim backed by native Lua 5.3+ operators (crosscheck.lua's).
if not pcall(require, "bit") then
  package.preload["bit"] = function()
    local M = {}
    function M.band(a, ...) local r = a; for _, v in ipairs({...}) do r = r & v end; return r & 0xFFFFFFFF end
    function M.bor(a, ...) local r = a; for _, v in ipairs({...}) do r = r | v end; return r & 0xFFFFFFFF end
    function M.bxor(a, ...) local r = a; for _, v in ipairs({...}) do r = r ~ v end; return r & 0xFFFFFFFF end
    function M.bnot(a) return (~a) & 0xFFFFFFFF end
    function M.lshift(a, n) return (a << n) & 0xFFFFFFFF end
    function M.rshift(a, n) return (a & 0xFFFFFFFF) >> n end
    return M
  end
end

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")

local gen1 = dofile("tools/save_convert/vendor/gen1lib.lua")

-- The vendor fixture needs no data/generated for BUILDING, but the import
-- (SaveConvert.importSav -> GenSave.decode) needs the crosswalk tables, so
-- skip cleanly on a checkout that never imported a ROM (like the luajit suite).
local loadPokemon = loadfile("data/generated/pokemon.lua")
if not loadPokemon then
  print("save_oversize_vendor skipped (needs data/generated/ for GenSave codec)")
  os.exit(0)
end

local realFS = love.filesystem

-- Same love.filesystem stub as save_file_io_tests.lua: keyed by full path with
-- the export surface SaveFileIO reaches (createDirectory/getSaveDirectory).
local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
  }
end

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

-- DroppedFile-shaped source (readSource treats a raw string of length != 32768
-- as a path, so hand a file object).
local function fileSource(bytes)
  return {
    _bytes = bytes,
    open = function() return true end,
    getSize = function(self) return #self._bytes end,
    read = function(self) return self._bytes end,
    close = function() return true end,
  }
end

-- A realistic 44-byte VBA MBC3 RTC footer (bgb.bircd.org/rtcsave.html).
local function rtcFooter()
  local parts = {}
  local function pushLe(v)
    parts[#parts + 1] = string.char(v % 256, math.floor(v / 256) % 256,
      math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  pushLe(27); pushLe(29); pushLe(11); pushLe(200)
  parts[#parts + 1] = string.rep("\0", 16)
  parts[#parts + 1] = string.rep("\0", 8)
  pushLe(0x669A00BF)
  return table.concat(parts)
end

-- Build a 32768-byte save ENTIRELY through the vendor codec: zero base buffer,
-- trainer/party/box fields written by gen1lib, checksum recomputed by
-- gen1lib.  GenSave had no part in producing these bytes.
local function vendorSave()
  local data = {
    raw_base64 = gen1.base64_encode(string.rep("\0", GenSave.SAVE_SIZE)),
    trainer = {
      name = "VENDOR", id = 12345, rival_name = "BLUE",
      money = 4321, coins = 0, badges = 0, options = 0, starter = 0,
      pikachu_friendship = 0, pikachu_beach_score = 0,
    },
    current_box = 1,
    party = {},
    boxes = {},
  }
  return gen1.build_save(data)
end

-- ---------------------------------------------- vendor-built oversize round trip

do
  local base = vendorSave()
  eq(#base, GenSave.SAVE_SIZE, "the vendor codec builds a 32768-byte save")
  eq(SaveConvert.mainChecksumValid(base), true,
    "the vendor-built save carries a valid main-data checksum")

  local oversize = base .. rtcFooter()
  eq(#oversize, 32768 + 44, "the oversize fixture is 32812 bytes")

  local files = fresh()
  -- the save the project has never seen imports cleanly once force truncates
  local ok, slotId = SaveFileIO.importToSlot(fileSource(oversize), "red", true)
  eq(ok, true, "the vendor-built oversize save imports with force")
  local loaded = SaveData.load("red")
  eq(loaded and loaded.player.name, "VENDOR", "the imported save keeps the vendor-written name")
  eq(loaded and loaded.money, 4321, "the imported save keeps the vendor-written money")

  local eok, path = SaveFileIO.exportActiveSlot("red")
  eq(eok, true, "the forced import exports")
  local rel = path:gsub("^/fake/save/", "")
  local outBytes = files[rel]
  eq(outBytes and #outBytes, GenSave.SAVE_SIZE, "the export is exactly 32768 bytes")

  -- INDEPENDENT ORACLE: the vendor codec re-parses the project's export.  If
  -- the truncation had damaged the save, or GenSave's codec self-consistently
  -- corrupted it, parse_save would disagree here.
  local outBuf = gen1.string_to_bytes(outBytes)
  local parsed = gen1.parse_save(outBuf)
  eq(parsed.trainer.name, "VENDOR", "vendor parse of the export: name intact")
  eq(parsed.trainer.money, 4321, "vendor parse of the export: money intact")
  eq(parsed.trainer.id, 12345, "vendor parse of the export: trainer id intact")
  eq(#parsed.party, 0, "vendor parse of the export: empty party preserved")
  eq(#parsed.boxes, 12, "vendor parse of the export: 12 boxes present")
end

love.filesystem = realFS

T.finish("save_oversize_vendor")
