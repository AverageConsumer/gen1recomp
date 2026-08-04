-- Driver: the swap cursor in the FIGHT move list (#814).  pokered
-- SelectMenuItem parks the hollow arrow 0xEC on the marked row (engine/battle/
-- core.asm:2600-2607) and HandleMenuInput's PlaceMenuCursor writes the filled
-- arrow 0xED into the tilemap over it whenever the cursor sits there
-- (home/window.asm:184-185), so the row under the cursor is always filled.
-- Font.drawCode blits black-on-transparent, so drawing both glyphs on one cell
-- merged the two arrows.  Eye check, no SPEED.
--   POKEPORT_DRIVER=tests/drivers/move_swap_arrow_bug814_test.lua \
--     POKEPORT_IDENTITY=bug814 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.player.name = "bryan"
  -- CHARIZARD at 50 knows four moves, so marking row 1 and parking the cursor
  -- on row 2 leaves both arrows on screen at once
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  local lead = game.save.party[1]
  check("the lead knows at least 3 moves (needs rows to scroll between)",
        #lead.moves >= 3)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)
  local ow = game.overworld
  check("overworld is up to push the battle from", ow ~= nil)

  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  local function tapUntil(cond, taps, gap)
    for _ = 1, (taps or 60) do
      if cond() then return true end
      U.tap(game, "a")
      for _ = 1, (gap or 6) do
        if cond() then return true end
        U.wait(1)
      end
    end
    return cond()
  end

  U.wait(220) -- the send-out intro plays before the menu is reachable
  check("reached the FIGHT/PKMN/ITEM/RUN menu",
        tapUntil(function() return battle.phase == "menu" end, 120))
  check("cursor starts on FIGHT", battle.menuIndex == 1)

  U.tap(game, "a")
  U.wait(20)
  check("the FIGHT move list is open (#814 lives on this screen)",
        battle.phase == "moveSelect")
  check("cursor starts on move 1", battle.moveIndex == 1)

  -- SELECT marks the move under the cursor for swapping
  U.tap(game, "select")
  U.wait(10)
  check("SELECT marked move 1 (moveSwapIndex == 1)",
        battle.moveSwapIndex == 1)

  -- cursor down to row 2: hollow arrow stays on row 1, filled follows to row 2
  U.tap(game, "down")
  U.wait(10)
  check("cursor moved to move 2", battle.moveIndex == 2)
  check("the mark stayed on move 1", battle.moveSwapIndex == 1)
  check("split-arrow screenshot reached disk",
        U.shot(game, DIR .. "/bug814_marked_row1_cursor_row2.png"))
  U.log("captured", DIR .. "/bug814_marked_row1_cursor_row2.png")

  -- cursor back up onto the marked row: this is the shot the fix is judged
  -- on -- the shared cell must show only the filled arrow
  U.tap(game, "up")
  U.wait(10)
  check("cursor is back on move 1", battle.moveIndex == 1)
  check("the mark is still on move 1", battle.moveSwapIndex == 1)
  check("cursor-on-marked-row screenshot reached disk",
        U.shot(game, DIR .. "/bug814_cursor_on_marked_row.png"))
  U.log("captured", DIR .. "/bug814_cursor_on_marked_row.png")

  -- ---- hand off ----------------------------------------------------------
  U.log("Move 1 is marked for swap and the cursor sits on it.  That row wants")
  U.log("one solid black arrow only; a hollow outline there, or a smudge of")
  U.log("both shapes, is the bug (#814).  Scroll DOWN and the hollow arrow")
  U.log("should reappear on row 1 while the solid one follows the cursor.")

  while true do
    coroutine.yield()
  end
end
