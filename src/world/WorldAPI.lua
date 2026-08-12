-- mod.world: the supported way for mod code to act on the running
-- overworld.  Every method resolves the live OverworldState by scanning
-- the state stack for the isOverworld marker and returns nil, "no
-- overworld" when none is up -- called from the title screen this is a
-- quiet no-op, never a crash.  Reaching into OverworldState internals
-- stays unsupported; anything a mod legitimately needs belongs here.

local Logger = require("src.core.Logger")
local MapLoader = require("src.world.MapLoader")
local MapOverview = require("src.world.MapOverview")
local Party = require("src.pokemon.Party")
local Runtime = require("src.mods.Runtime")

local WorldAPI = {}
WorldAPI.__index = WorldAPI

local NO_OVERWORLD = "no overworld"

local function acceptsMenuInput(game, ow)
  local stack = game and game.stack
  local runner = ow and ow.runner
  return ow and stack and stack.top and stack:top() == ow
    and not ow.transitioning and not ow.flyAnim and not ow.teleportOut
    and not ow.engaging and not ow.emote and not ow.pikaHop and not ow.healAnim
    and not (ow.player and (ow.player.moving or ow.player.inputLocked))
    and not (runner and runner.isRunning and runner:isRunning())
    and #(ow.scriptMoves or {}) == 0
end

local function validPartySlot(party, slot)
  return type(slot) == "number" and slot == math.floor(slot)
    and party[slot] ~= nil
end

function WorldAPI.new(game, modId)
  return setmetatable({ game = game, modId = modId }, WorldAPI)
end

-- the live overworld, or nil.  Game.overworld is the fast path; the stack
-- scan is the authority, so a state pushed over the world (a battle, a
-- menu) still resolves to the world underneath it.
function WorldAPI:overworld()
  local game = self.game
  local stack = game and game.stack
  local states = stack and stack.states
  if states then
    for i = #states, 1, -1 do
      if states[i].isOverworld then return states[i] end
    end
  end
  local ow = game and game.overworld
  if ow and ow.isOverworld and ow.map then return ow end
  return nil
end

function WorldAPI:current()
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  local p = ow.player
  return { mapId = ow.map.id, x = p and p.cellX, y = p and p.cellY,
           facing = p and p.facing }
end

-- Companion UIs may offer party ordering while the player is in free roam.
-- The same guard that makes opening a menu safe keeps scripts, transitions,
-- movement and screens above the overworld from observing a mid-action swap.
function WorldAPI:canReorderParty()
  local game, ow = self.game, self:overworld()
  local party = game and game.save and game.save.party or {}
  return #party > 1 and not not acceptsMenuInput(game, ow)
end

function WorldAPI:reorderParty(fromSlot, toSlot)
  local game, ow = self.game, self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not acceptsMenuInput(game, ow) then return nil, "world is busy" end
  local party = game.save and game.save.party or {}
  if not validPartySlot(party, fromSlot)
      or not validPartySlot(party, toSlot) then
    return nil, "invalid party slot"
  end
  if fromSlot ~= toSlot then
    party[fromSlot], party[toSlot] = party[toSlot], party[fromSlot]
    require("src.core.Sound").play(game.data, "Swap")
  end
  return true
end

-- A compact, read-only view of the active map for minimaps and companion UIs.
-- `rows` describes collision terrain; optional `tileRows` reduces each real
-- 8x8 map tile to its average Game Boy shade ("0" lightest, "3" darkest).
-- `tileDetailRows` preserves one shade per 4x4 quadrant. Markers identify
-- exits and item spots that are still active without exposing world internals.
function WorldAPI:mapOverview()
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  local map, markers = ow.map, {}
  local def = map.def or {}
  for _, warp in ipairs(def.warps or {}) do
    markers[#markers + 1] = { kind = "warp", x = warp.x, y = warp.y }
  end
  local game, save = self.game, self.game.save or {}
  for _, obj in ipairs(def.objects or {}) do
    if obj.item and obj.item ~= "0" and obj.item ~= 0
        and ow.objectVisible(save, map.id, obj) then
      markers[#markers + 1] = { kind = "item", x = obj.x, y = obj.y }
    end
  end
  local hidden = game.data and game.data.field and game.data.field.hiddenItems
  for _, item in ipairs(hidden and hidden[map.id] or {}) do
    local key = map.id .. "_" .. item.x .. "_" .. item.y
    if not (save.hiddenTaken and save.hiddenTaken[key]) then
      markers[#markers + 1] = { kind = "hidden", x = item.x, y = item.y }
    end
  end
  return MapOverview.build(map, markers)
end

-- opts.arrive = "fly" | "teleport" picks the arrival FX; anything else
-- lands the player without one, like a scripted warp.
function WorldAPI:warpTo(mapId, x, y, facing, opts)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not self.game.data.maps[mapId] then
    return nil, "unknown map: " .. tostring(mapId)
  end
  if opts and (opts.arrive == "fly" or opts.arrive == "teleport") then
    ow.arriveWarp = opts.arrive
  end
  ow:startWarpTo(mapId, x, y, facing or "down", opts and opts.onDone,
                 { via = "warp", keepMusic = opts and opts.keepMusic })
  return true
end

-- save.objectToggles is the same store the spawn filter reads, so a toggle
-- on an inactive map takes effect the next time it is entered.
function WorldAPI:toggleObject(mapId, objName, visible)
  local save = self.game and self.game.save
  if not save then return nil, "no save" end
  save.objectToggles = save.objectToggles or {}
  save.objectToggles[mapId] = save.objectToggles[mapId] or {}
  save.objectToggles[mapId][objName] = visible and true or false
  Runtime.emit("world.object_toggled",
    { mapId = mapId, objName = objName, visible = visible and true or false })
  local ow = self:overworld()
  if ow and ow.map and ow.map.id == mapId then
    ow:setMap(mapId, ow.player.cellX, ow.player.cellY, ow.player.facing,
              { seamless = true, via = "reload", keepMusic = true })
  end
  return true
end

function WorldAPI:setFlag(name, value)
  local save = self.game and self.game.save
  if not save or not save.flags then return nil, "no save" end
  save.flags[name] = value
  return true
end

function WorldAPI:getFlag(name)
  local save = self.game and self.game.save
  return save and save.flags and save.flags[name]
end

-- active map only: this mutates the runtime Map and rebuilds the renderer.
-- A layout change that must survive a reload belongs in a maps patch.
function WorldAPI:replaceBlock(bx, by, block)
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  ow:replaceBlock(bx, by, block)
  return true
end

-- objDef uses the same shape as maps[].objects.  Runtime objects are not
-- serialized: a permanent NPC belongs in a maps patch, this is for
-- scripted and dynamic actors the mod re-spawns on map.entered.
function WorldAPI:spawnNpc(mapId, objDef)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if type(objDef) ~= "table" then return nil, "objDef must be a table" end
  local copy = {}
  for k, v in pairs(objDef) do copy[k] = v end
  return ow:addRuntimeObject(mapId, copy, self.modId)
end

function WorldAPI:removeNpc(npcId)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  return ow:removeRuntimeObject(npcId, self.modId)
end

-- a handle onto a live NPC: scriptMove / marchInPlace / face, which is
-- everything the scripted-movement queue exposes
local Handle = {}
Handle.__index = Handle

function Handle:scriptMove(dir, tiles, onDone)
  self.ow:scriptMove(self.npc, dir, tiles or 1, onDone)
  return true
end

function Handle:marchInPlace(onDone)
  self.ow:marchInPlace(self.npc, onDone)
  return true
end

function Handle:face(dir)
  self.npc.facing = dir
  return true
end

function Handle:position()
  return self.npc.cellX, self.npc.cellY
end

function WorldAPI:npc(mapId, indexOrName)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if ow.map and ow.map.id ~= mapId then return nil, "map is not active" end
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def.index == indexOrName or npc.def.name == indexOrName
       or npc.id == indexOrName then
      return setmetatable({ ow = ow, npc = npc, id = npc.id }, Handle)
    end
  end
  return nil, "no such object: " .. tostring(indexOrName)
end

-- FIFO queueing is owned by the script runner; until it lands this runs
-- the rows when nothing else is running and refuses otherwise, so a mod
-- never silently loses a script.
function WorldAPI:queueScript(rows, extra)
  local ow = self:overworld()
  if not ow or not ow.runner then return nil, NO_OVERWORLD end
  if ow.runner:isRunning() then return nil, "a script is already running" end
  ow.runner:run(rows, extra)
  return true
end

-- The supported way to start a wild encounter.  Hand-rolling this -- build a
-- BattleState, push it -- silently costs evolutions and blackout-on-loss
-- (both hang off onFinish -> afterBattle) plus the entry wipe and battle
-- theme (both owned by pushBattle).  Nothing raises when they are missing.
function WorldAPI:startWildBattle(species, level)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not self.game.data.pokemon[species] then
    return nil, "unknown species: " .. tostring(species)
  end
  -- Pokemon.new writes the level through verbatim -- into level, the stat
  -- calc and the exp curve -- so a fraction has to be refused here rather
  -- than round somewhere downstream.  The % test also catches NaN, which
  -- passes both range comparisons.
  level = tonumber(level)
  if not level or level % 1 ~= 0 or level < 1 or level > 100 then
    return nil, "level must be a whole number 1..100"
  end
  -- overworld() resolves the world from UNDER whatever sits on top of it,
  -- so from a battle hook this would otherwise stack a second battle over
  -- the live one -- and on a loss its afterBattle blacks out and warps
  -- with the outer battle still on the stack.
  local BattleTransition = require("src.render.BattleTransition")
  for _, state in ipairs(self.game.stack and self.game.stack.states or {}) do
    if state.awardExp or getmetatable(state) == BattleTransition then
      return nil, "a battle is already running"
    end
  end
  if ow.transitioning then return nil, "the world is mid-warp" end
  -- BattleState.newWild marks the species SEEN before it reports an empty
  -- party, so the party check comes first: a refused call must not leave a
  -- Pokedex entry behind.
  local save = self.game.save
  if not (save and Party.firstHealthy(save.party or {})) then
    return nil, "no healthy party"
  end
  local battle = require("src.battle.BattleState")
    .newWild(self.game, species, level)
  battle.onFinish = function(result) ow:afterBattle(result, battle) end
  ow:pushBattle(battle)
  return true
end

-- drop a map's cached instance so the next load re-reads its record; when
-- it is the active map the world reloads around the player in place
function WorldAPI:invalidateMap(mapId)
  local ow = self:overworld()
  if not ow then
    local had = MapLoader.invalidate(mapId)
    Runtime.emit("map.reloaded", { mapId = mapId, reason = "invalidate" })
    return had
  end
  local ok, err = pcall(ow.reloadMap, ow, mapId, "invalidate")
  if not ok then
    Logger.warn("[%s] invalidateMap %s failed: %s", tostring(self.modId),
                tostring(mapId), tostring(err))
    return nil, tostring(err)
  end
  return true
end

return WorldAPI
