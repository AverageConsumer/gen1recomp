-- mod.world: the supported way for mod code to act on the running
-- overworld.  Every method resolves the live OverworldState by scanning
-- the state stack for the isOverworld marker and returns nil, "no
-- overworld" when none is up -- called from the title screen this is a
-- quiet no-op, never a crash.  Reaching into OverworldState internals
-- stays unsupported; anything a mod legitimately needs belongs here.

local Logger = require("src.core.Logger")
local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")
local MapLoader = require("src.world.MapLoader")
local Runtime = require("src.mods.Runtime")

local WorldAPI = {}
WorldAPI.__index = WorldAPI

local NO_OVERWORLD = "no overworld"
local DIG_TILESETS = { FOREST = true, CEMETERY = true, CAVERN = true,
                       FACILITY = true, INTERIOR = true }
local RODS = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }

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

local function acceptsMenuInput(game, ow)
  local runner = ow and ow.runner
  local stack = game and game.stack
  return ow and stack and stack.top and stack:top() == ow
    and not ow.transitioning and not ow.flyAnim and not ow.teleportOut
    and not ow.engaging and not ow.emote and not ow.pikaHop and not ow.healAnim
    and not (ow.player and (ow.player.moving or ow.player.inputLocked))
    and not (runner and runner.isRunning and runner:isRunning())
    and #(ow.scriptMoves or {}) == 0
end

function WorldAPI:canReorderParty()
  local ow, game = self:overworld(), self.game
  return not not (game and game.save and #(game.save.party or {}) > 1
    and acceptsMenuInput(game, ow))
end

-- The same field-only party reorder offered by PartyMenu's SWITCH command.
-- Keeping the mutation behind mod.world lets companion UIs use it without
-- reaching into the save, and makes every caller share the overworld lockout.
function WorldAPI:reorderParty(fromSlot, toSlot)
  local ow, game = self:overworld(), self.game
  if not ow then return nil, NO_OVERWORLD end
  if not acceptsMenuInput(game, ow) then return nil, "world is busy" end
  local party = game.save and game.save.party or {}
  fromSlot, toSlot = tonumber(fromSlot), tonumber(toSlot)
  if not fromSlot or fromSlot ~= math.floor(fromSlot) or not party[fromSlot]
      or not toSlot or toSlot ~= math.floor(toSlot) or not party[toSlot] then
    return nil, "invalid party slot"
  end
  if fromSlot ~= toSlot then
    party[fromSlot], party[toSlot] = party[toSlot], party[fromSlot]
    require("src.core.Sound").play(game.data, "Swap")
  end
  return true
end

local function outside(game, ow)
  return Map.isOutside(ow.map.def,
    FieldDefaults.field(game.data, "outsideTilesets"))
end

local function knows(mon, moveId)
  for _, move in ipairs(mon.moves or {}) do
    if move.id == moveId then return true end
  end
  return false
end

local function monInfo(game, mon, slot)
  local def = game.data.pokemon[mon.species] or {}
  return { slot = slot, species = mon.species,
    name = mon.nickname or def.name or mon.species, level = mon.level,
    hp = mon.hp, maxHp = mon.stats and mon.stats.hp or mon.hp }
end

local function softboiledSources(game)
  local party, sources = game.save.party or {}, {}
  for sourceSlot, source in ipairs(party) do
    local heal = source.stats and math.floor(source.stats.hp / 5) or 0
    if knows(source, "SOFTBOILED") and source.hp > heal then
      local info = monInfo(game, source, sourceSlot)
      info.targets = {}
      for targetSlot, target in ipairs(party) do
        if target ~= source and target.hp > 0 and target.stats
           and target.hp < target.stats.hp then
          info.targets[#info.targets + 1] = monInfo(game, target, targetSlot)
        end
      end
      if #info.targets > 0 then sources[#sources + 1] = info end
    end
  end
  return sources
end

-- Contextual shortcuts only: acquired actions that would succeed here and
-- now.  Locked moves and unusable scenery stay absent, so mods do not need
-- to copy badges, map rules or facing-tile checks.
function WorldAPI:availableFieldActions()
  local ow = self:overworld()
  local game, out = self.game, {}
  if not (ow and ow.map and ow.player and game and game.save) then return out end
  local save, inv = game.save, game.save.inventory or {}
  local function add(id, label) out[#out + 1] = { id = id, label = label } end

  if (inv.BICYCLE or 0) > 0 and not ow.player.surfing
     and (save.onBike or ow:bikeAllowed(ow.map.id)) then
    add("bicycle", save.onBike and "BIKE OFF" or "BICYCLE")
  end
  if inv.CASCADEBADGE and ow:useCutFieldMove() == "ok" then add("cut", "CUT") end
  if inv.SOULBADGE then
    local surf = ow:useSurfFieldMove()
    if surf == "ok" or surf == "dismount" then
      add("surf", surf == "dismount" and "LEAVE WATER" or "SURF")
    end
  end
  local fx, fy = ow.player:facingCell()
  if ow.map:inBounds(fx, fy) and ow.map:isWaterCell(fx, fy) then
    local rods = {}
    for _, id in ipairs(RODS) do
      if (inv[id] or 0) > 0 then
        local def = game.data.items and game.data.items[id]
        rods[#rods + 1] = { id = id, label = def and def.name or id }
      end
    end
    if #rods > 0 then
      add("fish", "FISH")
      out[#out].rods = rods
    end
  end
  if inv.RAINBOWBADGE and not ow.strengthActive
     and ow:partyKnows("STRENGTH") then add("strength", "STRENGTH") end
  if inv.BOULDERBADGE and ow.dark and ow:partyKnows("FLASH") then
    add("flash", "FLASH")
  end
  if DIG_TILESETS[ow.map.def.tileset] and ow.map.id ~= "AGATHAS_ROOM"
     and ow:partyKnows("DIG") then add("dig", "DIG") end
  if outside(game, ow) and ow:partyKnows("TELEPORT") then
    add("teleport", "TELEPORT")
  end
  local sources = softboiledSources(game)
  if #sources > 0 then
    add("softboiled", "SOFTBOILED")
    out[#out].sources = sources
  end
  return out
end

function WorldAPI:useFieldAction(id, opts)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if self.game.stack:top() ~= ow then return nil, "world is busy" end
  local found
  for _, action in ipairs(self:availableFieldActions()) do
    if action.id == id then found = action break end
  end
  if not found then return nil, "field action unavailable" end

  if id == "bicycle" then
    ow:toggleBike()
  elseif id == "cut" then
    local x, y = ow.player:facingCell()
    ow:tryCut(x, y)
  elseif id == "surf" then
    if ow:useSurfFieldMove() == "dismount" then
      ow:stopSurfing()
    else
      local x, y = ow.player:facingCell()
      ow:trySurf(x, y)
    end
  elseif id == "fish" then
    local rod = opts and opts.rod
    if not rod and #found.rods == 1 then rod = found.rods[1].id end
    local allowed
    for _, choice in ipairs(found.rods or {}) do
      if choice.id == rod then allowed = true break end
    end
    if not allowed then return nil, "fishing rod unavailable" end
    ow:useFishingRod(rod)
  elseif id == "strength" then
    ow:useStrengthFieldMove()
  elseif id == "flash" then
    ow:useFlashFieldMove()
  elseif id == "dig" or id == "teleport" then
    ow:beginTeleportOut()
  elseif id == "softboiled" then
    local sourceSlot, targetSlot = opts and tonumber(opts.sourceSlot),
                                   opts and tonumber(opts.targetSlot)
    local allowed
    for _, source in ipairs(found.sources or {}) do
      if source.slot == sourceSlot then
        for _, target in ipairs(source.targets or {}) do
          if target.slot == targetSlot then allowed = true break end
        end
      end
    end
    if not allowed then return nil, "softboiled target unavailable" end
    ow:useSoftboiledFieldMove(self.game.save.party[sourceSlot],
                              self.game.save.party[targetSlot])
  end
  return true
end

function WorldAPI:canFly()
  local ow, game = self:overworld(), self.game
  local inv = game and game.save and game.save.inventory or {}
  return ow ~= nil and ow.map ~= nil and not not inv.THUNDERBADGE
    and outside(game, ow) and ow:partyKnows("FLY") ~= nil
end

function WorldAPI:flyTo(mapId)
  local ow = self:overworld()
  if not self:canFly() then return nil, "fly unavailable" end
  if self.game.stack:top() ~= ow then return nil, "world is busy" end
  local save, field = self.game.save, self.game.data.field or {}
  if not (save.visited and save.visited[mapId]
      and field.flyWarps and field.flyWarps[mapId]) then
    return nil, "destination unavailable"
  end
  ow:flyTo(mapId)
  return true
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
