-- Contextual field actions share one public contract in both generations
-- while each engine keeps ownership of its own field-item and move paths.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("mod world field actions")

local facingWater = false
local redCut, redSurf = false, "no_water"
local redMoves = {}
local redWorld = {
  isOverworld = true,
  map = { id = "ROUTE_1", def = { tileset = "OVERWORLD" } },
  player = { moving = false, inputLocked = false, surfing = false },
  runner = { isRunning = function() return false end },
  scriptMoves = {},
  bikeAllowed = function() return true end,
  partyKnows = function() return nil end,
  facingIsShoreOrWater = function() return facingWater end,
  useCutFieldMove = function() return redCut and "ok" or "nothing" end,
  useSurfFieldMove = function() return redSurf end,
  partyKnows = function(_, move) return redMoves[move] end,
  useBicycle = function(self) self.bikeUsed = true return true end,
  useFishingRod = function(self, rod) self.rodUsed = rod return true end,
}
local redGame = {
  data = { field = { outsideTilesets = { "OVERWORLD" } },
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
    and type(RedWorld.useFishingRod) == "function"
    and type(RedWorld.useFlashFieldMove) == "function"
    and type(RedWorld.useStrengthFieldMove) == "function"
    and type(RedWorld.stopSurfing) == "function",
  "Red keeps field-action execution in its world")
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

redWorld.player.moving = false
facingWater, redCut, redSurf = false, true, "ok"
redWorld.dark = true
for _, move in ipairs({ "STRENGTH", "FLASH", "TELEPORT" }) do
  redMoves[move] = { species = "MEW", moves = { { id = move } } }
end
redWorld.player.facingCell = function() return 4, 5 end
redWorld.tryCut = function(self) self.cutUsed = true return true end
redWorld.trySurf = function(self) self.surfUsed = true end
redWorld.useStrengthFieldMove = function(self) self.strengthUsed = true return true end
redWorld.useFlashFieldMove = function(self) self.flashUsed = true return true end
redWorld.beginTeleportOut = function(self) self.teleportUsed = true end
actions = red:availableFieldActions()
local byId = {}
for _, action in ipairs(actions) do byId[action.id] = action end
T.check(byId.cut and byId.surf and byId.strength and byId.flash
    and byId.teleport, "Red lists field moves that can start now")
for _, id in ipairs({ "cut", "surf", "strength", "flash", "teleport" }) do
  T.check(red:useFieldAction(id), "Red accepts listed " .. id)
end
T.check(redWorld.cutUsed and redWorld.surfUsed and redWorld.strengthUsed
    and redWorld.flashUsed and redWorld.teleportUsed,
  "Red delegates every move to its overworld path")

redSurf = "dismount"
redWorld.player.surfing = true
redWorld.stopSurfing = function(self) self.dismounted = true end
T.check(red:useFieldAction("surf") and redWorld.dismounted,
  "Red delegates the contextual SURF dismount")
redWorld.player.surfing, redSurf = false, "ok"

redCut = false
ok, err = red:useFieldAction("cut")
T.check(not ok and err == "field action unavailable",
  "Red revalidates a stale field move")

redWorld.map.id = "ROCK_TUNNEL_1F"
redWorld.map.def.tileset = "CAVERN"
redMoves.DIG = { species = "MEW", moves = { { id = "DIG" } } }
redWorld.beginTeleportOut = function(self) self.digUsed = true end
byId = {}
for _, action in ipairs(red:availableFieldActions()) do byId[action.id] = action end
T.check(byId.dig and not byId.teleport,
  "Red distinguishes dungeon DIG from outdoor TELEPORT")
T.check(red:useFieldAction("dig") and redWorld.digUsed,
  "Red delegates DIG to its escape path")

local goldWorld = {
  map = { id = "ROUTE_29", def = { environment = "ROUTE" } },
  player = {}, playerState = "normal",
  acceptsMenuInput = function() return true end,
  playerCollision = function() return 0x00 end,
  alwaysOnBike = function() return false end,
  useFieldItem = function(self, item) self.itemUsed = item return "used" end,
  squirtbottleTreeScript = function() return { { op = "end" } } end,
  useFieldMove = function(self, move)
    self.moveUsed = move
    return { ok = true }
  end,
}
local goldGame = {
  data = { items = { OLD_ROD = { name = "OLD ROD" },
    SQUIRTBOTTLE = { name = "SQUIRTBOTTLE" } } },
  save = { inventory = { BICYCLE = 1, OLD_ROD = 1, SQUIRTBOTTLE = 1 },
    player = { badges = { FOG = true } },
    party = { { moves = { { id = "SURF" }, { id = "SWEET_SCENT" },
      { id = "TELEPORT" } } } } },
  world = goldWorld,
}
goldWorld.fieldContext = function(_, mon) return {
  save = goldGame.save, party = goldGame.save.party, mon = mon,
  facing = "right", facingColl = 0x29, playerColl = 0,
  environment = "ROUTE", playerState = "normal", alwaysOnBike = false,
  dark = false, canEscapeRope = false,
} end

local GoldAPI = require("src.world.gen2.WorldAPI")
local gold = GoldAPI.new(goldGame, "fixture")
actions = gold:availableFieldActions()
byId = {}
for _, action in ipairs(actions) do byId[action.id] = action end
T.eq(actions[1].id, "bicycle", "Gold shares the bicycle action id")
T.eq(actions[2].id, "fish", "Gold preserves the original action order")
T.check(byId.surf and byId.sweet_scent and byId.teleport,
  "Gold lists field moves through its generic dispatcher")
T.eq(byId.fish.rods[1].id, "OLD_ROD", "Gold shares the rod shape")
T.check(byId.squirtbottle,
  "Gold lists the SquirtBottle only at its matching tree")
T.check(gold:useFieldAction("sweet_scent"),
  "Gold accepts a listed field move")
T.eq(goldWorld.moveUsed, "SWEET_SCENT",
  "Gold delegates moves to its own field-move path")
T.check(gold:useFieldAction("fish", { rod = "OLD_ROD" }),
  "Gold accepts the same fishing request")
T.eq(goldWorld.itemUsed, "OLD_ROD",
  "Gold delegates to its own field-item path")
used = goldWorld.itemUsed
ok, err = gold:useFieldAction("fish", { rod = "SUPER_ROD" })
T.check(not ok and err == "fishing rod unavailable",
  "Gold rejects an unowned rod")
T.eq(goldWorld.itemUsed, used, "a rejected Gold rod changes nothing")
T.check(gold:useFieldAction("squirtbottle"),
  "Gold accepts the contextual SquirtBottle")
T.eq(goldWorld.itemUsed, "SQUIRTBOTTLE",
  "Gold delegates the SquirtBottle to its field-item path")

T.finish()
