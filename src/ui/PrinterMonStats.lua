local Font = require("src.render.Font")
local HudTiles = require("src.render.HudTiles")
local TileAtlas = require("src.render.TileAtlas")

local PrinterMonStats = {}

local function frontPic(game, mon)
  local path = require("src.pokemon.Sprites").path(game.data, mon.species, "front",
    { mon = mon, kind = "summary" })
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

-- pokeyellow engine/printer/printer2.asm:1
function PrinterMonStats.render(game, mon)
  local data = game.data
  local t = data.text
  local tiles = data.field.yellowPages.monStats
  local def = data.pokemon[mon.species]
  local stats = mon.stats
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, 0, 20, 18)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(TileAtlas.image(tiles.lv), 16, 80)
  love.graphics.draw(TileAtlas.image(tiles.hp), 16, 88)
  HudTiles.statusTile(0x74, 16, 64)
  HudTiles.statusTile(0x73, 72, 48)
  HudTiles.statusTile(0x74, 80, 48)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(tostring(mon.level), 32, 80)
  Font.draw(("%3d"):format(stats.hp), 32, 88)
  Font.draw(mon.nickname or def.name, 64, 16)
  Font.draw(def.name, 72, 24)
  Font.drawCode(0xF2, 24, 64)
  Font.draw(("%03d"):format(def.dex or 0), 32, 64)
  Font.draw(t["Printer_GetMonStats.OT"], 64, 32)
  Font.draw(mon.ot or game.save.player.name, 72, 40)
  Font.draw("/", 88, 48)
  Font.draw(("%05d"):format(mon.otId or game.save.player.id or 0), 104, 48)
  local row = 0
  for line in (t["Printer_GetMonStats.Stats"] .. "\n"):gmatch("(.-)\n") do
    Font.draw(line, 72, 64 + row * 8)
    row = row + 1
  end
  for i, value in ipairs({ stats.attack, stats.defense, stats.speed, stats.special }) do
    Font.draw(("%3d"):format(value), 128, 64 + (i - 1) * 8)
  end
  for i = 1, 4 do
    local mv = mon.moves[i]
    local name = mv and data.moves[mv.id] and data.moves[mv.id].name
    Font.draw(name or t["Printer_GetMonStats.Blank"], 8, 104 + (i - 1) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
  local pic = frontPic(game, mon)
  if pic then
    local pw, ph = pic:getDimensions()
    -- home/pics.asm:68-76
    local px = 8 + math.max(0, 56 - math.floor((8 - pw / 8) / 2) * 8 - pw)
    local py = 8 + math.max(0, 56 - ph)
    love.graphics.draw(pic, px + pw, py, 0, -1, 1)
  end
end

return PrinterMonStats
