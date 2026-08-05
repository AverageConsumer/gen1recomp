-- Animation-row SFX must obey PlaySound's channel-occupancy gate (#844).
--
-- Blizzard's animation is two rows -- `battle_anim BLIZZARD, ...` then
-- `battle_anim HYDRO_PUMP, ...` (data/moves/animations.asm, BlizzardAnim) --
-- and PlaySubanimation issues a PlaySound for every row
-- (engine/battle/animations.asm, PlaySubanimation).  The extracted data and
-- the row timing are both faithful; what the port was missing is that the
-- original never actually starts that second sound.  Audio2_PlaySound's
-- .playSfx/.sfxChannelLoop (audio/engine_2.asm) walks the channels the new
-- sfx declares and, for each one already busy, does
-- `ld a,[wSoundID] / cp [hl] / jr z,.playChannel / jr c,.playChannel / ret`:
-- a channel held by a LOWER sound id aborts the whole request, while an
-- equal or lower id takes the channel over (and .playChannel resets the
-- channel, cutting the old sound off).  SFX_BATTLE_29 (BLIZZARD, CHAN5+8) is
-- still sounding when the HYDRO_PUMP row starts, and SFX_BATTLE_2A wants
-- CHAN5+6+8, so on hardware it is dropped outright.  Unguarded, the port
-- layered it and its watery tail outlived the animation.
--
-- Sound ids order by header address: `DEF \1 EQUS "((\2 - SFX_Headers_1) / 3)"`
-- (constants/music_constants.asm, music_const), so a def's `address` is the
-- comparable rank inside one engine bank -- which is what Sound.playMove
-- compares and what ChipSynth.effectChannels supplies the channel set for.
--
-- ROM-free: ChipAsm blobs stand in for the sfx headers, so nothing here
-- reads data/generated/.
--   luajit tests/engine/move_sfx_channel_gate_bug844.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

-- ------- love.audio stub
-- tests/love_stub carries no love.audio (headless suites never play), and
-- the gate reads Source:isPlaying on the previously accepted row sound.
-- These stub sources never finish on their own, which is exactly the
-- "previous sfx is still sounding" state a mid-animation row sees.
local sources = {}

local Source = {}
Source.__index = Source
function Source:play() self.playing = true; self.plays = self.plays + 1 end
function Source:stop() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:pause() self.playing = false end
function Source:setLooping(value) self.looping = value end
function Source:setVolume(value) self.volume = value end
function Source:setPitch(value) self.pitch = value end
function Source:setFilter() end
function Source:getDuration() return 1 end

love.audio = {
  newSource = function(what, mode)
    local src = setmetatable({
      file = what, mode = mode, plays = 0, playing = false,
    }, Source)
    sources[#sources + 1] = src
    return src
  end,
}

local ChipAsm = require("src.audio.ChipAsm")
local ChipSynth = require("src.core.ChipSynth")
local Sound = require("src.core.Sound")
local Runtime = require("src.mods.Runtime")

-- ------- sfx fixtures
-- One audible note per channel.  ChipAsm.sfx numbers effect channels hw+4,
-- so hw 1/2/4 assemble as CHAN5/CHAN6/CHAN8 -- the same software channels
-- the real sfx headers claim.  `address` is the sound-id rank and `engine`
-- names the bank the rank is comparable within.
local function sfxDef(address, hws)
  local channels = {}
  for _, hw in ipairs(hws) do
    local program
    if hw == 4 then
      program = { { noiseNote = { len = 8, volume = 15, fade = 1,
        parameter = 0x11 } } }
    else
      program = { { squareNote = { len = 8, volume = 15, fade = 1,
        frequency = 0x600 } } }
    end
    channels[#channels + 1] = { hw = hw, program = program }
  end
  local def = ChipAsm.sfx{ channels = channels }
  def.address, def.engine = address, 2
  return def
end

-- Battle_29 = CHAN5,8 at rank 16975; Battle_2A = CHAN5,6,8 at 16981.  The
-- ranks below are the same ordering, scaled small for readability.
local defs = {
  Blizzard_Sfx = sfxDef(100, { 1, 4 }),      -- SFX_BATTLE_29 shape
  HydroPump_Sfx = sfxDef(106, { 1, 2, 4 }),  -- SFX_BATTLE_2A shape
  Disable_Sfx = sfxDef(100, { 4 }),          -- SFX_BATTLE_1B shape: CHAN8
  Leer_Sfx = sfxDef(106, { 1, 2 }),          -- SFX_BATTLE_31 shape: CHAN5,6
  Loud_Sfx = sfxDef(106, { 1, 4 }),          -- a high-ranked incumbent
  Quiet_Sfx = sfxDef(100, { 1 }),            -- a lower id that takes over
  Unranked_Sfx = ChipAsm.sfx{ channels = { { hw = 1, program = {
    { squareNote = { len = 8, volume = 15, fade = 1, frequency = 0x600 } },
  } } } },                                   -- a mod def: no header address
}

local data = { audio = { sfx = defs, cries = {}, songs = {} } }

-- the gate is only observable through what actually started, so watch the
-- Runtime event the mod SDK exposes for exactly that
local savedEvents, savedHooks = Runtime.events, Runtime.hooks
local events = require("src.mods.Events").new()
Runtime.install(events, require("src.mods.Hooks").new())

local played = {}
events:on("sound.played", function(p) played[#played + 1] = p end, nil, "test")

local function reset()
  Sound.invalidate() -- also clears the tracked row sound
  for index = #sources, 1, -1 do sources[index] = nil end
  for index = #played, 1, -1 do played[index] = nil end
end

local function playMove(name)
  Sound.playMove(data, { sound = name, pitch = 0, tempo = 0x80 })
end

local function names()
  local out = {}
  for _, p in ipairs(played) do out[#out + 1] = p.name end
  return table.concat(out, ",")
end

-- ------- the channel sets the gate reads
eq(table.concat(ChipSynth.effectChannels(data, defs.Blizzard_Sfx), ","),
  "5,8", "effectChannels reads CHAN5+8 off the Blizzard-shaped header")
eq(table.concat(ChipSynth.effectChannels(data, defs.HydroPump_Sfx), ","),
  "5,6,8", "effectChannels reads CHAN5+6+8 off the Hydro Pump-shaped header")
check(ChipSynth.effectChannels(data, "assets/beep.wav") == nil,
  "a file def has no knowable channel set")

-- ------- 1. higher id + overlapping channels is dropped (the Blizzard case)
reset()
playMove("Blizzard_Sfx")
check(#sources == 1 and sources[1].playing, "the Blizzard row sound starts")
playMove("HydroPump_Sfx")
eq(#played, 1, "the second Blizzard row is dropped, not layered (" .. names() .. ")")
eq(played[1] and played[1].name, "Blizzard_Sfx",
  "the sound that survives is the Blizzard row")
eq(#sources, 1, "the dropped row never even builds a source")
check(sources[1].playing, "the incumbent keeps sounding through the drop")

-- ------- 2. higher id + disjoint channels still plays (Disable/Leer)
-- The regression guard: SFX_BATTLE_1B is CHAN8 and SFX_BATTLE_31 is
-- CHAN5+6, so nothing is busy and both sounds are heard.
reset()
playMove("Disable_Sfx")
playMove("Leer_Sfx")
eq(#played, 2, "a higher id on disjoint channels is not gated (" .. names() .. ")")
eq(played[2] and played[2].name, "Leer_Sfx", "the second sound is the later row")
check(sources[1].playing and sources[2].playing,
  "neither disjoint sound cuts the other off")

-- ------- 3. a lower id takes the channels over
-- .playChannel zeroes the channel state, which stops whatever held it.
reset()
playMove("Loud_Sfx")
local incumbent = sources[1]
playMove("Quiet_Sfx")
eq(#played, 2, "a lower id is allowed to start (" .. names() .. ")")
check(not incumbent.playing,
  "taking CHAN5 over stops the sound that held it")
check(sources[2] and sources[2].playing, "the taking-over sound is playing")

-- ------- 4. an equal id restarts the sound
-- Repeated rows of one sound (Wrap, Metronome) must not be swallowed.
reset()
playMove("Blizzard_Sfx")
playMove("Blizzard_Sfx")
eq(#played, 2, "the same sound replayed is not gated against itself")
eq(#sources, 1, "the replay reuses the cached source")
eq(sources[1].plays, 2, "the cached source is restarted")
check(sources[1].playing, "and is sounding afterwards")

-- ------- 5. an unrankable def is left exactly as it was
-- A mod's chip sfx has no header address, so there is no comparable sound
-- id and the gate must not invent one.
reset()
playMove("Blizzard_Sfx")
playMove("Unranked_Sfx")
playMove("Unranked_Sfx")
eq(#played, 3, "unrankable defs play regardless of what is sounding ("
  .. names() .. ")")

-- an unrankable def must also not become an incumbent that gates the next
-- ranked row
reset()
playMove("Unranked_Sfx")
playMove("HydroPump_Sfx")
eq(#played, 2, "an unrankable def gates nothing after it (" .. names() .. ")")

-- ------- 6. a finished sound gates nothing
reset()
playMove("Blizzard_Sfx")
sources[1].playing = false -- the incumbent ran out
playMove("HydroPump_Sfx")
eq(#played, 2, "a row sound that already ended blocks nothing")

-- ------- 7. an invalidate (hot reload / cache flush) drops the tracking
-- Sound.invalidate stops and forgets the cached sources; a stale reference
-- would gate the next row against a dead source.
reset()
playMove("Blizzard_Sfx")
Sound.invalidate()
playMove("HydroPump_Sfx")
eq(#played, 2, "invalidate clears the tracked row sound")

Runtime.install(savedEvents, savedHooks)

T.finish("move sfx channel gate (#844)")
