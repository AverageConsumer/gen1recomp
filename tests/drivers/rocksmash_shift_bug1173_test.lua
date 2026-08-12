-- Route 40 smashable rocks stay on their cell through rock_smash, then a
-- seamless Olivine round trip.
-- #1173
-- engine/overworld/movement.asm:163 / maps/Route40.asm:291
-- POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/rocksmash_shift_bug1173_test.lua love .

local U = require("tests.drivers.util")

local ROCK_ID = 6
local ROCK_X, ROCK_Y = 12, 8
local SMASH = { 0x57, 10, 0x47 }

local function findRock(world, x, y)
  for _, npc in ipairs(world.npcs or {}) do
    if npc.def and npc.def.sprite == "SPRITE_ROCK"
        and npc.cellX == x and npc.cellY == y then
      return npc
    end
  end
  return nil
end

local function rockAt(world, x, y)
  for _, npc in ipairs(world.npcs or {}) do
    if npc.def and npc.def.sprite == "SPRITE_ROCK"
        and npc.cellX == x and npc.cellY == y then
      return true
    end
  end
  return false
end

return function(game)
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  world.mapScenes = world.mapScenes or {}
  world.mapScenes.ROUTE_40 = 0
  world.mapScenes.OLIVINE_CITY = 0

  assert(world:setMap("ROUTE_40", 12, 9, "up"), "ROUTE_40 did not load")
  U.wait(4)

  local pass, fail = 0, 0
  local function claim(ok, text)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", text)
  end

  local rock = findRock(world, ROCK_X, ROCK_Y)
  claim(rock ~= nil, ("rock is at (%d, %d)"):format(ROCK_X, ROCK_Y))

  world:beginMovement(ROCK_ID, SMASH)
  for _ = 1, 40 do
    if not world.moveState then break end
    U.wait(1)
  end
  claim(world.moveState == nil, "rock_smash stream finished")

  rock = findRock(world, ROCK_X, ROCK_Y)
  claim(rock ~= nil,
    ("after rock_smash the rock is still at (%d, %d), not one cell left")
      :format(ROCK_X, ROCK_Y))
  claim(not rockAt(world, ROCK_X - 1, ROCK_Y),
    "no smashable rock slid one cell left")

  assert(world:setMap("OLIVINE_CITY", 18, 15, "down", { seamless = true }),
    "OLIVINE_CITY did not load")
  U.wait(2)
  assert(world:setMap("ROUTE_40", 12, 9, "up", { seamless = true }),
    "ROUTE_40 did not reload")
  U.wait(4)

  claim(rockAt(world, ROCK_X, ROCK_Y),
    ("after Olivine round trip the rock is still at (%d, %d)")
      :format(ROCK_X, ROCK_Y))
  claim(not rockAt(world, ROCK_X - 1, ROCK_Y),
    "seamless reload did not shift the rock left")

  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))
  U.log("The three rocks should sit on (12, 8), (11, 7), (13, 6).")

  while true do U.wait(60) end
end
