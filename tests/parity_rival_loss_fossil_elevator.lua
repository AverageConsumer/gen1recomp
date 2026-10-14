package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.ROUTE_22) then Data:load() end

local S = require("tests.harness").suite("parity rival loss, fossil corner, hideout lift")
local check, eq = S.check, S.eq

local story2 = require("data.scripts.story2")
local story3 = require("data.scripts.story3")
local story5 = require("data.scripts.story5")

local function captureRows(mod, flags, x, y)
  local rows
  local ow = {
    player = {},
    runner = {
      isRunning = function() return false end,
      run = function(_, r) rows = r end,
    },
  }
  local game = { data = Data, save = { flags = flags } }
  mod.onStep(game, ow, x, y)
  return rows
end

local function lossTarget(rows)
  for i, row in ipairs(rows or {}) do
    if row[1] == "rival_battle" then
      local nxt = rows[i + 1]
      return nxt and nxt[1] == "jump_if_false" and nxt[2]
    end
  end
end

-- scripts/Route22.asm:152
eq(lossTarget(captureRows(story5.ROUTE_22, { EVENT_GOT_POKEDEX = true }, 29, 4)),
   "end", "Route 22 rival 1 stays shown after a lost battle")
eq(lossTarget(captureRows(story5.ROUTE_22, { EVENT_BEAT_GIOVANNI = true }, 29, 5)),
   "end", "Route 22 rival 2 stays shown after a lost battle")
-- scripts/SSAnne2F.asm:127
eq(lossTarget(captureRows(story5.SS_ANNE_2F, {}, 36, 8)),
   "end", "S.S. Anne rival stays shown after a lost battle")
-- scripts/SilphCo7F.asm:209
eq(lossTarget(captureRows(story5.SILPH_CO_7F, {}, 3, 2)),
   "end", "Silph Co 7F rival stays shown after a lost battle")

-- scripts/MtMoonB2F.asm:8
do
  local beaten = false
  local nerd = {}
  local ow = {
    npcByIndex = function() return nerd end,
    trainerDefeated = function() return beaten end,
  }
  local nb = story2.MT_MOON_B2F.noBattles
  check(type(nb) == "function", "Mt. Moon B2F has a no-battles zone")
  if nb then
    check(not nb({}, ow, 12, 7), "battles stay on before the Super Nerd is beaten")
    beaten = true
    check(nb({}, ow, 12, 7), "the fossil corner blocks battles once he is beaten")
    check(nb({}, ow, 11, 5) and nb({}, ow, 14, 8), "across the whole 4x4 area")
    check(not nb({}, ow, 15, 7) and not nb({}, ow, 12, 9), "and nowhere outside it")
  end
end

-- scripts/RocketHideoutElevator.asm:51
do
  local game = { data = Data }
  local want = { ROCKET_HIDEOUT_B1F = 5, ROCKET_HIDEOUT_B2F = 5, ROCKET_HIDEOUT_B4F = 3 }
  for mapId, warpIdx in pairs(want) do
    local ow = { map = { def = { warps = { {}, {} } } } }
    story3.ROCKET_HIDEOUT_ELEVATOR.onEnter(game, ow, mapId)
    eq(ow.map.def.warps[1].destWarp, warpIdx,
       mapId .. ": the car lets out on the right-hand door tile")
    eq(ow.map.def.warps[2].destMap, mapId, mapId .. ": both car warps lead there")
  end
end

S.finish()
