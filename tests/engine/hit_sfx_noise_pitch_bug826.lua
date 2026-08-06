-- The battle hit sounds must carry pokered's wFrequencyModifier onto the
-- noise channel (#826; #902 reports the same swap).  PlayApplyingAttackSound
-- (engine/battle/animations.asm) picks SFX_DAMAGE / SFX_SUPER_EFFECTIVE /
-- SFX_NOT_VERY_EFFECTIVE off wDamageMultipliers and writes a frequency
-- modifier with it ($20 / $e0 / $50), and Audio2_ApplyFrequencyModifier adds
-- that to the polynomial-counter byte -- the low byte of NR43 -- with 8-bit
-- wrap (audio/engine_2.asm).  The three programs are CHAN8-only, so that byte
-- IS their pitch.  Dropped, the super effective hit reads as the duller of
-- the two: super effective's tail (shifts 3 then 6) sits below not very
-- effective's (5, 4, 2, 2), which is exactly the "swapped" sound #826 and
-- #902 describe.  With the modifier on, super effective goes to shifts 1/4 --
-- a bright crack -- and not very effective to 10/9/7/7 -- a dull thud.
--
-- ROM-free: ChipAsm blobs stand in for the sfx headers, so nothing here
-- reads data/generated/.  The noise-note streams below are transcribed from
-- audio/sfx/{damage,super_effective,not_very_effective}.asm, so the "sounds
-- swapped when bare" ordering is asserted against the real program shape.
--   luajit tests/engine/hit_sfx_noise_pitch_bug826.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

love = require("tests.love_stub")

local ChipAsm = require("src.audio.ChipAsm")
local ChipSynth = require("src.core.ChipSynth")

local data = { audio = {} }

-- noise_note len, volume, fade, parameter  (the asm streams, verbatim)
local HITS = {
  {
    name = "Damage",
    pitch = 0x20,
    notes = {
      { len = 2,  parameter = 0x44 },
      { len = 2,  parameter = 0x14 },
      { len = 15, parameter = 0x32 },
    },
    want = { 0x64, 0x34, 0x52 },
  },
  {
    name = "Super_Effective",
    pitch = 0xe0,
    notes = {
      { len = 4,  parameter = 0x34 },
      { len = 15, parameter = 0x64 },
    },
    want = { 0x14, 0x44 },
  },
  {
    name = "Not_Very_Effective",
    pitch = 0x50,
    notes = {
      { len = 4,  parameter = 0x55 },
      { len = 2,  parameter = 0x44 },
      { len = 8,  parameter = 0x22 },
      { len = 15, parameter = 0x21 },
    },
    want = { 0xa5, 0x94, 0x72, 0x71 },
  },
}

local function hitDef(notes)
  local program = {}
  for _, n in ipairs(notes) do
    program[#program + 1] = {
      noiseNote = { len = n.len, volume = 15, fade = 1, parameter = n.parameter },
    }
  end
  return ChipAsm.sfx{ channels = { { hw = 4, program = program } } }
end

-- every noise note the program emits, as { parameter, duration }, walking
-- one event at a time by marking each consumed
local function noiseNotes(def, offset)
  local engine = ChipSynth.newEngine(data, def, {
    sfx = true, allowLoops = false, frequencyOffset = offset,
  })
  local channel = assert(engine.channels[1], "hit sfx uses exactly CHAN8")
  local out = {}
  while not engine:finished() do
    channel:sample()
    local event = channel.event
    if not event then break end
    if event.noiseParameter ~= nil then
      out[#out + 1] = { parameter = event.noiseParameter, duration = event.duration }
    end
    event.sample = event.samples -- force the walk on to the next event
  end
  return out
end

-- NR43 shift-clock nibble, weighted by each note's on-air duration: the
-- number #826/#902 ears actually compare (higher = duller)
local function weightedShift(notes)
  local total, sum = 0, 0
  for _, n in ipairs(notes) do
    total = total + n.duration
    sum = sum + math.floor(n.parameter / 16) * n.duration
  end
  return total > 0 and sum / total or 0
end

local results = {}
for _, hit in ipairs(HITS) do
  local def = hitDef(hit.notes)
  local bare = noiseNotes(def, 0)
  local pitched = noiseNotes(def, hit.pitch)
  results[hit.name] = { bare = bare, pitched = pitched }
  check(#bare == #hit.notes,
    hit.name .. " program emits " .. #hit.notes .. " notes, not " .. #bare)
  for i, n in ipairs(hit.notes) do
    check(bare[i] and bare[i].parameter == n.parameter,
      ("%s note %d reads NR43 $%02x unmodified"):format(hit.name, i, n.parameter))
    check(pitched[i] and pitched[i].parameter == hit.want[i],
      ("%s note %d reads NR43 $%02x once $%02x is applied"):format(
        hit.name, i, hit.want[i], hit.pitch))
  end
end

-- the ordering that IS the bug: unpitched, super effective ends duller than
-- not very effective, so they sound swapped; pitched, the bright crack lands
-- on super effective and the dull thud on not very effective
local superBare = weightedShift(results.Super_Effective.bare)
local nveBare = weightedShift(results.Not_Very_Effective.bare)
check(superBare > nveBare,
  ("bare, super effective (%.2f) reads duller than not very effective (%.2f)"):format(
    superBare, nveBare))
local superPitched = weightedShift(results.Super_Effective.pitched)
local nvePitched = weightedShift(results.Not_Very_Effective.pitched)
check(superPitched < nvePitched,
  ("pitched, super effective (%.2f) is the brighter hit, not very effective (%.2f) the duller"):format(
    superPitched, nvePitched))

-- the neutral hit shifts a shade duller than it used to be, per pokered
local damageBare = weightedShift(results.Damage.bare)
local damagePitched = weightedShift(results.Damage.pitched)
check(damagePitched > damageBare,
  ("the neutral hit dulls a little under $20 (%.2f -> %.2f)"):format(
    damageBare, damagePitched))

T.finish("hit sfx noise pitch (#826/#902)")
