-- Battle checkpoints are exposed only at a settled, reconstructable player
-- decision boundary. This suite is ROM-free and exercises the public engine
-- checkpoint capability against the fixture battle implementation.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("battle checkpoint boundary")
local Fixtures = require("tests.modkit").fixtures
local BattleState = require("src.battle.BattleState")
local Checkpoint = require("src.core.Checkpoint")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")

local Data = Fixtures.fresh()

local function makeGame(kind)
  kind = kind or "wild"
  local save = SaveData.newGame()
  save.meta.playthroughId = "battle-playthrough"
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local overworld = {
    map = { id = save.player.map },
    player = {
      cellX = save.player.x, cellY = save.player.y,
      facing = save.player.facing, surfing = false,
    },
    runner = { isRunning = function() return false end },
    parallelRunners = {}, pendingScripts = {}, parallelQueue = {}, scriptMoves = {},
  }
  function overworld:captureSave(progress)
    progress.player.map = self.map.id
    progress.player.x = self.player.cellX
    progress.player.y = self.player.cellY
    progress.player.facing = self.player.facing
  end
  local game = { data = Data, save = save, stack = stack, overworld = overworld }
  stack.states[1] = overworld
  local battle = kind == "trainer"
    and BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
    or BattleState.newWild(game, "FIXMON_B", 12)
  battle.phase = "menu"
  battle.queue = {}
  battle.checkpointOrigin = kind == "trainer"
    and { kind = "trainer_encounter", map = save.player.map,
      npcId = "TRAINER_1", trainerClass = "OPP_FIX_YOUNGSTER", partyIndex = 1,
      event = "EVENT_BEAT_TRAINER_1" }
    or { kind = "wild_encounter" }
  battle.onFinish = function() end
  stack.states[2] = battle
  return game, overworld, battle
end

local game, overworld, battle = makeGame()
T.same(Checkpoint.inspect(game), {
  canCapture = true, canRestore = true, kind = "battle",
}, "settled standard wild battle is a checkpoint boundary")

local function settleRealBattle(kind)
  local liveGame, _, liveBattle = makeGame(kind)
  liveBattle.phase, liveBattle.queue = nil, {}
  liveGame.input = {
    wasPressed = function(_, button) return button == "a" end,
    isDown = function(_, button) return button == "a" end,
  }
  liveBattle:enter()
  local frames = 0
  while liveBattle.phase ~= "menu" and frames < 10000 do
    frames = frames + 1
    liveBattle:update(1 / 60)
  end
  T.eq(liveBattle.phase, "menu", "the real battle intro reaches its command menu")
  return liveGame
end

local realGame = settleRealBattle("wild")
T.same(Checkpoint.inspect(realGame), {
  canCapture = true, canRestore = true, kind = "battle",
}, "the completed real battle intro is a checkpoint boundary")
local oldGetRandomState, oldSetRandomState =
  love.math.getRandomState, love.math.setRandomState
love.math.getRandomState = function() return "real-boundary-rng" end
love.math.setRandomState = function() end
local realSnapshot, realCaptureCode = Checkpoint.capture(realGame)
T.check(type(realSnapshot) == "table" and realSnapshot.kind == "battle",
  "the first real command decision captures for deferred tools: "
    .. tostring(realCaptureCode))
love.math.getRandomState, love.math.setRandomState =
  oldGetRandomState, oldSetRandomState
local realTrainerGame = settleRealBattle("trainer")
T.same(Checkpoint.inspect(realTrainerGame), {
  canCapture = true, canRestore = true, kind = "battle",
}, "the completed real trainer intro is a checkpoint boundary")

local function refused(mutator, code, label)
  local game2, ow2, battle2 = makeGame()
  mutator(game2, ow2, battle2)
  local capability = Checkpoint.inspect(game2)
  T.check(capability.canCapture == false and capability.reason == code,
    label .. ": " .. tostring(capability.reason))
end

refused(function(_, _, b) b.phase = "messages" end,
  "battle_phase_busy", "message phase is rejected")
refused(function(_, _, b) b.queue = { { text = "busy" } } end,
  "battle_phase_busy", "nonempty action queue is rejected")
refused(function(_, _, b) b.waitFrames = 1 end,
  "battle_phase_busy", "partial wait is rejected")
refused(function(_, _, b) b.enemy.mon.hp = b.enemy.mon.hp - 1 end,
  "battle_phase_busy", "unfinished HP display synchronization is rejected")
refused(function(_, _, b) b.player.mustRecharge = true end,
  "battle_phase_busy", "automatic locked action is rejected")
refused(function(_, ow) ow.runner = { isRunning = function() return true end } end,
  "script_busy", "unknown suspended script beneath battle is rejected")
refused(function(_, _, b) b.checkpointOrigin = nil end,
  "battle_origin_unsupported", "unknown completion closure is rejected")
refused(function(_, _, b) b.safari = { balls = 30, steps = 10 } end,
  "battle_variant_unsupported", "Safari battle is rejected")
refused(function(_, _, b) b.ghost = true end,
  "battle_variant_unsupported", "ghost battle is rejected")
refused(function(_, _, b) b.demo = true end,
  "battle_variant_unsupported", "old-man demo is rejected")
refused(function(_, _, b) b.kind = "link" end,
  "link_battle_unsupported", "link battle is rejected")

-- Ordinary overworld behavior remains unchanged by the battle branch.
game.stack.states[2] = nil
T.same(Checkpoint.inspect(game), {
  canCapture = true, canRestore = true, kind = "overworld",
}, "settled overworld remains supported")

T.finish()
