-- ../pokered/engine/battle/move_effects/substitute.asm:2-3, :47-55
-- ../pokered/engine/battle/animations.asm:1936-1973
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Timing = require("src.core.Timing")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

Data.moves.FIX_SUBSTITUTE = {
  id = "FIX_SUBSTITUTE", name = "FIX SUB", index = 164,
  power = 0, accuracy = 100, type = "NORMAL", pp = 10,
  effect = "SUBSTITUTE_EFFECT",
  anim = { seq = { { effect = "SE_SLIDE_MON_OFF" },
                   { subanim = 71, delay = 8 },
                   { effect = "SE_SUBSTITUTE_MON" } } },
}

local function newBattle(animations)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  save.options = save.options or {}
  save.options.animations = animations
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  battle.queue, battle.nextInsert = {}, 0
  return battle
end

local function indexOf(battle, pred)
  for i, item in ipairs(battle.queue) do
    if pred(item) then return i end
  end
  return nil
end

local function useSub(battle)
  battle.enemy.mon.hp = battle.enemy.mon.stats.hp
  battle:performMove(battle.enemy, battle.player,
                     { id = "FIX_SUBSTITUTE", pp = 10 })
end

for _, animations in ipairs({ true, false }) do
  local label = animations and "animations on" or "animations off"
  local battle = newBattle(animations)
  useSub(battle)

  T.check(battle.enemy.substituteHP ~= nil,
    label .. ": the substitute is up in RAM as soon as the effect runs")
  T.check(battle.enemy.substitutePending == true,
    label .. ": but the doll is not on screen yet")
  T.eq(battle:faintPicKind(battle.enemy), "pic",
    label .. ": faintPicKind still reports the mon's own pic")

  local used = indexOf(battle, function(it)
    return it.text and it.text:find("used", 1, true) ~= nil
  end)
  local wait = indexOf(battle, function(it)
    return it.wait == Timing.SUBSTITUTE_ENTRY
  end)
  local anim = indexOf(battle, function(it) return it.anim == "FIX_SUBSTITUTE" end)
  local fn = indexOf(battle, function(it) return it.fn ~= nil end)
  local said = indexOf(battle, function(it)
    return it.text and it.text:find("SUBSTITUTE!", 1, true) ~= nil
  end)

  T.check(used ~= nil, label .. ": the announcement is queued")
  T.check(wait ~= nil, label .. ": the 50-frame entry hold is queued")
  T.check(fn ~= nil, label .. ": the doll reveal is queued as an act row")
  T.check(said ~= nil, label .. ": _SubstituteText is queued")
  T.check(used < wait, label .. ": the hold follows the announcement")
  T.check(wait < fn, label .. ": the hold runs before the doll appears")
  T.check(fn < said, label .. ": the doll appears before _SubstituteText")
  if animations then
    T.check(anim ~= nil, label .. ": the move animation row is queued")
    T.check(wait < anim, label .. ": the hold runs before the animation")
    T.check(anim < fn, label .. ": the animation plays before the doll lands")
  else
    T.eq(anim, nil, label .. ": no move animation row, so no 30-frame hold")
  end

  battle.queue[fn].fn()
  T.eq(battle.enemy.substitutePending, nil,
    label .. ": running the act row puts the doll on screen")
  T.eq(battle:faintPicKind(battle.enemy), "doll",
    label .. ": and faintPicKind reports the doll")
end

do
  -- ../pokered/data/battle_anims/special_effect_pointers.asm:45
  local battle = newBattle(true)
  useSub(battle)
  battle.animAttackerIsPlayer = false
  local pf = battle:picFxFor(battle.enemy)
  pf.kind, pf.hidden = "slideOff", true
  battle:applyAnimEffect({ effect = "SE_SUBSTITUTE_MON" })
  T.eq(battle.enemy.substitutePending, nil,
    "SE_SUBSTITUTE_MON reveals the doll on its own")
  T.eq(pf.kind, nil, "AnimationShowMonPic clears the slide-off")
  T.eq(pf.hidden, nil, "AnimationShowMonPic unhides the pic slot")
end

do
  local battle = newBattle(true)
  useSub(battle)
  battle.animAttackerIsPlayer = false
  battle:applyAnimEffect({ effect = "SE_SLIDE_MON_OFF" })
  T.eq(battle:picFxFor(battle.enemy).kind, "slideOff",
    "the user still slides off under a pending substitute")
end

do
  for _, case in ipairs({ "already", "tooWeak" }) do
    local battle = newBattle(true)
    battle.enemy.mon.hp = battle.enemy.mon.stats.hp
    if case == "already" then
      battle.enemy.substituteHP = 10
    else
      battle.enemy.mon.hp = math.floor(battle.enemy.mon.stats.hp / 4) - 1
    end
    battle:performMove(battle.enemy, battle.player,
                       { id = "FIX_SUBSTITUTE", pp = 10 })
    T.check(indexOf(battle, function(it)
      return it.wait == Timing.SUBSTITUTE_ENTRY
    end) ~= nil, case .. ": the 50-frame hold is paid before the failure text")
    T.eq(battle.enemy.substitutePending, nil,
      case .. ": a failed substitute queues no doll reveal")
  end
end

T.finish("the substitute doll lands with its animation (#2030)")
