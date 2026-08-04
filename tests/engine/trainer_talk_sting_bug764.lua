-- Talking a trainer into battle must start the encounter sting (#764).
-- TalkToTrainer (pokered home/trainers.asm:88) prints the before-battle
-- text and then `call EngageMapTrainer` -> PlayTrainerMusic
-- (home/trainers.asm:399): evil list, female list, male by default, rivals
-- excluded.  The port only ran the sting on the sight-line path
-- (startTrainerApproach), so a trainer challenged from the side or back --
-- and every scripted battle routed through ow:engageTrainer -- went into
-- the battle in map music.  Asserts the talk path now plays the class
-- sting, skips rivals, and does not restart it when the sight path
-- (self.engaging) already did.
-- ROM-free: stubs Game/TextBox/BattleState/Music around engageTrainer.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed = {}
local stackStub = {
  push = function(_, item) pushed[#pushed + 1] = item end,
}
local textBoxStub = {
  new = function(_, text, onDone) return { text = text, onDone = onDone } end,
  substitute = function(_, text) return text end,
}

-- Music / BattleState are required lazily at the call site; stub via
-- package.loaded (same trick as tests/engine/oaks_pc_flow.lua)
local plays = {}
local realMusic = package.loaded["src.core.Music"]
package.loaded["src.core.Music"] = {
  play = function(_, song) plays[#plays + 1] = song end,
}
local realBattle = package.loaded["src.battle.BattleState"]
package.loaded["src.battle.BattleState"] = {
  newTrainer = function() return {} end,
}

local fakeGame = {
  data = {
    text = {},
    trainerHeader = function() return nil end,
    resolveText = function() return "You looked at me\nfunny!" end,
  },
  stack = stackStub,
}
T.check(setUpvalue(OW.engageTrainer, "Game", fakeGame),
  "Game upvalue on engageTrainer")
T.check(setUpvalue(OW.engageTrainer, "TextBox", textBoxStub),
  "TextBox upvalue on engageTrainer")

-- pushBattle would touch the real stack machinery; the engagement is over
-- by the time it runs, so a no-op keeps the test on the music question
local fakeSelf = setmetatable({
  map = { def = { label = "Route24" } },
  pushBattle = function() end,
}, { __index = OW })

-- run engageTrainer for one class and return what the sting played
local function stingFor(cls, engaging)
  pushed, plays = {}, {}
  fakeSelf.engaging = engaging
  fakeSelf:engageTrainer({ id = "npc#1", def = { trainerClass = cls,
                                                 trainerParty = 1, index = 1 } })
  T.eq(#pushed, 1, "engageTrainer pushes the before-battle text")
  T.eq(#plays, 0, "no sting while the dialogue is still up (" .. cls .. ")")
  pushed[1].onDone() -- close the box; TalkToTrainer engages here
  return plays[1], #plays
end

-- PlayTrainerMusic's three buckets (data/trainers/encounter_types.asm)
T.eq(stingFor("OPP_LASS"), "Music_MeetFemaleTrainer",
  "female-list class plays the female sting")
T.eq(stingFor("OPP_ROCKET"), "Music_MeetEvilTrainer",
  "evil-list class plays the evil sting")
T.eq(stingFor("OPP_YOUNGSTER"), "Music_MeetMaleTrainer",
  "any other class defaults to the male sting")

-- the rivals `ret z` out of PlayTrainerMusic; their scripts run
-- MUSIC_MEET_RIVAL themselves (data/scripts/oaks_lab.lua)
local _, rivalCount = stingFor("OPP_RIVAL1")
T.eq(rivalCount, 0, "rival classes play no encounter sting here")

-- sight path already engaged: TrainerEngage started the sting before the
-- "!" bubble, and TalkToTrainer's BIT_SEEN_BY_TRAINER guard keeps the
-- talk path from restarting it
local _, seenCount = stingFor("OPP_LASS", true)
T.eq(seenCount, 0, "self.engaging suppresses a second sting")

if realMusic ~= nil then package.loaded["src.core.Music"] = realMusic
else package.loaded["src.core.Music"] = nil end
if realBattle ~= nil then package.loaded["src.battle.BattleState"] = realBattle
else package.loaded["src.battle.BattleState"] = nil end

T.finish("trainer_talk_sting_bug764")
