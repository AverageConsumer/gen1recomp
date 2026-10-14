local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_birch_rescue_speed_2912"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  local function finish()
    print(string.format("[driver] em_birch_rescue_speed_2912: %d failure(s)", fails))
    love.event.quit(fails == 0 and 0 or 1)
    U.wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Field = require("src.core.game3.field")
  local Message = require("src.ui.game3.message")
  local VARS = Flags.forVersion("emerald").VAR_IDS
  result(Runtime.getSession() ~= nil, "field session exists")
  if not Runtime.getSession() then return finish() end

  local steps = 0
  local origFixed = game.fixedUpdate
  game.fixedUpdate = function(self, dt) steps = steps + 1; return origFixed(self, dt) end

  game.speedOverride = nil
  game.options.speedOverworld, game.options.speedBattle, game.options.speedMenu = 4, 1, 1
  result(game:logicSpeed() == 4, "OVERWORLD SPEED 4X is the logic speed (" .. tostring(game:logicSpeed()) .. ")")

  -- data/maps/LittlerootTown/scripts.inc:8
  Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_TOWN_STATE, 1)
  Flags.setVar(Space.store, nil, VARS.VAR_ROUTE101_STATE, 0)
  Map.load(nil, game, "EM_LITTLEROOT_TOWN", { x = 11, y = 3, facing = "up" })
  local s = Runtime.getSession()
  s.x, s.y, s.facing = 11, 3, "up"
  Player.cellX, Player.cellY, Player.px, Player.py = 11, 3, 11 * 16, 3 * 16
  Player.targetX, Player.targetY, Player.facing = 11, 3, "up"
  U.wait(40)

  local rescue = Space.scriptKey("Route101_EventScript_StartBirchRescue")
  local function running() return Space.vm and Space.vm:isRunning() and Space.vm._scriptKey or nil end
  local function pressA() table.insert(game.input.pressQueue, "a") end

  steps = 0
  local hist, total = {}, 0
  local function sample()
    total = total + 1
    hist[steps] = (hist[steps] or 0) + 1
    steps = 0
  end
  local started
  for i = 1, 600 do
    if Message.isOpen and Message.isOpen() and i % 10 == 0 then
      pressA()
    else
      table.insert(game.input.pressQueue, "up")
      game.input.state.up = true
    end
    coroutine.yield()
    game.input.state.up = false
    sample()
    if running() == rescue then started = true break end
  end
  result(started == true, "walking north from Littleroot starts Route101_EventScript_StartBirchRescue")
  if not started then return finish() end
  U.still(game, DIR .. "/2912_01_help_me.png")

  hist, total = {}, 0
  local chaseShot = false
  local ran = 0
  for i = 1, 4000 do
    if i % 12 == 0 then pressA() end
    coroutine.yield()
    sample()
    ran = i
    if not chaseShot and i > 60 and Field.isLocked() and not (Message.isOpen and Message.isOpen()) then
      chaseShot = true
      U.still(game, DIR .. "/2912_02_zigzagoon_chase.png")
    end
    if not Field.isLocked() and not running() then break end
  end
  local at4 = hist[4] or 0
  local keys = {}
  for k in pairs(hist) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do print(string.format("[driver] steps=%d updates=%d", k, hist[k])) end
  result(ran < 4000, "rescue script finished (" .. ran .. " updates)")
  result(total > 0 and at4 >= total * 0.95, string.format("rescue ran at 4 logic steps per update (%d/%d)", at4, total))
  result(Flags.getVar(Space.store, nil, VARS.VAR_ROUTE101_STATE) == 2, "VAR_ROUTE101_STATE is 2 after the scene")
  U.still(game, DIR .. "/2912_03_after_rescue.png")
  return finish()
end
