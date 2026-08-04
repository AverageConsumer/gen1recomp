-- Gen 1 Leech Seed drains right after the SEEDED mon's move, not in an
-- end-of-round sweep (#784): MainInBattleLoop calls
-- HandlePoisonBurnLeechSeed after every Execute*Move (core.asm:426-464),
-- and the drain plays the ABSORB animation from the healing side
-- (core.asm:506-517).  The port ran the whole residual sweep in
-- endOfTurn, after both sides had acted, and showed no drain animation.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
               stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  battle.rng = function() return 0 end -- every roll lands: moves always hit
  battle.enemyAction = function() return { id = "FIX_SCRATCH", pp = 35 } end
  -- the seeded foe moves first, so its drain is observable mid-turn
  battle.enemy.curStats.speed = 200
  battle.player.curStats.speed = 1
  return battle
end

-- consume the queue the way updateQueue does, minus the presentation;
-- keeps the text and anim rows in order
local function drain(battle)
  local rows = {}
  for _ = 1, 400 do
    local item = table.remove(battle.queue, 1)
    if not item then return rows end
    if item.text then rows[#rows + 1] = { text = item.text } end
    if item.anim then
      rows[#rows + 1] = { anim = item.anim,
                          attackerIsPlayer = item.attackerIsPlayer }
    end
    if item.fn then
      battle.nextInsert = 0
      item.fn()
    end
  end
  error("the turn queue never drained")
end

local function indexOf(rows, pred)
  for i, row in ipairs(rows) do
    if pred(row) then return i end
  end
  return nil
end

local function saidWith(rows, needle)
  return indexOf(rows, function(r)
    return r.text and r.text:find(needle, 1, true) ~= nil
  end)
end

-- ---------------------------------------------------------------------
-- the seeded foe is faster: its drain lands between the two moves
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.enemy.leechSeeded = true
  battle:resolveTurn({ id = "FIX_TACKLE", pp = 35 })
  local rows = drain(battle)

  local scratchIdx = saidWith(rows, "FIX SCRATCH")
  local seedIdx = saidWith(rows, "LEECH SEED")
  local tackleIdx = saidWith(rows, "FIX TACKLE")
  T.check(scratchIdx ~= nil, "the foe's move announces")
  T.check(seedIdx ~= nil, "the drain announces")
  T.check(tackleIdx ~= nil, "the player's move announces")
  T.check(scratchIdx < seedIdx,
    "the drain comes right after the seeded mon's move")
  T.check(seedIdx < tackleIdx,
    "and before the slower mon acts, not at end of round")

  local animIdx = indexOf(rows, function(r) return r.anim == "ABSORB" end)
  T.check(animIdx ~= nil, "the drain plays the ABSORB animation")
  T.check(animIdx ~= nil and rows[animIdx].attackerIsPlayer == true,
    "played from the healing side (hWhoseTurn flipped)")
  T.check(animIdx ~= nil and animIdx > seedIdx and animIdx < tackleIdx,
    "and it rides with the drain, between the two moves")
end

-- ---------------------------------------------------------------------
-- a seeded foe at 1 HP faints to its own drain right after moving:
-- the slower player never gets a move that turn (core.asm:426-429)
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.enemy.leechSeeded = true
  battle.enemy.mon.hp = 1
  battle:resolveTurn({ id = "FIX_TACKLE", pp = 35 })
  local rows = drain(battle)

  T.check(saidWith(rows, "FIX SCRATCH") ~= nil, "the foe still moves first")
  T.check(saidWith(rows, "LEECH SEED") ~= nil, "the drain still runs")
  T.eq(battle.enemy.mon.hp, 0, "the drain faints the seeded foe")
  T.check(saidWith(rows, "FIX TACKLE") == nil,
    "the slower mon never moves after the residual faint")
  T.eq(battle.result, "win", "and the battle is decided there and then")
end

-- ---------------------------------------------------------------------
-- the modern ruleset keeps the Gen 3+ end-of-round sweep, with no
-- mid-turn drain animation
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.ruleset = require("src.battle.rulesets.modern_clean")
  battle.enemy.leechSeeded = true
  battle:resolveTurn({ id = "FIX_TACKLE", pp = 35 })
  local rows = drain(battle)

  local scratchIdx = saidWith(rows, "FIX SCRATCH")
  local seedIdx = saidWith(rows, "LEECH SEED")
  local tackleIdx = saidWith(rows, "FIX TACKLE")
  T.check(scratchIdx ~= nil and tackleIdx ~= nil and seedIdx ~= nil,
    "all three beats still happen under the modern ruleset")
  T.check(scratchIdx < tackleIdx and tackleIdx < seedIdx,
    "but the drain waits for the end of the round")
  T.check(indexOf(rows, function(r) return r.anim == "ABSORB" end) == nil,
    "and no mid-turn drain animation is queued")
end

-- ---------------------------------------------------------------------
-- an item turn spends the player's move but its residual still ticks
-- (ExecutePlayerMove rets early on wActionResultOrTookBattleTurn and
-- MainInBattleLoop calls HandlePoisonBurnLeechSeed anyway)
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.player.mon.status = "PSN"
  battle:itemUsed({})
  local rows = drain(battle)

  local scratchIdx = saidWith(rows, "FIX SCRATCH")
  local poisonIdx = saidWith(rows, "hurt by poison")
  T.check(scratchIdx ~= nil and poisonIdx ~= nil,
    "the foe moves and the poison ticks on an item turn")
  T.check(scratchIdx < poisonIdx, "the tick lands right after the foe's move")
end

T.finish("leech seed drain timing (#784)")
