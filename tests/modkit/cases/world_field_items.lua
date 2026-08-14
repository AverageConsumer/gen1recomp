-- Contextual bicycle and fishing actions share one public contract in both
-- generations while each engine keeps ownership of its own field-item path.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("mod world field items")

local facingWater = false
local redWorld = {
  isOverworld = true,
  map = { id = "ROUTE_1", def = { tileset = "OVERWORLD" } },
  player = { moving = false, inputLocked = false, surfing = false },
  runner = { isRunning = function() return false end },
  scriptMoves = {},
  bikeAllowed = function() return true end,
  partyKnows = function() return nil end,
  facingIsShoreOrWater = function() return facingWater end,
  useBicycle = function(self) self.bikeUsed = true return true end,
  useFishingRod = function(self, rod) self.rodUsed = rod return true end,
}
local redGame = {
  data = { field = { outsideTilesets = {} },
    items = { OLD_ROD = { name = "OLD ROD" } } },
  save = { player = { name = "RED" }, party = {},
    inventory = { BICYCLE = 1, OLD_ROD = 1 } },
  stack = { states = { redWorld } },
  overworld = redWorld,
}
function redGame.stack:top() return self.states[#self.states] end

local RedAPI = require("src.world.WorldAPI")
local red = RedAPI.new(redGame, "fixture")
local RedWorld = require("src.world.OverworldController")
T.check(type(RedWorld.useBicycle) == "function"
    and type(RedWorld.useFishingRod) == "function",
  "Red keeps field-item execution in its world")
local actions = red:availableFieldActions()
T.eq(actions[1].id, "bicycle", "Red lists an owned usable bicycle")
T.check(red:useFieldAction("bicycle"), "Red accepts the listed bicycle")
T.check(redWorld.bikeUsed, "Red delegates to its world-owned bicycle path")

facingWater = true
actions = red:availableFieldActions()
T.eq(actions[2].rods[1].id, "OLD_ROD", "Red lists owned rods at water")
T.check(red:useFieldAction("fish", { rod = "OLD_ROD" }),
  "Red accepts a listed rod")
T.eq(redWorld.rodUsed, "OLD_ROD", "Red delegates to its fishing path")
local used = redWorld.rodUsed
local ok, err = red:useFieldAction("fish", { rod = "SUPER_ROD" })
T.check(not ok and err == "fishing rod unavailable",
  "Red rejects an unowned rod")
T.eq(redWorld.rodUsed, used, "a rejected Red rod changes nothing")

redWorld.player.moving = true
T.eq(#red:availableFieldActions(), 0, "Red hides actions while moving")
ok, err = red:useFieldAction("bicycle")
T.check(not ok and err == "world is busy",
  "Red refuses a stale action while busy")

local goldWorld = {
  map = { id = "ROUTE_29", def = { environment = "ROUTE" } },
  player = {}, playerState = "normal",
  acceptsMenuInput = function() return true end,
  playerCollision = function() return 0x00 end,
  alwaysOnBike = function() return false end,
  fieldContext = function() return { facingColl = 0x20, party = {} } end,
  useFieldItem = function(self, item) self.itemUsed = item return "used" end,
}
local goldGame = {
  data = { items = { OLD_ROD = { name = "OLD ROD" } } },
  save = { inventory = { BICYCLE = 1, OLD_ROD = 1 } },
  world = goldWorld,
}

local GoldAPI = require("src.world.gen2.WorldAPI")
local gold = GoldAPI.new(goldGame, "fixture")
actions = gold:availableFieldActions()
T.eq(actions[1].id, "bicycle", "Gold shares the bicycle action id")
T.eq(actions[2].rods[1].id, "OLD_ROD", "Gold shares the rod shape")
T.check(gold:useFieldAction("fish", { rod = "OLD_ROD" }),
  "Gold accepts the same fishing request")
T.eq(goldWorld.itemUsed, "OLD_ROD",
  "Gold delegates to its own field-item path")
used = goldWorld.itemUsed
ok, err = gold:useFieldAction("fish", { rod = "SUPER_ROD" })
T.check(not ok and err == "fishing rod unavailable",
  "Gold rejects an unowned rod")
T.eq(goldWorld.itemUsed, used, "a rejected Gold rod changes nothing")

T.finish()
