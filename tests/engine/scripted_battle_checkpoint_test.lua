-- Scripted story battles checkpoint a semantic row-list continuation. The
-- suspended Lua coroutine is deliberately never serialized.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local oldGetRandomState = love.math.getRandomState
local oldSetRandomState = love.math.setRandomState
local checkpointRng = "scripted-battle-rng"
love.math.getRandomState = function() return checkpointRng end
love.math.setRandomState = function(state) checkpointRng = state end

local T = require("tests.harness").suite("scripted battle checkpoints")
local BattleState = require("src.battle.BattleState")
local Checkpoint = require("src.core.Checkpoint")
local Fixtures = require("tests.modkit").fixtures
local GameMethods = require("src.core.Game")
local OverworldState = require("src.world.OverworldController")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local ScriptRunner = require("src.script.ScriptRunner")
local StateStack = require("src.core.StateStack")

local Data = Fixtures.fresh()

local function makeGame()
  local save = SaveData.newGame()
  save.meta.playthroughId = "script-battle-playthrough"
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  SaveData.validate(save, Data)
  save.player.map, save.player.x, save.player.y = "FIX_TOWN", 2, 3
  save.player.facing, save.player.surfing = "left", false

  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local game
  local ow = setmetatable({
    map = { id = "FIX_TOWN" },
    player = { cellX = 2, cellY = 3, facing = "left", surfing = false },
    parallelRunners = {}, pendingScripts = {}, parallelQueue = {}, scriptMoves = {},
  }, { __index = OverworldState })
  function ow:captureSave(target)
    target.player.map = self.map.id
    target.player.x, target.player.y = self.player.cellX, self.player.cellY
    target.player.facing, target.player.surfing = self.player.facing, false
  end
  function ow:pushBattle(battle) game.stack:push(battle) end
  function ow:afterBattle(result, battle)
    self.after = { result = result, battle = battle }
  end
  game = setmetatable({ data = Data, save = save, stack = stack, overworld = ow },
    { __index = GameMethods })
  function game:restoreCheckpointSave(loaded)
    self.save = loaded
    ow.map = { id = loaded.player.map }
    ow.player = {
      cellX = loaded.player.x, cellY = loaded.player.y,
      facing = loaded.player.facing, surfing = loaded.player.surfing and true or false,
    }
    ow.parallelRunners, ow.pendingScripts, ow.parallelQueue, ow.scriptMoves = {}, {}, {}, {}
    ow.runner = ScriptRunner.new(self, ow)
    self.stack.states = { ow }
  end
  stack.states[1] = ow
  ow.runner = ScriptRunner.new(game, ow)
  return game, ow
end

local rows = {
  { "start_battle", "trainer", "OPP_FIX_YOUNGSTER", 1 },
  { "set_flag", "EVENT_STORY_CONTINUED" },
}

local game, ow = makeGame()
ow.runner:run(rows)
local battle = game.stack:top()
T.check(getmetatable(battle) == BattleState,
  "script command starts the fixture trainer battle")
T.check(type(battle.checkpointOrigin) == "table"
    and battle.checkpointOrigin.kind == "script_battle",
  "script battle owns a semantic checkpoint continuation")
battle.phase, battle.queue = "menu", {}
battle.afterQueue, battle.introSlide = nil, nil
battle.player.shownHP, battle.player.shownStatus =
  battle.player.mon.hp, battle.player.mon.status
battle.enemy.shownHP, battle.enemy.shownStatus =
  battle.enemy.mon.hp, battle.enemy.mon.status
local scriptedCapability = Checkpoint.inspect(game)
T.same(scriptedCapability, {
  canCapture = true, canRestore = true, kind = "battle",
}, "settled scripted trainer decision is checkpoint-safe: "
  .. tostring(scriptedCapability.reason))

local origin = battle.checkpointOrigin
T.check(type(origin.script) == "table" and origin.pc == 1,
  "continuation records detached rows and the command program counter")
T.eq(origin.resumeCoroutine, nil,
  "continuation never exposes a coroutine or Lua execution stack")

local snapshot, captureCode, captureMessage = Checkpoint.capture(game)
T.check(snapshot and snapshot.kind == "battle",
  "scripted battle captures through the generic checkpoint API: "
    .. tostring(captureCode or captureMessage))
if snapshot then
  game.save.money = 1
  local restored, restoreCode, restoreMessage = Checkpoint.restore(game, snapshot)
  T.check(restored == true,
    "scripted battle reconstructs through the generic checkpoint API: "
      .. tostring(restoreCode or restoreMessage))
  local rebuilt = game.stack:top()
  T.check(rebuilt ~= battle and getmetatable(rebuilt) == BattleState,
    "scripted restore creates a fresh battle controller")
  T.same(Checkpoint.capture(game), snapshot,
    "scripted battle capture/restore/capture is a differential roundtrip")
end

-- Rebind the continuation on a freshly reconstructed overworld. Completing
-- the battle must replay the current command as an already-completed battle,
-- then execute the remaining story rows exactly once.
local restoredGame, restoredOw = makeGame()
local restoredBattle = BattleState.newTrainer(restoredGame,
  "OPP_FIX_YOUNGSTER", 1)
restoredBattle.checkpointOrigin = origin
T.check(restoredOw:restoreBattleContinuation(restoredBattle, origin) == true,
  "script continuation reconstructs without the old runner")
restoredBattle.onFinish("win")
T.check(restoredGame.save.flags.EVENT_STORY_CONTINUED == true,
  "restored battle resumes subsequent story progress")
T.same(restoredOw.after, { result = "win", battle = restoredBattle },
  "restored script battle uses the canonical afterBattle path")
T.check(not restoredOw.runner:isRunning(),
  "reconstructed continuation completes without a suspended runner")

-- Unsafe rows and opaque completion callbacks must stay fail-closed.
local unsafeGame, unsafeOw = makeGame()
local unsafeRows = {
  { "start_battle", "trainer", "OPP_FIX_YOUNGSTER", 1 },
}
unsafeRows.opaque = function() end
unsafeOw.runner:run(unsafeRows)
local unsafeBattle = unsafeGame.stack:top()
unsafeBattle.phase, unsafeBattle.queue = "menu", {}
T.eq(unsafeBattle.checkpointOrigin, nil,
  "non-data-only script arguments do not create a continuation")
T.eq(Checkpoint.inspect(unsafeGame).reason, "battle_origin_unsupported",
  "non-data-only scripted battle remains unavailable")

local callbackGame, callbackOw = makeGame()
callbackOw.runner:run(rows, { onDone = function() end })
local callbackBattle = callbackGame.stack:top()
callbackBattle.phase, callbackBattle.queue = "menu", {}
T.eq(callbackBattle.checkpointOrigin, nil,
  "opaque script completion callbacks are not guessed")
T.eq(Checkpoint.inspect(callbackGame).reason, "battle_origin_unsupported",
  "opaque scripted completion remains fail-closed")

local rivalGame, rivalOw = makeGame()
local rivalRows = {
  { "rival_battle", "OPP_FIX_YOUNGSTER", 1 },
  { "jump_if_false", "end" },
  { "set_flag", "EVENT_RIVAL_STORY_CONTINUED" },
}
rivalOw.runner:run(rivalRows)
local rivalBattle = rivalGame.stack:top()
local rivalOrigin = rivalBattle.checkpointOrigin
T.check(rivalOrigin and rivalOrigin.command == "rival_battle" and rivalOrigin.pc == 1,
  "wrapper battle records the wrapper command rather than skipping its tail")
local rivalResumeGame, rivalResumeOw = makeGame()
local rivalRestored = BattleState.newTrainer(rivalResumeGame,
  "OPP_FIX_YOUNGSTER", 1)
T.check(rivalResumeOw:restoreBattleContinuation(rivalRestored, rivalOrigin) == true,
  "rival wrapper continuation reconstructs")
rivalRestored.onFinish("win")
T.check(rivalResumeGame.save.flags.EVENT_RIVAL_STORY_CONTINUED == true,
  "rival wrapper and following branch execute exactly once after restore")

love.math.getRandomState = oldGetRandomState
love.math.setRandomState = oldSetRandomState
T.finish()
