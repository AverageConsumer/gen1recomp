package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["src.core.Logger"] = { warn = function() end }
package.loaded["src.world.MapLoader"] = { invalidate = function() end }
package.loaded["src.mods.Runtime"] = { emit = function() end }
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

local known = { CUT = true, SURF = true, STRENGTH = true,
                TELEPORT = true, FLY = true }
local water = false
local world = {
  isOverworld = true,
  map = { id = "ROUTE_1", def = { tileset = "OVERWORLD" },
    inBounds = function() return true end,
    isWaterCell = function() return water end },
  player = { surfing = false, facingCell = function() return 4, 5 end },
  strengthActive = false,
  useCutFieldMove = function() return "ok" end,
  useSurfFieldMove = function() return "ok" end,
  bikeAllowed = function() return true end,
  partyKnows = function(_, id) return known[id] and { species = "TEST" } end,
}
local game = {
  data = { field = {
    outsideTilesets = { "OVERWORLD" },
    flyWarps = { PALLET_TOWN = { x = 1, y = 2 } },
  }, items = { OLD_ROD = { name = "OLD ROD" },
               GOOD_ROD = { name = "GOOD ROD" } },
    pokemon = { TEST = { name = "TEST" } } },
  save = {
    inventory = { BICYCLE = 1, CASCADEBADGE = 1, SOULBADGE = 1,
      RAINBOWBADGE = 1, THUNDERBADGE = 1 },
    visited = { PALLET_TOWN = true },
  },
  stack = { states = { world } },
  overworld = world,
}
function game.stack:top() return self.states[#self.states] end

local api = require("src.world.WorldAPI").new(game, "test_mod")
local actions = api:availableFieldActions()
local ids = {}
for _, action in ipairs(actions) do ids[action.id] = true end
check(ids.bicycle and ids.cut and ids.surf and ids.strength and ids.teleport,
  "only acquired, currently usable shortcuts are exposed")
check(not ids.flash and not ids.dig and not ids.fly,
  "locked and map-inapplicable actions stay absent; Fly stays on the map")

water = true
game.save.inventory.OLD_ROD, game.save.inventory.GOOD_ROD = 1, 1
actions = api:availableFieldActions()
local fish
for _, action in ipairs(actions) do if action.id == "fish" then fish = action end end
check(fish and #fish.rods == 2, "only owned rods appear while facing water")
world.useFishingRod = function(_, rod) world.usedRod = rod end
local ok, err = api:useFieldAction("fish", { rod = "SUPER_ROD" })
check(not ok and err == "fishing rod unavailable",
  "unowned rod cannot be submitted")
check(api:useFieldAction("fish", { rod = "GOOD_ROD" }),
  "owned contextual rod accepted")
eq(world.usedRod, "GOOD_ROD", "chosen rod reaches the engine")
water = false

local donor = { species = "TEST", level = 20, hp = 100,
  stats = { hp = 100 }, moves = { { id = "SOFTBOILED" } } }
local target = { species = "TEST", level = 10, hp = 50,
  stats = { hp = 100 }, moves = {} }
game.save.party = { donor, target }
actions = api:availableFieldActions()
local soft
for _, action in ipairs(actions) do if action.id == "softboiled" then soft = action end end
check(soft and soft.sources[1].slot == 1
  and soft.sources[1].targets[1].slot == 2,
  "Softboiled appears only with a valid donor-target pair")
world.useSoftboiledFieldMove = function(_, source, healed)
  world.softPair = { source, healed }
end
check(api:useFieldAction("softboiled", { sourceSlot = 1, targetSlot = 2 }),
  "valid Softboiled pair accepted")
check(world.softPair[1] == donor and world.softPair[2] == target,
  "Softboiled uses the selected live party members")
target.hp = target.stats.hp
ok, err = api:useFieldAction("softboiled", { sourceSlot = 1, targetSlot = 2 })
check(not ok and err == "field action unavailable",
  "Softboiled vanishes when no target needs healing")
game.save.party = nil

world.tryCut = function(_, x, y) world.cutAt = { x, y } end
check(api:useFieldAction("cut"), "available action accepted")
eq(world.cutAt[1], 4, "action uses the live facing cell")
game.stack.states[2] = {}
ok, err = api:useFieldAction("cut")
check(not ok and err == "world is busy", "actions cannot fire through another screen")
game.stack.states[2] = nil

check(api:canFly(), "Fly eligibility includes move, badge and outdoor map")
world.flyTo = function(_, id) world.flewTo = id end
check(api:flyTo("PALLET_TOWN"), "visited Fly destination accepted")
eq(world.flewTo, "PALLET_TOWN", "semantic Fly reaches the engine")
game.save.inventory.THUNDERBADGE = nil
check(not api:canFly(), "Fly is hidden without the Thunder Badge")

S.finish()
