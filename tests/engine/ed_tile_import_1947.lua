-- engine/menus/naming_screen.asm:326, gfx/font/ED.1bpp (#1947)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

if not _G.love then _G.love = require("tests.love_stub") end

love.image.newImageData = function(width, height)
  local px = {}
  local img = { w = width or 8, h = height or 8 }
  function img:getWidth() return self.w end
  function img:getHeight() return self.h end
  function img:getDimensions() return self.w, self.h end
  function img:setPixel(x, y, r, g, b, a)
    px[y * self.w + x] = { r, g, b, a }
  end
  function img:getPixel(x, y)
    local p = px[y * self.w + x]
    if not p then return 0, 0, 0, 0 end
    return p[1], p[2], p[3], p[4]
  end
  function img:mapPixel(fn)
    for y = 0, self.h - 1 do
      for x = 0, self.w - 1 do
        px[y * self.w + x] = { fn(x, y, self:getPixel(x, y)) }
      end
    end
  end
  function img:encode() return { getString = function() return "" end } end
  return img
end

local RomExtractor = require("src.import.RomExtractor")

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
end

local MANIFESTS = {
  { "tools/rom_manifest.json", 1, 26471 },
  { "tools/rom_manifest_blue.json", 1, 26471 },
  { "tools/rom_manifest_yellow.json", 1, 25829 },
}

for _, spec in ipairs(MANIFESTS) do
  local path, expectedBank, expectedAddress = spec[1], spec[2], spec[3]
  local text = readFile(path)
  T.check(text ~= nil, path .. " is readable")
  if text then
    local bank, address = text:match(
      '"ED_Tile"%s*:%s*%[%s*(%d+)%s*,%s*(%d+)%s*%]')
    T.eq(bank, tostring(expectedBank), path .. ": ED_Tile bank")
    T.eq(address, tostring(expectedAddress), path .. ": ED_Tile address")
  end
end

local gen = readFile("tools/make_rom_manifest.py")
T.check(gen ~= nil, "tools/make_rom_manifest.py is readable")
T.check(gen ~= nil and gen:find('"ED_Tile"', 1, true) ~= nil,
  "a regenerated manifest keeps ED_Tile")

local ED_BYTES = { 0xFF, 0x81, 0xA5, 0x81, 0xBD, 0x81, 0x81, 0xFF }
local BASE_SYMBOLS = {
  FontGraphics = { 4, 0 },
  TextBoxGraphics = { 4, 4096 },
  PokedexTileGraphics = { 4, 8192 },
  PTile = { 4, 12288 },
}

local function fakeExtractor(withEd)
  local symbols = {}
  for name, location in pairs(BASE_SYMBOLS) do symbols[name] = location end
  if withEd then symbols.ED_Tile = { 1, 26471 } end
  local reads, saved, written = {}, {}, {}
  local ex = setmetatable({
    symbols = symbols,
    manifest = { fontCharmap = {} },
    stage = 0,
    rom = {
      bytes = function(_, bank, address, length)
        table.insert(reads,
          { bank = bank, address = address, length = length })
        local out = {}
        if symbols.ED_Tile and bank == symbols.ED_Tile[1]
           and address == symbols.ED_Tile[2] and length == 8 then
          for i = 1, 8 do out[i] = ED_BYTES[i] end
          return out
        end
        for i = 1, length do out[i] = 0 end
        return out
      end,
    },
  }, RomExtractor)
  ex.save = function(_, image, relative) saved[relative] = image end
  ex.write = function(_, name, value) written[name] = value end
  return ex, reads, saved, written
end

do
  local ex, reads, saved, written = fakeExtractor(true)
  local ok, data = pcall(ex.extractFont, ex)
  T.check(ok, "extractFont runs against the fake ROM: " .. tostring(data))
  local edRead
  for _, read in ipairs(reads) do
    if read.length == 8 and read.bank == 1 then edRead = read end
  end
  T.check(edRead ~= nil, "the Fonts stage reads an 8-byte tile")
  if edRead then
    T.eq(edRead.bank, 1, "from the manifest's ED_Tile bank")
    T.eq(edRead.address, 26471, "and its address")
  end
  local ed = saved["fonts/ed.png"]
  T.check(ed ~= nil, "and saves fonts/ed.png")
  if ed then
    T.eq(ed:getWidth(), 8, "the tile is 8 wide")
    T.eq(ed:getHeight(), 8, "and 8 tall")
    local wrong = 0
    for y = 0, 7 do
      for x = 0, 7 do
        local _, _, _, a = ed:getPixel(x, y)
        local on = math.floor(ED_BYTES[y + 1] / 2 ^ (7 - x)) % 2 == 1
        if (a == 1) ~= on then wrong = wrong + 1 end
      end
    end
    T.eq(wrong, 0, "1bpp decodes MSB-left, a set bit is opaque black")
  end
  T.eq(type(data) == "table" and data.imageEd or nil,
    "assets/generated/fonts/ed.png", "font.lua publishes the path")
  T.eq(written.font and written.font.imageEd or nil,
    "assets/generated/fonts/ed.png", "and the written font table carries it")
end

do
  local ex, _, saved, written = fakeExtractor(false)
  local ok, data = pcall(ex.extractFont, ex)
  T.check(ok, "a manifest without ED_Tile still imports: " .. tostring(data))
  T.eq(saved["fonts/ed.png"], nil, "no ed.png is written")
  T.eq(type(data) == "table" and data.imageEd or nil, nil,
    "and font.lua publishes no path")
  T.check(written.font ~= nil, "the rest of the font stage still runs")
end

T.finish("ED tile import")
