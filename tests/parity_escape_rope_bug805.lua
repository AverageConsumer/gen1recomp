-- Parity test (#805): ESCAPE ROPE / DIG / TELEPORT must land on an outdoor
-- fly-warp cell, and must re-point the LAST_MAP memory at it.
--
-- pret: ItemUseEscapeRope (engine/items/item_effects.asm) sets BIT_FLY_WARP
-- and BIT_ESCAPE_WARP, and LoadSpecialWarpData's .usedFlyWarp path
-- (engine/overworld/special_warps.asm) warps to wLastBlackoutMap with the
-- landing cell read from FlyWarpDataPtr.  wLastBlackoutMap is ALWAYS an
-- outdoor map: SetLastBlackoutMap (engine/events/set_blackout_map.asm)
-- copies wLastMap, and WarpFound2 (home/overworld.asm) only writes wLastMap
-- when CheckIfInOutsideMap passes.  PrepareForSpecialWarp
-- (engine/overworld/special_warps.asm) then does `ld [wLastMap], a` with
-- that destination for every fly/escape warp that is not a dungeon warp.
--
-- The port broke both halves.  A .sav import stamps lastHeal from wherever
-- the cartridge was saved (src/save_convert/SaveConvert.lua mergeDefaults,
-- which records no outdoor), so a save made inside Seafoam Islands made
-- ESCAPE ROPE warp the player back into that cave; and the teleport branch
-- skipped rememberOutdoor, so the first LAST_MAP exit after the rope still
-- resolved against the dungeon door walked in through.
--
-- Self-contained; run via `luajit tests/parity_escape_rope_bug805.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity escape rope #805")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game          = require("src.core.Game")
local Input         = require("src.core.Input")
local StateStack    = require("src.core.StateStack")
local Renderer      = require("src.render.Renderer")
local SaveData      = require("src.core.SaveData")
local Pokemon       = require("src.pokemon.Pokemon")
local Map           = require("src.world.Map")
local FieldDefaults = require("src.world.FieldDefaults")
local OW            = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.party = { Pokemon.new(Data, "SQUIRTLE", 20) }

-- The player is deep in a cave, having walked in from the outdoor door
-- cell the LAST_MAP exits still point at.
Game.stack:push(OW, "SEAFOAM_ISLANDS_B2F", 5, 5, "down")
local ow = Game.stack:top()
Game.overworld = ow

-- Capture the warp target instead of running the real Transition.
local dest
local realStart = ow.startWarpTo
ow.startWarpTo = function(self, mapId, x, y, facing, onDone, opts)
  dest = { map = mapId, x = x, y = y }
  self.arriveWarp = nil
  self.transitioning = false
end

local outsideTilesets = FieldDefaults.field(Data, "outsideTilesets")
local function isOutside(mapId)
  local def = Data.maps[mapId]
  return def ~= nil and Map.isOutside(def, outsideTilesets)
end

local flyWarps = Data.field.flyWarps or {}
local bootHeal = SaveData.defaultHeal(Data.field.boot)

-- --------------------------------------------------------------- 1. healthy
-- A save healed by a nurse records the outdoor town alongside the interior
-- heal cell; the rope lands on that town's FlyWarpDataPtr cell.
Game.save.lastHeal = { map = "VIRIDIAN_POKECENTER", x = 3, y = 3,
                       outdoor = { id = "VIRIDIAN_CITY", x = 23, y = 27 } }
ow:rememberOutdoor("ROUTE_23", 8, 60) -- the Victory Road door walked in from
dest = nil
ow:warpToHealPoint(nil, { arrive = "teleport" })

check(flyWarps.VIRIDIAN_CITY ~= nil, "Viridian City has a fly warp cell")
eq(dest.map, "VIRIDIAN_CITY", "healthy heal record: rope lands on the town")
eq(dest.x, flyWarps.VIRIDIAN_CITY.x, "rope lands on the FlyWarpDataPtr x")
eq(dest.y, flyWarps.VIRIDIAN_CITY.y, "rope lands on the FlyWarpDataPtr y")

-- 3. PrepareForSpecialWarp: the destination becomes the new wLastMap, so a
-- LAST_MAP exit taken after the rope resolves against the town just landed
-- in, not the dungeon door from before.
eq(Game.save.lastOutdoor.id, "VIRIDIAN_CITY",
   "teleport warp re-points wLastMap at the destination (#805)")
eq(Game.save.lastOutdoor.x, dest.x, "wLastMap x follows the landing cell")
eq(Game.save.lastOutdoor.y, dest.y, "wLastMap y follows the landing cell")

-- --------------------------------------------------------------- 2. imported
-- Exactly what SaveConvert stamps for a cartridge save made in a cave: the
-- player's own cell, no outdoor town.  wLastBlackoutMap can never name an
-- indoor map, so this record is unusable and falls back to the boot heal
-- town (vanilla's zero-filled wLastBlackoutMap is map 0, Pallet Town).
Game.save.lastHeal = { map = "SEAFOAM_ISLANDS_B2F", x = 5, y = 5 }
ow:rememberOutdoor("ROUTE_23", 8, 60)
dest = nil
ow:warpToHealPoint(nil, { arrive = "teleport" })

check(not isOutside("SEAFOAM_ISLANDS_B2F"),
      "Seafoam Islands B2F is not an outside map")
check(dest.map ~= "SEAFOAM_ISLANDS_B2F",
      "imported heal record does not dump the rope back in the cave (#805)")
check(isOutside(dest.map), "escape-warp destination is always an outside map")
eq(dest.map, bootHeal.map, "unusable heal record falls back to the boot town")
eq(dest.x, bootHeal.x, "boot-town fallback keeps its landing x")
eq(dest.y, bootHeal.y, "boot-town fallback keeps its landing y")
eq(Game.save.lastOutdoor.id, bootHeal.map,
   "fallback landing is remembered as wLastMap too")

-- --------------------------------------------------------------- 3. blackout
-- A blackout (no opts) still lands on the interior heal cell and re-points
-- LAST_MAP exits at the remembered town door: HandleBlackOut never sets
-- BIT_FLY_WARP, so it is not a special warp destination of its own.
Game.save.lastHeal = { map = "VIRIDIAN_POKECENTER", x = 3, y = 3,
                       outdoor = { id = "VIRIDIAN_CITY", x = 23, y = 27 } }
ow:rememberOutdoor("ROUTE_23", 8, 60)
dest = nil
ow:warpToHealPoint()

eq(dest.map, "VIRIDIAN_POKECENTER", "blackout still lands at the heal cell")
eq(Game.save.lastOutdoor.id, "VIRIDIAN_CITY",
   "blackout re-points wLastMap at the remembered town door")
eq(Game.save.lastOutdoor.x, 23, "blackout keeps the recorded door x")
eq(Game.save.lastOutdoor.y, 27, "blackout keeps the recorded door y")

ow.startWarpTo = realStart
S.finish()
