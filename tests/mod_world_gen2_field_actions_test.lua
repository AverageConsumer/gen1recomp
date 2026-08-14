package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 mod world field actions")
local check = S.check
local Gen2Api = require("src.world.gen2.WorldAPI")

local save = {
  inventory = { BICYCLE = 1, OLD_ROD = 1, SQUIRTBOTTLE = 1 },
  player = { badges = { FOG = true } },
  party = { { moves = {
    { id = "SURF" }, { id = "SWEET_SCENT" }, { id = "TELEPORT" },
  } } },
}
local usedItem, usedMove
local world = {
  map = { def = { environment = "ROUTE" } },
  player = {}, playerState = "normal", strengthActive = false,
  busy = function() return false end,
  playerCollision = function() return 0 end,
  alwaysOnBike = function() return false end,
  fieldContext = function(_, mon)
    return { save = save, party = save.party, mon = mon,
      facing = "right", facingColl = 0x29, playerColl = 0,
      environment = "ROUTE", playerState = "normal",
      alwaysOnBike = false, dark = false, canEscapeRope = false }
  end,
  squirtbottleTreeScript = function() return { { op = "end" } } end,
  useFieldItem = function(_, id) usedItem = id return "used" end,
  useFieldMove = function(_, id) usedMove = id return { ok = true } end,
}
local game = { world = world, save = save, data = { items = {
  OLD_ROD = { name = "OLD ROD" },
  SQUIRTBOTTLE = { name = "SQUIRTBOTTLE" },
} } }
local api = Gen2Api.new(game, "tester")
local actions, byId = api:availableFieldActions(), {}
for _, action in ipairs(actions) do byId[action.id] = action end

check(byId.bicycle ~= nil, "Gold exposes the usable bicycle")
check(byId.surf ~= nil and byId.sweet_scent ~= nil
    and byId.teleport ~= nil, "Gold exposes usable shared field moves")
check(byId.fish and #byId.fish.rods == 1
    and byId.fish.rods[1].id == "OLD_ROD",
  "Gold exposes only acquired rods while facing water")
check(byId.squirtbottle ~= nil,
  "Gold exposes its key item only at the Sudowoodo context")
check(byId.cut == nil, "an unavailable move stays absent")

check(api:useFieldAction("sweet_scent") == true
    and usedMove == "SWEET_SCENT", "a move uses Gold's field-move path")
check(api:useFieldAction("fish", { rod = "OLD_ROD" }) == true
    and usedItem == "OLD_ROD", "a rod uses Gold's field-item path")
local refused = api:useFieldAction("fish", { rod = "SUPER_ROD" })
check(refused == nil, "a rod not present in the offered record is refused")

S.finish()
