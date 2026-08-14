package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("mod battle api")
local check, eq = S.check, S.eq

local mon = { species = "TESTMON", level = 5, hp = 18,
  stats = { hp = 20 }, moves = {} }
local game = { data = { pokemon = { TESTMON = { name = "TESTMON" } },
  moves = {}, items = {} }, save = { party = { mon }, inventory = {} },
  input = { pressQueue = {} }, stack = { states = {} } }
function game.stack:pop() return table.remove(self.states) end

local battle = { isBattleState = true, phase = "menu", queue = {},
  player = { mon = mon, curMoves = {}, curTypes = { "NORMAL" } },
  enemy = { mon = { species = "TESTMON", level = 4, hp = 12,
    stats = { hp = 12 }, moves = {} }, curTypes = { "NORMAL" } } }
function battle:battleKind() return "wild" end
function battle:chooseMenu(choice)
  if choice == "fight" then self.phase = "moveSelect" end
  return true
end
function battle:chooseMove(slot)
  self.chosen, self.phase = slot, "messages"
  return true
end
function battle:cancelMove() self.phase = "menu" return true end
game.stack.states = { battle }

local api = require("src.battle.BattleAPI").new(game, "test")
local root = api:snapshot()
check(root and root.kind == "wild" and root.prompt == "menu",
  "Gen 1 battle is exposed as a copied snapshot")
eq(root.player.maxHp, 20, "Gen 1 max HP comes from battle stats")
check(api:submit({ id = 1, revision = root.revision, kind = "fight" }),
  "Gen 1 semantic menu intent accepted")
local moves = api:snapshot()
check(api:submit({ id = 2, revision = moves.revision,
  kind = "move", slot = 1 }), "Gen 1 semantic move intent accepted")
eq(battle.chosen, 1, "Gen 1 battle validates the selected slot")

S.finish()
