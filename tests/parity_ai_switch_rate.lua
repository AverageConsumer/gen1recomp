-- Parity test: the per-class trainer switch rolls (#890).
--
-- Reports keep landing that Jugglers and Agatha "never switch".  The rolls
-- are exact byte compares in pokered, so they are machine-assertable: sweep
-- every one of the 256 random bytes through TrainerAI.classAction and count
-- the switch outcomes.
--
--   JugglerAI (engine/battle/trainer_ai.asm:324-327)
--     cp 25 percent + 1 / ret nc / jp AISwitchIfEnoughMons
--     `percent` is `* $ff / 100` (macros/data.asm:3), so the threshold is
--     25 * 255 / 100 + 1 = 64 and the switch fires on rolls 0..63.
--   AgathaAI (engine/battle/trainer_ai.asm:429-437)
--     cp 8 percent / jp c, AISwitchIfEnoughMons -> 8 * 255 / 100 = 20, so
--     rolls 0..19 switch; the SAME byte then feeds cp 50 percent + 1 = 128
--     for the SUPER POTION branch, which is why the two outcomes partition
--     the byte range instead of rolling twice.
--
-- Self-contained; run via `luajit tests/parity_ai_switch_rate.lua`.
-- Also picked up by tests/run_tests.lua's parity_* glob.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.RATTATA) then Data:load() end

local Pokemon = require("src.pokemon.Pokemon")
local TrainerAI = require("src.battle.TrainerAI")
local BattleState = require("src.battle.BattleState")
local S = require("tests.harness").suite("parity ai switch rate")
local check, eq = S.check, S.eq

-- Just the fields classAction reads: the class lookup goes through
-- trainer.id, the HP fraction through enemy.mon, the reserve scan through
-- enemyParty/enemyIndex.  hpFrac is current/max for the item branches.
local function stubBattle(id, roll, hpFrac)
  local maxHp = 100
  return {
    kind = "trainer", trainer = { id = id, name = id }, data = Data,
    aiUses = 3,
    enemy = { mon = { hp = math.floor(maxHp * hpFrac), stats = { hp = maxHp } },
              stages = {}, name = "MON" },
    enemyParty = { { hp = maxHp }, { hp = maxHp }, { hp = maxHp } },
    enemyIndex = 1,
    rng = function() return roll end,
  }
end

-- Sweep the whole byte range: the counts ARE the thresholds.
local function sweep(id, hpFrac)
  local switches, items = 0, 0
  for roll = 0, 255 do
    local act = TrainerAI.classAction(stubBattle(id, roll, hpFrac))
    if act and act.special == "aiSwitch" then switches = switches + 1
    elseif act and act.special == "aiItem" then items = items + 1 end
  end
  return switches, items
end

do
  local sw, it = sweep("OPP_JUGGLER", 1.0)
  eq(sw, 64, "Juggler switches on 64 of 256 rolls (cp 25 percent + 1)")
  eq(it, 0, "Juggler never reaches for an item")
  local swLow = sweep("OPP_JUGGLER", 0.05)
  eq(swLow, 64, "the Juggler roll does not depend on the enemy's HP")
end

do
  -- above 1/4 max HP the item branch is refused, so only the switch fires
  local sw, it = sweep("OPP_AGATHA", 1.0)
  eq(sw, 20, "Agatha switches on 20 of 256 rolls (cp 8 percent)")
  eq(it, 0, "Agatha holds the SUPER POTION above 1/4 HP")
  -- below 1/4 the shared byte splits: 0..19 switch, 20..127 potion
  local swLow, itLow = sweep("OPP_AGATHA", 0.1)
  eq(swLow, 20, "the switch roll still wins the low rolls at low HP")
  eq(itLow, 108, "the same byte leaves 20..127 for the SUPER POTION")
end

-- AISwitchIfEnoughMons (engine/battle/trainer_ai.asm:554-582) counts every
-- unfainted party mon including the active one and needs 2 or more, so a
-- one-mon roster never switches however low the roll lands.
do
  local b = stubBattle("OPP_JUGGLER", 0, 1.0)
  b.enemyParty = { { hp = 100 } }
  check(TrainerAI.classAction(b) == nil,
        "a lone enemy mon never switches (cp 2 / jp nc)")
  local b2 = stubBattle("OPP_JUGGLER", 0, 1.0)
  b2.enemyParty = { { hp = 100 }, { hp = 0 }, { hp = 100 } }
  local act = TrainerAI.classAction(b2)
  check(act and act.index == 3,
        "the switch takes the first living reserve, skipping the fainted slot")
end

-- End to end through the real battle: the action a Juggler picks has to
-- reach executeAction and actually swap the active mon plus print
-- _AIBattleWithdrawText, otherwise a correct roll is invisible in play.
do
  local Game = {
    data = Data,
    save = { party = { Pokemon.new(Data, "BULBASAUR", 50) },
             player = { name = "RED" }, inventory = {},
             options = { battleStyle = "set" },
             pokedex = { seen = {}, owned = {} }, flags = {}, money = 0 },
    stack = { push = function() end, pop = function() end, top = function() end },
  }
  -- Juggler party 2 is the four-mon Victory Road roster
  local b = BattleState.newTrainer(Game, "OPP_JUGGLER", 2)
  eq(b.aiUses, 3, "wAICount seeded from the class record on send-out")
  b.rng = function(lo) return lo end -- roll 0: inside every threshold
  local act = b:enemyAction()
  check(act and act.special == "aiSwitch", "the enemy turn resolves to a switch")
  local outgoing = b.enemy.name
  b:executeAction(b.enemy, b.player, act)
  eq(b.enemyIndex, 2, "the active enemy slot moved to the reserve")
  check(b.enemy.name ~= outgoing, "a different mon is out")
  eq(b.aiUses, 3, "EnemySendOutFirstMon reseeds wAICount (core.asm:1305-1307)")
  local withdrew = false
  for _, item in ipairs(b.queue) do
    if item.text and item.text:find("with%-\ndrew") then withdrew = true end
  end
  check(withdrew, "_AIBattleWithdrawText is queued for the player to read")
end

S.finish()
