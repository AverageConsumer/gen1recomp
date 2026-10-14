-- pokered/engine/battle/animations.asm:694
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local AnimPlayer = require("src.battle.AnimPlayer")
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local Sound = require("src.core.Sound")

local blocks = {}
for i = 1, 11 do blocks[i] = { block = "BALL", coord = "ARC", mode = i == 1 and 0 or 4 } end
local animData = {
  tilesheets = { [0] = { tiles = 79 } },
  moveAnims = {},
  subanims = { ARC = { type = "NORMAL", blocks = blocks } },
  frameBlocks = { BALL = { { x = 0, y = 0, tile = 2 } } },
  baseCoords = { ARC = { x = 60, y = 40 } },
  idEffects = {},
}
for _, id in ipairs({ "TOSS_ANIM", "GREATTOSS_ANIM", "ULTRATOSS_ANIM", "TACKLE" }) do
  animData.moveAnims[id] = { seq = { { subanim = "ARC", tileset = 0,
    delay = id == "ULTRATOSS_ANIM" and 2 or 3 } } }
end

for _, scenario in ipairs({
  { "TOSS_ANIM", "POKE_BALL", false, 14 },
  { "GREATTOSS_ANIM", "GREAT_BALL", false, 14 },
  { "ULTRATOSS_ANIM", "ULTRA_BALL", true, 13 },
  { "ULTRATOSS_ANIM", "SAFARI_BALL", false, 13 },
  { "TOSS_ANIM", "MASTER_BALL", true, 14 },
}) do
  local id, ball, flicker, expected = unpack(scenario)
  local p = AnimPlayer.new(animData)
  p:start(id, true, { ball = ball, ballFlicker = flicker })
  local sounds, last = 0, -1
  local function poll()
    for _, ev in ipairs(p:pollEffects()) do
      T.check(ev.frame >= last, ball .. " events remain chronological")
      last = ev.frame
      if ev.effect == "SFX_BALL_TOSS" then
        sounds = sounds + 1
        T.eq(p.elapsed, expected, ball .. " toss sound follows first block cleanup")
      end
    end
  end
  poll()
  for frame = 1, expected - 1 do
    p:update()
    poll()
    T.eq(sounds, 0, ball .. " has no premature sound at tick " .. frame)
  end
  T.eq(#p.steps[1].sprites, 0, ball .. " initial tile load is blank")
  T.eq(p.steps[2].sprites[1].obp, "f0", ball .. " first block uses normal palette")
  T.eq(p.steps[3].sprites[1].obp, flicker and "f0x" or "f0",
    ball .. " next block preserves palette flicker")
  p:update()
  poll()
  T.eq(sounds, 1, ball .. " sound occurs at the first block end")
  for _ = 1, 200 do
    if p:isDone() then break end
    p:update()
    poll()
  end
  T.check(p:isDone(), ball .. " animation terminates")
  T.eq(sounds, 1, ball .. " emits exactly one toss sound")
end

local unrelated = AnimPlayer.new(animData)
unrelated:start("TACKLE", true)
for _, ev in ipairs(unrelated.events) do
  T.neq(ev.effect, "SFX_BALL_TOSS", "unrelated move has no toss sound")
end

local realPlay = Sound.play
local heard = {}
Sound.play = function(_, id) heard[#heard + 1] = id end
local data = T.fixtures.fresh()
for _, ball in ipairs({ "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "SAFARI_BALL" }) do
  data.items[ball] = { name = ball }
end
local function battle()
  local game = {
    data = data,
    save = { player = { name = "RED" }, party = { Pokemon.new(data, "FIXMON_A", 20) },
      inventory = {}, options = { battleAnim = "on" }, flags = {},
      pokedex = { seen = {}, owned = {} } },
    stack = { top = function() end },
  }
  local b = BattleState.newWild(game, "FIXMON_B", 5)
  b.catchAttempt = function() return false, 0 end
  return b
end
for _, scenario in ipairs({ "wild", "trainer", "noCatch", "ghost", "oldMan", "safari" }) do
  local b = battle()
  if scenario == "trainer" then b.kind = "trainer" end
  if scenario == "noCatch" then b.noCatch = true end
  if scenario == "ghost" then b.ghost = true end
  heard = {}
  if scenario == "oldMan" then
    b:oldManThrow()
  elseif scenario == "safari" then
    b.safari = { balls = 30 }
    b:safariAction("ball")
  else
    b:throwBall("POKE_BALL")
  end
  local found
  for _ = 1, 20 do
    local row = table.remove(b.queue, 1)
    if not row then break end
    if row.fn then b.nextInsert = 0 row.fn() found = true break end
  end
  T.check(found, scenario .. " executes real throw setup callback")
  T.eq(#heard, 0, scenario .. " setup plays no eager toss sound")
  local toss
  for _, row in ipairs(b.queue) do
    if row.anim and row.anim:find("TOSS_ANIM", 1, true) then toss = row break end
  end
  T.check(toss ~= nil, scenario .. " still queues the toss animation")
  if scenario == "wild" or scenario == "oldMan" then
    T.eq(b.queue[1].wait, 20, scenario .. " keeps the original prethrow wait")
  end
  if toss then
    local p = AnimPlayer.new(animData)
    p:start(toss.anim, toss.attackerIsPlayer, { ball = toss.ball })
    for _ = 1, 200 do
      for _, ev in ipairs(p:pollEffects()) do b:applyAnimEffect(ev) end
      if p:isDone() then break end
      p:update()
    end
    T.eq(#heard, 1, scenario .. " routes one timeline sound to Sound.play")
    T.eq(heard[1], "Ball_Toss", scenario .. " preserves the real sound ID")
  end
end
Sound.play = realPlay

T.finish("ball toss sound synchronization 2611")
