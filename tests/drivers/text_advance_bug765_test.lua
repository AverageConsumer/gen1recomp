-- Manual check for the pages that must NOT wait on a button (#765).
-- Only TX_PROMPT_BUTTON blinks the arrow and waits (home/text.asm:434-446);
-- the used-move line (engine/battle/used_move_text.asm) ends in `text_end`
-- and both save pages come from SaveMenu .save (engine/menus/save.asm:164-181),
-- where "Now saving..." is a bare PlaceString + DelayFrames 120 and
-- GameSavedText ends in `done`.  Ordering is asserted headlessly in
-- tests/parity_battle_auto_text_bug765.lua; this run is for pacing.
-- No POKEPORT_SPEED: the save beat and the SFX_SAVE hold are the moment.
--   POKEPORT_DRIVER=tests/drivers/text_advance_bug765_test.lua POKEPORT_IDENTITY=bug765 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local TextBox = require("src.render.TextBox")
  local Menu = require("src.ui.Menu")
  local ChoiceBox = require("src.ui.ChoiceBox")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 50) }
  game.save.player.name = "RED"
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  -- ---- part 1: START -> SAVE -> YES, hands off the pad -------------------
  U.tap(game, "start")
  U.wait(10)
  local menu = game.stack:top()
  check("START opened the menu", getmetatable(menu) == Menu)
  if getmetatable(menu) == Menu then
    -- walk the cursor onto SAVE by label: which rows exist depends on
    -- story flags, so counting from the top is not stable
    local target
    for i, item in ipairs(menu.items) do
      if tostring(item.label) == "SAVE" then target = i end
    end
    check("the menu lists SAVE", target ~= nil)
    -- the cursor position survives closing the menu
    -- (wBattleAndStartSavedMenuItem), so it may start above OR below SAVE
    for _ = 1, #menu.items do
      if not target or menu.index == target then break end
      U.tap(game, menu.index < target and "down" or "up")
      U.wait(4)
    end
    U.tap(game, "a")
    U.wait(10)
  end

  -- the player/badges/dex/time panel types out, page-breaks (\f) into the
  -- confirmation, then the YES/NO box opens; A through all of it, YES last
  local chose = false
  for _ = 1, 30 do
    local top = game.stack:top()
    if getmetatable(top) == ChoiceBox then
      U.tap(game, "a")
      chose = true
      break
    end
    U.tap(game, "a")
    U.wait(20)
  end
  check("the SAVE confirmation was reached and answered YES", chose)

  -- the answered box holds 15 frames before it pops and runs the choice
  -- (DisplayTwoOptionMenu, engine/menus/text_box.asm:322-334), so wait it out
  for _ = 1, 60 do
    if getmetatable(game.stack:top()) ~= ChoiceBox then break end
    U.wait(1)
  end

  -- from here NOTHING is pressed: both boxes must clear themselves
  U.wait(2)
  local saving = game.stack:top()
  check("the Now saving... box is up", getmetatable(saving) == TextBox)
  local savingPopped
  for f = 1, 300 do
    if game.stack:top() ~= saving then savingPopped = f break end
    U.wait(1)
  end
  check("it held about 2s and popped with no button (DelayFrames 120)",
        savingPopped ~= nil and savingPopped > 60)
  local savedPopped = false
  for _ = 1, 600 do
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox and getmetatable(top) ~= Menu then
      savedPopped = true
      break
    end
    U.wait(1)
  end
  check("the saved-the-game box cleared itself after SFX_SAVE", savedPopped)

  -- ---- part 2: a wild battle's used-move line ----------------------------
  local wild = BattleState.newWild(game, "RATTATA", 2)
  wild.onFinish = function() end
  local ow = game.overworld
  if ow then ow:pushBattle(wild) end
  for _ = 1, 400 do
    if game.stack:top() == wild and (wild.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the wild battle reached the screen", game.stack:top() == wild)

  -- the intro page ends in `prompt` (WildMonAppearedText), so it still
  -- waits; A through it and the send-out, then pick FIGHT + first move
  for _ = 1, 600 do
    if wild.phase == "menu" then break end
    if wild.msgPrompt then U.tap(game, "a") end
    U.wait(1)
  end
  check("the intro still holds on its arrow and A walks it to the menu",
        wild.phase == "menu")
  U.tap(game, "a") -- FIGHT
  U.wait(10)
  U.tap(game, "a") -- first move

  -- from here NOTHING is pressed: "BULBASAUR used X!" must flow straight
  -- into its animation with the line still on screen and no arrow
  local sawUsed, promptedOnUsed, handedOff = false, false, false
  for _ = 1, 900 do
    local cur = wild.current
    local t = cur and cur.text
    if t and t:find("used", 1, true) then
      sawUsed = true
      if wild.msgPrompt then promptedOnUsed = true end
    elseif sawUsed then
      handedOff = true
      break
    end
    U.wait(1)
  end
  check("the used-move line reached the screen", sawUsed)
  check("it never raised the prompt arrow", not promptedOnUsed)
  check("it handed off by itself, no A pressed", handedOff)
  check("the line stays drawn under the animation (msgHold)",
        wild.msgHold == true or wild.animPlaying == true)

  -- ...and the pages after it still wait: a level-50 BULBASAUR one-shots a
  -- level-2 RATTATA, so the faint line (BattleMonFaintedText class, ends in
  -- `prompt`) comes up next and must hold on its arrow
  local promptAfter = false
  for _ = 1, 900 do
    if wild.msgPrompt then promptAfter = true break end
    U.wait(1)
  end
  check("the page after it still holds on the arrow", promptAfter)

  U.log("Handing off.  What just happened, and what to look for on a replay:")
  U.log("the save flow ran with no button after YES: \"Now saving...\" held")
  U.log("about 2 seconds, then \"RED saved the game!\" played the save jingle")
  U.log("and cleared itself.  In the battle, \"BULBASAUR used <MOVE>!\" flowed")
  U.log("straight into the move animation with the line still up and no")
  U.log("blinking arrow; the faint line after it is waiting on A right now.")

  while true do
    coroutine.yield()
  end
end
