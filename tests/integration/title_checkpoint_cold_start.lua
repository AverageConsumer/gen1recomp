package.path = "./?.lua;./?/init.lua;" .. package.path

local phase, root = arg[1], arg[2]
assert(phase == "capture" or phase == "resume", "phase must be capture or resume")
assert(type(root) == "string" and root ~= "", "test needs a persistence root")

local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function full(path) return root .. "/" .. path end

local fs = {}
function fs.createDirectory(path)
  return os.execute("mkdir -p " .. quote(full(path))) == 0
end
function fs.write(path, body)
  local parent = path:match("^(.*)/[^/]+$")
  if parent then assert(fs.createDirectory(parent)) end
  local handle = assert(io.open(full(path), "wb"))
  handle:write(body)
  handle:close()
  return true
end
function fs.read(path)
  local handle = io.open(full(path), "rb")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end
function fs.remove(path)
  os.remove(full(path))
  return true
end
function fs.getInfo(path)
  if os.execute("test -d " .. quote(full(path))) == 0 then
    return { type = "directory" }
  end
  local handle = io.open(full(path), "rb")
  if handle then handle:close(); return { type = "file" } end
  return nil
end
function fs.load(path)
  local body = fs.read(path)
  if not body then return nil, "no file: " .. path end
  return load(body, "@" .. path)
end
function fs.getDirectoryItems(path)
  local items = {}
  local pipe = io.popen("find " .. quote(full(path))
    .. " -mindepth 1 -maxdepth 1 -printf '%f\\n' 2>/dev/null")
  if pipe then
    for item in pipe:lines() do items[#items + 1] = item end
    pipe:close()
  end
  table.sort(items)
  return items
end
function fs.getSaveDirectory() return root end

love = require("tests.love_stub")
love.filesystem = fs

local Loader = require("src.mods.Loader")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameMethods = require("src.core.Game")
local StateStack = require("src.core.StateStack")

local function writeProbe()
  fs.write("mods/cold_start_probe/manifest.json",
    '{"id":"cold_start_probe","name":"cold start probe","version":"1.0.0",'
      .. '"entry":"main.lua","api":2,"profile":"content"}')
  fs.write("mods/cold_start_probe/main.lua", [[
return function(mod)
  _G.COLD_STORAGE = mod.storage
  _G.COLD_CHECKPOINTS = mod.checkpoints
end
]])
end

local function runtime(save, title)
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local game
  local overworld = {
    map = { id = "PALLET_TOWN" },
    player = { cellX = 3, cellY = 6, facing = "down", surfing = false },
    scriptMoves = {}, pendingScripts = {}, parallelRunners = {}, parallelQueue = {},
    runner = { isRunning = function() return false end },
  }
  function overworld:captureSave(target)
    target.player.map, target.player.x, target.player.y = self.map.id,
      self.player.cellX, self.player.cellY
    target.player.facing, target.player.surfing = self.player.facing,
      self.player.surfing and true or false
  end
  function overworld:enter(mapId, x, y, facing)
    self.map = { id = mapId }
    self.player = { cellX = x, cellY = y, facing = facing,
      surfing = game.save.player.surfing and true or false }
    self.scriptMoves, self.pendingScripts = {}, {}
    self.parallelRunners, self.parallelQueue = {}, {}
    self.runner = { isRunning = function() return false end }
  end
  game = setmetatable({
    save = save, stack = stack, overworld = overworld,
    data = {
      pokemon = {}, moves = { TACKLE = { pp = 35 } }, items = { POTION = {} },
      constants = { fallbackMove = "TACKLE" },
      field = { boot = { startMap = "PALLET_TOWN", startX = 3, startY = 6 } },
      maps = { PALLET_TOWN = { id = "PALLET_TOWN", width = 10, height = 9 } },
    },
  }, { __index = GameMethods })
  stack.states[1] = title and { screenId = "TitleState" } or overworld
  if title then function game:makeTitleState() return { screenId = "TitleState" } end end
  return game
end

writeProbe()
SaveData.resetSlotState()
local loader = Loader.new({ fs = fs })

if phase == "capture" then
  local game = runtime(SaveData.newGame({ version = "red" }), false)
  loader.game = game
  assert(loader:load({}) == true)
  assert(_G.COLD_STORAGE:write(game, "history/index", { newest = "q0001" }))
  local checkpoint = assert(_G.COLD_CHECKPOINTS:capture(game))
  assert(_G.COLD_STORAGE:write(game, "history/q0001", checkpoint))
  local id = assert(game.save.meta.playthroughId)
  assert(_G.COLD_CHECKPOINTS:ensureNormalSave(game, checkpoint))
  local normal = assert(SaveData.load("red"))
  assert(normal.meta.playthroughId == id)
  fs.write("cold-start-witness.lua", SaveSerializer.encode({ playthroughId = id }))
  print("cold-start capture persisted")
else
  local title = runtime(SaveData.newGame({ version = "red" }), true)
  title.save.options = { volume = 7, bindings = {} }
  loader.game = title
  assert(loader:load({}) == true)
  local selected = assert(_G.COLD_STORAGE:selected(title))
  local witness = assert(SaveSerializer.decode(assert(fs.read("cold-start-witness.lua"))))
  assert(selected:context().playthroughId == witness.playthroughId)
  assert(selected:read("history/index").newest == "q0001")
  local checkpoint = assert(selected:read("history/q0001"))
  assert(_G.COLD_CHECKPOINTS:resume(title, checkpoint))
  assert(title.save.meta.playthroughId == witness.playthroughId)
  assert(title.save.options.volume == 7)
  assert(SaveSerializer.encode(_G.COLD_CHECKPOINTS:capture(title))
    == SaveSerializer.encode(checkpoint))
  local normal = assert(SaveData.load("red"))
  assert(normal.meta.playthroughId == witness.playthroughId)
  print("cold-start resume reconstructed")
end
