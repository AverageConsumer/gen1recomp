-- audio/engine_2.asm:259
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity move sfx channel end #2969")
local check = S.check

local ChipSynth = require("src.core.ChipSynth")

local function readAll(path, mode)
  local f = io.open(path, mode or "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local audioChunk = loadfile("data/generated/audio.lua")
local movesChunk = loadfile("data/generated/moves.lua")
local bytes = readAll("assets/generated/audio/programs.bin", "rb")
if not (audioChunk and movesChunk and bytes) then
  print("[skip] parity_move_sfx_channel_end_2969: no ROM cache")
  os.exit(0)
end
local audio = audioChunk()
audio.programBytes = bytes
local data = { audio = audio, moves = movesChunk() }
ChipSynth.invalidateBanks()

local function rendered(def, options)
  local engine = ChipSynth.newEngine(data, def, options)
  local ran, cap = 0, ChipSynth.SAMPLE_RATE * 20
  while ran < cap and not engine:finished() do
    ran = ran + 1
    engine:sample()
  end
  return ran * 60 / ChipSynth.SAMPLE_RATE
end

local savedRate = ChipSynth.SAMPLE_RATE
ChipSynth.setSampleRate(8000)
for _, case in ipairs({
  { "PSYBEAM", { [5] = 143, [6] = 131, [8] = 126 } },
  { "THUNDERBOLT", { [5] = 72, [6] = 90, [8] = 90 } },
  { "KARATE_CHOP", { [8] = 32 } },
}) do
  local move, want = case[1], case[2]
  local anim = data.moves[move].anim
  local def = audio.sfx[anim.sound]
  local function options()
    return { sfx = true, allowLoops = false,
             frequencyOffset = anim.pitch or 0,
             frameTicks = 0x80 + (anim.tempo or 0x80) }
  end
  local frames = ChipSynth.effectChannelFrames(data, def, options())
  local longest = 0
  for ch, n in pairs(want) do
    check(frames and frames[ch] and math.abs(frames[ch] - n) < 1,
      ("%s: CHAN%d clears its sound id after %d frames (got %s)"):format(
        move, ch, n, tostring(frames and frames[ch])))
    if n > longest then longest = n end
  end
  local whole = rendered(def, options())
  check(whole >= longest,
    ("%s: the rendered source (%.1f) is not shorter than its longest channel"):format(
      move, whole))
end
ChipSynth.setSampleRate(savedRate)
ChipSynth.invalidateBanks()

S.finish()
