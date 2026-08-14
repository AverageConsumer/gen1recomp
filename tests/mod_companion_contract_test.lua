package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("mod companion contract")
local check = S.check
local OverworldState = require("src.world.OverworldController")
local BattleState = require("src.battle.BattleState")

for _, method in ipairs({ "toggleBike", "useFishingRod", "stopSurfing",
    "useStrengthFieldMove", "useFlashFieldMove",
    "useSoftboiledFieldMove" }) do
  check(type(OverworldState[method]) == "function",
    "Gen 1 overworld implements " .. method)
end
check(type(BattleState.catchChance) == "function",
  "Gen 1 battle implements catchChance")

S.finish()
