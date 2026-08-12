-- Public battle auxiliary actions are a narrow semantic entry point for tool
-- mods.  They run only at the same settled ordinary decision boundary as a
-- battle checkpoint, consume no FIGHT/PKMN/ITEM/RUN action, and receive no
-- live BattleState object.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("battle menu auxiliary action")
local Fixtures = require("tests.modkit").fixtures
local BattleState = require("src.battle.BattleState")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")

local Data = Fixtures.fresh()

local function makeGame(kind)
  local save = SaveData.newGame()
  save.meta.playthroughId = "battle-menu-playthrough"
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local overworld = {
    map = { id = save.player.map },
    player = { cellX = save.player.x, cellY = save.player.y, facing = save.player.facing },
    runner = { isRunning = function() return false end },
    parallelRunners = {}, pendingScripts = {}, parallelQueue = {}, scriptMoves = {},
  }
  local game = { data = Data, save = save, stack = stack }
  game.input = { wasPressed = function(_, button) return button == "start" end }
  game.overworld = overworld
  stack.states[1] = overworld
  local battle = kind == "trainer"
    and BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
    or BattleState.newWild(game, "FIXMON_B", 12)
  battle.phase, battle.queue = "menu", {}
  battle.checkpointOrigin = kind == "trainer"
    and { kind = "trainer_encounter", map = save.player.map, npcId = "TRAINER_1",
      trainerClass = "OPP_FIX_YOUNGSTER", partyIndex = 1, event = "EVENT_BEAT_TRAINER_1" }
    or { kind = "wild_encounter", map = save.player.map }
  battle.onFinish = function() end
  stack.states[2] = battle
  return game, battle
end

local oldHooks = Runtime.hooks
local hooks = Hooks.new()
Runtime.hooks = hooks

local game, battle = makeGame("wild")
local calls = 0
hooks:wrap("battle.menu_auxiliary", function(nextFn, liveGame, context)
  calls = calls + 1
  T.check(liveGame == game, "auxiliary action receives the live game")
  T.same(context, { kind = "wild" }, "auxiliary action receives only data-only battle context")
  return true
end, 0, "tool_fixture")

local originalIndex = battle.menuIndex
battle:update(1 / 60)
T.eq(calls, 1, "START reaches the public auxiliary action at a wild decision")
T.eq(battle.phase, "menu", "handled auxiliary action does not advance the battle")
T.eq(battle.menuIndex, originalIndex, "handled auxiliary action preserves cursor")
T.eq(#battle.queue, 0, "handled auxiliary action does not enqueue a turn")

hooks:removeOwner("tool_fixture")
local trainerGame, trainer = makeGame("trainer")
local trainerCalls = 0
hooks:wrap("battle.menu_auxiliary", function(_, liveGame, context)
  trainerCalls = trainerCalls + 1
  T.check(liveGame == trainerGame, "trainer action receives its live game")
  T.same(context, { kind = "trainer" }, "trainer context remains data-only")
  return true
end, 0, "trainer_fixture")
trainer:update(1 / 60)
T.eq(trainerCalls, 1, "START reaches the public auxiliary action at a trainer decision")
hooks:removeOwner("trainer_fixture")

local scriptedGame, scripted = makeGame("trainer")
scripted.checkpointOrigin = { kind = "script_battle", scriptId = "STORY_TEST", pc = 4 }
scripted.checkpointScriptContinuation = { kind = "script_battle" }
local scriptedCalls = 0
hooks:wrap("battle.menu_auxiliary", function(_, liveGame, context)
  scriptedCalls = scriptedCalls + 1
  T.check(liveGame == scriptedGame,
    "scripted action receives the live game without its runner")
  T.same(context, { kind = "trainer" },
    "supported scripted trainer context remains data-only")
  return true
end, 0, "scripted_fixture")
scripted:update(1 / 60)
T.eq(scriptedCalls, 1,
  "START reaches the public auxiliary action at a supported scripted decision")
hooks:removeOwner("scripted_fixture")

local unsafeGame, unsafe = makeGame("wild")
unsafe.phase = "messages"
local unsafeCalls = 0
hooks:wrap("battle.menu_auxiliary", function() unsafeCalls = unsafeCalls + 1 return true end,
  0, "unsafe_fixture")
unsafe:update(1 / 60)
T.eq(unsafeCalls, 0, "messages never expose the auxiliary action")
hooks:removeOwner("unsafe_fixture")

Runtime.hooks = oldHooks
T.finish()
