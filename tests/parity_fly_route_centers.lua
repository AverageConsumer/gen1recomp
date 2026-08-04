-- Parity test: the Route 4 / Route 10 Pokemon Centers are not FLY
-- destinations (#788).
--
-- pokered keeps fly-warp landing spots for ROUTE_4 and ROUTE_10 in
-- data/maps/special_warps.asm FlyWarpDataPtr, but the fly picker never
-- offers them: BuildFlyLocationsList (engine/items/town_map.asm) walks map
-- ids 0..NUM_CITY_MAPS-1 only, and MarkTownVisitedAndLoadToggleableObjects
-- (engine/overworld/toggleable_objects.asm) sets a wTownVisitedFlag bit
-- only for maps below FIRST_ROUTE_MAP.  The port walked the whole fly-warp
-- table and gated on "outdoor", so both route centers showed up as fly
-- targets the moment the player had set foot on those routes.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity fly route centers")
local check, eq = S.check, S.eq

local Map = require("src.world.Map")
local FlyMenu = require("src.ui.FlyMenu")
local TownMap = require("src.ui.TownMap")

local TOWNS = {
  "PALLET_TOWN", "VIRIDIAN_CITY", "PEWTER_CITY", "CERULEAN_CITY",
  "LAVENDER_TOWN", "VERMILION_CITY", "CELADON_CITY", "FUCHSIA_CITY",
  "CINNABAR_ISLAND", "INDIGO_PLATEAU", "SAFFRON_CITY",
}

-- ------------------------------------------------------------------
-- 1) the gate itself, straight off generated map records
-- ------------------------------------------------------------------
-- map indices 0..10 are exactly the eleven towns (data/generated/maps.lua
-- carries pokered's map constant order), and Map.isFlyTown keys off them
check(Map.isFlyTown(Data.maps.PALLET_TOWN), "PALLET_TOWN is a fly town")
check(Map.isFlyTown(Data.maps.INDIGO_PLATEAU),
      "INDIGO_PLATEAU is a fly town (index 9, past the PLATEAU tileset)")
check(not Map.isFlyTown(Data.maps.ROUTE_4), "ROUTE_4 is not a fly town")
check(not Map.isFlyTown(Data.maps.ROUTE_10), "ROUTE_10 is not a fly town")
check(not Map.isFlyTown(Data.maps.POKEMON_MANSION_1F),
      "POKEMON_MANSION_1F (dungeon escape spot) is not a fly town")
-- a mod-authored town has no vanilla index and keeps the outdoor test
check(Map.isFlyTown({ tileset = "OVERWORLD" }),
      "an index-less outdoor map (mod town) is a fly town")
check(not Map.isFlyTown({ tileset = "CAVERN" }),
      "an index-less cave map is not a fly town")

-- ------------------------------------------------------------------
-- 2) both pickers exclude the route centers, even on a polluted save
-- ------------------------------------------------------------------
-- Saves written before this fix already carry visited.ROUTE_4 /
-- visited.ROUTE_10 (any map with a fly warp was marked on entry), so the
-- menu side has to filter, not just the writer.
local visited = { ROUTE_4 = true, ROUTE_10 = true }
for _, id in ipairs(TOWNS) do visited[id] = true end
local save = { visited = visited }

local menu = FlyMenu.new({ data = Data, save = save })
local menuIds = {}
for _, item in ipairs(menu.items or {}) do menuIds[#menuIds + 1] = item.value end
eq(#menuIds, #TOWNS, "FLY lists exactly the eleven towns")
for i, id in ipairs(TOWNS) do
  eq(menuIds[i], id, ("FLY entry %d is %s"):format(i, id))
end

local tm = TownMap.new({ data = Data, save = save }, { fly = true })
check(tm.fly == true, "the town map opens in fly mode")
local listed = {}
for _, id in ipairs(tm.flyMapIds or {}) do listed[id] = true end
eq(#tm.flyMapIds, #TOWNS, "the fly town map cycles exactly the eleven towns")
check(not listed.ROUTE_4, "ROUTE_4 is not on the fly town map")
check(not listed.ROUTE_10, "ROUTE_10 is not on the fly town map")
for _, id in ipairs(TOWNS) do
  check(listed[id], id .. " is on the fly town map")
end

S.finish()
