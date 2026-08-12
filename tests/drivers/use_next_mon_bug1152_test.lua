-- After a wild faint, "Use next POKéMON?" yes/no; NO tries to run. Issue #1152.
-- pokegold engine/battle/core.asm:2590 (AskUseNextPokemon).
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/use_next_mon_bug1152_test.lua love .
-- Do not add POKEPORT_SPEED: you need the yes/no box to sit there.

local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  local function claim(ok, text)
    print((ok and "[use-next] PASS " or "[use-next] FAIL ") .. text)
    return ok
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    print("[use-next] FAIL gold world did not boot")
    while true do U.wait(60) end
  end

  local lead = Mon.new(game.data, "SENTRET", 5)
  local backup = Mon.new(game.data, "CYNDAQUIL", 12)
  if not (lead and backup) then
    print("[use-next] FAIL could not build the party")
    while true do U.wait(60) end
  end
  lead.hp = 1
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  backup.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  game.save.party = { lead, backup }

  local wild = Mon.new(game.data, "PIDGEY", 20)
  if not wild then
    print("[use-next] FAIL could not build a wild PIDGEY")
    while true do U.wait(60) end
  end
  if not world:startBattle({ wild = wild }) then
    print("[use-next] FAIL startBattle failed")
    while true do U.wait(60) end
  end

  local screen
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  if not (screen and screen.battle) then
    print("[use-next] FAIL battle screen never came up")
    while true do U.wait(60) end
  end

  for _ = 1, 200 do
    if screen.phase == "menu" then break end
    tap("a", 3)
  end
  if screen.phase ~= "menu" then
    print("[use-next] FAIL never reached the battle menu")
    while true do U.wait(60) end
  end

  tap("a")
  U.wait(6)
  tap("a")

  local sawAsk, sawForced = false, false
  for _ = 1, 400 do
    if screen.phase == "ask-next-mon" then sawAsk = true break end
    if screen.phase == "forced-switch" or screen.phase == "submenu" then
      sawForced = true
      break
    end
    if screen.battle.over then break end
    tap("a", 3)
  end

  claim(sawAsk, "wild faint opened Use next POKéMON?")
  claim(not sawForced, "wild faint did not skip to the party list")
  claim(screen.phase == "ask-next-mon",
    "phase is ask-next-mon (YES switches, NO/B tries to run)")
  print("[use-next] YES sends you to the party. NO or B tries to run.")
  print("[use-next] a failed run still opens the party. trainers skip this.")

  while true do U.wait(60) end
end
