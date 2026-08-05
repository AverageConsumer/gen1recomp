-- Driver: Fighting Dojo prize balls, #853 (dex page first) and #854 (the
-- question stays on screen under YES/NO).  pokered scripts/FightingDojo.asm
-- runs `ld a, HITMONLEE / call DisplayPokedex` before .Text, and .Text is a
-- text_end string printed with PrintText immediately followed by YesNoChoice.
-- No POKEPORT_SPEED here: the dex page and the YES/NO pop are what is judged.
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/dojo_balls_bug853_test.lua POKEPORT_IDENTITY=bug853 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local DexEntryMenu = require("src.ui.DexEntryMenu")
  local MapScripts = require("src.script.MapScripts")
  local Screens = require("src.ui.Screens")
  local OW = require("src.world.OverworldController")
  local Pokemon = require("src.pokemon.Pokemon")

  -- pokered data/maps/objects/FightingDojo.asm: the two SPRITE_POKE_BALL
  -- objects sit at (4, 1) HITMONLEE and (5, 1) HITMONCHAN, on the north wall
  -- under the posters.  The only approach is from the mat below them.
  local MAP = "FIGHTING_DOJO"
  local LEE = { name = "FIGHTINGDOJO_HITMONLEE_POKE_BALL", x = 4, y = 1 }
  local CHAN = { name = "FIGHTINGDOJO_HITMONCHAN_POKE_BALL", x = 5, y = 1 }
  local START = { x = 4, y = 4 } -- walk up from here to (4, 2), facing LEE

  local failures = {}
  local function check(cond, msg)
    if cond then U.log("PASS", msg) else
      failures[#failures + 1] = msg
      U.log("FAIL", msg)
    end
    return cond
  end

  local function topIs(mt) return getmetatable(game.stack:top()) == mt end
  local function under()
    return game.stack.states[#game.stack.states - 1]
  end

  local function npcByName(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
  end

  local function pageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local page = top.pages and top.pages[top.pageIndex]
    return page and table.concat(page, "\n") or ""
  end

  local function waitFor(cond, cap)
    for _ = 1, (cap or 200) do
      if cond() then return true end
      U.wait(2)
    end
    return cond()
  end

  local function mashUntil(cond, cap)
    for _ = 1, (cap or 100) do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(2)
    end
    return cond()
  end

  -- fresh dojo with the master already beaten and neither prize taken
  local function seed(x, y, facing)
    while game.stack:top() do game.stack:pop() end
    game.save.flags = {
      EVENT_BEAT_KARATE_MASTER = true,
      EVENT_BEAT_FIGHTING_DOJO_TRAINER_0 = true,
      EVENT_BEAT_FIGHTING_DOJO_TRAINER_1 = true,
      EVENT_BEAT_FIGHTING_DOJO_TRAINER_2 = true,
      EVENT_BEAT_FIGHTING_DOJO_TRAINER_3 = true,
    }
    game.save.defeatedTrainers = { FIGHTING_DOJO_obj_1 = true }
    game.save.objectToggles = {}
    game.save.player.name = game.save.player.name or "RED"
    -- one mon so give_pokemon has a party to append to, and room for a prize
    game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
    game.stack:push(OW, MAP, x, y, facing or "up")
    U.wait(10)
    return game.stack:top()
  end

  local ow = seed(START.x, START.y, "up")

  ------------------------------------------------------------------
  -- machine-checkable half: seed, objects, script rows, text, screen id
  ------------------------------------------------------------------
  check(game.save.flags.EVENT_BEAT_KARATE_MASTER == true,
        "EVENT_BEAT_KARATE_MASTER is set (the balls answer at all)")
  check(not game.save.flags.EVENT_GOT_HITMONLEE
        and not game.save.flags.EVENT_GOT_HITMONCHAN,
        "neither prize taken yet (no 'greedy' refusal path)")

  local leeBall, chanBall = npcByName(ow, LEE.name), npcByName(ow, CHAN.name)
  check(leeBall ~= nil, "HITMONLEE ball object loaded")
  check(chanBall ~= nil, "HITMONCHAN ball object loaded")
  check(leeBall and leeBall.cellX == LEE.x and leeBall.cellY == LEE.y,
        ("HITMONLEE ball sits at the asm cell (%d, %d)"):format(LEE.x, LEE.y))
  check(chanBall and chanBall.cellX == CHAN.x and chanBall.cellY == CHAN.y,
        ("HITMONCHAN ball sits at the asm cell (%d, %d)"):format(CHAN.x, CHAN.y))

  check(type(MapScripts.talkScript(MAP, "TEXT_FIGHTINGDOJO_HITMONLEE_POKE_BALL"))
          == "function",
        "TEXT_FIGHTINGDOJO_HITMONLEE_POKE_BALL has a hand-ported talk script")
  check(type(MapScripts.talkScript(MAP, "TEXT_FIGHTINGDOJO_HITMONCHAN_POKE_BALL"))
          == "function",
        "TEXT_FIGHTINGDOJO_HITMONCHAN_POKE_BALL has a hand-ported talk script")

  -- the ask() string is the extracted descriptor, not the "You want X?" stub
  local leeText = game.data.text._FightingDojoHitmonleePokeBallText
  local chanText = game.data.text._FightingDojoHitmonchanPokeBallText
  check(type(leeText) == "string" and leeText ~= "",
        "_FightingDojoHitmonleePokeBallText resolves")
  check(type(chanText) == "string" and chanText ~= "",
        "_FightingDojoHitmonchanPokeBallText resolves")
  if type(leeText) == "string" then
    U.log("lee prompt reads:", (leeText:gsub("\n", " / ")))
  end
  local dexOk = pcall(Screens.get, game, "DexEntryMenu")
  check(dexOk, "DexEntryMenu resolves through the Screens registry")

  ------------------------------------------------------------------
  -- rehearsal on the HITMONCHAN ball, answered NO so nothing is consumed
  ------------------------------------------------------------------
  if chanBall then
    ow:talkTo(chanBall)
    check(waitFor(function() return topIs(DexEntryMenu) end, 60),
          "#853: the ball opens the HITMONCHAN dex page before any question")
    U.shot(game, DIR .. "/dojo_balls_1_dex.png")
    U.tap(game, "b")
    check(waitFor(function() return topIs(TextBox) end, 60),
          "#853: closing the dex page leads into the offer text")
    mashUntil(function() return topIs(ChoiceBox) end, 60)
    check(topIs(ChoiceBox), "#854: the YES/NO menu opens on the offer")
    check(getmetatable(under()) == TextBox,
          "#854: the question box is still on the stack under the YES/NO menu")
    U.shot(game, DIR .. "/dojo_balls_2_choice.png")
    U.tap(game, "b") -- B answers NO; the prize stays unclaimed
    waitFor(function() return game.stack:top() == ow end, 120)
    check(not game.save.flags.EVENT_GOT_HITMONCHAN,
          "answering NO leaves the HITMONCHAN prize unclaimed")
    check(#game.save.party == 1, "answering NO adds nothing to the party")
  end

  ------------------------------------------------------------------
  -- hand-off: walk to the HITMONLEE ball and open it for real
  ------------------------------------------------------------------
  ow = seed(START.x, START.y, "up")
  for _ = 1, 12 do
    if ow.player.cellY <= LEE.y + 1 then break end
    U.hold(game, "up", 16)
    U.wait(4)
  end

  local function facingTheBall()
    local cur = game.overworld
    local ball = cur and npcByName(cur, LEE.name)
    if not ball then return false end
    local fx, fy = cur.player:facingCell()
    return cur:npcAtCell(fx, fy) == ball
  end

  if not facingTheBall() then
    -- a map edit or a mod moved the ball: stand on any free walkable
    -- neighbour instead.  {dx, dy, facing} is the offset from the ball to
    -- the stand cell plus the direction that looks back at it.
    local sides = {
      { 0, 1, "up" }, { 1, 0, "left" }, { -1, 0, "right" }, { 0, -1, "down" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = LEE.x + s[1], LEE.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("walk up stopped short; standing on", cx, cy, "facing", s[3])
        ow = seed(cx, cy, s[3])
        break
      end
    end
  end
  check(facingTheBall(), "player is standing against the HITMONLEE ball")

  U.tap(game, "a")
  check(waitFor(function() return topIs(DexEntryMenu) end, 60),
        "#853: pressing A opens the HITMONLEE dex page")
  U.shot(game, DIR .. "/dojo_balls_3_handoff.png")

  if #failures == 0 then
    U.log("all checks passed")
  else
    U.log(("%d check(s) failed:"):format(#failures), table.concat(failures, "; "))
  end

  U.log("On screen now: the HITMONLEE dex page the ball opened, name and")
  U.log("sprite only, since the mon is seen but not owned yet.  Press B: the")
  U.log("offer types out, and the YES/NO menu should appear above it with the")
  U.log("question still readable -- the old bug swapped the text away for a")
  U.log("bare YES/NO over the overworld.  Answer YES to take HITMONLEE; the")
  U.log("HITMONCHAN ball beside it stays put and gives the greedy refusal.")

  while true do
    coroutine.yield()
  end
end
