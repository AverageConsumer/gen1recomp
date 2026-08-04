-- Manual check that the trade cinematic draws real art, not rectangles (#750).
-- The ROM importer never wrote assets/generated/trade/*, so on a player's
-- cache every tryImage in TradeAnim.new returned nil and the whole
-- InternalClockTradeAnim sequence fell back to love.graphics.rectangle:
-- an outlined box for the Game Boy, a flat bar for the cable, a blank
-- screen during the open-cable phase.  The machine half below asserts the
-- ten art files are in the cache at the sizes trade.asm implies and that
-- the running TradeAnim actually loaded them; the shots are for the human
-- half.  A cache imported before this fix re-imports on launch (the
-- REQUIRED_FILES entry), so a FAIL on the file checks means the re-import
-- has not happened yet.
--   SHOT_DIR=/tmp/trade750 POKEPORT_DRIVER=tests/drivers/trade_anim_bug750_test.lua POKEPORT_IDENTITY=bug750 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/trade750"
  local Pokemon = require("src.pokemon.Pokemon")
  local TradeAnim = require("src.ui.TradeAnim")
  local TextBox = require("src.render.TextBox")
  local PartyMenu = require("src.ui.PartyMenu")
  local ChoiceBox = require("src.ui.ChoiceBox")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Expected sizes: GameBoyTiles is a 6x8-tile plate and LinkCableTiles a
  -- 12x3 one (pokered data/tilemaps.asm), Trade_DrawCableAcrossScreen fills
  -- a 20-tile row, the ball and its bulge frame are one tile mirrored into
  -- 2x2 OAM blocks, and TradeBubbleIconGFX is two 16x16 quadrant frames.
  local FILES = {
    { "assets/generated/trade/game_boy.png", 48, 64 },
    { "assets/generated/trade/open_cable.png", 96, 24 },
    { "assets/generated/trade/cable_horiz.png", 160, 8 },
    { "assets/generated/trade/cable_conn.png", 8, 8 },
    { "assets/generated/trade/cable_seg.png", 8, 8 },
    { "assets/generated/trade/cable_corner.png", 8, 8 },
    { "assets/generated/trade/cable_end.png", 8, 8 },
    { "assets/generated/trade/cable_vert.png", 8, 8 },
    { "assets/generated/trade/cable_ball.png", 16, 16 },
    { "assets/generated/trade/cable_ball_alt.png", 16, 16 },
    { "assets/generated/trade/bubble.png", 16, 32 },
  }
  for _, spec in ipairs(FILES) do
    local ok, image = pcall(love.graphics.newImage, spec[1])
    if check(spec[1] .. " is in the cache", ok and image ~= nil) then
      local w, h = image:getDimensions()
      check(("%s is %dx%d"):format(spec[1], spec[2], spec[3]),
            w == spec[2] and h == spec[3])
    end
  end
  check("field.lua carries tradeArt paths",
        game.data.field and game.data.field.tradeArt
        and game.data.field.tradeArt.gameBoy ~= nil)

  local function topIs(cls)
    return getmetatable(game.stack:top()) == cls
  end

  -- pokered data/maps/objects/VermilionTradeHouse.asm: the LITTLE_GIRL
  -- (SPEAROW -> DUX FARFETCH'D) stands at (3, 5) facing up, so (3, 6)
  -- facing up puts the player in front of her.
  game.save.party = { Pokemon.new(game.data, "SPEAROW", 10) }
  U.teleport(game, "VERMILION_TRADE_HOUSE", 3, 6, "up")
  U.wait(5)

  U.tap(game, "a")
  U.wait(10)
  for _ = 1, 200 do
    if topIs(ChoiceBox) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  check("trade offer choice appeared", topIs(ChoiceBox))
  U.tap(game, "a") -- YES
  U.wait(6)
  for _ = 1, 60 do
    if topIs(PartyMenu) then break end
    U.wait(1)
  end
  check("party menu opened", topIs(PartyMenu))
  U.tap(game, "a") -- pick the SPEAROW
  U.wait(6)
  for _ = 1, 200 do
    if topIs(TradeAnim) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  local anim = game.stack:top()
  if not check("TradeAnim is on the stack", getmetatable(anim) == TradeAnim) then
    U.log("cannot reach the cinematic; nothing more to verify")
    while true do coroutine.yield() end
  end

  -- the running state loaded the art rather than falling back
  check("TradeAnim loaded the Game Boy plate", anim.img.gameBoy ~= nil)
  check("TradeAnim loaded the open cable plate", anim.img.openCable ~= nil)
  check("TradeAnim loaded the cable ball", anim.img.cableBall ~= nil)
  check("TradeAnim loaded the bubble ring", anim.img.bubble ~= nil)

  -- step the phases at real speed and shoot the moments the reporter's
  -- video shows broken
  local function ffUntil(phase, cap)
    for _ = 1, cap or 3000 do
      if anim.phase == phase or anim.phase == "done" then break end
      if anim.waitingText or topIs(TextBox) then
        U.wait(1)
      else
        anim:update(1 / 60)
      end
    end
    U.wait(1)
  end

  ffUntil("open_cable", 800)
  while anim.phase == "open_cable" and anim.scx > 0 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/bug750_open_cable.png")

  ffUntil("ball_enter", 200)
  while anim.phase == "ball_enter" and anim.ballX < 0x80 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/bug750_ball_enter.png")

  ffUntil("transfer_lr", 400)
  for _ = 1, 24 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/bug750_transfer_lr.png")

  ffUntil("transfer_rl", 4000)
  for _ = 1, 140 do
    if anim.phase ~= "transfer_rl" then break end
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/bug750_transfer_rl.png")

  U.log("shots in", DIR)
  U.log("open_cable should be the link cable plate with its open end, not a")
  U.log("blank screen; ball_enter a small ball riding the cable; the two")
  U.log("transfer shots a real Game Boy body with the cable plugged in and")
  U.log("the mon's 16x16 party icon inside a round 32x32 ring -- no outlined")
  U.log("rectangles, no flat gray bar, no squashed battle pic.")

  while true do
    coroutine.yield()
  end
end
