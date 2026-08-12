-- A tool can persist a checkpoint before the first normal Pokémon save. After
-- a restart the title runtime is deliberately a fresh save skeleton, so it
-- needs a non-allocating binding to the already-selected playthrough -- not a
-- call to the normal active-playthrough storage methods, which would mint an id.
--
-- This is a public SDK contract test. The fixture never reaches into storage
-- paths or launcher slot internals.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("mod title playthrough context")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local Version = require("src.core.Version")
local GameMethods = require("src.core.Game")
local StateStack = require("src.core.StateStack")

local savedEvents, savedHooks = Runtime.events, Runtime.hooks
local realFs = love.filesystem

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
          if child and not seen[child] then seen[child] = true; out[#out + 1] = child end
        end
      end
      table.sort(out)
      return out
    end,
  }
end

local files = {
  ["mods/probe/manifest.json"] =
    '{"id":"probe","name":"probe","version":"1.0.0",'
      .. '"entry":"main.lua","api":2,"profile":"content"}',
  ["mods/probe/main.lua"] = [[
return function(mod)
  _G.MOD_TITLE_STORAGE = mod.storage
  _G.MOD_TITLE_CHECKPOINTS = mod.checkpoints
  mod.events:on("checkpoint.restored", function(ev)
    _G.MOD_TITLE_RESTORE_COUNT = (_G.MOD_TITLE_RESTORE_COUNT or 0) + 1
    _G.MOD_TITLE_RESTORE_KIND = ev.kind
  end)
end
]],
}
local fs = memfs(files)
love.filesystem = fs
-- Production storage and checkpoint resume share the same engine persistence
-- backend. Route the test's default SaveData lookup to this fixture backend so
-- the restart path exercises that shared mapping rather than host test files.
local originalLoadOptions = SaveData.loadOptions
SaveData.loadOptions = function(injectedFs)
  return originalLoadOptions(injectedFs or fs)
end
local active = { save = SaveData.newGame({ version = "red" }) }
local loader = Loader.new({ fs = fs })
loader.game = active
T.check(loader:load({}) == true, "title-context fixture mod loads")

local storage = _G.MOD_TITLE_STORAGE
T.check(type(storage) == "table", "loader exposes the public storage facade")
if type(storage) == "table" then
  local written, writeCode, writeMessage = storage:write(active, "history/index", {
    format = 1, newest = "q0001",
  })
  T.check(written == true,
    "a fresh playthrough can durably store tool history: "
      .. tostring(writeCode or writeMessage))
  local originalId = active.save.meta and active.save.meta.playthroughId
  T.check(type(originalId) == "string" and originalId ~= "",
    "first tool persistence allocates the opaque active playthrough identity")
  local nonTitleSelected, nonTitleCode = storage:selected(active)
  T.check(nonTitleSelected == nil and nonTitleCode == "not_at_title",
    "selected-playthrough storage cannot be used from active gameplay")

  -- Simulate a fresh process/title session. The normal save was never written:
  -- only the engine-owned slot/playthrough mapping and this mod's durable data
  -- exist. The title skeleton must remain unmodified by browsing.
  SaveData.resetSlotState()
  local title = {
    save = SaveData.newGame({ version = "red" }),
    stack = {
      states = { { screenId = "TitleState" } },
      top = function(self) return self.states[#self.states] end,
    },
  }
  T.check(title.save.meta.playthroughId == nil,
    "title starts from an unbound fresh skeleton before normal SAVE")
  T.check(type(storage.selected) == "function",
    "public storage exposes a read-only selected-playthrough binding at title")

  if type(storage.selected) == "function" then
    local selected, selectedCode, selectedMessage = storage:selected(title)
    T.check(type(selected) == "table",
      "title resolves the selected existing playthrough: "
        .. tostring(selectedCode or selectedMessage))
    if type(selected) == "table" then
      T.same(selected:context(), {
        engineVersion = Version.engine,
        gameVersion = "red",
        playthroughId = originalId,
      }, "selected binding reports the durable playthrough without exposing a slot path")
      T.same(selected:read("history/index"), { format = 1, newest = "q0001" },
        "title reads only this mod's selected-playthrough durable history")
      T.check(selected:write("history/title-operation", { allowed = true }) == true,
        "title binding supports safe same-namespace durable operations")
      T.same(selected:read("history/title-operation"), { allowed = true },
        "title durable operation remains scoped to the selected playthrough")
    end
    T.check(title.save.meta.playthroughId == nil,
      "opening title history never allocates or adopts a playthrough identity")
  end

  local function makeRuntime(save, title)
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
    if title then
      -- The failure-injection path needs the same title recovery contract as a
      -- real Game without constructing renderer-owned title content.
      function game:makeTitleState() return { screenId = "TitleState" } end
    end
    return game
  end

  local runtime = makeRuntime(active.save, false)
  local checkpoints = _G.MOD_TITLE_CHECKPOINTS
  T.check(type(checkpoints) == "table", "loader exposes the public checkpoint facade")
  local checkpoint = checkpoints and checkpoints:capture(runtime)
  T.check(type(checkpoint) == "table",
    "a fresh playthrough can capture a stable overworld checkpoint")
  T.check(type(checkpoints and checkpoints.ensureNormalSave) == "function",
    "public checkpoints expose an idempotent first-save anchor")
  local normalWrites = 0
  local writeSave = runtime.writeSave
  function runtime:writeSave()
    normalWrites = normalWrites + 1
    return writeSave(self)
  end
  local anchored, anchorCode, anchorMessage =
    checkpoints:ensureNormalSave(runtime, checkpoint)
  T.check(anchored == true,
    "first persisted checkpoint can anchor normal progress: "
      .. tostring(anchorCode or anchorMessage))
  T.eq(normalWrites, 1,
    "first checkpoint creates exactly one normal Pokemon save")
  local anchoredAgain, againCode = checkpoints:ensureNormalSave(runtime, checkpoint)
  T.check(anchoredAgain == true and againCode == "already_exists",
    "later checkpoints leave the established normal save independent")
  T.eq(normalWrites, 1,
    "idempotent anchor never rewrites the established normal save")
  local normalBytes = files["save.lua"]
  T.check(type(normalBytes) == "string" and normalBytes ~= "",
    "first checkpoint anchor is durably represented before restart")
  local anchoredAt = SaveSerializer.decode(normalBytes).meta.savedAt
  SaveData.resetSlotState()
  local titleRuntime = makeRuntime(SaveData.newGame({ version = "red" }), true)
  titleRuntime.save.options = { volume = 9, bindings = {} }
  T.check(type(checkpoints and checkpoints.resume) == "function",
    "public checkpoints expose validated title-session resume")
  if type(checkpoints and checkpoints.resume) == "function" and checkpoint then
    local resumed, resumeCode, resumeMessage = checkpoints:resume(titleRuntime, checkpoint)
    T.check(resumed == true,
      "title resumes the durable checkpoint: " .. tostring(resumeCode or resumeMessage))
    T.eq(titleRuntime.save.meta.playthroughId, originalId,
      "title bootstrap retains the checkpoint's original playthrough identity")
    T.eq(titleRuntime.save.options.volume, 9,
      "title bootstrap preserves current options rather than rewinding them")
    T.eq(SaveData.selectedNormalSaveInfo({
      version = "red", meta = { playthroughId = originalId },
    }, fs).savedAt, anchoredAt,
      "title bootstrap never rewrites the first normal save")
    T.same(checkpoints:capture(titleRuntime), checkpoint,
      "bootstrapped overworld differentially recaptures the selected checkpoint")
    T.eq(_G.MOD_TITLE_RESTORE_COUNT, 1,
      "a successfully verified title resume emits checkpoint.restored exactly once")
    T.eq(_G.MOD_TITLE_RESTORE_KIND, "overworld",
      "title resume lifecycle reports the reconstructed checkpoint kind")

    -- Force a failure after restoreCheckpointSave has already installed the
    -- checkpoint's canonical save and overworld. Title has no live checkpoint
    -- rollback, so it must rebuild a clean title session.
    SaveData.resetSlotState()
    local failingTitle = makeRuntime(SaveData.newGame({ version = "red" }), true)
    failingTitle.save.options = { volume = 7, bindings = {} }
    local restoreCheckpointSave = failingTitle.restoreCheckpointSave
    function failingTitle:restoreCheckpointSave(loaded)
      restoreCheckpointSave(self, loaded)
      error("forced title reconstruction failure")
    end
    local failed, failureCode = checkpoints:resume(failingTitle, checkpoint)
    T.check(failed == false and failureCode == "resume_failed",
      "failed title reconstruction reports a recoverable bootstrap failure")
    T.eq(failingTitle.stack:top().screenId, "TitleState",
      "failed title reconstruction returns to a usable title session")
    T.check(failingTitle.save.meta.playthroughId == nil,
      "failed title reconstruction restores the unbound title skeleton")
    T.eq(failingTitle.save.options.volume, 7,
      "failed title reconstruction retains current title options")
    T.eq(SaveData.selectedNormalSaveInfo({
      version = "red", meta = { playthroughId = originalId },
    }, fs).savedAt, anchoredAt,
      "failed title reconstruction never rewrites the normal Pokémon save")
    T.eq(_G.MOD_TITLE_RESTORE_COUNT, 1,
      "failed title reconstruction emits no additional restored lifecycle event")
  end

  -- A title policy may compare its own durable checkpoint chronology with the
  -- ordinary CONTINUE target, but it must never receive that save's contents,
  -- slot path, or a way to open another playthrough. This fixture writes the
  -- canonical normal save directly to model an already-completed vanilla SAVE.
  active.save.meta.savedAt = 4321
  T.check(SaveData.save(active.save) == true,
    "fixture updates the selected normal save chronology")
  SaveData.resetSlotState()
  local titleWithNormalSave = {
    save = SaveData.newGame({ version = "red" }),
    stack = { states = { { screenId = "TitleState" } } },
  }
  local selectedWithNormal, normalCode, normalMessage = storage:selected(titleWithNormalSave)
  T.check(type(selectedWithNormal) == "table",
    "legacy-to-slot migration keeps the selected playthrough identity: "
      .. tostring(normalCode or normalMessage))
  if type(selectedWithNormal) == "table" then
    T.eq(selectedWithNormal:context().normalSavedAt, 4321,
      "title selected context exposes only matching normal-save chronology")
  end
  T.check(titleWithNormalSave.save.meta.playthroughId == nil,
    "normal-save chronology lookup does not bind the fresh title skeleton")

  local explicitNewGame = SaveData.newGame({ version = "red" })
  local freshContext = storage:context({ save = explicitNewGame })
  T.check(freshContext and freshContext.playthroughId ~= originalId,
    "an explicit New Game receives a distinct identity and cannot inherit old history")
end

Runtime.events, Runtime.hooks = savedEvents, savedHooks
Runtime.currentMod = nil
_G.MOD_TITLE_STORAGE = nil
_G.MOD_TITLE_CHECKPOINTS = nil
_G.MOD_TITLE_RESTORE_COUNT = nil
_G.MOD_TITLE_RESTORE_KIND = nil
SaveData.resetSlotState()
SaveData.loadOptions = originalLoadOptions
love.filesystem = realFs

T.finish()
