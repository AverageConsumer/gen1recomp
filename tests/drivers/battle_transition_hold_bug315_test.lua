-- engine/battle/battle_transitions.asm:391-393
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local BattleTransition = require("src.render.BattleTransition")

  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end

  game.save.player.name = "bryan"
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(20)
  local ow = game.overworld
  check("overworld is up to push the battle from", ow ~= nil)

  -- ---- measure the hold --------------------------------------------------
  -- No screenshots in this pass: U.shot spins frames of its own and would
  -- corrupt the count.
  local function measure()
    local battle = BattleState.newWild(game, "PIDGEY", 8)
    battle.onFinish = function() end
    ow:pushBattle(battle)
    local tr = game.stack:top()
    if getmetatable(tr) ~= BattleTransition then return nil, "no transition" end
    local style, wipeLen = tr.style, tr.wipeLen
    local f, wipeDone, popped = 0, nil, nil
    while f < 600 do
      f = f + 1
      if not wipeDone and tr.phase == "wipe" and tr.t >= wipeLen then
        wipeDone = f
      end
      if game.stack:top() ~= tr then popped = f break end
      U.wait(1)
    end
    return { style = style, wipeLen = wipeLen, wipeDone = wipeDone,
             popped = popped, battle = battle, tr = tr }, nil
  end

  local m, err = measure()
  check("a BattleTransition was pushed for the battle", m ~= nil)
  if not m then
    U.log("could not measure:", tostring(err))
    love.event.quit(1)
    return
  end
  U.log(("style %s: wipe is %d frames"):format(tostring(m.style), m.wipeLen))
  check("the wipe reached its last frame", m.wipeDone ~= nil)
  check("the transition popped itself", m.popped ~= nil)
  local hold = (m.wipeDone and m.popped) and (m.popped - m.wipeDone) or -1
  local delayed = m.style == "shrink" or m.style == "split"
  local want = delayed and 91 or 70
  U.log(("black hold measured: %d frames, transition hold %s, want %d")
          :format(hold, tostring(m.tr.hold), want))
  check(("the style's hold is %d (got %s)"):format(want, tostring(m.tr.hold)),
        m.tr.hold == want)
  check(("the measured black hold matches it within a frame (got %d)")
          :format(hold), math.abs(hold - want) <= 1)

  -- unwind that battle before the next one
  while game.stack:top() ~= ow do game.stack:pop() end
  U.wait(10)

  -- ---- screenshot the beat ------------------------------------------------
  -- One frame inside the hold (solid black edge to edge) and one after the pop.
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  local tr = game.stack:top()
  check("second transition pushed", getmetatable(tr) == BattleTransition)
  for _ = 1, 600 do
    if tr.phase == "wipe" and tr.t >= tr.wipeLen then break end
    U.wait(1)
  end
  check("hold screenshot reached disk",
        U.still(game, DIR .. "/315_01_black_hold.png"))
  for _ = 1, 300 do
    if game.stack:top() ~= tr then break end
    U.wait(1)
  end
  U.wait(2)
  check("post-hold screenshot reached disk",
        U.shot(game, DIR .. "/315_02_battle_appears.png"))

  while game.stack:top() ~= ow do game.stack:pop() end
  U.log(failed and "FAIL battle_transition_hold_bug315" or "PASS battle_transition_hold_bug315")
  love.event.quit(failed and 1 or 0)
end
