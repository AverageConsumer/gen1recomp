-- Manual check of the Rocket Hideout B4F Jessie & James ambush: James walks
-- the full four tiles to the player's side (#865) and their loss line prints
-- on the battle screen before the prize money (#866).
-- pokeyellow scripts/RocketHideoutB4F.asm (MovementData_45605 falls through
-- into _45606) and data/maps/objects/RocketHideoutB4F.asm.  No fast-forward:
--   POKEPORT_DRIVER=tests/drivers/jessie_james_bug866_test.lua POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Commands = require("src.script.Commands")
  local GameVersion = require("src.core.GameVersion")
  local mapScripts = require("data.scripts.init")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local MAP = "ROCKET_HIDEOUT_B4F"
  local BEAT = "EVENT_BEAT_ROCKET_HIDEOUT_4_JESSIE_JAMES"
  local JAMES, JESSIE = "ROCKETHIDEOUTB4F_JAMES", "ROCKETHIDEOUTB4F_JESSIE"
  -- RocketHideoutB4FScript_455a5 fires on wYCoord $e with wXCoord $18 or $19.
  -- x=24 leaves EVENT_ROCKET_HIDEOUT_4_JESSIE_JAMES_ON_LEFT clear, which is
  -- the branch that hands the four-step blob to James (object 2, spawned at
  -- 25,10) and the three-step one to Jessie (object 3, at 24,10).
  local TRIGGER = { x = 24, y = 14 }
  local EXPECT = {
    [JAMES] = { x = 25, y = 14, facing = "left" },
    [JESSIE] = { x = 24, y = 13, facing = "down" },
  }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  check("running the Yellow cache (the duo exists nowhere else)",
        GameVersion.isYellow())
  if not GameVersion.isYellow() then
    U.log("re-run with POKEPORT_VERSION=yellow; nothing below will be true")
  end

  local hooks = mapScripts.get(MAP)
  check("yellow_jessie_james registered an onStep for " .. MAP,
        type(hooks) == "table" and type(hooks.onStep) == "function")
  check("their talk entries are registered too",
        type(hooks) == "table" and type(hooks.talk) == "table"
          and hooks.talk.TEXT_ROCKETHIDEOUTB4F_JAMES ~= nil
          and hooks.talk.TEXT_ROCKETHIDEOUTB4F_JESSIE ~= nil)

  -- the #866 fix is a new script verb; if a mod shadowed it or the registry
  -- never picked it up, the row would silently no-op and the line would come
  -- back after the money instead of before it
  local verb = Commands.resolve(game.data, "save_end_battle_text")
  check("save_end_battle_text resolves as a script verb", type(verb) == "function")

  local texts = {}
  for i = 1, 4 do
    local key = "_RocketHideoutJessieJamesText" .. i
    texts[i] = game.data.text[key]
    check(key .. " resolves to a string",
          type(texts[i]) == "string" and texts[i] ~= "")
  end
  if type(texts[3]) == "string" then
    U.log("the armed loss line reads:", (texts[3]:gsub("\n", " / ")))
  end

  local objs = (game.data.maps[MAP] or {}).objects or {}
  local defs = {}
  for _, o in ipairs(objs) do
    if o.name == JAMES or o.name == JESSIE then defs[o.name] = o end
  end
  check("James is object 2 of " .. MAP .. ", hidden at (25,10)",
        defs[JAMES] ~= nil and defs[JAMES].index == 2
          and defs[JAMES].x == 25 and defs[JAMES].y == 10
          and defs[JAMES].hidden == true)
  check("Jessie is object 3, hidden at (24,10)",
        defs[JESSIE] ~= nil and defs[JESSIE].index == 3
          and defs[JESSIE].x == 24 and defs[JESSIE].y == 10
          and defs[JESSIE].hidden == true)

  local rocket = game.data.trainers.OPP_ROCKET
  check("OPP_ROCKET party 43 (the duo's shared team) exists",
        rocket ~= nil and rocket.parties ~= nil and rocket.parties[43] ~= nil)

  -- arm the site: the ambush is gated only on its beat flag, so no story
  -- progress is needed to make it live
  game.save.flags[BEAT] = nil
  game.save.flags.EVENT_ROCKET_HIDEOUT_4_JESSIE_JAMES_ON_LEFT = nil
  check(BEAT .. " cleared, so the trigger is live",
        game.save.flags[BEAT] == nil)

  -- a real party, because the human has to win the battle for the loss line
  -- to print at all
  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 60),
    Pokemon.new(game.data, "NIDOKING", 58),
    Pokemon.new(game.data, "STARMIE", 58),
  }
  game.save.player.name = "RED"

  -- walk in from the north; the two elevator warps sit on row 15, so the
  -- approach cannot come from below
  U.teleport(game, MAP, TRIGGER.x, TRIGGER.y - 1, "down")
  local ow = game.overworld
  if not ow.map:isWalkableCell(TRIGGER.x, TRIGGER.y - 1) then
    -- a map edit moved the free cell: any walkable neighbour of the trigger
    -- works, the script only reads the tile the player lands on
    local sides = { { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" } }
    for _, s in ipairs(sides) do
      local cx, cy = TRIGGER.x + s[1], TRIGGER.y + s[2]
      if ow.map:isWalkableCell(cx, cy) then
        U.log("standing on", cx, cy, "facing", s[3], "instead")
        U.teleport(game, MAP, cx, cy, s[3])
        ow = game.overworld
        U.hold(game, s[3] == "down" and "down" or (s[3] == "right" and "right" or "left"), 20)
        break
      end
    end
  else
    U.hold(game, "down", 20)
  end
  U.wait(10)
  check("player stepped onto the trigger tile (24,14)",
        ow.player.cellX == TRIGGER.x and ow.player.cellY == TRIGGER.y)
  check("the ambush script is running", ow.runner:isRunning())

  U.log("The cutscene is yours now: press A to read, then fight and win.")
  U.log("Right looks like both Rockets closing in -- Jessie stopping one tile")
  U.log("above you, James coming all the way down to stand at your right -- and")
  U.log("after you win, \"ROCKET: Such a dreadful twerp!\" appearing on the")
  U.log("battle screen just before the money line.  The near-miss to watch for")
  U.log("is James halting three tiles up by the wall, or that line showing up")
  U.log("in the overworld box after the payout with no ROCKET: tag on it.")
  U.log("Two more checks print below as you get to them.")

  local function npcNamed(name)
    for _, n in ipairs(game.overworld and game.overworld.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  local approachDone, battleSeen = false, false
  while true do
    if not approachDone then
      local j, s = npcNamed(JAMES), npcNamed(JESSIE)
      local ow2 = game.overworld
      if j and s and not j.moving and not s.moving and ow2
         and #(ow2.scriptMoves or {}) == 0
         and (j.cellY > 10 or s.cellY > 10) then
        approachDone = true
        check("James walked the full four tiles to (25,14) facing left",
              j.cellX == EXPECT[JAMES].x and j.cellY == EXPECT[JAMES].y
                and j.facing == EXPECT[JAMES].facing)
        check("Jessie stopped three down at (24,13) facing the player",
              s.cellX == EXPECT[JESSIE].x and s.cellY == EXPECT[JESSIE].y
                and s.facing == EXPECT[JESSIE].facing)
        U.log("James at", j.cellX, j.cellY, j.facing,
              "Jessie at", s.cellX, s.cellY, s.facing)
        U.shot(game, SHOT_DIR .. "/jj866_approach.png")
      end
    end
    if not battleSeen then
      local top = game.stack:top()
      if getmetatable(top) == BattleState then
        battleSeen = true
        -- BattleState prints endBattleText between _TrainerDefeatedText and
        -- _MoneyForWinningText, so an armed field IS the ordering fix
        check("the battle carries the loss line as its end-battle text",
              type(top.endBattleText) == "string" and top.endBattleText ~= ""
                and top.endBattleText == texts[3])
        if type(top.endBattleText) == "string" then
          U.log("armed:", (top.endBattleText:gsub("\n", " / ")))
        end
      end
    end
    coroutine.yield()
  end
end
