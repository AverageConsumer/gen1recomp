-- Driver: the FIGHT/PKMN/ITEM/RUN cursor after a voluntary switch (#770).
-- SendOutMon (pokered engine/battle/core.asm:1733-1735) zeroes the saved
-- battle-menu byte AND the move-list byte behind it on every player
-- send-out, so the reopened menu starts on FIGHT; the #737 sendOutMonCursors
-- reset already covers this and the driver is the proof.  Judge WITHOUT
-- POKEPORT_SPEED: fast-forward makes the reopened menu impossible to read.
--   POKEPORT_DRIVER=tests/drivers/battle_menu_default_bug770_test.lua POKEPORT_IDENTITY=bug770 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local PartyMenu = require("src.ui.PartyMenu")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- :L60 pair so the foe's free move after the switch cannot faint anyone
  -- and force the ChooseNextMon path instead of the voluntary one
  check("CHARIZARD resolves in the species table",
        game.data.pokemon.CHARIZARD ~= nil)
  check("SNORLAX resolves in the species table",
        game.data.pokemon.SNORLAX ~= nil)
  game.save.player.name = "bryan"
  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 60),
    Pokemon.new(game.data, "SNORLAX", 60),
  }
  check("party has two healthy mons",
        #game.save.party == 2
        and game.save.party[1].hp > 0 and game.save.party[2].hp > 0)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)
  check("overworld is up to push the battle from", game.overworld ~= nil)

  local battle = BattleState.newWild(game, "PIDGEY", 5)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)

  local function mashUntil(cond, max)
    for _ = 1, max or 120 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return cond()
  end

  U.wait(220) -- the send-out intro plays before the menu is reachable
  check("the wild battle reached its action menu",
        mashUntil(function() return battle.phase == "menu" end))
  check("cursor starts on FIGHT", battle.menuIndex == 1)

  -- park the cursor on PKMN first: with it off FIGHT, "still 1 afterwards"
  -- proves a reset happened rather than nothing ever moving
  U.tap(game, "right")
  U.wait(4)
  check("cursor moved to PKMN", battle.menuIndex == 2)
  U.tap(game, "a")
  U.wait(10)
  local menu = game.stack:top()
  check("A on PKMN opened the party menu", getmetatable(menu) == PartyMenu)

  -- steer onto slot 2; #768 seeds the cursor from partyMenuSavedIndex so
  -- the start slot is not fixed, but down wraps and must land on 2
  for _ = 1, 6 do
    if getmetatable(menu) ~= PartyMenu or menu.index == 2 then break end
    U.tap(game, "down")
    U.wait(4)
  end
  check("party cursor sits on slot 2",
        getmetatable(menu) == PartyMenu and menu.index == 2)
  U.tap(game, "a") -- SWITCH / STATS / CANCEL, SWITCH preselected
  U.wait(6)
  check("the SWITCH submenu is open",
        getmetatable(menu) == PartyMenu and menu.submenu ~= nil
        and menu.subIndex == 1)
  U.tap(game, "a") -- SWITCH -> resolveSwitch; the foe takes a free move
  U.wait(10)

  check("the turn resolved back to the action menu",
        mashUntil(function() return battle.phase == "menu" end, 300))
  check("the second mon is the one out now",
        battle.player.mon == game.save.party[2])
  check("menuIndex reset to FIGHT after the send-out (#770)",
        battle.menuIndex == 1)
  check("moveIndex reset to the first slot too", battle.moveIndex == 1)
  U.shot(game, DIR .. "/bug770_menu_after_switch.png")
  U.log("captured", DIR .. "/bug770_menu_after_switch.png")

  U.log("The menu on screen just reopened after a PKMN switch; the cursor")
  U.log("should be back on FIGHT.  Switch again yourself: it must land on")
  U.log("FIGHT every time -- reopening on PKMN is the old #770 bug.")

  while true do
    coroutine.yield()
  end
end
