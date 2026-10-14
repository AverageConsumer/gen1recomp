-- The dex-completion diploma (engine/events/diploma.asm DisplayDiploma /
-- diploma2.asm DisplayDiplomaTop): a bordered certificate page with the
-- player's name and character sprite, shown by the Celadon Mansion 3F game designer
-- once 150 species are owned. Diploma.render also backs the printed copy
-- (engine/printer/printer.asm PrintDiploma -> src/core/Printer.lua).

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local PixelCanvas = require("src.render.PixelCanvas")
local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local Sprites = require("src.pokemon.Sprites")
local SpriteRenderer = require("src.render.SpriteRenderer")
local Strings = require("src.core.Strings")
local TileAtlas = require("src.render.TileAtlas")

-- engine/events/diploma.asm:65
local OBP0_90 = { { 255, 255, 255 }, { 255, 255, 255 },
                  { 170, 170, 170 }, { 85, 85, 85 } }
local PIC_X, PIC_Y = 115, 80

local Diploma = {}
Diploma.__index = Diploma
Diploma.isOpaque = true

-- SGB: PalPacket_Generic (MEWMON), whole screen (engine/events/diploma.asm:67)
function Diploma:sgbPalettes(game)
  return PaletteFX.wholeNamed(game.data, "MEWMON")
end

local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then return img end
  local ok2, img2 = pcall(love.graphics.newImage, path)
  return ok2 and img2 or nil
end

local function loadFrame()
  local frame = tryImage("assets/generated/trainer_card/trainer_info.png")
  if not frame then return nil end
  local quads = {}
  for i = 0, 8 do
    quads[i] = love.graphics.newQuad((i % 3) * 8,
                                     math.floor(i / 3) * 8,
                                     8, 8, frame:getDimensions())
  end
  return { img = frame, quads = quads }
end

local function drawFrameBox(frame, tx, ty, tw, th)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  if not frame then
    Font.drawBox(tx, ty, tw, th)
    return
  end
  local img = frame.img
  local q = frame.quads
  love.graphics.setColor(1, 1, 1, 1)
  -- engine/link/cable_club.asm:937
  love.graphics.draw(img, q[2], tx * 8, ty * 8)
  love.graphics.draw(img, q[4], (tx + tw - 1) * 8, ty * 8)
  love.graphics.draw(img, q[6], tx * 8, (ty + th - 1) * 8)
  love.graphics.draw(img, q[7], (tx + tw - 1) * 8, (ty + th - 1) * 8)
  for x = 1, tw - 2 do
    love.graphics.draw(img, q[3], (tx + x) * 8, ty * 8)
    love.graphics.draw(img, q[0], (tx + x) * 8, (ty + th - 1) * 8)
  end
  for y = 1, th - 2 do
    love.graphics.draw(img, q[5], tx * 8, (ty + y) * 8)
    love.graphics.draw(img, q[1], (tx + tw - 1) * 8, (ty + y) * 8)
  end
end

local function playerName(game)
  return (game.save.player and game.save.player.name) or "RED"
end

local function drawLines(game)
  -- engine/events/diploma.asm:95
  Font.draw(Strings("Player"), 24, 32)
  -- engine/events/diploma.asm:39
  Font.draw(playerName(game), 80, 32)

  -- engine/events/diploma.asm:97
  local congrats = {
    { text = Strings.source("Congrats! This"),    y = 48 },
    { text = Strings.source("diploma certifies"), y = 64 },
    { text = Strings.source("that you have"),     y = 80 },
    { text = Strings.source("completed your"),    y = 96 },
    { text = Strings.source("POKéDEX."),          y = 112 },
  }
  for _, line in ipairs(congrats) do
    Font.draw(Strings(line.text), 16, line.y)
  end

  -- engine/events/diploma.asm:98
  Font.draw(Strings("GAME FREAK"), 72, 128)
end

local overlayCanvas, overlayKey

local function textOverlay(game)
  local g = love.graphics
  if not (g.newCanvas and g.setCanvas and g.push and g.pop) then return nil end
  local key = playerName(game) .. "\0" .. tostring(Strings.active())
  if overlayCanvas and overlayKey == key then return overlayCanvas end
  if not overlayCanvas then
    local ok, c = pcall(PixelCanvas.new, 160, 144)
    if not ok or not c then return nil end
    overlayCanvas = c
  end
  g.push("all")
  g.setCanvas(overlayCanvas)
  g.origin()
  g.setScissor()
  g.setShader()
  g.clear(0, 0, 0, 0)
  g.setColor(0, 0, 0, 1)
  drawLines(game)
  g.pop()
  overlayKey = key
  return overlayCanvas
end

function Diploma.new(game, onDone)
  local self = setmetatable({
    game = game,
    onDone = onDone,
  }, Diploma)
  return self
end

function Diploma:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

local function yellowPages(game)
  local field = GameVersion.isYellow() and game.data and game.data.field
  return field and field.yellowPages and field.yellowPages.diploma
end

local function drawLinesDouble(text, x, y)
  local row = 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    Font.draw(line, x, y + row * 16)
    row = row + 1
  end
end

-- pokeyellow engine/events/diploma2.asm:125-146
local function yellowBorders(img, borderRow)
  love.graphics.setColor(1, 1, 1, 1)
  for x = 0, 19 do
    TileAtlas.draw(img, x % 2 == 0 and 0x02 or 0x01, x * 8, borderRow * 8)
  end
  for y = 0, 17 do
    local id = y % 2 == 0 and 0x04 or 0x03
    TileAtlas.draw(img, id, 0, y * 8)
    TileAtlas.draw(img, id, 152, y * 8)
  end
  TileAtlas.draw(img, 0x00, 0, borderRow * 8)
  TileAtlas.draw(img, 0x00, 152, borderRow * 8)
end

-- pokeyellow engine/events/diploma2.asm:3
local function renderYellowTop(game, pages)
  local t = game.data.text
  local img = TileAtlas.image(pages.tiles)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  yellowBorders(img, 0)
  TileAtlas.draw(img, 0x10, 40, 16)
  TileAtlas.draw(img, 0x10, (6 + Font.glyphCount(t.DiplomaText)) * 8, 16)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(t.DiplomaText, 48, 16)
  Font.draw(t.DiplomaPlayer, 24, 32)
  Font.draw(playerName(game), 80, 32)
  drawLinesDouble(t.DiplomaCongrats, 16, 48)
  Font.draw(t.DiplomaGameFreak, 72, 128)
  love.graphics.setColor(1, 1, 1, 1)
end

local function ownedCount(game)
  local dex = game.save.pokedex
  local owned = 0
  for _ in pairs(dex and dex.owned or {}) do owned = owned + 1 end
  return owned
end

-- pokeyellow engine/events/diploma2.asm:67
local function renderYellowBottom(game, pages)
  local t = game.data.text
  local img = TileAtlas.image(pages.tiles)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  yellowBorders(img, 17)
  TileAtlas.box(img, pages.pikachu, 6, 2, 10, 12)
  TileAtlas.box(img, pages.congrats, 5, 13, 1, 11)
  local secs = math.floor(tonumber(game.save.playTime) or 0)
  local hours = tostring(math.min(255, math.floor(secs / 3600)))
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(t.DiplomaPlayTime, 16, 120)
  Font.draw(hours, 96, 120)
  love.graphics.setColor(1, 1, 1, 1)
  TileAtlas.draw(img, 0x16, (12 + #hours) * 8, 120)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(("%02d"):format(math.floor(secs / 60) % 60), (13 + #hours) * 8, 120)
  love.graphics.setColor(1, 1, 1, 1)
  -- pokeyellow engine/events/diploma2.asm:104-110
  if ownedCount(game) == 151 then
    TileAtlas.box(img, pages.mew, 2, 0, 4, 5)
  end
end

function Diploma.printHeight(game)
  return yellowPages(game) and 288 or 144
end

-- pokeyellow engine/printer/printer.asm:160
function Diploma.renderPrint(game)
  local pages = yellowPages(game)
  if not pages then return Diploma.render(game) end
  renderYellowTop(game, pages)
  love.graphics.push()
  love.graphics.translate(0, 144)
  renderYellowBottom(game, pages)
  love.graphics.pop()
end

-- the DisplayDiploma / DisplayDiplomaTop layout (hlcoord tiles -> x*8, y*8)
function Diploma.render(game)
  local pages = yellowPages(game)
  if pages then return renderYellowTop(game, pages) end
  local frame = loadFrame()
  local circle = tryImage("assets/generated/trainer_card/circle_tile.png")

  -- 1. Outer ornate frame border: hlcoord 0, 0 / bc 16, 18 -> (0, 0, 20, 18)
  drawFrameBox(frame, 0, 0, 20, 18)

  -- 2. Draw Player character sprite: farcall DrawPlayerCharacter
  -- engine/movie/title.asm:321
  local title = (game.data and game.data.field and game.data.field.title) or {}
  local titlePlayer = title.player
  if type(titlePlayer) == "table" then titlePlayer = titlePlayer.path end
  local picPath, picTrueColor = Sprites.playerPic(
    titlePlayer or "assets/generated/title/player.png",
    { side = "front", kind = "diploma", data = game.data })
  local pic
  local ogObp = false
  if picPath then
    if picTrueColor then
      pic = tryImage(picPath)
    else
      ogObp = PaletteFX.usesSpriteObp() and PaletteFX.pass() == "ui"
      local ramp, group = OBP0_90, "diploma"
      if ogObp then
        local c = PaletteFX.ogObjBase()
        -- engine/events/diploma.asm:65
        ramp = { c[1], c[1], c[2], c[3] }
        group = GameVersion.isBlue() and "diploma_og_blue" or "diploma_og"
      end
      local ok, faded = pcall(SpriteRenderer.obpImage, picPath, ramp, group)
      pic = (ok and faded) or tryImage(picPath)
      ogObp = ogObp and ok and faded ~= nil
    end
  end
  if pic then
    love.graphics.setColor(1, 1, 1, 1)
    -- engine/events/diploma.asm:44
    love.graphics.draw(pic, PIC_X, PIC_Y)
    if picTrueColor then
      PaletteFX.markTrueColor(PIC_X, PIC_Y, pic:getDimensions())
    elseif ogObp then
      PaletteFX.markUiSpriteRedraw(pic, nil, PIC_X, PIC_Y)
    end
  end

  -- 3. Header: hlcoord 5, 2 with flanking circle tiles ($70)
  love.graphics.setColor(1, 1, 1, 1)
  if circle then
    love.graphics.draw(circle, 40, 16)   -- hlcoord 5, 2
    love.graphics.draw(circle, 104, 16)  -- hlcoord 13, 2
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("Diploma"), 48, 16)  -- hlcoord 6, 2

  drawLines(game)
  love.graphics.setColor(1, 1, 1, 1)

  if ogObp then
    local overlay = textOverlay(game)
    if overlay then
      -- engine/events/diploma.asm:44
      PaletteFX.markUiSpriteRedraw(overlay, nil, 0, 0,
        { clip = { PIC_X, PIC_Y, pic:getWidth(), pic:getHeight() } })
    end
  end
end

function Diploma:draw()
  Diploma.render(self.game)
end

return Diploma
