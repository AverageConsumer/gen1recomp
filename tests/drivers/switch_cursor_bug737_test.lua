-- Manual check that a voluntary switch resets both battle cursors (#737).
-- SendOutMon (pokered engine/battle/core.asm:1733-1735) zeroes
-- wBattleAndStartSavedMenuItem and, via the same hli/hl pair, the
-- wPlayerMoveListIndex byte behind it (wram.asm:242-244), so after any
-- player send-out the main menu reopens on FIGHT and the move list on
-- slot 1.  The port used to keep both cursors where they were.
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/switch_cursor_bug737_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  -- CHARMANDER at 12 knows Scratch/Growl/Ember, so the move cursor can be
  -- parked on slot 3 before the switch
  game.save.party = {
    Pokemon.new(game.data, "CHARMANDER", 12),
    Pokemon.new(game.data, "SQUIRTLE", 10),
  }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local battle = BattleState.newWild(game, "PIDGEY", 4)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function mashUntil(cond, max)
    for _ = 1, max or 120 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return false
  end

  check("intro drains to the battle menu",
        mashUntil(function() return battle.phase == "menu" end))

  -- open FIGHT and park the cursor on move slot 3, then back out
  U.tap(game, "a"); U.wait(6)
  U.tap(game, "down"); U.wait(4)
  U.tap(game, "down"); U.wait(4)
  check("move cursor parked on slot 3", battle.moveIndex == 3)
  U.tap(game, "b"); U.wait(6)

  -- FIGHT/PKMN/ITEM/RUN: right to PKMN, A opens the party
  U.tap(game, "right"); U.wait(4)
  check("battle menu parked on PKMN", battle.menuIndex == 2)
  U.tap(game, "a"); U.wait(12)
  local pm = game.stack:top()
  check("party menu opened", pm ~= nil and pm.onSwitch ~= nil)

  -- pick SQUIRTLE, then SWITCH from the SWITCH/STATS/CANCEL submenu
  U.tap(game, "down"); U.wait(4)
  U.tap(game, "a"); U.wait(8)
  U.tap(game, "a"); U.wait(8)

  -- the switch queues "Come back!" / "Go!" plus the enemy's free move;
  -- drain back to the next command menu
  check("switch turn drains back to the menu",
        mashUntil(function() return battle.phase == "menu" end, 300))
  check("player is now SQUIRTLE", battle.player.mon.species == "SQUIRTLE")

  -- the machine-checkable half of #737
  check("battle menu is back on FIGHT", battle.menuIndex == 1)
  check("move cursor is back on slot 1", battle.moveIndex == 1)

  U.shot(game, DIR .. "/bug737_menu_after_switch.png")
  U.tap(game, "a"); U.wait(8)
  U.shot(game, DIR .. "/bug737_moves_after_switch.png")
  U.log("captured", DIR .. "/bug737_menu_after_switch.png",
        "and", DIR .. "/bug737_moves_after_switch.png")

  U.log("The fight menu on screen is SQUIRTLE's, opened right after the")
  U.log("switch.  The cursor should sit on the first move; before #737 it")
  U.log("kept CHARMANDER's old slot (3), and the main menu reopened on PKMN.")

  while true do
    coroutine.yield()
  end
end
