-- Driver: #862 Celadon Game Corner poster grunt, loss line + exit walk.
-- GameCornerRocketText saves _GameCornerRocketBattleEndText ("Dang!") for
-- PrintEndBattleText, and GameCornerRocketBattleScript picks the exit walk
-- from the player's cell (pokered/scripts/GameCorner.asm:54-102): east of
-- him it is WalkAroundPlayer, DOWN/R/R/UP/R/R/R/R, never UP into the poster.
-- No POKEPORT_SPEED: the walk and the battle text are what is under test.
--   SHOT_DIR=/tmp/shots POKEPORT_IDENTITY=bug862 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/game_corner_grunt_bug862_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  os.execute("mkdir -p " .. DIR)

  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local BattleState = require("src.battle.BattleState")

  local pass, fail = 0, 0
  local function check(label, ok, detail)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label, detail or "")
    return ok
  end

  -- pokered/data/maps/objects/GameCorner.asm:36 -- the grunt is
  -- object_event 9, 5, SPRITE_ROCKET, STAY, UP, facing the poster bg_event
  -- at (9,4), which is wall.  Standing east of him on (10,5) is the branch
  -- that matters: wYCoord ~= 6 and wXCoord ~= 8, so the script takes
  -- GameCornerMovement_Rocket_WalkAroundPlayer.
  local MAP = "GAME_CORNER"
  local NAME = "GAMECORNER_ROCKET"
  local GX, GY = 9, 5
  local STAND = { x = 10, y = 5, facing = "left" }
  local POSTER = { x = 9, y = 4 }
  -- DOWN, RIGHT, RIGHT, UP, RIGHT x4 from (9,5), ending on (15,5)
  local AROUND = {
    { 9, 6 }, { 10, 6 }, { 11, 6 }, { 11, 5 },
    { 12, 5 }, { 13, 5 }, { 14, 5 }, { 15, 5 },
  }

  -- clean slate: he must not read as already defeated or already hidden
  game.save.defeatedTrainers = {}
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.objectToggles.GAME_CORNER = nil
  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "RED"
  game.save.money = game.save.money or 3000

  -- a tank that one-shots OPP_ROCKET #7, so the mash win below is quick and
  -- the same every run whatever the type matchups are
  local tank = Pokemon.new(game.data, "MEWTWO", 100)
  tank.moves = {
    { id = "PSYCHIC_M", pp = 99 },
    { id = "THUNDERBOLT", pp = 99 },
    { id = "ICE_BEAM", pp = 99 },
    { id = "EARTHQUAKE", pp = 99 },
  }
  game.save.party = { tank }

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  local ow = game.overworld

  local function findGrunt()
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == NAME then return n end
    end
    return nil
  end

  local grunt = findGrunt()
  check("GAMECORNER_ROCKET is on the floor", grunt ~= nil)
  if grunt then
    check("he stands on (9,5)", grunt.cellX == GX and grunt.cellY == GY,
          ("at (%d,%d)"):format(grunt.cellX, grunt.cellY))
  end

  -- a map edit or a mod could take (10,5) away; anything east of him keeps
  -- the WalkAroundPlayer branch, so fall back to a free walkable neighbour
  -- and say which branch that lands on
  local function facingGrunt()
    local g = findGrunt()
    if not g then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == g
  end
  if grunt and not facingGrunt() then
    local sides = {
      { 1, 0, "left" }, { 0, 1, "up" }, { -1, 0, "right" }, { 0, -1, "down" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = grunt.cellX + s[1], grunt.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d,%d) is blocked; standing on"):format(STAND.x, STAND.y),
              cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        ow = game.overworld
        grunt = findGrunt()
        break
      end
    end
  end
  check("the player is face to face with him", facingGrunt())
  local px, py = ow.player.cellX, ow.player.cellY
  local around = not (py == 6 or px == 8)
  U.log(("talking from (%d,%d): the script should take %s"):format(
          px, py, around and "WalkAroundPlayer (down, right, right, up, "
                          .. "right x4)" or "WalkDirect (right x5)"))

  -- the two strings the fix depends on, and the poster cell the pre-fix
  -- single UP step walked him into
  local t = game.data.text
  check("_GameCornerRocketBattleEndText resolves",
        type(t._GameCornerRocketBattleEndText) == "string"
        and t._GameCornerRocketBattleEndText ~= "",
        tostring(t._GameCornerRocketBattleEndText))
  check("_GameCornerRocketAfterBattleText resolves",
        type(t._GameCornerRocketAfterBattleText) == "string"
        and t._GameCornerRocketAfterBattleText ~= "")
  check("(9,4) is the poster wall, not a cell he can stand on",
        not ow.map:isWalkableCell(POSTER.x, POSTER.y))

  -- engageTrainer has to accept the script-supplied loss line; a stale
  -- two-parameter copy would silently drop it and print nothing
  local info = debug.getinfo(ow.engageTrainer, "S")
  local sigOk = false
  if info and info.short_src then
    local src = io.open((info.short_src:gsub("^@", "")), "r")
    if src then
      local n = 0
      for line in src:lines() do
        n = n + 1
        if n == info.linedefined then
          sigOk = line:find("endBattleText", 1, true) ~= nil
          break
        end
      end
      src:close()
    end
  end
  check("engageTrainer takes an endBattleText argument", sigOk)

  U.shot(game, DIR .. "/bug862_0_before.png")

  -- Talk and mash to a win, recording every battle message in order and
  -- pausing on the loss line long enough to photograph it.
  local said, battle = {}, nil
  local lastSaid, dangShot = nil, false
  local function sample()
    local top = game.stack:top()
    if getmetatable(top) == BattleState then
      battle = battle or top
      local cur = top.current
      local text = type(cur) == "table" and cur.text
      if type(text) == "string" and text ~= lastSaid then
        lastSaid = text
        said[#said + 1] = text
        U.log("battle says:", (text:gsub("\n", " ")))
      end
    end
  end

  local function pageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local parts = {}
    for _, page in ipairs(top.pages or {}) do
      if type(page) == "table" then
        for _, line in ipairs(page) do parts[#parts + 1] = tostring(line) end
      end
    end
    return table.concat(parts, " ")
  end

  local function idle()
    return game.stack:top() == ow and not ow.runner:isRunning()
           and #ow.scriptMoves == 0 and not ow.transitioning
  end

  U.tap(game, "a")
  local sawAfter = false
  for f = 1, 4000 do
    sample()
    if pageText():find("hideout", 1, true) then sawAfter = true break end
    local top = game.stack:top()
    if lastSaid and lastSaid:find("Dang", 1, true) and not dangShot then
      -- stop mashing for a moment: the loss line is on the battle screen.
      -- The row is picked up the frame it starts typing, so let it finish
      -- before the capture or the shot is one letter wide.
      dangShot = true
      U.wait(60)
      U.shot(game, DIR .. "/bug862_1_dang.png")
    elseif top and top.phase then
      if top.phase == "menu" then top.menuIndex = 1
      elseif top.phase == "moveSelect" then top.moveIndex = 1 end
      U.tap(game, "a")
      if f > 2400 and top.onFinish then
        U.log("force-finishing a stalled battle")
        top.onFinish("win")
        if game.stack:top() == top then game.stack:pop() end
      end
    else
      U.tap(game, "a")
    end
    U.wait(2)
    sample()
  end
  check("reached the after-battle 'hideout' line", sawAfter)
  check("the battle carried the script's loss line",
        battle ~= nil and type(battle.endBattleText) == "string"
        and battle.endBattleText:find("Dang", 1, true) ~= nil,
        battle and tostring(battle.endBattleText) or "no battle seen")

  -- PrintEndBattleText sits between TrainerDefeatedText and
  -- MoneyForWinningText (engine/battle/core.asm TrainerBattleVictory)
  local iDefeat, iDang, iMoney
  for i, line in ipairs(said) do
    if not iDefeat and line:find("defeated", 1, true) then iDefeat = i end
    if not iDang and line:find("Dang", 1, true) then iDang = i end
    if not iMoney and line:find("winning", 1, true) then iMoney = i end
  end
  check("the loss line printed on the battle screen", iDang ~= nil)
  check("it printed with the ROCKET: name tag",
        iDang ~= nil and said[iDang]:find(":", 1, true) ~= nil,
        iDang and said[iDang] or "")
  check("order is defeated -> Dang! -> payout",
        iDefeat ~= nil and iDang ~= nil and iMoney ~= nil
        and iDefeat < iDang and iDang < iMoney,
        ("defeated=%s dang=%s payout=%s"):format(tostring(iDefeat),
                                                 tostring(iDang),
                                                 tostring(iMoney)))
  U.shot(game, DIR .. "/bug862_2_afterbattle.png")

  -- Dismiss the after-battle box and watch the exit walk cell by cell.
  U.tap(game, "a")
  local visited, order, lowShot = {}, {}, false
  local function mark(cx, cy)
    local key = cx .. "," .. cy
    if not visited[key] then
      visited[key] = true
      order[#order + 1] = key
    end
  end
  -- the last step's hide_object rides its own onDone, so the grunt leaves
  -- ow.npcs on the frame he lands: count the cell he is walking INTO as
  -- visited too, or the destination never shows up in the sample
  local last = { GX, GY }
  for _ = 1, 900 do
    local g = findGrunt()
    if g then
      mark(g.cellX, g.cellY)
      last = { g.cellX, g.cellY }
      if g.targetX and g.targetY then
        mark(g.targetX, g.targetY)
        last = { g.targetX, g.targetY }
      end
      if g.cellY > GY and not lowShot then
        lowShot = true
        U.shot(game, DIR .. "/bug862_3_walk.png")
      end
    elseif idle() then
      break
    end
    if game.stack:top() ~= ow then U.tap(game, "a") end
    U.wait(1)
  end
  for _ = 1, 400 do
    if idle() then break end
    if game.stack:top() ~= ow then U.tap(game, "a") end
    U.wait(2)
  end
  U.wait(5)
  U.shot(game, DIR .. "/bug862_4_gone.png")

  U.log("cells he stood on:", table.concat(order, " "))
  check("he never stood on the poster cell (9,4)",
        not visited[POSTER.x .. "," .. POSTER.y])
  check("he never stepped north of his start row", (function()
    for key in pairs(visited) do
      local y = tonumber(key:match(",(%d+)$"))
      if y and y < GY then return false end
    end
    return true
  end)())
  if around then
    check("he stepped down to (9,6) to get past the player", visited["9,6"])
    check("he came back up onto row 5 and finished on (15,5)",
          last[1] == 15 and last[2] == 5,
          ("last seen on (%d,%d)"):format(last[1], last[2]))
  else
    check("he walked straight along row 5 to (15,5)",
          last[1] == 15 and last[2] == 5 and not visited["9,6"],
          ("last seen on (%d,%d)"):format(last[1], last[2]))
  end
  local toggles = game.save.objectToggles.GAME_CORNER
  check("he despawned only after the last step", findGrunt() == nil)
  check("his objectToggle is hidden",
        toggles ~= nil and toggles.GAMECORNER_ROCKET == false)
  check("he is recorded as defeated",
        game.save.defeatedTrainers["GAME_CORNER_obj_11"] == true)
  U.log(("checks: %d passed, %d failed"):format(pass, fail))

  -- Hand the pad over on a clean copy of the same setup so the whole beat
  -- can be watched at speed.
  game.save.defeatedTrainers = {}
  game.save.objectToggles.GAME_CORNER = nil
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.log("You are east of the grunt again, facing him. Press A and win.")
  U.log("Right looks like: he says his piece on the battle screen after")
  U.log("\"RED defeated ROCKET!\" -- one box, \"ROCKET: Dang!\" -- and the")
  U.log("¥ payout comes after it, not before. Then the hideout line, then")
  U.log("he steps DOWN off row 5, right past you, back up and out east.")
  U.log("The near miss to watch for: he steps UP into the poster, or the")
  U.log("Dang! box turns up in the overworld after the battle has torn down.")
  U.log("Talk to him from (9,6) below instead and he takes the straight")
  U.log("five-step version east; both are correct, the branch is your cell.")

  while true do
    coroutine.yield()
  end
end
