-- Manual check of the ghost MAROWAK send-off on POKEMON_TOWER_6F (#867).
-- PokemonTower6FMarowakDepartedText (pokered scripts/PokemonTower6F.asm) is
-- two texts: the CUBONE's-mother line, then PlayCry RESTLESS_SOUL + 30 frames
-- before the calmed line; the port showed only the calmed line and no cry.
-- Never under POKEPORT_SPEED -- the cry-then-text beat is the thing under test.
--   POKEPORT_DRIVER=tests/drivers/marowak_departed_bug867_test.lua POKEPORT_IDENTITY=bug867 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local TextBox = require("src.render.TextBox")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- machine checks ----------------------------------------------------
  -- Both keys come out of the stock extractor (data/generated/text.lua); a
  -- rename there would drop story3.lua onto its hand fallbacks, which still
  -- displays but is worth knowing about.
  local mother = game.data.text._PokemonTower6FGhostWasCubonesMotherText
  local calmed = game.data.text._PokemonTower6FSoulWasCalmedText
  check("_PokemonTower6FGhostWasCubonesMotherText extracted",
        type(mother) == "string" and mother ~= "")
  check("_PokemonTower6FSoulWasCalmedText extracted",
        type(calmed) == "string" and calmed ~= "")
  if type(mother) == "string" then
    U.log("first line reads:", (mother:gsub("[\n\011\012]", " / ")))
  end
  if type(calmed) == "string" then
    U.log("second line reads:", (calmed:gsub("[\n\011\012]", " / ")))
  end
  check("MAROWAK is a real species (RESTLESS_SOUL EQU MAROWAK)",
        game.data.pokemon.MAROWAK ~= nil)

  local opts = game.save.options or {}
  U.log("sfxVol", tostring(opts.sfxVol), "musicVol", tostring(opts.musicVol))
  if opts.sfxVol == 0 then
    U.log("sfxVol is 0: raise it in OPTION or the cry cannot be judged")
  end

  -- ---- reach the trigger -------------------------------------------------
  -- pokered scripts/PokemonTower6F.asm PokemonTower6FMarowakCoords:
  -- dbmapcoord 10, 16 (a coord array, not an object).  Row 17 is solid wall
  -- and (9, 16) is the stairwell warp, so the approach is from (10, 15)
  -- facing down, same as tests/drivers/ghost_unveil_bug492_test.lua.
  local MAP = "POKEMON_TOWER_6F"
  local TRIGGER = { x = 10, y = 16 }
  local STAND = { x = 10, y = 15, facing = "down", step = "down" }

  -- one mon, one damaging move: the A-mash below always picks FIGHT slot 1,
  -- and a stat move there stalls the run (route.lua learned this the hard way)
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  if game.data.moves.PSYCHIC_M then
    mon.moves = { { id = "PSYCHIC_M", pp = 99 } }
  end
  game.save.party = { mon }
  game.save.player.name = "RED"
  -- the scope buys the unveil so the ghost can be damaged at all (#492)
  game.save.inventory.SILPH_SCOPE = 1
  game.save.flags.EVENT_BEAT_GHOST_MAROWAK = nil

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up on " .. MAP, ow ~= nil and ow.map ~= nil)

  if ow and ow.map and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit moved the approach: stand on any walkable neighbour of the
    -- trigger that is not the stairwell warp and step back onto it.
    -- {dx, dy, facing} is the trigger-to-stand offset plus the direction
    -- that walks back onto the trigger cell.
    local sides = { { 0, -1, "down" }, { 1, 0, "left" },
                    { -1, 0, "right" }, { 0, 1, "up" } }
    for _, s in ipairs(sides) do
      local cx, cy = TRIGGER.x + s[1], TRIGGER.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow.map:warpAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, approaching from"):format(STAND.x, STAND.y),
              cx, cy, "stepping", s[3])
        STAND = { x = cx, y = cy, facing = s[3], step = s[3] }
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        ow = game.overworld
        break
      end
    end
  end

  -- walk onto the trigger; MapScripts onStep fires on the completed step
  U.hold(game, STAND.step, 20)
  U.wait(20)
  check("the Be-gone text opened", game.stack:top() ~= game.overworld)

  -- ---- win the battle ----------------------------------------------------
  local sawBattle = false
  for _ = 1, 1500 do
    -- onFinish sets the flag and queues the departed rows in the same call,
    -- so break on the flag BEFORE tapping: a stray A here would eat the
    -- CUBONE's-mother box before it is recorded
    if game.save.flags.EVENT_BEAT_GHOST_MAROWAK then break end
    if getmetatable(game.stack:top()) == BattleState then sawBattle = true end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the MAROWAK battle opened", sawBattle)
  check("the battle was won (EVENT_BEAT_GHOST_MAROWAK set)",
        game.save.flags.EVENT_BEAT_GHOST_MAROWAK == true)

  -- ---- record the send-off boxes -----------------------------------------
  -- Each box is sampled the frame it is first seen: the calmed box carries
  -- the armed cry as opts.auto {sound, wait} (src/script/Commands.lua), and
  -- TextBox clears .auto once the cry has played, so a late read looks like
  -- no cry at all.
  local boxes = {}
  local lastBox = nil
  local budget = 1200
  while budget > 0 do
    local top = game.stack:top()
    if getmetatable(top) == TextBox then
      if top ~= lastBox then
        lastBox = top
        local shown = {}
        for _, page in ipairs(top.pages or {}) do
          for _, line in ipairs(page) do shown[#shown + 1] = line end
        end
        boxes[#boxes + 1] = {
          text = table.concat(shown, " / "),
          cry = top.auto ~= nil and top.auto.sound ~= nil,
        }
        U.log(("box %d reads:"):format(#boxes), boxes[#boxes].text)
        -- let the typewriter finish before the shot so the capture shows the
        -- line; the auto sample above already happened on the open frame
        for _ = 1, 240 do
          if top.waiting or top.done or game.stack:top() ~= top then break end
          U.wait(1)
          budget = budget - 1
        end
        U.shot(game, DIR .. ("/bug867_box%d.png"):format(#boxes))
      end
      U.tap(game, "a")
      U.wait(3)
      budget = budget - 4
    else
      if #boxes >= 2 then break end
      U.wait(1)
      budget = budget - 1
    end
  end

  check("the send-off is two boxes, not one (#867)", #boxes == 2)
  check("box 1 is the CUBONE's-mother line",
        boxes[1] ~= nil and boxes[1].text:find("CUBONE", 1, true) ~= nil)
  check("box 1 opens silent (the asm plays no cry before it)",
        boxes[1] ~= nil and not boxes[1].cry)
  check("box 2 is the calmed line",
        boxes[2] ~= nil and boxes[2].text:find("calmed", 1, true) ~= nil)
  check("box 2 opens with the MAROWAK cry armed",
        boxes[2] ~= nil and boxes[2].cry == true)

  -- ---- the trigger is spent ----------------------------------------------
  -- step off and back onto (10, 16): with the flag set, onStep must pass
  local back = ({ down = "up", up = "down", left = "right", right = "left" })
               [STAND.step]
  U.hold(game, back, 20)
  U.wait(10)
  U.hold(game, STAND.step, 20)
  U.wait(20)
  check("re-stepping the trigger cell stays quiet",
        getmetatable(game.stack:top()) ~= TextBox)
  U.shot(game, DIR .. "/bug867_after.png")
  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))

  -- ---- hand off ----------------------------------------------------------
  U.log("The pad is yours on 6F with the ghost already sent off.  What should")
  U.log("have happened: after the win, \"The GHOST was the / restless soul of /")
  U.log("CUBONE's mother!\" first, then the MAROWAK cry sounds as the second box")
  U.log("opens with \"The mother's soul / was calmed.\"  The old bug jumped")
  U.log("straight to the calmed line, no mother line and no cry at all.")
  U.log("Screenshots: " .. DIR .. "/bug867_*.png")

  while true do
    coroutine.yield()
  end
end
