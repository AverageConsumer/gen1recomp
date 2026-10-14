-- engine/battle/link_battle_versus_text.asm:2
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/2957"
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local LinkState = require("src.link.LinkState")
  local LinkBattle = require("src.link.LinkBattle")
  local Net = require("src.link.Net")
  local Session = require("src.link.Session")

  local failed = false
  local function check(ok, label)
    U.log((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(5)
  local mine = { Pokemon.new(game.data, "KADABRA", 30), Pokemon.new(game.data, "PIKACHU", 20) }
  local theirs = { Pokemon.new(game.data, "HAUNTER", 30), Pokemon.new(game.data, "RATTATA", 20),
                   Pokemon.new(game.data, "GRAVELER", 30) }
  local a = Net.loopbackPair()
  local net = Session.new(a, { role = "host", kind = "link" })
  local battle = LinkBattle.newHost(game, net, {
    myParty = Protocol.packParty(mine), theirParty = Protocol.packParty(theirs),
    theirName = "BERT", seed = 7, verdict = "full", cable = true,
  })
  check(battle ~= nil, "link_battle_built")
  battle.enemyParty[2].hp = 0
  local vs = LinkState.versus(game, battle)
  game.stack:push(vs)
  U.wait(20)
  U.still(game, DIR .. "/2957_08_versus_box.png")
  check(game.stack:top() == vs, "versus_box_holds")
  for _ = 1, 200 do
    if game.stack:top() ~= vs then break end
    U.wait(1)
  end
  check(game.stack:top() ~= vs, "versus_box_closes_itself")

  local res = LinkState.versus(game, battle, "win")
  game.stack:push(res)
  for _ = 1, 400 do
    if res.t >= 160 or game.stack:top() ~= res then break end
    U.wait(1)
  end
  U.still(game, DIR .. "/2957_09_you_win.png")
  check(game.stack:top() == res and res.t >= 150, "result_box_shows_after_versus")
  net:close()
  love.event.quit(failed and 1 or 0)
end
