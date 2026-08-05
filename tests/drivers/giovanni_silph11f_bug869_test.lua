-- Giovanni's Silph Co 11F coordinate trigger speaks BEFORE he walks (#869).
-- pokered scripts/SilphCo11F.asm SilphCo11FDefaultScript: DisplayTextID
-- TEXT_SILPHCO11F_GIOVANNI first, then MoveSprite .GiovanniMovement (3x down)
-- and EngageMapTrainer with no second box.  Do not set POKEPORT_SPEED: the
-- box-vs-walk ordering is exactly the moment under test.
--   POKEPORT_DRIVER=tests/drivers/giovanni_silph11f_bug869_test.lua POKEPORT_IDENTITY=bug869 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local BattleTransition = require("src.render.BattleTransition")
  local BattleState = require("src.battle.BattleState")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- Positions from ../pokered/data/maps/objects/SilphCo11F.asm: Giovanni
  -- object_event (6, 9), SILPHCO11F_ROCKET1 (3, 16).  Trigger tiles from
  -- ../pokered/scripts/SilphCo11F.asm .PlayerCoordsArray: (6, 13) and
  -- (7, 12).  data/generated/maps.lua stores the same cells 1:1.
  local MAP = "SILPH_CO_11F"
  local GIO_HOME = { x = 6, y = 9 }
  local GIO_STOP = { x = 6, y = 12 }   -- home + 3x NPC_MOVEMENT_DOWN

  local failed = 0
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = failed + 1 end
    return ok
  end

  -- party strong enough that the human can win the OPP_GIOVANNI#2 fight
  -- and watch the unchanged aftermath (victories.lua "Arrgh!!", then the
  -- "Blast it all!" speech and the rockets leaving)
  game.save.party = {
    Pokemon.new(game.data, "MEWTWO", 80),
    Pokemon.new(game.data, "SNORLAX", 77),
    Pokemon.new(game.data, "CHARIZARD", 70),
  }
  game.save.player.name = "RED"

  -- (6,13) and (7,13) sit in the card-key doorway of the boss room: block
  -- (3,6) stays the closed id 32 until EVENT_SILPH_CO_11_UNLOCKED_DOOR is
  -- set (stampClosedDoors, mirroring pokered engine/events/card_key.asm),
  -- and a closed door refuses the step this test needs.  A real player has
  -- opened it before the trigger can fire, so open it here too.
  game.save.flags.EVENT_SILPH_CO_11_UNLOCKED_DOOR = true

  check("EVENT_BEAT_SILPH_CO_GIOVANNI starts unset -- trigger is armed",
        not game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI)
  local opts = game.save.options or {}
  if (opts.sfxVol or 0) == 0 then
    U.log("sfxVol is 0 -- the evil-trainer sting will be inaudible")
  end
  if (opts.musicVol or 0) == 0 then
    U.log("musicVol is 0 -- the encounter sting and battle theme are muted")
  end

  local function findNpc(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  local function topBox()
    local t = game.stack:top()
    if getmetatable(t) == TextBox then return t end
    return nil
  end

  local function boxText(box)
    local shown = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do shown[#shown + 1] = line end
    end
    return table.concat(shown, " / ")
  end

  -- Stand next to (tx, ty) and take one real walking step onto it; onStep
  -- hooks fire on a finished step, so a bare teleport onto the tile would
  -- prove nothing.  `sides` are {dx, dy, facing} in preference order, each
  -- checked for walkability so a map edit only degrades to the next side.
  local function stepOnto(tx, ty, sides)
    U.teleport(game, MAP, tx + sides[1][1], ty + sides[1][2], sides[1][3])
    U.wait(10)
    local ow = game.overworld
    for _, s in ipairs(sides) do
      local cx, cy = tx + s[1], ty + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        if ow.player.cellX ~= cx or ow.player.cellY ~= cy then
          U.teleport(game, MAP, cx, cy, s[3])
          U.wait(10)
        end
        U.hold(game, s[3], 24)
        U.wait(10)
        return true
      end
    end
    return false
  end

  -- Regression on the shared engageTrainer path first: an ordinary trainer
  -- with no skipBattleText must still get its normal pre-battle box.
  -- ROCKET1 faces up, so talk to him from above.
  check("regression: reached ROCKET1's cell",
        stepOnto(3, 15, { { 0, 1, "up" }, { 0, -1, "down" },
                          { 1, 0, "left" }, { -1, 0, "right" } }))
  do
    local ow = game.overworld
    local rocket = findNpc(ow, "SILPHCO11F_ROCKET1")
    check("regression: ROCKET1 object loaded", rocket ~= nil)
    if rocket then
      -- walk down one so we face him from (3, 15)
      local fx, fy = ow.player:facingCell()
      if ow:npcAtCell(fx, fy) ~= rocket then
        -- stepOnto left us adjacent to (3, 15); face the rocket directly
        local dx = rocket.cellX - ow.player.cellX
        local dy = rocket.cellY - ow.player.cellY
        local face = (dy > 0 and "down") or (dy < 0 and "up")
                     or (dx > 0 and "right") or "left"
        U.tap(game, face)
        U.wait(10)
      end
      U.tap(game, "a")
      U.wait(30)
      local box = topBox()
      check("regression: talking to ROCKET1 still opens the pre-battle box",
            box ~= nil)
      if box then
        local t = boxText(box)
        U.log("rocket box reads:", t)
        check("regression: it is his battle line (\"Stop right there!\")",
              t:find("Stop right there", 1, true) ~= nil)
      end
    end
  end

  -- Both trigger tiles must fire with Giovanni still at his desk.  The
  -- (7, 12) probe is abandoned before the box is dismissed (the teleport
  -- rebuilds the map state), so the trigger re-arms for the main run --
  -- vanilla re-arms too, since only a win sets the event flag.
  do
    check("(7,12) approach: stepped onto the trigger from the right",
          stepOnto(7, 12, { { 1, 0, "left" }, { 0, 1, "up" },
                            { -1, 0, "right" } }))
    local box = topBox()
    check("(7,12) approach: intro box opened", box ~= nil)
    local gio = findNpc(game.overworld, "SILPHCO11F_GIOVANNI")
    check("(7,12) approach: Giovanni is still at his desk (6,9)",
          gio ~= nil and gio.cellX == GIO_HOME.x and gio.cellY == GIO_HOME.y)
  end

  -- Main run, the route the issue screenshots show: (6,15) facing up, two
  -- steps onto (6,13).
  U.teleport(game, MAP, 6, 15, "up")
  U.wait(10)
  U.hold(game, "up", 24)
  U.hold(game, "up", 24)
  U.wait(15)
  if not topBox() then
    -- blocked approach fallback: one step onto (6,13) from any free side
    stepOnto(6, 13, { { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" } })
  end

  local ow = game.overworld
  local gio = findNpc(ow, "SILPHCO11F_GIOVANNI")
  check("Giovanni object loaded on " .. MAP, gio ~= nil)
  local box = topBox()
  check("stepping onto (6,13) opened a text box", box ~= nil)
  if box then
    local t = boxText(box)
    U.log("intro box reads:", t)
    check("it is the Giovanni intro (\"So we meet again!\")",
          t:find("So we meet again", 1, true) ~= nil)
  end
  check("the box opened with Giovanni STILL at his desk (6,9) -- the fix",
        gio ~= nil and gio.cellX == GIO_HOME.x and gio.cellY == GIO_HOME.y)
  U.shot(game, SHOT_DIR .. "/bug869_box_before_walk.png")
  U.wait(30)
  check("he holds the desk for the whole box, not just its first frame",
        gio ~= nil and gio.cellX == GIO_HOME.x and gio.cellY == GIO_HOME.y)

  -- dismiss every page; the walk and the battle must follow with NO
  -- further dialogue box in between (EngageMapTrainer runs bare in the
  -- original, so engageTrainer is called with skipBattleText here)
  for _ = 1, 300 do
    if not topBox() then break end
    U.tap(game, "a")
    U.wait(5)
  end
  check("intro box dismissed", topBox() == nil)
  local sawSecondBox, battleReached = false, false
  for _ = 1, 900 do
    local t = game.stack:top()
    local mt = getmetatable(t)
    if mt == TextBox and not sawSecondBox then
      sawSecondBox = true
      U.log("unexpected box reads:", boxText(t))
    end
    if mt == BattleTransition or mt == BattleState then
      battleReached = true
      break
    end
    U.wait(1)
  end
  check("battle wipe started after the box", battleReached)
  check("no second dialogue box between the walk and the battle", not sawSecondBox)
  check("Giovanni walked the three tiles down to (6,12) first",
        gio ~= nil and gio.cellX == GIO_STOP.x and gio.cellY == GIO_STOP.y)

  U.log(failed == 0 and "PASS all machine checks clean"
                     or ("FAIL " .. failed .. " machine check(s) above"))

  U.log("The battle wipe is running now; take the pad and win the fight.")
  U.log("Right looks like what just played: his speech opened while he was")
  U.log("behind the desk, then he walked down and the fight began straight")
  U.log("away, with the evil-trainer sting and no extra dialogue. After the")
  U.log("win you should get \"Arrgh!!\" on the battle screen, the \"Blast it")
  U.log("all!\" speech, a fade, and every rocket gone. Wrong is the old bug:")
  U.log("he crosses the room in silence and only then talks, point-blank.")

  while true do
    coroutine.yield()
  end
end
