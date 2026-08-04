-- Parity test: the FLY town map opens on PALLET_TOWN and Up walks the
-- towns forward, Down backward (#795).
--
-- pokered's LoadTownMap_Fly (engine/items/town_map.asm) enters its loop
-- with hl on wFlyLocationsList[0] -- the cursor ALWAYS starts on the first
-- fly destination, PALLET_TOWN, never the town the player is standing in.
-- .pressedUp does `inc hl` (next town, skipping NOT_VISITED entries,
-- wrapping at the $ff terminator back to the start) and .pressedDown does
-- `dec hl` (previous town, wrapping off the top to the last visited town).
-- The port started the cursor on the player's current town and had Up and
-- Down swapped, so the menu felt like it cycled in a random order.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity fly cursor order")
local check, eq = S.check, S.eq

local TownMap = require("src.ui.TownMap")

local function makeGame(visited, currentMap)
  local pressed = {}
  local game = {
    data = Data,
    save = { visited = visited },
    overworld = currentMap and { map = { id = currentMap } } or nil,
    input = { wasPressed = function(_, name)
      local p = pressed[name]
      pressed[name] = nil
      return p
    end },
    stack = { pop = function() end },
  }
  return game, function(name) pressed[name] = true end
end

local function selection(tm)
  return tm.flyMapIds[tm.sel]
end

local ALL = {
  PALLET_TOWN = true, VIRIDIAN_CITY = true, PEWTER_CITY = true,
  CERULEAN_CITY = true, LAVENDER_TOWN = true, VERMILION_CITY = true,
  CELADON_CITY = true, FUCHSIA_CITY = true, CINNABAR_ISLAND = true,
  INDIGO_PLATEAU = true, SAFFRON_CITY = true,
}

-- ------------------------------------------------------------------
-- 1) the cursor opens on PALLET_TOWN, not the player's town
-- ------------------------------------------------------------------
local game, tap = makeGame(ALL, "CELADON_CITY")
local tm = TownMap.new(game, { fly = true })
check(tm.fly == true, "the town map opens in fly mode")
eq(selection(tm), "PALLET_TOWN",
   "the fly cursor opens on PALLET_TOWN while the player stands in Celadon")

-- ------------------------------------------------------------------
-- 2) Up walks the towns forward, Down backward, both wrapping
-- ------------------------------------------------------------------
tap("up") tm:update(0)
eq(selection(tm), "VIRIDIAN_CITY", "Up from PALLET_TOWN selects VIRIDIAN_CITY")
tap("up") tm:update(0)
eq(selection(tm), "PEWTER_CITY", "Up again selects PEWTER_CITY")
tap("down") tm:update(0)
eq(selection(tm), "VIRIDIAN_CITY", "Down steps back to VIRIDIAN_CITY")
tap("down") tm:update(0)
eq(selection(tm), "PALLET_TOWN", "Down again returns to PALLET_TOWN")
tap("down") tm:update(0)
eq(selection(tm), "SAFFRON_CITY",
   "Down off the top wraps to the last visited town (SAFFRON_CITY)")
tap("up") tm:update(0)
eq(selection(tm), "PALLET_TOWN", "Up off the bottom wraps back to PALLET_TOWN")

-- ------------------------------------------------------------------
-- 3) unvisited towns are skipped, in list order
-- ------------------------------------------------------------------
local PARTIAL = { PALLET_TOWN = true, VIRIDIAN_CITY = true, CELADON_CITY = true }
local game2, tap2 = makeGame(PARTIAL, "VIRIDIAN_CITY")
local tm2 = TownMap.new(game2, { fly = true })
eq(selection(tm2), "PALLET_TOWN",
   "the fly cursor opens on PALLET_TOWN on a partial save too")
tap2("up") tm2:update(0)
eq(selection(tm2), "VIRIDIAN_CITY", "Up selects VIRIDIAN_CITY")
tap2("up") tm2:update(0)
eq(selection(tm2), "CELADON_CITY", "Up skips every unvisited town to CELADON")
tap2("up") tm2:update(0)
eq(selection(tm2), "PALLET_TOWN", "Up off the end wraps to PALLET_TOWN")
tap2("down") tm2:update(0)
eq(selection(tm2), "CELADON_CITY",
   "Down off the top wraps to CELADON, the last visited town")

-- ------------------------------------------------------------------
-- 4) the plain town map viewer still opens on the player's town
-- ------------------------------------------------------------------
local game3 = makeGame(ALL, "CERULEAN_CITY")
local viewer = TownMap.new(game3)
check(not viewer.fly, "the plain viewer is not in fly mode")
check(viewer.locs[viewer.sel] == viewer.playerLoc,
      "the plain viewer still opens on the player's current location")

S.finish()
