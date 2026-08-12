-- Public mod.checkpoints contract over a semantic Game/StateStack fixture.
-- The mod entry chunk sees no private module; the harness builds the engine side.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local oldGetRandomState = love.math.getRandomState
local oldSetRandomState = love.math.setRandomState
local checkpointRngState = "overworld-rng-A"
love.math.getRandomState = function() return checkpointRngState end
love.math.setRandomState = function(state) checkpointRngState = state end

local T = require("tests.harness").suite("mod checkpoints")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local GameMethods = require("src.core.Game")
local BattleState = require("src.battle.BattleState")
local Fixtures = require("tests.modkit").fixtures
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local Version = require("src.core.Version")

local savedEvents, savedHooks = Runtime.events, Runtime.hooks

local function memfs(files)
  return {
    read = function(path) return files[path] end,
    write = function(path, body) files[path] = body return true end,
    remove = function(path) files[path] = nil return true end,
    createDirectory = function() return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], path)
    end,
    getDirectoryItems = function(path)
      local prefix, seen, out = path .. "/", {}, {}
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            out[#out + 1] = child
          end
        end
      end
      table.sort(out)
      return out
    end,
  }
end

local function baseSave()
  return {
    version = "red",
    meta = { format = 4, mods = {}, playthroughId = "play-a" },
    player = {
      map = "PALLET_TOWN", x = 5, y = 6, facing = "down", surfing = false,
      name = "RED", rival = "BLUE", id = 7,
    },
    money = 3000,
    party = { { species = "BULBASAUR", level = 5, hp = 19,
      moves = { "TACKLE" } } },
    flags = { GOT_STARTER = true },
    inventory = { POTION = 1 },
    pcItems = { POTION = 2 },
    box = { { species = "BULBASAUR", level = 4, hp = 16,
      moves = { "TACKLE" } } },
    boxes = { [2] = { { species = "BULBASAUR", level = 3, hp = 14,
      moves = { "TACKLE" } } } },
    defeatedTrainers = { PALLET_RIVAL = true },
    objectToggles = { PALLET_TOWN = { OAK = false } },
    itemsTaken = { PALLET_TOWN_POTION = true },
    pokedex = { seen = { BULBASAUR = true }, owned = { BULBASAUR = true } },
    modData = {},
    options = { volume = 4, bindings = {} },
  }
end

local function makeGame()
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local game
  local ow = {
    map = { id = "PALLET_TOWN" },
    player = { cellX = 5, cellY = 6, facing = "down", surfing = false },
    scriptMoves = {}, pendingScripts = {}, parallelRunners = {}, parallelQueue = {},
    runner = { isRunning = function() return false end },
  }
  function ow:captureSave(save)
    save.player.map = self.map.id
    save.player.x = self.player.cellX
    save.player.y = self.player.cellY
    save.player.facing = self.player.facing
    save.player.surfing = self.player.surfing and true or false
  end
  function ow:enter(mapId, x, y, facing, opts)
    game.lastEnterOpts = opts
    if game.failNextEnter then
      game.failNextEnter = false
      error("injected reconstruction failure")
    end
    self.map = { id = mapId }
    self.player = {
      cellX = x, cellY = y, facing = facing,
      surfing = game.save.player.surfing and true or false,
    }
    self.scriptMoves, self.pendingScripts = {}, {}
    self.parallelRunners, self.parallelQueue = {}, {}
    self.runner = { isRunning = function() return false end }
  end
  game = setmetatable({
    save = baseSave(), stack = stack, overworld = ow,
    data = {
      pokemon = { BULBASAUR = { dex = 1 } },
      moves = { TACKLE = { pp = 35 } },
      items = { POTION = {} },
      constants = { fallbackMove = "TACKLE" },
      field = { boot = { startMap = "PALLET_TOWN", startX = 5, startY = 6 } },
      maps = {
        PALLET_TOWN = { id = "PALLET_TOWN", width = 10, height = 9 },
        ROUTE_1 = { id = "ROUTE_1", width = 10, height = 18 },
        BROKEN = { id = "BROKEN", width = 10, height = 9 },
      },
    },
  }, { __index = GameMethods })
  stack.states[1] = ow
  return game, ow
end

local files = {
  ["mods/probe/manifest.json"] =
    '{"id":"probe","name":"probe","version":"1.0.0",'
      .. '"entry":"main.lua","api":2,"profile":"content"}',
  ["mods/probe/main.lua"] = [[
return function(mod)
  _G.MOD_CHECKPOINTS = mod.checkpoints
  _G.MOD_HOOKS = mod.hooks
end
]],
}
local game, ow = makeGame()
local loader = Loader.new({ fs = memfs(files) })
loader.game = game
T.check(loader:load({}) == true, "checkpoint fixture mod loads")
local checkpoints = _G.MOD_CHECKPOINTS
T.check(type(checkpoints) == "table",
  "Loader exposes mod.checkpoints through the public mod object")
if type(checkpoints) ~= "table" then
  Runtime.events, Runtime.hooks = savedEvents, savedHooks
  _G.MOD_CHECKPOINTS = nil
  T.finish()
end

local capability = checkpoints:inspect(game)
T.same(capability, { canCapture = true, canRestore = true, kind = "overworld" },
  "plain overworld control is a stable checkpoint boundary")

local function refused(mutator, expectedCode, message)
  local undo = mutator()
  local result = checkpoints:inspect(game)
  T.check(result.canCapture == false and result.reason == expectedCode, message)
  undo()
end

refused(function()
  ow.transitioning = true
  return function() ow.transitioning = nil end
end, "transition_busy", "transition frames are rejected")

refused(function()
  ow.runner = { isRunning = function() return true end }
  return function() ow.runner = { isRunning = function() return false end } end
end, "script_busy", "foreground suspended scripts are rejected")

refused(function()
  ow.parallelRunners = { { isRunning = function() return true end } }
  return function() ow.parallelRunners = {} end
end, "script_busy", "parallel suspended scripts are rejected")

refused(function()
  ow.pendingScripts = { { rows = {} } }
  return function() ow.pendingScripts = {} end
end, "script_busy", "queued scripts are rejected")

refused(function()
  ow.scriptMoves = { { entity = ow.player } }
  return function() ow.scriptMoves = {} end
end, "script_busy", "scripted movement is rejected")

refused(function()
  game.stack.states[2] = { screenId = "StartMenu" }
  return function() game.stack.states[2] = nil end
end, "screen_busy", "modal screens over the overworld are rejected")

refused(function()
  ow.emote = { frames = 1 }
  return function() ow.emote = nil end
end, "animation_busy", "partial overworld animations are rejected")

refused(function()
  ow.player.moving = true
  return function() ow.player.moving = nil end
end, "movement_busy", "partial player movement is rejected")

local titleGame = { save = game.save, stack = {
  top = function() return { screenId = "TitleState" } end,
} }
local titleCapability = checkpoints:inspect(titleGame)
T.check(titleCapability.canCapture == false
    and titleCapability.reason == "not_overworld",
  "title and non-playthrough runtime is rejected")

-- Capture synchronizes semantic position into a detached data-only record.
ow.map.id, ow.player.cellX, ow.player.cellY = "ROUTE_1", 7, 8
ow.player.facing, ow.player.surfing = "left", true
local snapshot, code, message = checkpoints:capture(game)
T.check(snapshot ~= nil, "stable overworld captures: " .. tostring(code or message))
T.eq(snapshot.format, 1, "checkpoint format is explicit")
T.eq(snapshot.kind, "overworld", "checkpoint runtime kind is explicit")
T.same(snapshot.identity, {
    engineVersion = Version.engine,
    gameVersion = "red",
    playthroughId = "play-a",
  },
  "checkpoint carries compatibility identity")
T.same(snapshot.runtime.overworld,
  { map = "ROUTE_1", x = 7, y = 8, facing = "left", surfing = true },
  "checkpoint carries exact semantic overworld position")
T.eq(snapshot.save.player.map, "ROUTE_1",
  "captured progress is synchronized from the live controller")
T.eq(snapshot.save.options, nil, "global settings are excluded from progress rewind")
T.same(snapshot.rng, { love = "overworld-rng-A" },
  "overworld checkpoint carries deterministic gameplay RNG")

local legacy = checkpoints:capture(game)
legacy.rng = nil
checkpointRngState = "legacy-runtime-rng"
local legacyRestored, legacyCode = checkpoints:restore(game, legacy)
T.check(legacyRestored == true,
  "legacy format-1 overworld checkpoint without RNG remains loadable: "
    .. tostring(legacyCode))
T.eq(checkpointRngState, "legacy-runtime-rng",
  "legacy checkpoint leaves the current RNG stream untouched")
checkpointRngState = "overworld-rng-A"

snapshot.save.money = 1
snapshot.runtime.overworld.x = 1
T.eq(game.save.money, 3000, "mutating a checkpoint cannot mutate live progress")
T.eq(ow.player.cellX, 7, "mutating a checkpoint cannot move the live player")

-- Recapture the unmodified canonical A used for the differential roundtrip.
snapshot = checkpoints:capture(game)
local original = snapshot

game.save.money = 999999
game.save.flags.GOT_STARTER = nil
game.save.party[1].hp = 1
game.save.inventory.POTION = 99
game.save.pcItems.POTION = nil
game.save.box = {}
game.save.boxes = {}
game.save.defeatedTrainers.PALLET_RIVAL = nil
game.save.objectToggles.PALLET_TOWN.OAK = true
game.save.itemsTaken.PALLET_TOWN_POTION = nil
game.save.pokedex.seen.BULBASAUR = nil
game.save.pokedex.owned.BULBASAUR = nil
game.save.options.volume = 9
checkpointRngState = "overworld-rng-B"
ow.map.id, ow.player.cellX, ow.player.cellY = "PALLET_TOWN", 2, 3
ow.player.facing, ow.player.surfing = "up", false

local restored, restoreCode, restoreMessage = checkpoints:restore(game, original)
T.check(restored == true,
  "valid checkpoint restores: " .. tostring(restoreCode or restoreMessage))
local recaptured = checkpoints:capture(game)
T.same(recaptured, original,
  "capture A, mutate B, restore A, capture A2 yields normalized A == A2")
T.eq(game.save.options.volume, 9,
  "checkpoint restoration preserves current global settings")
T.eq(checkpointRngState, "overworld-rng-A",
  "overworld checkpoint restores gameplay RNG")
T.eq(game.save.inventory.POTION, 1, "inventory progress roundtrips")
T.eq(game.save.pcItems.POTION, 2, "PC item progress roundtrips")
T.eq(game.save.box[1].hp, 16, "current box Pokemon roundtrips")
T.eq(game.save.boxes[2][1].hp, 14, "stored box collection roundtrips")
T.eq(game.save.defeatedTrainers.PALLET_RIVAL, true,
  "defeated trainer progress roundtrips")
T.eq(game.save.objectToggles.PALLET_TOWN.OAK, false,
  "map object toggle progress roundtrips")
T.eq(game.save.itemsTaken.PALLET_TOWN_POTION, true,
  "taken-object progress roundtrips")
T.eq(game.save.pokedex.owned.BULBASAUR, true, "Pokedex progress roundtrips")
T.check(game.lastEnterOpts and game.lastEnterOpts.checkpoint == true,
  "engine reconstruction is marked to suppress map-entry side effects")

-- Compatibility and schema failures occur before any mutation.
local beforeRejected = checkpoints:capture(game)
local wrongFormat = checkpoints:capture(game)
wrongFormat.format = 99
restored, restoreCode = checkpoints:restore(game, wrongFormat)
T.check(not restored and restoreCode == "unsupported_format",
  "unknown checkpoint format is rejected")

local wrongGame = checkpoints:capture(game)
wrongGame.identity.gameVersion = "blue"
restored, restoreCode = checkpoints:restore(game, wrongGame)
T.check(not restored and restoreCode == "wrong_game",
  "another game version is rejected")

local wrongProfile = checkpoints:capture(game)
wrongProfile.identity.playthroughId = "play-b"
restored, restoreCode = checkpoints:restore(game, wrongProfile)
T.check(not restored and restoreCode == "wrong_playthrough",
  "another playthrough is rejected")

local badMap = checkpoints:capture(game)
badMap.runtime.overworld.map = "MISSING_MAP"
badMap.save.player.map = "MISSING_MAP"
restored, restoreCode = checkpoints:restore(game, badMap)
T.check(not restored and restoreCode == "invalid_map",
  "unknown content reference is rejected")
T.same(checkpoints:capture(game), beforeRejected,
  "validation failures leave the live state unchanged")

local invalidGame = makeGame()
local badSpecies = checkpoints:capture(invalidGame)
badSpecies.save.party[1].species = "MISSING_SPECIES"
restored, restoreCode = checkpoints:restore(invalidGame, badSpecies)
T.check(not restored and restoreCode == "invalid_content",
  "unknown Pokemon content is rejected before reconstruction")
T.eq(invalidGame.save.party[1].species, "BULBASAUR",
  "invalid Pokemon content leaves the live party unchanged")

-- A reconstruction exception rolls back to the exact pre-operation state.
local target = checkpoints:capture(game)
target.runtime.overworld.map = "BROKEN"
target.runtime.overworld.x, target.runtime.overworld.y = 1, 1
target.save.player.map = "BROKEN"
target.save.player.x, target.save.player.y = 1, 1
target.save.money = 42
local beforeFailure = checkpoints:capture(game)
game.failNextEnter = true
restored, restoreCode = checkpoints:restore(game, target)
T.check(not restored and restoreCode == "restore_failed",
  "reconstruction exception is returned as a structured failure")
T.same(checkpoints:capture(game), beforeFailure,
  "failed reconstruction rolls back the complete pre-operation checkpoint")

-- The same public facade must carry a real battle checkpoint end to end. The
-- engine-side fixture is deliberately constructed outside the probe mod; the
-- mod sees and calls only mod.checkpoints.
local function makeBattleGame()
  local data = Fixtures.fresh()
  local save = SaveData.newGame()
  save.meta.playthroughId = "public-battle-playthrough"
  save.party = { Pokemon.new(data, "FIXMON_A", 20) }
  -- The tiny fixture registry intentionally omits several full-game defaults.
  -- Normalize those once, then place the save on its fixture map.
  SaveData.validate(save, data)
  save.player.map, save.player.x, save.player.y = "FIX_TOWN", 2, 3
  save.player.facing, save.player.surfing = "left", false
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local battleGame
  local battleOw = {
    map = { id = "FIX_TOWN" },
    player = { cellX = 2, cellY = 3, facing = "left", surfing = false },
    runner = { isRunning = function() return false end },
    parallelRunners = {}, pendingScripts = {}, parallelQueue = {}, scriptMoves = {},
  }
  function battleOw:captureSave(target)
    target.player.map = self.map.id
    target.player.x, target.player.y = self.player.cellX, self.player.cellY
    target.player.facing = self.player.facing
    target.player.surfing = self.player.surfing and true or false
  end
  function battleOw:enter(mapId, x, y, facing)
    self.map = { id = mapId }
    self.player = { cellX = x, cellY = y, facing = facing, surfing = false }
  end
  function battleOw:restoreBattleContinuation(restoredBattle, origin)
    if origin.kind ~= "wild_encounter" or origin.map ~= self.map.id then
      return false
    end
    restoredBattle.onFinish = function() end
    return true
  end
  battleGame = setmetatable({
    data = data, save = save, stack = stack, overworld = battleOw,
  }, { __index = GameMethods })
  stack.states[1] = battleOw
  local battle = BattleState.newWild(battleGame, "FIXMON_B", 12)
  battle.phase, battle.queue = "menu", {}
  battle.checkpointOrigin = { kind = "wild_encounter", map = "FIX_TOWN" }
  battle.musicKind = battle:computeMusicKind()
  battle.onFinish = function() end
  stack.states[2] = battle
  return battleGame, battle
end

checkpointRngState = "public-battle-rng-A"
local battleGame, liveBattle = makeBattleGame()
T.same(checkpoints:inspect(battleGame), {
  canCapture = true, canRestore = true, kind = "battle",
}, "public mod.checkpoints reports a settled battle boundary")
liveBattle.turnCount = 4
liveBattle.player.stages.attack = 2
local battleSnapshot, battleCaptureCode = checkpoints:capture(battleGame)
T.check(battleSnapshot and battleSnapshot.kind == "battle",
  "public mod.checkpoints captures a data-only battle: "
    .. tostring(battleCaptureCode))
if battleSnapshot then
  battleGame.save.money = 1
  liveBattle.turnCount = 99
  checkpointRngState = "public-battle-rng-B"
  local battleRestored, battleRestoreCode, battleRestoreMessage = checkpoints:restore(
    battleGame, battleSnapshot)
  T.check(battleRestored == true,
    "public mod.checkpoints reconstructs a battle: "
      .. tostring(battleRestoreCode) .. " / " .. tostring(battleRestoreMessage))
  local restoredBattle = battleGame.stack:top()
  T.eq(restoredBattle.turnCount, 4,
    "public battle reconstruction restores the exact turn")
  T.eq(restoredBattle.player.stages.attack, 2,
    "public battle reconstruction restores battler stages")
  T.eq(checkpointRngState, "public-battle-rng-A",
    "public battle reconstruction restores gameplay RNG")
  T.same(checkpoints:capture(battleGame), battleSnapshot,
    "public battle capture/restore/capture is a normalized differential roundtrip")
end

-- The mod receives the normal public hook facade, never BattleState. START
-- at the restored safe decision reaches its semantic auxiliary action without
-- selecting a native command.
local auxiliaryCalls = 0
_G.MOD_HOOKS:wrap("battle.menu_auxiliary", function(nextFn, liveGame, context)
  auxiliaryCalls = auxiliaryCalls + 1
  T.check(liveGame == battleGame, "public battle auxiliary action receives the game")
  T.same(context, { kind = "wild" }, "public auxiliary context is data-only")
  return true
end)
battleGame.input = { wasPressed = function(_, button) return button == "start" end }
local boundary = battleGame.stack:top()
local originalMenuIndex = boundary.menuIndex
boundary:update(1 / 60)
T.eq(auxiliaryCalls, 1, "public mod hook receives START at the checkpoint boundary")
T.eq(boundary.phase, "menu", "public auxiliary hook does not advance the turn")
T.eq(boundary.menuIndex, originalMenuIndex, "public auxiliary hook preserves cursor")

Runtime.events, Runtime.hooks = savedEvents, savedHooks
Runtime.currentMod = nil
_G.MOD_CHECKPOINTS = nil
_G.MOD_HOOKS = nil
love.math.getRandomState = oldGetRandomState
love.math.setRandomState = oldSetRandomState

T.finish()
