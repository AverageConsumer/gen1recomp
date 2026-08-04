-- Parity: which trainers get the gym-leader battle theme (#782).
-- PlayBattleMusic (audio/play_battle_music.asm) picks MUSIC_GYM_LEADER_BATTLE
-- only when wGymLeaderNo is set, and the eight gym scripts
-- (scripts/PewterGym.asm .. ViridianGym.asm) are its only writers; Lance
-- shares the theme by opponent class and the Champion (OPP_RIVAL3) takes
-- MUSIC_FINAL_BATTLE.  Giovanni's Rocket Hideout (OPP_GIOVANNI#1) and Silph
-- Co (OPP_GIOVANNI#2) fights never touch the byte, so they must play
-- MUSIC_TRAINER_BATTLE.  The port keyed the boss check on the trainer CLASS
-- alone, so every Giovanni battle borrowed the Earth Badge roster's theme,
-- the gym victory jingle, and the Pikachu GYMLEADER happiness bump.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity battle music bug782")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local function makeGame()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "BULBASAUR", 60) }
  return { data = Data, save = save,
           input = { wasPressed = function() return false end,
                     isDown = function() return false end },
           stack = { top = function() return nil end,
                     push = function() end, pop = function() end } }
end

local function kindOf(oppClass, partyIndex)
  local battle = BattleState.newTrainer(makeGame(), oppClass, partyIndex)
  return battle:computeMusicKind(), battle.isGymLeader
end

-- the two non-gym Giovanni fights: plain trainer theme, no gym-leader flag
do
  local kind, gym = kindOf("OPP_GIOVANNI", 1) -- Rocket Hideout B4F
  eq(kind, "trainer", "Rocket Hideout Giovanni plays the trainer theme")
  check(not gym, "Rocket Hideout Giovanni is not a gym leader")
  kind, gym = kindOf("OPP_GIOVANNI", 2) -- Silph Co 11F
  eq(kind, "trainer", "Silph Co Giovanni plays the trainer theme")
  check(not gym, "Silph Co Giovanni is not a gym leader")
end

-- the badge fight itself keeps the gym theme and the happiness bump
do
  local kind, gym = kindOf("OPP_GIOVANNI", 3) -- Viridian Gym
  eq(kind, "gym", "Viridian Gym Giovanni plays the gym-leader theme")
  check(gym, "Viridian Gym Giovanni sets isGymLeader")
end

-- regression guards around the branch below the badge lookup
do
  local kind, gym = kindOf("OPP_BROCK", 1)
  eq(kind, "gym", "Brock plays the gym-leader theme")
  check(gym, "Brock sets isGymLeader")
  kind, gym = kindOf("OPP_LANCE", 1)
  eq(kind, "gym", "Lance shares the gym-leader theme")
  check(not gym, "Lance is not a wGymLeaderNo writer (no happiness bump)")
  kind = kindOf("OPP_RIVAL3", 1)
  eq(kind, "final", "the Champion plays the final-battle theme")
  kind, gym = kindOf("OPP_YOUNGSTER", 1)
  eq(kind, "trainer", "an ordinary trainer plays the trainer theme")
  check(not gym, "an ordinary trainer is not a gym leader")
end

S.finish()
