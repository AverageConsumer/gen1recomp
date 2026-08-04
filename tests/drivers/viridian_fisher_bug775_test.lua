-- Manual check of the Viridian fisher's TM42 gift pre text (#775).
-- pokered ViridianCityFisherText (scripts/ViridianCity.asm) prints
-- .YouCanHaveThisText ("Yawn! I must have dozed off...") before GiveItem;
-- the port had no pre entry, so A jumped straight to "received TM42!".
--   POKEPORT_DRIVER=tests/drivers/viridian_fisher_bug775_test.lua POKEPORT_IDENTITY=bug775 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")

  -- pokered data/maps/objects/ViridianCity.asm: the FISHER stays at (6, 23)
  -- facing down, so stand one cell below him and look up
  local MAP = "VIRIDIAN_CITY"
  local STAND = { x = 6, y = 24, facing = "up" }
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  U.newGame(game)
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  local TextBox = require("src.render.TextBox")
  local function boxText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return nil end
    local lines = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    return table.concat(lines, " / ")
  end

  check("no TM42 in the bag before talking",
        (game.save.inventory.TM_DREAM_EATER or 0) == 0)

  U.tap(game, "a")
  U.wait(30)

  local first = boxText()
  check("pressing A opened a text box", first ~= nil)
  U.log("first box reads:", first or "(none)")
  check("it opens on the pre text, not the receipt",
        first ~= nil and first:find("Yawn!", 1, true) ~= nil)
  check("the DROWZEE dream paragraph is in it",
        first ~= nil and first:find("DROWZEE", 1, true) ~= nil)
  check("the receipt has not fired yet",
        first == nil or first:find("received", 1, true) == nil)
  check("the flag is still unset mid pre text",
        not game.save.flags.EVENT_GOT_TM42)
  U.shot(game, SHOT_DIR .. "/bug775_pre.png")

  -- type out and dismiss every page of the pre text, then the receipt and
  -- the explanation behind it
  for _ = 1, 40 do
    if not boxText() then break end
    U.tap(game, "a")
    U.wait(15)
  end
  check("TM42 reached the bag", (game.save.inventory.TM_DREAM_EATER or 0) == 1)
  check("EVENT_GOT_TM42 is set", game.save.flags.EVENT_GOT_TM42 == true)

  -- second talk: the flag routes to the DREAM EATER explanation, no re-gift
  U.tap(game, "a")
  U.wait(30)
  local again = boxText()
  U.log("second talk reads:", again or "(none)")
  check("a second talk shows the explanation, not Yawn! again",
        again ~= nil and again:find("Yawn!", 1, true) == nil)
  U.shot(game, SHOT_DIR .. "/bug775_repeat.png")

  U.log("The screen is on the fisher's repeat-visit line now.  The first")
  U.log("talk should have read three pages: Yawn / the DROWZEE dream /")
  U.log("\"Here, you can have this TM.\", and only then the TM42 receipt.")
  U.log("Shots are in " .. SHOT_DIR .. " as bug775_pre.png / bug775_repeat.png.")

  while true do
    coroutine.yield()
  end
end
