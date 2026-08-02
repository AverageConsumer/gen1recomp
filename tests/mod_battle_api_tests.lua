package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("mod battle api")
local check, eq = S.check, S.eq

local visible = require("src.battle.BattleState").visibleText({
  phase = "messages", current = {}, lineIndex = 3,
  shown = { {}, {} }, lines = {
    { text = "OLD" }, { text = "TEST USED" }, { text = "TACKLE!" },
  },
})
eq(table.concat(visible, "|"), "TEST USED|TACKLE!",
  "battle text exposes the same rolling two-line window")
visible = require("src.render.TextBox").visibleText({
  pages = { { "FIRST", "SECOND", "THIRD" } }, pageIndex = 1,
  lineIndex = 3, shown = { {}, {} },
})
eq(table.concat(visible, "|"), "SECOND|THIRD",
  "overlay text exposes its current rolling two-line window")

local mon = {
  species = "TESTMON", level = 5, hp = 18, status = nil,
  stats = { hp = 20 }, moves = {},
}
local game = {
  data = {
    pokemon = { TESTMON = { name = "TESTMON" } },
    moves = {}, items = {},
  },
  save = { party = { mon }, inventory = {} },
  input = { pressQueue = {} },
  stack = { states = {} },
}
function game.stack:top() return self.states[#self.states] end
function game.stack:pop() return table.remove(self.states) end
function game.stack:push(state) table.insert(self.states, state) end

local battle = {
  isBattleState = true,
  game = game,
  phase = "menu",
  queue = {},
  player = { mon = mon, curMoves = {}, curTypes = { "NORMAL" } },
  enemy = {
    mon = { species = "TESTMON", level = 4, hp = 12,
            stats = { hp = 12 }, moves = {} },
    curTypes = { "NORMAL" },
  },
}
function battle:battleKind() return self.kindOverride or "wild" end
function battle:chooseMenu(choice)
  if self.phase ~= "menu" then return nil, "wrong phase" end
  if choice == "fight" then self.phase = "moveSelect" end
  return true
end
function battle:chooseMove(slot)
  if self.phase ~= "moveSelect" then return nil, "wrong phase" end
  self.chosen = slot
  self.phase = "messages"
  return true
end
function battle:cancelMove()
  self.phase = "menu"
  return true
end
game.stack.states = { battle }

local api = require("src.battle.BattleAPI").new(game, "test_mod")
local first = api:snapshot()
eq(first.prompt, "menu", "snapshot exposes only the current semantic prompt")
function battle:visibleText()
  if self.phase == "messages" then return { "TEST USED", "TACKLE!" } end
end
battle.phase, battle.current, battle.msgPrompt = "messages", {}, true
local announced = api:snapshot()
eq(table.concat(announced.message, "|"), "TEST USED|TACKLE!",
  "snapshot copies the visible battle message")
battle.phase, battle.current, battle.msgPrompt = "menu", nil, nil
game.data.items.POKE_BALL = { name = "POKE BALL" }
game.save.inventory.POKE_BALL = 3
function battle:catchChance() return 37.5 end
local catchable = api:snapshot()
check(catchable.catchable and catchable.items[1].catchChance == 37.5,
  "wild snapshot exposes authoritative per-ball catch odds")
battle.ghost = true
local blocked = api:snapshot()
check(not blocked.catchable and blocked.items[1].catchChance == nil,
  "uncatchable encounters hide catch odds")
battle.ghost = nil
first = api:snapshot()
check(api:submit({ id = 1, revision = first.revision, kind = "fight" }),
      "current menu intent accepted")
eq(battle.phase, "moveSelect", "engine-owned menu transition ran")

local moves = api:snapshot()
local ok, err = api:submit({ id = 2, revision = first.revision,
                             kind = "move", slot = 1 })
check(not ok and err == "stale battle context", "stale intent rejected")
ok, err = api:submit({ id = 1, revision = moves.revision,
                       kind = "move", slot = 1 })
check(not ok and err == "duplicate intent", "duplicate intent id rejected")
check(api:submit({ id = 2, revision = moves.revision,
                   kind = "move", slot = 1 }),
      "fresh move intent accepted")
eq(battle.chosen, 1, "semantic move reached battle validator")

battle.phase = "messages"
battle.current = { text = "Waiting" }
battle.msgPrompt = true
local waiting = api:snapshot()
eq(waiting.prompt, "advance", "waiting battle text is touch-controllable")
check(api:submit({ id = 3, revision = waiting.revision,
                   kind = "advance" }), "battle text advance accepted")
eq(game.input.pressQueue[1], "a", "advance uses the engine input path")

battle.current, battle.msgPrompt, battle.phase = nil, nil, "menu"
battle.kindOverride, battle.safari = "safari", { balls = 17 }
function battle:safariAction(action)
  self.safariChosen, self.phase = action, "messages"
end
local safari = api:snapshot()
check(safari.prompt == "safari" and safari.safariBalls == 17,
      "Safari exposes its native four-choice menu")
check(api:submit({ id = 4, revision = safari.revision,
                   kind = "safari", action = "rock" }),
      "Safari touch action reaches the engine")
eq(battle.safariChosen, "rock", "Safari action stays semantic")

battle.kindOverride, battle.safari, battle.phase = nil, nil, "mimicSelect"
game.data.moves.COPY_ME = { name = "COPY ME", pp = 10 }
battle.mimicMoves, battle.mimicIndex = { { slot = 2, id = "COPY_ME" } }, 1
function battle:chooseMimic(index)
  if self.phase ~= "mimicSelect" or not self.mimicMoves[index] then
    return nil, "invalid mimic slot"
  end
  self.mimicChosen, self.phase = index, "messages"
  return true
end
local mimic = api:snapshot()
check(mimic.prompt == "mimic" and mimic.mimicMoves[1].name == "COPY ME",
      "Mimic exposes the opponent move picker")
check(api:submit({ id = 5, revision = mimic.revision,
                   kind = "mimic", index = 1 }),
      "Mimic touch choice reaches the engine validator")
eq(battle.mimicChosen, 1, "Mimic chose the requested row")
battle.phase, battle.mimicMoves, battle.mimicIndex = "menu", nil, nil

local TypeChart = require("src.battle.TypeChart")
local MoveEffects = require("src.battle.MoveEffects")
game.data.type_chart = {
  matchups = {
    { attacker = "FIRE", defender = "GRASS", multiplier = 20 },
    { attacker = "GHOST", defender = "PSYCHIC", multiplier = 0 },
  },
  types = {},
}
TypeChart.load(game.data)
game.data.moves = {
  FIRE_HIT = { name = "FIRE HIT", type = "FIRE", power = 40,
    accuracy = 100, pp = 10, effect = "NO_ADDITIONAL_EFFECT" },
  FIXED = { name = "FIXED", type = "FIRE", power = 1,
    accuracy = 100, pp = 10, effect = "SPECIAL_DAMAGE_EFFECT" },
  COUNTER = { name = "COUNTER", type = "FIRE", power = 1,
    accuracy = 100, pp = 10, effect = "NO_ADDITIONAL_EFFECT" },
  GHOST_HIT = { name = "GHOST HIT", type = "GHOST", power = 20,
    accuracy = 100, pp = 10, effect = "NO_ADDITIONAL_EFFECT" },
  OHKO = { name = "OHKO", type = "NORMAL", power = 1,
    accuracy = 30, pp = 5, effect = "OHKO_EFFECT" },
}
battle.player.curMoves = {
  { id = "FIRE_HIT", pp = 10 }, { id = "FIXED", pp = 10 },
  { id = "COUNTER", pp = 10 }, { id = "GHOST_HIT", pp = 10 },
}
battle.player.stages = { accuracy = 0, evasion = 0 }
battle.enemy.stages = { accuracy = 0, evasion = 0 }
battle.enemy.curTypes = { "GRASS" }
battle.ruleset = { name = "gen1_faithful", oneIn256Miss = true }
function battle:effectRecord(effect) return MoveEffects.RECORDS[effect] end

local hints = api:snapshot().moves
eq(hints[1].effectiveness, 20, "ordinary hint uses the live type chart")
eq(hints[1].hitChance, 255 * 100 / 256,
   "faithful 100 percent move exposes the 1-in-256 miss")
eq(hints[2].effectiveness, 10,
   "fixed damage is neutral outside immunity")
eq(hints[2].displayPower, nil, "fixed damage hides meaningless base power")
eq(hints[3].effectiveness, nil, "Counter does not invent a type hint")

battle.player.curMoves[1] = { id = "OHKO", pp = 5 }
eq(api:snapshot().moves[1].hitChance, nil,
   "gated moves do not advertise an incomplete success percentage")
battle.player.curMoves[1] = { id = "FIRE_HIT", pp = 10 }

battle.enemy.curTypes = { "PSYCHIC" }
eq(api:snapshot().moves[4].effectiveness, 0,
   "type-chart quirks such as Ghost versus Psychic stay authoritative")
battle.ruleset = { name = "modern_clean", oneIn256Miss = false }
eq(api:snapshot().moves[1].hitChance, 100,
   "modern ruleset removes the 1-in-256 miss from the same preview path")

S.finish()
