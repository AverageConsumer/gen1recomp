-- Fury Attack / Barrage hit 2-5 times, Twineedle stays at 2. Issue #1168.
-- pokegold engine/battle/effect_commands.asm:5228 (BattleCommand_EndLoop).
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/multihit_bug1168_test.lua love .
-- Do not add POKEPORT_SPEED: the per-strike HP steps are what you are judging.

local U = require("tests.drivers.util")
local Battle = require("src.battle.gen2.Battle")
local Effects = require("src.battle.gen2.Effects")
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
    print((ok and "[multihit] PASS " or "[multihit] FAIL ") .. text)
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    print("[multihit] FAIL gold world did not boot")
    while true do U.wait(60) end
  end

  local fury = game.data.moves and game.data.moves.FURY_ATTACK
  local twine = game.data.moves and game.data.moves.TWINEEDLE
  claim(fury ~= nil, "FURY_ATTACK is in the move table")
  claim(fury and fury.effect == "EFFECT_MULTI_HIT",
    "FURY_ATTACK is EFFECT_MULTI_HIT")
  claim(twine ~= nil, "TWINEEDLE is in the move table")
  claim(twine and twine.effect == "EFFECT_POISON_MULTI_HIT",
    "TWINEEDLE is EFFECT_POISON_MULTI_HIT")
  claim(Effects.hitCount("EFFECT_DOUBLE_HIT") == 2, "DOUBLE_HIT is 2")
  claim(Effects.hitCount("EFFECT_POISON_MULTI_HIT") == 2,
    "POISON_MULTI_HIT (Twineedle) is 2")

  local seq, si = { 0, 1, 2, 0, 3, 3 }, 0
  local function scripted()
    si = si + 1
    return seq[si] or 0
  end
  claim(Effects.hitCount("EFFECT_MULTI_HIT", scripted) == 2, "roll 0 -> 2 hits")
  claim(Effects.hitCount("EFFECT_MULTI_HIT", scripted) == 3, "roll 1 -> 3 hits")
  claim(Effects.hitCount("EFFECT_MULTI_HIT", scripted) == 2,
    "roll 2 then 0 -> 2 hits")
  claim(Effects.hitCount("EFFECT_MULTI_HIT", scripted) == 5,
    "roll 3 then 3 -> 5 hits")

  local function fiveHitRandom(n)
    if n == 4 then return 3 end
    return 0
  end

  local headP = Mon.new(game.data, "CYNDAQUIL", 20)
  local headW = Mon.new(game.data, "SNORLAX", 20)
  if headP and headW then
    headP.moves = { { id = "FURY_ATTACK", pp = 20, maxPp = 20 } }
    local b = Battle.new({
      data = game.data, party = { headP }, wild = headW,
      random = fiveHitRandom,
    })
    local landed, hitLine = 0, nil
    for _, ev in ipairs(b:takeTurn({ kind = "move", move = "FURY_ATTACK" })) do
      if ev.kind == "damage" and ev.side == "enemy" then
        landed = landed + 1
      end
      if ev.kind == "message" and ev.text then
        local n = ev.text:match("Hit (%d+) time")
        if n then hitLine, landed = ev.text, tonumber(n) end
      end
    end
    claim(landed == 5,
      ("scripted Fury Attack hit %d times (want 5, not 2)"):format(landed))
    if hitLine then print("[multihit] " .. hitLine) end
  else
    claim(false, "could not build a headless Fury Attack pair")
  end

  local player = Mon.new(game.data, "CYNDAQUIL", 20)
  if not player then
    print("[multihit] FAIL could not build CYNDAQUIL")
    while true do U.wait(60) end
  end
  player.moves = { { id = "FURY_ATTACK", pp = 20, maxPp = 20 } }
  game.save.party = { player }

  local wild = Mon.new(game.data, "SNORLAX", 20)
  if not wild then
    print("[multihit] FAIL could not build SNORLAX")
    while true do U.wait(60) end
  end
  if not world:startBattle({ wild = wild }) then
    print("[multihit] FAIL startBattle failed")
    while true do U.wait(60) end
  end

  local screen
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  if not (screen and screen.battle) then
    print("[multihit] FAIL battle screen never came up")
    while true do U.wait(60) end
  end

  local left = 2
  screen.battle.random = function(n)
    if n == 4 and left > 0 then
      left = left - 1
      return 3
    end
    if left > 0 then return 0 end
    if love and love.math and love.math.random then
      return love.math.random(n) - 1
    end
    return math.random(n) - 1
  end

  for _ = 1, 200 do
    if screen.phase == "menu" then break end
    tap("a", 3)
  end
  if screen.phase ~= "menu" then
    print("[multihit] FAIL never reached the battle menu")
    while true do U.wait(60) end
  end

  tap("a")
  U.wait(6)
  tap("a")
  print("[multihit] Fury Attack should strike five times on this turn.")
  print("[multihit] later turns are 2-5. Twineedle would stay at 2.")

  while true do U.wait(60) end
end
