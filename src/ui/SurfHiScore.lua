local Font = require("src.render.Font")
local PaletteFX = require("src.render.PaletteFX")
local TileAtlas = require("src.render.TileAtlas")

local SurfHiScore = {}
SurfHiScore.__index = SurfHiScore
SurfHiScore.isOpaque = true

local LABEL = "Printer_PrepareSurfingMinigameHighScoreTileMap."

-- pokeyellow engine/printer/printer.asm:690
function SurfHiScore:sgbPalettes(game)
  return PaletteFX.wholeNamed(game.data, "MEWMON")
end

function SurfHiScore.new(game, onDone)
  return setmetatable({ game = game, onDone = onDone }, SurfHiScore)
end

-- pokeyellow scripts/SummerBeachHouse.asm:175
function SurfHiScore:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

-- pokeyellow engine/printer/printer.asm:631
function SurfHiScore.render(game)
  local pages = game.data.field.yellowPages.hiScore
  local t = game.data.text
  local img = TileAtlas.image(pages.tiles)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  for x = 0, 19 do
    local id = x % 2 == 0 and 0x00 or 0x01
    TileAtlas.draw(img, id, x * 8, 0)
    TileAtlas.draw(img, id, x * 8, 136)
  end
  for y = 0, 17 do
    local id = y % 2 == 0 and 0x02 or 0x03
    TileAtlas.draw(img, id, 0, y * 8)
    TileAtlas.draw(img, id, 152, y * 8)
  end
  for _, c in ipairs({ { 0, 0 }, { 0, 136 }, { 152, 0 }, { 152, 136 } }) do
    TileAtlas.draw(img, 0x04, c[1], c[2])
  end
  TileAtlas.box(img, pages.box1, 10, 8, 3, 8)
  TileAtlas.box(img, pages.box2, 2, 11, 6, 16)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(t[LABEL .. "PikachusBeachString"], 24, 16)
  Font.draw(t[LABEL .. "HiScoreString"], 72, 32)
  Font.draw(t[LABEL .. "PointsString"], 96, 48)
  local name = (game.save.player and game.save.player.name) or ""
  -- pokeyellow engine/printer/printer.asm:672-688
  local col = 2 + math.max(0, 8 - (Font.glyphCount(name) + 1))
  Font.draw(name, col * 8, 32)
  -- pokeyellow engine/printer/printer.asm:752
  local score = math.max(0, math.floor(tonumber(game.save.surfingHighScore) or 0))
  Font.draw(("%04d"):format(score % 10000), 56, 48)
  love.graphics.setColor(1, 1, 1, 1)
end

function SurfHiScore:draw()
  SurfHiScore.render(self.game)
end

return SurfHiScore
