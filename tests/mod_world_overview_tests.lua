package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local WorldAPI = require("src.world.WorldAPI")
local Assets = require("src.render.Assets")
love.image = { newImageData = function() end }
Assets.imageData = function()
  return { getPixel = function(_, x)
    local shade = x < 8 and 1 or 0
    return shade, shade, shade, 1
  end }
end
local map = {
  id = "TEST_MAP", widthCells = 5, heightCells = 6,
  tileset = { image = "test.png", tilesPerRow = 2 },
  def = {
    warps = { { x = 1, y = 2 } },
    objects = { { index = 1, x = 3, y = 4, item = "POTION" } },
  },
  isWarpTileCell = function(_, x, y) return x == 1 and y == 2 end,
  isWaterCell = function(_, x, y) return x == 0 and y == 0 end,
  isWalkableCell = function() return true end,
  tileAt = function(_, x) return x % 2 end,
}
local save = {}
local world = {
  isOverworld = true, map = map,
  player = { cellX = 2, cellY = 3, facing = "down" },
  objectVisible = function(s, id, obj)
    return not (s.itemsTaken and s.itemsTaken[id .. "_obj_" .. obj.index])
  end,
}
local game = {
  save = save,
  data = { field = { hiddenItems = {
    TEST_MAP = { { x = 4, y = 5, item = "NUGGET" } },
  } } },
  stack = { states = { world } },
}
local api = WorldAPI.new(game, "test")

local function hasMarker(kind)
  for _, marker in ipairs(api:mapOverview().markers) do
    if marker.kind == kind then return true end
  end
  return false
end

local overview = api:mapOverview()
assert(overview.rows[1]:sub(1, 1) == "~"
  and overview.rows[3]:sub(2, 2) == "+", "terrain overview")
assert(overview.tileWidth == 10 and overview.tileHeight == 12
  and overview.tileRows[1]:sub(1, 2) == "03", "real tile overview")
assert(hasMarker("warp") and hasMarker("item") and hasMarker("hidden"),
  "enhanced overview markers")
save.itemsTaken = { TEST_MAP_obj_1 = true }
save.hiddenTaken = { TEST_MAP_4_5 = true }
assert(hasMarker("warp") and not hasMarker("item") and not hasMarker("hidden"),
  "collected markers disappear")

print("mod world overview: 4/4 checks passed")
