-- Eye check: FAITHFUL RATIO's mobile scale lock keeps the display outside the
-- locked 160x144 viewport black through the pre-battle flash (pokered
-- BattleTransition_FlashScreen_, engine/battle/battle_transitions.asm), the
-- post-battle fade (GBFadeInFromWhite, home/fade.asm) and Oak speech (#864).
--   POKEPORT_DRIVER=tests/drivers/faithful_res_mobile_veil_bug864_test.lua POKEPORT_FORCE_MOBILE=1 POKEPORT_IDENTITY=bug864 POKEPORT_TOUCH=0 POKEPORT_VERSION=red SHOT_DIR=/tmp/shots love .
-- No POKEPORT_SPEED anywhere: the flash and the fade ARE the frames under test.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Renderer = require("src.render.Renderer")
  local FaithfulRes = require("src.core.FaithfulRes")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- FaithfulRes.isMobile reads the env per call, so the desktop build only
  -- takes the scale-cap branch when the launcher command set it.  Without it
  -- every check below tests the ordinary letterbox and proves nothing.
  if not check("POKEPORT_FORCE_MOBILE=1 is set (the branch under test)",
               os.getenv("POKEPORT_FORCE_MOBILE") == "1") then
    U.log("Re-run with POKEPORT_FORCE_MOBILE=1; nothing below is meaningful.")
    while true do coroutine.yield() end
  end

  -- A phone-shaped window, so the locked viewport (160x144 at the largest
  -- whole multiple, here 3x = 480x432) leaves tall bars above and below --
  -- the "dead display" FaithfulRes.lua's contract says must stay black.
  -- 480x960 keeps the width an exact 3x so the bars are purely vertical.
  if love.window and love.window.setMode then
    love.window.setMode(480, 960, { resizable = true,
                                    minwidth = FaithfulRes.MIN_W,
                                    minheight = FaithfulRes.MIN_H })
  end
  U.wait(3)

  -- New Game replaces game.save (and Game:applyOptions re-applies its fresh
  -- options, which releases the lock), so re-arm before every shot rather
  -- than trusting one application to survive the whole run.
  local function lock()
    game.save.options = game.save.options or {}
    game.save.options.faithfulRes = 1
    game.save.options.battleBg = "black"
    FaithfulRes.applyOptions(game.save.options)
    return FaithfulRes.scaleCap()
  end
  check("the mobile scale lock engaged (FaithfulRes.scaleCap ~= nil)",
        lock() ~= nil)

  local opts = game.save.options
  if (opts.musicVol or 0) == 0 or (opts.sfxVol or 0) == 0 then
    U.log("WARN music/sfx volume is zero; the flash's battle theme will be silent")
  end

  -- Load a captured PNG back as ImageData; love.image cannot read absolute
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

  -- The locked viewport in framebuffer pixels: the same uiSize * fitScale
  -- centring endFrame uses for ox/oy/vpw/vph, which is the rectangle the
  -- veil is clamped to under the lock.  Screenshots are framebuffer-sized,
  -- so no dpi divide.
  local function viewBox(img)
    local pw, ph = img:getWidth(), img:getHeight()
    local uiw, uih = Renderer:uiSize()
    local S = Renderer:fitScale()
    local bw, bh = uiw * S, uih * S
    return math.floor((pw - bw) / 2), math.floor((ph - bh) / 2), bw, bh, pw, ph
  end

  -- Mean over every bar strip the window has (top/bottom always here,
  -- left/right only if the width is not an exact multiple).  Inset by 2px so
  -- the viewport's own edge pixels cannot bleed into the bar sample.
  local function barMean(img)
    local bx, by, bw, bh, pw, ph = viewBox(img)
    local sum, n = 0, 0
    local function add(x, y, w, h)
      if w < 1 or h < 1 then return end
      local m, c = regionMean(img, x, y, w, h)
      sum, n = sum + m * c, n + c
    end
    if by >= 8 then
      add(0, 0, pw, by - 2)
      add(0, by + bh + 2, pw, ph - (by + bh) - 2)
    end
    if bx >= 8 then
      add(0, by, bx - 2, bh)
      add(bx + bw + 2, by, bx - 2, bh)
    end
    return n > 0 and sum / n or -1, n
  end

  local function innerMean(img)
    local bx, by, bw, bh = viewBox(img)
    return regionMean(img, bx + math.floor(bw / 4), by + math.floor(bh / 4),
                      math.floor(bw / 2), math.floor(bh / 2))
  end

  -- shot + the two-sided assertion every moment shares: bars dead black,
  -- viewport interior at least `bright` (the effect visibly inside the frame)
  local function shotAndCheck(name, bright)
    check("lock still held at " .. name, lock() ~= nil)
    local path = DIR .. "/bug864_" .. name .. ".png"
    U.shot(game, path)
    local img = loadShot(path)
    if not check(name .. " shot decoded", img ~= nil) then return nil end
    local bars, n = barMean(img)
    local inner = innerMean(img)
    U.log(("  %s: bar mean %.3f over %d px, viewport interior %.3f")
          :format(name, bars, n, inner))
    check(name .. ": window has bars to sample", n > 0)
    check(name .. ": bars stay dead black (#864)", n > 0 and bars < 0.05)
    check(name .. ": the effect still lights the viewport", inner > bright)
    return img
  end

  -- ---- (3rd symptom first: it is where a boot starts) New Game -----------
  -- OakSpeech sets letterboxWhite; before #864 that painted the WHOLE phone
  -- paper white, leaving the locked frame indistinguishable from its bars.
  U.wait(5)
  U.tap(game, "start") -- skip intro movie
  U.wait(10)
  U.tap(game, "a")     -- title -> menu
  U.wait(5)
  U.tap(game, "a")     -- NEW GAME (POKEPORT_IDENTITY=bug864 has no save)
  local oak
  for _ = 1, 300 do
    for i = #game.stack.states, 1, -1 do
      local s = game.stack.states[i]
      if s and s.letterboxWhite then oak = s break end
    end
    if oak then break end
    U.tap(game, "a")
    U.wait(2)
  end
  check("Oak speech reached (a letterboxWhite state is on the stack)",
        oak ~= nil)
  U.wait(40) -- let Oak's pic and a line of text land inside the frame
  shotAndCheck("oakspeech", 0.5)

  -- mash through the rest of the speech into the overworld; the naming
  -- screens and the closing shrink-away beat (~103 unskippable frames) eat
  -- most of this, so the headroom is generous on purpose
  for _ = 1, 900 do
    U.tap(game, "a")
    U.wait(2)
    if game.overworld and game.stack:top() == game.overworld then break end
  end
  check("New Game landed in the overworld",
        game.overworld ~= nil and game.stack:top() == game.overworld)

  -- ---- the pre-battle flash ----------------------------------------------
  -- pokered data/maps/objects/Route1.asm puts its youngsters at (5,24) and
  -- (15,13) and the sign at (9,27), so the top of the road is empty; the
  -- battle is pushed straight in, the cell is only somewhere to stand.
  local MAP = "ROUTE_1"
  local STAND = { x = 5, y = 6, facing = "down" }

  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 12) }
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up on " .. MAP, ow ~= nil and ow.map.id == MAP)
  if ow and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit moved the road: any free neighbour serves, the cell is not
    -- itself under test
    for _, d in ipairs({ {0,1}, {0,-1}, {1,0}, {-1,0} }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("stand cell (%d, %d) blocked, using (%d, %d)")
              :format(STAND.x, STAND.y, cx, cy))
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(10)
        ow = game.overworld
        break
      end
    end
  end

  U.shot(game, DIR .. "/bug864_route1_base.png") -- unlit reference frame
  lock()

  -- wild, weaker (L5 vs the L12 lead), not a dungeon map: the 3-bit select
  -- (battle_transitions.asm) lands on %000 doublecircle, one of the two
  -- wipes that call BattleTransition_FlashScreen first
  local battle = BattleState.newWild(game, "RATTATA", 5)
  ow:pushBattle(battle)
  local trans = game.stack:top()
  check("the transition is a flashing wipe (doublecircle)",
        trans ~= nil and trans.def ~= nil and trans.def.flash == true)

  -- screenVeil is written during draw and cleared at beginFrame, so at
  -- update time it holds the LAST rendered frame's veil; catch the white
  -- peak (shade 1, near-full alpha) and shoot the very next frames while
  -- the 2-frame palette holds keep it bright
  local caught = false
  for _ = 1, 400 do
    local v = game.renderer and game.renderer.screenVeil
    if v and v[1] == 1 and v[2] >= 0.9 then caught = true break end
    U.wait(1)
  end
  check("caught the flash at its white peak", caught)
  local flashImg = shotAndCheck("flash", 0.5)
  local baseImg = loadShot(DIR .. "/bug864_route1_base.png")
  if flashImg and baseImg then
    local lit, plain = innerMean(flashImg), innerMean(baseImg)
    U.log(("  viewport interior %.3f unlit -> %.3f mid-flash")
          :format(plain, lit))
    check("the flash visibly brightens the viewport over the base frame",
          lit > plain + 0.15)
  end

  -- ---- the post-battle fade in from white --------------------------------
  for _ = 1, 600 do
    if game.stack:top() == battle then break end
    U.wait(1)
  end
  check("the battle reached the screen", game.stack:top() == battle)
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  check("the battle reached its FIGHT/PKMN/ITEM/RUN menu",
        battle.phase == "menu")

  -- run away (down+right lands on RUN from anywhere in the 2x2 grid; the
  -- L12 lead outspeeds the L5 wild mon, so the escape always succeeds),
  -- then watch for BattleReturn's white veil -- battle over, shade 1,
  -- alpha 1 through its hold frames
  local sawReturn = false
  for _ = 1, 1500 do
    local top = game.stack:top()
    local v = game.renderer and game.renderer.screenVeil
    if top ~= battle and v and v[1] == 1 and v[2] >= 0.9 then
      sawReturn = true
      break
    end
    if top == battle then
      if battle.phase == "menu" then
        U.tap(game, "down")
        U.wait(1)
        U.tap(game, "right")
        U.wait(1)
        U.tap(game, "a")
        U.wait(2)
      else
        U.tap(game, "a")
        U.wait(3)
      end
    else
      U.wait(1)
    end
  end
  check("caught the post-battle fade in from white", sawReturn)
  shotAndCheck("return", 0.8)

  -- ---- over to you --------------------------------------------------------
  U.log("You are back on Route 1 with the picture locked to a 480x432 frame in")
  U.log("the middle of a tall window. Open the three shots in " .. DIR .. ":")
  U.log("bug864_oakspeech, bug864_flash and bug864_return should each show a lit")
  U.log("frame -- paper, white flash, white fade -- with dead-black bars above")
  U.log("and below. Before #864 the white spilled over the whole window and the")
  U.log("frame had no edge at all. Walking into grass here replays the flash live.")

  while true do
    coroutine.yield()
  end
end
