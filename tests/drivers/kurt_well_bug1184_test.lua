-- Kurt stays at moveobject (11, 6) for the visit, then ROM spawn (16, 14)
-- on the next load.
-- #1184
-- maps/SlowpokeWellB1F.asm:48 / engine/overworld/map_setup.asm:78
-- POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/kurt_well_bug1184_test.lua love .

local U = require("tests.drivers.util")

local KURT_ID = 8
local ROM_X, ROM_Y = 16, 14
local MOVE_X, MOVE_Y = 11, 6
local FLAG_KURT = 1856
local FLAG_ROCKETS = 1788

local function findKurt(world)
  for _, npc in ipairs(world.npcs or {}) do
    if npc.def and npc.def.sprite == "SPRITE_KURT" then return npc end
  end
  return nil
end

local function kurtDef(world)
  local objects = world.map and world.map.def and world.map.def.objects
  return objects and objects[KURT_ID - 1]
end

return function(game)
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  world.mapScenes = world.mapScenes or {}
  world.mapScenes.PLAYERS_HOUSE_1F = 1
  world.mapScenes.NEW_BARK_TOWN = 1
  world.events:set(FLAG_KURT, false)
  world.events:set(FLAG_ROCKETS, true)

  assert(world:setMap("SLOWPOKE_WELL_B1F", 15, 14, "right"),
    "SLOWPOKE_WELL_B1F did not load")
  U.wait(4)

  local pass, fail = 0, 0
  local function claim(ok, text)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", text)
  end

  local kurt = findKurt(world)
  claim(kurt ~= nil, "Kurt is on the well map")
  claim(kurt and kurt.cellX == ROM_X and kurt.cellY == ROM_Y,
    ("Kurt ROM spawn is (%d, %d), saw (%s, %s)")
      :format(ROM_X, ROM_Y,
        tostring(kurt and kurt.cellX), tostring(kurt and kurt.cellY)))

  world:moveObject(KURT_ID, MOVE_X, MOVE_Y)
  world:appearObject(KURT_ID)
  U.wait(4)

  kurt = findKurt(world)
  claim(kurt and kurt.cellX == MOVE_X and kurt.cellY == MOVE_Y,
    ("after moveobject Kurt is at (%d, %d), saw (%s, %s)")
      :format(MOVE_X, MOVE_Y,
        tostring(kurt and kurt.cellX), tostring(kurt and kurt.cellY)))

  assert(world:setMap("PLAYERS_HOUSE_1F", 3, 3, "down"),
    "PLAYERS_HOUSE_1F did not load")
  U.wait(2)
  world.events:set(FLAG_KURT, false)
  assert(world:setMap("SLOWPOKE_WELL_B1F", 15, 14, "right"),
    "SLOWPOKE_WELL_B1F did not reload")
  U.wait(4)

  local def = kurtDef(world)
  kurt = findKurt(world)
  claim(def and def.x == ROM_X and def.y == ROM_Y,
    ("reload restored Kurt def to (%d, %d), saw (%s, %s)")
      :format(ROM_X, ROM_Y,
        tostring(def and def.x), tostring(def and def.y)))
  claim(kurt and kurt.cellX == ROM_X and kurt.cellY == ROM_Y,
    ("reload put Kurt at (%d, %d), not the blocking cell (%d, %d); saw (%s, %s)")
      :format(ROM_X, ROM_Y, MOVE_X, MOVE_Y,
        tostring(kurt and kurt.cellX), tostring(kurt and kurt.cellY)))

  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))
  U.log("Kurt should be at the well entrance, not on the inner path.")

  while true do U.wait(60) end
end
