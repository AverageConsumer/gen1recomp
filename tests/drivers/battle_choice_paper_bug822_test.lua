-- Eye check: a YES/NO box over a classic battle wears the same paper as the
-- field behind it (#822).  pokered data/sgb/sgb_packets.asm BlkPacket_Battle
-- attributes all 18 rows, and home/yes_no.asm InitYesNoTextBoxParameters puts
-- the box at hlcoord 14,7 -- inside the player-HP-bar region, pal 0.
--   POKEPORT_DRIVER=tests/drivers/battle_choice_paper_bug822_test.lua POKEPORT_IDENTITY=bug822 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
-- No POKEPORT_SPEED: it scales the logic clock only, and these frames are judged as drawn.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local PaletteFX = require("src.render.PaletteFX")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local Theme = require("src.ui.Theme")

  -- pokered data/maps/objects/Route1.asm puts the two youngsters at (5,24) and
  -- (15,13) and the sign at (9,27), so the top of the road is empty grass; the
  -- battle is pushed rather than walked into, the cell is only somewhere to stand.
  local MAP = "ROUTE_1"
  local STAND = { x = 5, y = 6, facing = "down" }
  local PARTY = { { "BULBASAUR", 12 }, { "PIDGEOTTO", 18 } }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- machine-checkable preconditions ------------------------------------
  local opts = game.save.options or {}
  local sfxVol = opts.sfxVol or 7
  if sfxVol == 0 then
    U.log("FAIL SFX volume is 0, so the box's A/B click is gone and there is no")
    U.log("     way to tell a dead box from a live one you cannot hear. Set SFX to 7.")
  end
  check(("SFX volume %d, so the YES/NO box clicks when you answer it"):format(sfxVol),
        sfxVol > 0)
  check("the shade-remap shader compiled (no shader, no colorization at all)",
        PaletteFX.shader() ~= nil)
  check("PaletteFX.sendShades exists -- the raw sender the #822 fix needs",
        type(PaletteFX.sendShades) == "function")
  check("all 7 COLORS modes are on the ladder ("
        .. table.concat(PaletteFX.MODES, ", ") .. ")", #PaletteFX.MODES == 7)
  local cl = PaletteFX.CLASSIC
  check(("CLASSIC paper is the light pea green %d,%d,%d and its second shade"
         .. " the darker %d,%d,%d -- the pair #822 confused")
          :format(cl[1][1], cl[1][2], cl[1][3], cl[2][1], cl[2][2], cl[2][3]),
        cl[1][1] == 155 and cl[1][2] == 188 and cl[2][1] == 139)
  check("OG's GRAYS start at pure white, so OG is the shader identity",
        PaletteFX.GRAYS[1][1] == 255)
  local box = Theme.choiceBox
  check(("the YES/NO box sits at tile %d,%d (%dx%d) -- InitYesNoTextBoxParameters'"
         .. " hlcoord 14,7"):format(box.tx, box.ty, box.tw, box.th),
        box.tx == 14 and box.ty == 7)

  -- ---- get into a battle with the box up ----------------------------------
  game.save.party = {}
  for _, slot in ipairs(PARTY) do
    table.insert(game.save.party, Pokemon.new(game.data, slot[1], slot[2]))
  end
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(20)
  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit moved the road: any free neighbour will do, nothing here
    -- depends on the cell beyond having somewhere legal to stand
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y), cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(20)
        ow = game.overworld
        break
      end
    end
  end
  check("the overworld is up on " .. MAP, ow ~= nil and ow.map.id == MAP)

  local battle = BattleState.newWild(game, "RATTATA", 5)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  for _ = 1, 120 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  check("the battle reached its FIGHT/PKMN/ITEM/RUN menu", battle.phase == "menu")

  -- The same bare box BattleState pushes for the switch offer (BattleState.lua
  -- :1291): no anchor, so it sits over the battle rather than riding a dialogue
  -- box.  Pushed directly because the reporter's screen is the box on top of a
  -- live battle, and how it got there changes nothing about the colorization.
  local choice = ChoiceBox.new(game, function() end)
  game.stack:push(choice)
  U.wait(10)
  check("a YES/NO box is on top of the battle", game.stack:top() == choice)

  -- ---- measure both papers, mode by mode ----------------------------------
  -- Replays what Game:draw does for a classic battle with an overlay above it:
  -- every state paints onto the one 160x144 UI canvas, then the topmost state
  -- with sgbPalettes owns the screen.  BattleState:sgbPalettes returns nil for
  -- the classic layout, so PaletteFX.ensureZones decides whether a whole-screen
  -- shade pass runs at all -- it does in OG / OG INV / CLASSIC, and does not in
  -- the colorized modes.  Offscreen so the sample boxes stay in clean 160x144
  -- space whatever the window is doing; the U.shot next to each reading is the
  -- same frame as presented.
  local g = love.graphics
  local shader = PaletteFX.shader()

  -- The empty pocket the SGB attribute map leaves at tiles 9,4 - 10,6: below
  -- the enemy HP bar (rows 0-3), right of the player mon (cols 0-8), left of
  -- the enemy mon (col 11 on).  Nothing is ever drawn here, so it is the field
  -- paper and nothing else.
  local FIELD = { 74, 36, 85, 52 }
  -- Inside the YES/NO box, clear of its border tiles.  The glyphs and cursor
  -- live in here too, which is why the reading is the most common color rather
  -- than one pixel.
  local BOXI = { 120, 64, 151, 87 }

  local function modal(id, r)
    local counts, best, bestN = {}, nil, -1
    for y = r[2], r[4] do
      for x = r[1], r[3] do
        local pr, pg, pb = id:getPixel(x, y)
        local key = math.floor(pr * 255 + 0.5) .. "," .. math.floor(pg * 255 + 0.5)
                    .. "," .. math.floor(pb * 255 + 0.5)
        counts[key] = (counts[key] or 0) + 1
        if counts[key] > bestN then best, bestN = key, counts[key] end
      end
    end
    return best
  end

  local function sample()
    local prev = g.getCanvas()
    local a = g.newCanvas(160, 144)
    local b = g.newCanvas(160, 144)
    g.setCanvas(a)
    g.clear(1, 1, 1, 1) -- the battle letterbox is white (letterboxWhite)
    g.setColor(1, 1, 1, 1)
    battle:draw()
    choice:draw()
    g.setCanvas(b)
    g.clear(0, 0, 0, 1)
    local zones = PaletteFX.ensureZones(nil)
    if zones and zones[1] then
      g.setShader(shader)
      PaletteFX.sendColors(shader, PaletteFX.GRAYS)
    end
    g.setColor(1, 1, 1, 1)
    g.draw(a, 0, 0)
    g.setShader()
    g.setCanvas(prev)
    local id = b:newImageData()
    return modal(id, FIELD), modal(id, BOXI), zones ~= nil and zones[1] ~= nil
  end

  local mismatched = {}
  for _, m in ipairs(PaletteFX.MODES) do
    -- set the SAVED option too: Game:applyOptions re-reads save.options.colors,
    -- so a bare setMode gets reverted underneath the next frame
    game.save.options = game.save.options or {}
    game.save.options.colors = m
    PaletteFX.setMode(m)
    U.wait(20)
    local field, boxp, framePass = sample()
    local label = PaletteFX.modeLabel(m)
    local same = field == boxp
    local known = (m == "gbc" or m == "gbc_inv")
    U.log(("%-9s field %-13s box %-13s %s"):format(
            label, field, boxp,
            framePass and "whole-screen pass" or "no whole-screen pass"))
    if m == "classic" then
      check("CLASSIC field is the light pea green 155,188,15, not the darker"
            .. " 139,172,15 one bucket down", field == "155,188,15")
    end
    if known then
      -- the other half of #822, left open on purpose: with no frame-level pass
      -- the overlay paints raw DMG white onto a canvas the battle has already
      -- colorized, and nothing local to drawZonePass can reach it
      U.log(("  %s draws its overlays raw, so a mismatch here is the known"
             .. " open half, not this fix failing"):format(label))
    else
      if not same then mismatched[#mismatched + 1] = label end
      check(label .. " box paper matches the field behind it", same)
    end
    U.shot(game, DIR .. "/bug822_" .. m .. ".png")
  end
  check("no forced-mono or ADVANCED/OG RED mode left the box a different color"
        .. " from the field", #mismatched == 0)
  if #mismatched > 0 then
    U.log("  mismatched on:", table.concat(mismatched, ", "))
  end

  -- ---- over to you --------------------------------------------------------
  PaletteFX.setMode("classic")
  game.save.options.colors = "classic"
  U.wait(20)
  U.log("You are looking at a YES/NO box sitting on a wild RATTATA battle in")
  U.log("CLASSIC. The paper inside the box and the empty field around the mons")
  U.log("should be the one same pea green, with no seam where the box begins;")
  U.log("press 2 through the ladder and OG INV should go black-on-black the same")
  U.log("way, while OG, OG RED and ADVANCED look exactly as they always did.")
  U.log("The near miss is a box that is only slightly lighter than the field --")
  U.log("that is the old one-bucket slip, not a border. SGB and SGB INV still")
  U.log("show a white box over a tinted field; that half of #822 is open.")
  U.log("Shots: " .. DIR .. "/bug822_*.png. A or B answers the box and it goes.")

  while true do
    coroutine.yield()
  end
end
