package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["src.core.Logger"] = { warn = function() end }
package.loaded["src.world.MapLoader"] = { invalidate = function() end }
package.loaded["src.mods.Runtime"] = { emit = function() end }
package.loaded["src.core.Sound"] = { play = function() end }
package.loaded["src.world.FieldDefaults"] = {
  field = function(data, key) return data.field[key] end,
}
package.loaded["src.world.Map"] = {
  isOutside = function(def, tilesets)
    for _, id in ipairs(tilesets or {}) do
      if def.tileset == id then return true end
    end
    return false
  end,
}

local S = require("tests.harness").suite("mod world field actions")
local check, eq = S.check, S.eq

local water = false
local world = {
  isOverworld = true,
  map = { id = "ROUTE_1", def = { tileset = "OVERWORLD" },
    inBounds = function() return true end,
    isWaterCell = function() return water end },
  player = { surfing = false, facingCell = function() return 4, 5 end },
  facingIsShoreOrWater = function() return water end,
  useCutFieldMove = function() return "no" end,
  useSurfFieldMove = function() return "no" end,
  bikeAllowed = function() return true end,
  partyKnows = function() return nil end,
}
local game = {
  data = { field = { outsideTilesets = { "OVERWORLD" } },
    items = { OLD_ROD = { name = "OLD ROD" } }, pokemon = {} },
  save = { inventory = { BICYCLE = 1, OLD_ROD = 1 }, party = {} },
  stack = { states = { world } }, overworld = world,
}
function game.stack:top() return self.states[#self.states] end

local api = require("src.world.WorldAPI").new(game, "test_mod")
for _, method in ipairs({ "current", "mapOverview", "availableFieldActions",
    "useFieldAction", "canFly", "flyTo", "canReorderParty",
    "reorderParty" }) do
  check(type(api[method]) == "function", method .. " is present in mod.world")
end

local actions = api:availableFieldActions()
eq(actions[1].id, "bicycle", "owned bicycle is exposed on a valid map")
world.useBicycle = function() world.usedBike = true return true end
check(api:useFieldAction("bicycle"), "bicycle action is accepted")
check(world.usedBike, "bicycle action reaches the overworld")

water = true
actions = api:availableFieldActions()
local fish
for _, action in ipairs(actions) do if action.id == "fish" then fish = action end end
check(fish and fish.rods[1].id == "OLD_ROD",
  "owned rod is exposed while facing water")
world.useFishingRod = function(_, rod) world.usedRod = rod return true end
check(api:useFieldAction("fish", { rod = "OLD_ROD" }),
  "owned fishing rod is accepted")
eq(world.usedRod, "OLD_ROD", "fishing action reaches the overworld")

S.finish()
