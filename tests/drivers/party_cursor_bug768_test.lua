-- Manual check for #768: the field party menu keeps its cursor across
-- close/reopen (wPartyAndBillsPCSavedMenuItem: PartyMenuInit reads it,
-- HandlePartyMenuInput writes it back, only a battle zeroes it via
-- InitBattleVariables / end_of_battle.asm), and the per-mon submenu lists
-- field moves ABOVE STATS/SWITCH (DisplayFieldMoveMonMenu prints the move
-- names above PokemonMenuEntries, engine/menus/text_box.asm).
--   POKEPORT_DRIVER=tests/drivers/party_cursor_bug768_test.lua POKEPORT_IDENTITY=bug768 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Slot 1 knows FLY (movesAtLevel never grants it, so inject it, same as
  -- the #203 driver); the badge gates the submenu entry.
  local flyer = Pokemon.new(game.data, "PIDGEOT", 40)
  flyer.moves[1] = { id = "FLY", pp = 15 }
  game.save.party = {
    flyer,
    Pokemon.new(game.data, "PIKACHU", 30),
    Pokemon.new(game.data, "SNORLAX", 77),
  }
  game.save.player.name = "bryan"
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.THUNDERBADGE = true

  -- Pallet Town is OVERWORLD, so FLY is listed (CheckIfInOutsideMap)
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  -- half 1: the submenu puts the field move on top
  Screens.push(game, "PartyMenu")
  U.wait(5)
  local pm = game.stack:top()
  U.tap(game, "a") -- open the per-mon submenu on the FLY mon
  U.wait(2)
  local items = pm.subItems or {}
  check("submenu row 1 is FLY, not STATS",
        items[1] ~= nil and items[1].action == "fly")
  check("STATS/SWITCH close the list under the field move",
        #items == 3 and items[2].action == "stats"
        and items[3].action == "switch")
  U.shot(game, DIR .. "/bug768_submenu.png")
  U.tap(game, "b") -- back out of the submenu
  U.wait(2)

  -- half 2: the cursor survives closing and reopening the menu
  U.tap(game, "down")
  U.wait(2)
  U.tap(game, "down")
  U.wait(2)
  check("cursor moved to slot 3", pm.index == 3)
  U.tap(game, "b") -- close the party menu entirely
  U.wait(5)
  Screens.push(game, "PartyMenu")
  U.wait(5)
  local pm2 = game.stack:top()
  check("reopened menu is still on slot 3 (SNORLAX)",
        pm2 ~= pm and pm2.index == 3)
  U.shot(game, DIR .. "/bug768_reopened.png")

  U.log("The party menu on screen was just reopened; the cursor should sit")
  U.log("on slot 3 (SNORLAX), not slot 1.  A on slot 1 shows FLY above")
  U.log("STATS/SWITCH.  Input is yours now: walk north into the Route 1")
  U.log("grass, win or run from a wild battle, then reopen the party menu --")
  U.log("the cursor should be back on slot 1 (the battle cleared it).")

  while true do
    coroutine.yield()
  end
end
