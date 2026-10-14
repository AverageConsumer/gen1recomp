return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SHOTS = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local fails = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local mon = Pokemon.new(game.data, "NIDORINA", 20)
  mon.nickname = "TERRY"
  game.save.party[1] = mon
  game.save.party[2] = Pokemon.new(game.data, "PIKACHU", 100)

  local summary = Screens.push(game, "SummaryMenu", mon)
  U.wait(30)
  U.still(game, SHOTS .. "/2944_01_status_page1.png")
  summary.page = 2
  U.wait(4)
  U.still(game, SHOTS .. "/2963_02_status_page2_species.png")
  check(summary.page == 2, "status page 2 open")
  while game.stack:top() ~= game.overworld do game.stack:pop() end

  Screens.push(game, "SummaryMenu", game.save.party[2])
  U.wait(30)
  U.still(game, SHOTS .. "/2945_03_status_pikachu_pic.png")
  while game.stack:top() ~= game.overworld do game.stack:pop() end

  local DexEntryMenu = require("src.ui.DexEntryMenu")
  game.stack:push(DexEntryMenu.new(game, { species = "KOFFING", forceOwned = true }))
  U.wait(90)
  U.still(game, SHOTS .. "/2944_04_dex_no_dot_koffing.png")
  while game.stack:top() ~= game.overworld do game.stack:pop() end

  local Slot = require("src.ui.SlotMachine")
  game.save.coins = 297
  local slots = Slot.new(game, false)
  game.stack:push(slots)
  U.wait(20)
  U.still(game, SHOTS .. "/2938_05_slots_bet_credit.png")
  check(slots.stage == "bet", "slot machine opens on the bet menu")
  while game.stack:top() ~= game.overworld do game.stack:pop() end

  love.event.quit(fails == 0 and 0 or 1)
end
