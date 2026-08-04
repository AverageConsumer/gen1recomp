-- Eye check: BATTLE BG = WORLD dims the surround only, never the battle's own
-- 160x144 field (#777, dup #772).  Renderer:endFrame used to fill the WHOLE
-- window with the 55% veil; the classic battle hid that under its opaque paper
-- field, but a pipeline that stages the fight on the map and keys the field
-- out (the Dramatic Shape Voxel Mod) got the veil straight onto its sprites
-- and HP boxes.  On hardware there is nothing behind the battle to dim at all:
-- _InitBattleCommon calls ClearScreen (pokered home/copy2.asm) over the whole
-- tilemap before the battle draws.
--   POKEPORT_DRIVER=tests/drivers/battle_bg_world_dim_bug777_test.lua POKEPORT_IDENTITY=bug777 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
-- POKEPORT_TOUCH=0 matters: the on-screen controls draw after endFrame and
-- would land in the void samples.  No POKEPORT_SPEED around the shots.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Game = require("src.core.Game")
  local Renderer = require("src.render.Renderer")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  -- pokered data/maps/objects/Route1.asm puts both youngsters at (5,24) and
  -- (15,13) and the sign at (9,27), so the top of the road is empty; the
  -- battle is pushed straight in, the cell is only somewhere to stand.
  local MAP = "ROUTE_1"
  local STAND = { x = 5, y = 6, facing = "down" }
  local PARTY = { { "BULBASAUR", 12 }, { "PIDGEOTTO", 18 } }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Load a captured PNG back as ImageData.  love.image cannot read absolute
  -- paths, so go through io.open + newFileData.
  local function loadShot(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local ok, img = pcall(function()
      return love.image.newImageData(
        love.filesystem.newFileData(bytes, "shot.png"))
    end)
    return ok and img or nil
  end

  -- Mean brightness of a pixel rect.  Whole-region averages, so NPC steps and
  -- flower/water animation between two shots wash out instead of flipping a
  -- single-pixel compare.
  local function regionMean(img, x, y, w, h)
    local sum, n = 0, 0
    local x2 = math.min(x + w, img:getWidth()) - 1
    local y2 = math.min(y + h, img:getHeight()) - 1
    for yy = math.max(y, 0), y2 do
      for xx = math.max(x, 0), x2 do
        local r, g, b = img:getPixel(xx, yy)
        sum = sum + (r + g + b) / 3
        n = n + 1
      end
    end
    return n > 0 and sum / n or 0, n
  end

  -- The UI letterbox in framebuffer pixels, the same math endFrame uses for
  -- uox/uoy/uvpw/uvph (screenshots are framebuffer-sized, so no dpi divide).
  local function uiBox(img)
    local pw, ph = img:getWidth(), img:getHeight()
    local uiw, uih = Renderer:uiSize()
    local Up = Renderer:uiScale()
    local bw, bh = math.floor(uiw * Up + 0.5), math.floor(uih * Up + 0.5)
    local bx = math.floor((pw - bw) / 2)
    local by = math.floor((ph - bh) / 2)
    return bx, by, bw, bh, pw, ph
  end

  game.save.options = game.save.options or {}
  game.save.options.battleFit = nil -- classic letterbox, the geometry under test

  game.save.party = {}
  for _, slot in ipairs(PARTY) do
    table.insert(game.save.party, Pokemon.new(game.data, slot[1], slot[2]))
  end
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(30)
  local ow = game.overworld
  check("the overworld is up on " .. MAP, ow ~= nil and ow.map.id == MAP)

  -- ---- machine half: veil geometry, no battle needed -----------------------
  -- In the overworld the UI canvas is transparent over the map, so the veil
  -- is not hidden by an opaque field the way the classic battle hides it.
  -- Arm the dim through the real per-frame wiring (Game:draw reads
  -- Game.worldBgBattleDim every frame) and compare against an unarmed shot:
  -- the surround must darken, the letterbox interior must not.
  local baseShot = DIR .. "/bug777_0_overworld.png"
  local veilShot = DIR .. "/bug777_0_overworld_veiled.png"
  U.shot(game, baseShot)
  local realDim = Game.worldBgBattleDim
  Game.worldBgBattleDim = function() return BattleState.BG_WORLD_DIM end
  U.wait(2)
  U.shot(game, veilShot)
  Game.worldBgBattleDim = realDim
  U.wait(2)

  local base, veil = loadShot(baseShot), loadShot(veilShot)
  if check("both overworld shots decoded", base ~= nil and veil ~= nil) then
    local bx, by, bw, bh, pw = uiBox(base)
    local inBase = regionMean(base, bx, by, bw, bh)
    local inVeil = regionMean(veil, bx, by, bw, bh)
    U.log(("  letterbox %dx%d at (%d, %d), interior mean %.3f -> %.3f")
          :format(bw, bh, bx, by, inBase, inVeil))
    -- 0.75 sits between "unchanged" and the 0.55 veil's 0.45x; whole-box
    -- means make a frame of tile animation worth far less than that gap.
    check("the veil leaves the battle box alone (#777)",
          inVeil >= inBase * 0.75)
    if bx >= 8 then
      local outBase = regionMean(base, 0, 0, bx, base:getHeight())
      local outVeil = regionMean(veil, 0, 0, bx, veil:getHeight())
      U.log(("  left void strip mean %.3f -> %.3f"):format(outBase, outVeil))
      check("the veil still dims the surround", outVeil <= outBase * 0.75)
    else
      U.log("  window has no side voids at this scale, surround check skipped")
    end
  end

  -- ---- the real battle, all three BATTLE BG modes --------------------------
  local battle = BattleState.newWild(game, "RATTATA", 5)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the battle reached the screen", game.stack:top() == battle)
  for _ = 1, 120 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  check("the battle reached its FIGHT/PKMN/ITEM/RUN menu",
        battle.phase == "menu")

  -- bgMode reads save.options.battleBg per frame, so one battle covers all
  -- three modes; the menu is idle between shots.
  local shots = {}
  for _, mode in ipairs({ "white", "black", "world" }) do
    game.save.options.battleBg = mode
    U.wait(5)
    local path = DIR .. "/bug777_" .. mode .. ".png"
    U.shot(game, path)
    shots[mode] = loadShot(path)
  end

  if check("all three battle shots decoded",
           shots.white ~= nil and shots.black ~= nil and shots.world ~= nil) then
    local bx, by, bw, bh = uiBox(shots.white)
    local inWhite = regionMean(shots.white, bx, by, bw, bh)
    local inWorld = regionMean(shots.world, bx, by, bw, bh)
    U.log(("  battle box mean, WHITE %.3f vs WORLD %.3f"):format(inWhite, inWorld))
    check("WORLD leaves the battle's own screen at WHITE's brightness",
          math.abs(inWhite - inWorld) < 0.02)
    if bx >= 8 then
      local outWhite = regionMean(shots.white, 0, 0, bx, shots.white:getHeight())
      local outWorld = regionMean(shots.world, 0, 0, bx, shots.world:getHeight())
      U.log(("  void strip mean, WHITE %.3f vs WORLD %.3f"):format(outWhite, outWorld))
      check("WORLD's surround is the dimmed map, not paper",
            outWorld < outWhite - 0.05)
    end
  end

  -- ---- over to you ---------------------------------------------------------
  U.log("You are at the battle menu with BATTLE BG = WORLD: the frozen Route 1")
  U.log("map sits around the battle at 55% brightness. Put bug777_white.png and")
  U.log("bug777_world.png side by side: inside the battle box they must match")
  U.log("exactly, same paper, same pics, same HP bars; only the frame around it")
  U.log("changes. #777 dimmed the whole window instead, which with a mod that")
  U.log("stages the fight on the map dropped the veil straight over the sprites")
  U.log("and health boxes. The near miss to look for is the opposite failure:")
  U.log("a surround that is NOT dimmed at all, which means the veil got lost")
  U.log("rather than scoped.")
  U.log("Shots: " .. DIR .. "/bug777_*.png")

  while true do
    coroutine.yield()
  end
end
