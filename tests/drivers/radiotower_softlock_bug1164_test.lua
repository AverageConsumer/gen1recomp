-- Radio Tower 5F director returns to the office after a downstairs/upstairs
-- reload, not on the stair warp at (12, 0).
-- #1164 / #1188
-- maps/RadioTower5F.asm:115 / engine/overworld/map_setup.asm:78
-- POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/radiotower_softlock_bug1164_test.lua love .

local U = require("tests.drivers.util")

local DIRECTOR_ID = 2
local OFFICE_X, OFFICE_Y = 3, 6
local STAIR_X, STAIR_Y = 12, 0
local FLAG_ROCKETS = 1742
local FLAG_CIVILIANS = 1744

local function findDirector(world)
  for _, npc in ipairs(world.npcs or {}) do
    if npc.def and npc.def.sprite == "SPRITE_GENTLEMAN" then return npc end
  end
  return nil
end

local function directorDef(world)
  local objects = world.map and world.map.def and world.map.def.objects
  return objects and objects[DIRECTOR_ID - 1]
end

return function(game)
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  world.mapScenes = world.mapScenes or {}
  world.mapScenes.RADIO_TOWER_5F = 2
  world.mapScenes.RADIO_TOWER_4F = 0
  world.events:set(FLAG_ROCKETS, true)
  world.events:set(FLAG_CIVILIANS, false)

  assert(world:setMap("RADIO_TOWER_5F", 10, 4, "down"),
    "RADIO_TOWER_5F did not load")
  U.wait(4)

  local pass, fail = 0, 0
  local function claim(ok, text)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", text)
  end

  local director = findDirector(world)
  claim(director ~= nil, "director is on 5F")
  claim(director and director.cellX == OFFICE_X and director.cellY == OFFICE_Y,
    ("director office spawn is (%d, %d), saw (%s, %s)")
      :format(OFFICE_X, OFFICE_Y,
        tostring(director and director.cellX),
        tostring(director and director.cellY)))

  world:moveObject(DIRECTOR_ID, STAIR_X, STAIR_Y)
  world:appearObject(DIRECTOR_ID)
  U.wait(4)

  director = findDirector(world)
  claim(director and director.cellX == STAIR_X and director.cellY == STAIR_Y,
    ("after moveobject director is at the stairs (%d, %d), saw (%s, %s)")
      :format(STAIR_X, STAIR_Y,
        tostring(director and director.cellX),
        tostring(director and director.cellY)))

  assert(world:setMap("RADIO_TOWER_4F", 12, 4, "down"),
    "RADIO_TOWER_4F did not load")
  U.wait(2)
  assert(world:setMap("RADIO_TOWER_5F", 10, 4, "down"),
    "RADIO_TOWER_5F did not reload")
  U.wait(4)

  local def = directorDef(world)
  director = findDirector(world)
  claim(def and def.x == OFFICE_X and def.y == OFFICE_Y,
    ("reload restored director def to (%d, %d), saw (%s, %s)")
      :format(OFFICE_X, OFFICE_Y,
        tostring(def and def.x), tostring(def and def.y)))
  claim(not (director and director.cellX == STAIR_X and director.cellY == STAIR_Y),
    "director is not standing on the stair warp")
  claim(director and director.cellX == OFFICE_X and director.cellY == OFFICE_Y,
    ("reload put director in the office (%d, %d); saw (%s, %s)")
      :format(OFFICE_X, OFFICE_Y,
        tostring(director and director.cellX),
        tostring(director and director.cellY)))

  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))
  U.log("The gentleman should be in the office. The stairs must be clear.")

  while true do U.wait(60) end
end
