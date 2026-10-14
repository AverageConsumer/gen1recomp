-- engine/link/cable_club.asm:682
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/2957"
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local LinkState = require("src.link.LinkState")
  local Net = require("src.link.Net")
  local Session = require("src.link.Session")
  local TradeAnim = require("src.ui.TradeAnim")

  local failed = false
  local function check(ok, label)
    U.log((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(5)
  game.save.party = {
    Pokemon.new(game.data, "SANDSHREW", 9),
    Pokemon.new(game.data, "PIDGEY", 7),
  }
  local peerParty = {
    Pokemon.new(game.data, "RATTATA", 8),
    Pokemon.new(game.data, "EKANS", 9),
  }

  local mine, theirs = Net.loopbackPair()
  local ls = LinkState.new(game)
  ls.net = Session.new(mine, { role = "guest", kind = "link" })
  ls.peerName = "MG"
  ls.verdict = "full"
  ls.isHost = false
  ls.stage = "trade"
  ls.trade = Protocol.TradeSession.new(game.data, game.save.party, { peerName = "MG" })
  ls.net:send(ls.trade:opening())
  ls:resetPickUi()
  game.stack:push(ls)
  local seen = {}
  local baseUpdateTrade = ls.updateTrade
  ls.updateTrade = function(self, input)
    baseUpdateTrade(self, input)
    if self.trade then seen[self.trade.stage] = true end
  end
  local endPhases = {}
  local baseTradeEnd = LinkState.tradeEnd
  LinkState.tradeEnd = function(...)
    local screen = baseTradeEnd(...)
    local baseUpdate = screen.update
    screen.update = function(self, ...)
      baseUpdate(self, ...)
      endPhases[self.phase] = true
    end
    return screen
  end

  local peer = Protocol.TradeSession.new(game.data, peerParty, { peerName = "RED" })
  theirs:send(peer:opening())
  local function pump()
    theirs:update()
    for _, msg in ipairs(theirs:poll()) do
      local reply = peer:handle(msg)
      if reply then theirs:send(reply) end
    end
    if peer.stage == "restart" then peer:reset() end
    if peer.stage == "done" then
      peer:apply(nil)
      theirs:send({ type = "tradeSync" })
      peer = Protocol.TradeSession.new(game.data, peerParty, { peerName = "RED" })
      theirs:send(peer:opening())
    end
  end
  local function step(n)
    for _ = 1, n or 1 do pump() U.wait(1) end
  end
  local function waitFor(cond, n)
    for _ = 1, n do
      if cond() then return true end
      step(1)
    end
    return cond()
  end
  local function tap(btn) pump() U.tap(game, btn) end

  waitFor(function() return ls.trade.stage == "picking" end, 120)
  tap("a") tap("right") tap("a")
  step(10)
  U.shot(game, DIR .. "/2957_01_waiting_trade_row.png")
  check(ls.waitRow and ls.pickChoice == 2 and ls.trade.stage == "waitPick",
        "trade_row_kept_while_waiting")

  theirs:send(peer:pick(1))
  check(waitFor(function() return ls.willText and ls.willText.arrow end, 400),
        "will_be_traded_text_waits_at_arrow")
  U.shot(game, DIR .. "/2957_02_will_be_traded.png")
  tap("a")
  check(waitFor(function() return ls.willText and ls.willText.done end, 200),
        "will_be_traded_text_finishes")
  step(2)
  U.shot(game, DIR .. "/2957_03_trade_cancel_menu.png")

  tap("down") tap("a")
  theirs:send(peer:confirm(true))
  step(5)
  U.shot(game, DIR .. "/2957_04_too_bad.png")
  check(seen.declined, "cancel_at_confirm_shows_too_bad")
  if peer.stage == "declined" then peer:reset() end
  check(waitFor(function() return ls.trade.stage == "picking" end, 150)
        and game.stack:top() == ls and ls.net:getStatus() ~= "closed",
        "too_bad_returns_to_the_list_still_linked")

  tap("down") tap("down") tap("a")
  step(5)
  U.shot(game, DIR .. "/2957_05_cancel_waiting.png")
  check(ls.cancelWaiting and ls.trade.stage == "waitPick", "cancel_waits_for_the_other_game")
  theirs:send(peer:pick(1))
  step(5)
  check(ls.trade.stage == "picking" and ls.side == "cancel" and game.stack:top() == ls,
        "one_sided_cancel_returns_to_the_list")

  tap("up") tap("a") tap("right") tap("a")
  theirs:send(peer:pick(1))
  waitFor(function() return ls.willText and ls.willText.arrow end, 400)
  tap("a")
  waitFor(function() return ls.willText and ls.willText.done end, 200)
  tap("a")
  theirs:send(peer:confirm(true))
  local sawWill = waitFor(function()
    local top = game.stack:top()
    return getmetatable(top) == TradeAnim and top.dialogText ~= nil
  end, 300)
  local anim = game.stack:top()
  check(sawWill and anim.phase == "will_trade", "guest_movie_opens_with_will_trade")
  U.still(game, DIR .. "/2957_06_guest_will_trade.png")

  for _ = 1, 3000 do
    if getmetatable(game.stack:top()) ~= TradeAnim then break end
    pump()
    U.tap(game, "start")
  end
  local ended = waitFor(function()
    local top = game.stack:top()
    return top and top.phase == "completed"
  end, 400)
  check(ended or endPhases.completed, "trade_completed_after_waiting")
  U.shot(game, DIR .. "/2957_07_trade_completed.png")
  check(waitFor(function()
    return game.stack:top() == ls and ls.trade.stage == "picking"
  end, 400), "next_round_reaches_the_list")
  check(game.save.party[2] and game.save.party[2].species == "RATTATA",
        "received_mon_appended")

  ls.net:close()
  love.event.quit(failed and 1 or 0)
end
