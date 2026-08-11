package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 mod battle api")
local check, eq = S.check, S.eq

local player = { species = "CHIKORITA", level = 5, hp = 20,
  maxHp = 21, moves = { { id = "TACKLE", pp = 35, maxPp = 35 } } }
local enemy = { species = "RATTATA", level = 3, hp = 12, maxHp = 12,
  moves = {} }
local battle = { player = player, enemy = enemy, party = { player },
  wild = true, turn = 0 }
function battle:moveDisabled() return false end
function battle:takeTurn(action)
  self.lastAction = action
  self.turn = self.turn + 1
  return {}
end

local screen = { screenId = "Gen2BattleState", battle = battle,
  phase = "menu", menuIndex = 1, moveIndex = 1 }
function screen:submit(action)
  self.phase = "resolving"
  self.battle:takeTurn(action)
end
local game = {
  data = { pokemon = {
    CHIKORITA = { name = "CHIKORITA" }, RATTATA = { name = "RATTATA" },
  }, moves = { TACKLE = { name = "TACKLE", type = "NORMAL",
    power = 35, accuracy = 95, pp = 35 } } },
  save = { party = { player } },
  stack = { states = { screen } },
}

local api = require("src.battle.gen2.BattleAPI").new(game, "test")
local snapshot = api:snapshot()
check(snapshot and snapshot.kind == "wild" and snapshot.prompt == "menu",
  "Gold battle is discovered through its screen id")
eq(snapshot.player.maxHp, 21, "Gold max HP uses the mon field")
eq(snapshot.moves[1].name, "TACKLE", "Gold moves are copied")

check(api:submit({ id = 1, revision = snapshot.revision, kind = "fight" }),
  "fight opens the Gold move menu")
eq(screen.phase, "moves", "Gold screen owns the phase transition")
local moves = api:snapshot()
local ok, err = api:submit({ id = 2, revision = snapshot.revision,
  kind = "move", slot = 1 })
check(not ok and err == "stale battle context", "stale Gold intent rejected")
check(api:submit({ id = 2, revision = moves.revision,
  kind = "move", slot = 1 }), "fresh Gold move accepted")
eq(battle.lastAction.move, "TACKLE", "Gold battle receives the move id")

screen.phase = "moves"
local back = api:snapshot()
check(api:submit({ id = 3, revision = back.revision, kind = "back" }),
  "back closes the Gold move menu")
eq(screen.phase, "menu", "Gold move menu returns to root")

S.finish()
