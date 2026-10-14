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
  slots:resolveWin({ symbol = "CHERRY", payout = 8 })
  for _ = 1, 60 do
    if slots.stage == "message" then break end
    U.wait(1)
  end
  U.wait(2)
  check(slots.stage == "message", "slot win reaches the lined-up text")
  U.still(game, SHOTS .. "/2938_06_slots_win_arrow.png")
  while game.stack:top() ~= game.overworld do game.stack:pop() end

  local BattleState = require("src.battle.BattleState")
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 12) }
  game.save.safari = { balls = 30, steps = 400 }
  local safari = BattleState.newWild(game, "CHANSEY", 25)
  safari:makeSafari(game.save.safari)
  safari.onFinish = function() end
  game.overworld:pushBattle(safari)
  for _ = 1, 120 do
    if safari.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  U.wait(10)
  check(safari.phase == "menu", "safari battle menu is up")
  U.still(game, SHOTS .. "/2944_07_safari_ball_x.png")
  while game.stack:top() ~= game.overworld do game.stack:pop() end
  game.save.safari = nil

  local fainted = Pokemon.new(game.data, "RATTATA", 5)
  fainted.hp = 0
  game.save.party = { Pokemon.new(game.data, "MEW", 50), fainted }
  local battle = BattleState.newWild(game, "PIDGEY", 3)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)
  for _ = 1, 120 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  local pm
  for _ = 1, 20 do
    local top = game.stack:top()
    if top and top.onSwitch ~= nil and top.index ~= nil then pm = top break end
    U.tap(game, "right"); U.wait(6)
    U.tap(game, "a"); U.wait(14)
  end
  check(pm ~= nil, "battle party menu open")
  if pm then
    U.tap(game, "down"); U.wait(6)
    U.tap(game, "a"); U.wait(8)
    U.tap(game, "up"); U.wait(4)
    check(pm.subIndex == 1, "submenu up from SWITCH does not wrap")
    U.tap(game, "a"); U.wait(90)
    check(pm.subEdge ~= nil, "no-will refusal keeps the submenu edge")
    U.still(game, SHOTS .. "/2950_08_no_will_edge.png")
  end
  while game.stack:top() ~= game.overworld do game.stack:pop() end

  love.event.quit(fails == 0 and 0 or 1)
end
