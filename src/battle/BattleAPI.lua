-- Safe, semantic battle controls for mods.  The facade exposes copied
-- snapshots and validates every intent against the current state revision;
-- mods never receive a mutation method for HP, PP, inventory or party data.

local Bag = require("src.inventory.Bag")
local Damage = require("src.battle.Damage")
local ItemEffects = require("src.inventory.ItemEffects")
local TextBox = require("src.render.TextBox")
local TypeChart = require("src.battle.TypeChart")

local BattleAPI = {}
BattleAPI.__index = BattleAPI

function BattleAPI.new(game, modId)
  return setmetatable({
    game = game,
    modId = modId,
    revision = 0,
    signature = nil,
    lastIntentId = nil,
  }, BattleAPI)
end

local function activeBattle(game)
  local states = game and game.stack and game.stack.states or {}
  local battle
  for i = #states, 1, -1 do
    if states[i].isBattleState then
      battle = states[i]
      break
    end
  end
  return battle, states[#states]
end

local function monName(data, mon)
  local def = mon and data.pokemon[mon.species]
  return (mon and mon.nickname) or (def and def.name) or (mon and mon.species)
end

local function monCopy(data, mon, active)
  if not mon then return nil end
  return {
    species = mon.species,
    name = monName(data, mon),
    level = mon.level,
    hp = mon.hp,
    maxHp = mon.stats and mon.stats.hp or mon.hp,
    status = mon.status,
    active = active and true or false,
  }
end

local function visibleMessage(battle, top)
  local source = top and top.isTextBox and top or top == battle and battle
  local lines = source and source.visibleText and source:visibleText()
  if not lines then return nil end
  local copy = {}
  for i, line in ipairs(lines) do copy[i] = tostring(line) end
  return copy
end

local function battleSignature(game, battle, top)
  if not battle then return "none" end
  local parts = {
    tostring(battle), tostring(top), battle.phase or "",
    tostring(battle.turnCount or 0), tostring(#(battle.queue or {})),
    tostring(battle.current), tostring(battle.msgWaiting),
    tostring(battle.msgPrompt),
    tostring(battle.menuIndex), tostring(battle.mimicIndex),
    tostring(battle.safari and battle.safari.balls),
    tostring(battle.baitFactor), tostring(battle.escapeFactor),
    tostring(battle.ghost), tostring(battle.noCatch),
    tostring(top and top.isTextBox and top.waiting),
    tostring(top and top.isTextBox and top.done),
    table.concat(visibleMessage(battle, top) or {}, "\n"),
  }
  for _, move in ipairs(battle.mimicMoves or {}) do
    parts[#parts + 1] = tostring(move.slot) .. ":" .. tostring(move.id)
  end
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    local mon = battler and battler.mon
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon and mon.hp)
    parts[#parts + 1] = tostring(mon and mon.status)
    parts[#parts + 1] = table.concat(battler and battler.curTypes or {}, ",")
    parts[#parts + 1] = tostring(battler and battler.stages
      and battler.stages.accuracy)
    parts[#parts + 1] = tostring(battler and battler.stages
      and battler.stages.evasion)
    parts[#parts + 1] = tostring(battler and battler.xAccuracy)
    parts[#parts + 1] = tostring(battler and battler.invulnerable)
  end
  parts[#parts + 1] = tostring(battle.ruleset and battle.ruleset.name)
  for _, mon in ipairs(game.save.party or {}) do
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon.hp)
    parts[#parts + 1] = tostring(mon.status)
  end
  for id, count in pairs(game.save.inventory or {}) do
    if ItemEffects.isBall(id) or ItemEffects.isBattleMedicine(id) then
      parts[#parts + 1] = id .. "=" .. tostring(count)
    end
  end
  return table.concat(parts, "|")
end

function BattleAPI:_revision(battle, top)
  local signature = battleSignature(self.game, battle, top)
  if signature ~= self.signature then
    self.signature = signature
    self.revision = self.revision + 1
  end
  return self.revision
end

local IMMUNITY_ONLY = {
  SPECIAL_DAMAGE_EFFECT = true,
  SUPER_FANG_EFFECT = true,
  OHKO_EFFECT = true,
}

local function movePreview(battle, move, def)
  local record = battle.effectRecord and battle:effectRecord(def.effect)
  local power = def.power or 0
  local typeMult
  if power > 0 and move.id ~= "COUNTER" then
    local raw = TypeChart.effectiveness(def.type, battle.enemy.curTypes or {})
    if IMMUNITY_ONLY[def.effect] then
      typeMult = raw == 0 and 0 or 10
    elseif not (record and record.chooseDamage) then
      typeMult = raw
    end
  end

  local hitChance
  if record and record.neverMiss then
    hitChance = 100
  elseif record and record.gate then
    -- OHKO and Dream Eater have non-accuracy gates.  A raw accuracy
    -- percentage would claim a success chance the engine does not promise.
    hitChance = nil
  elseif power > 0 or (record and record.accuracyChecked) then
    hitChance = battle.enemy.invulnerable and 0
      or Damage.accuracyChance(battle.ruleset, def,
                               battle.player, battle.enemy)
  end
  local displayPower = power > 0 and move.id ~= "COUNTER"
    and not IMMUNITY_ONLY[def.effect]
    and not (record and record.chooseDamage) and power or nil
  return typeMult, hitChance, displayPower
end

local function moveCopies(game, battle)
  local out = {}
  for slot, move in ipairs(battle.player.curMoves or {}) do
    local def = game.data.moves[move.id] or {}
    local mult, hitChance, displayPower = movePreview(battle, move, def)
    out[#out + 1] = {
      slot = slot,
      id = move.id,
      name = def.name or move.id,
      pp = move.pp,
      maxPp = (def.pp or move.pp or 0)
        + (move.ppUps or 0) * math.floor((def.pp or 0) / 5),
      type = def.type,
      power = def.power,
      accuracy = def.accuracy,
      displayPower = displayPower,
      hitChance = hitChance,
      effectiveness = mult,
      disabled = battle.player.disabledSlot == slot,
    }
  end
  return out
end

local function itemCopies(game, battle, catchable)
  local out = {}
  for id, count in pairs(game.save.inventory or {}) do
    if count > 0
       and (ItemEffects.isBall(id) or ItemEffects.isBattleMedicine(id)) then
      local def = game.data.items[id] or {}
      local ball = ItemEffects.isBall(id)
      out[#out + 1] = {
        id = id,
        name = def.name or id,
        count = count,
        ball = ball,
        needsTarget = not ball,
        catchChance = ball and catchable and battle.catchChance
          and battle:catchChance(id) or nil,
      }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function mimicCopies(game, battle)
  local out = {}
  for i, move in ipairs(battle.mimicMoves or {}) do
    local def = game.data.moves[move.id] or {}
    out[i] = { index = i, slot = move.slot, id = move.id,
      name = def.name or move.id }
  end
  return out
end

function BattleAPI:snapshot()
  local game = self.game
  local battle, top = activeBattle(game)
  if not battle then return nil end
  local kind = battle:battleKind()
  local catchable = kind == "wild" and not battle.ghost and not battle.noCatch
  local supported = kind ~= "oldman" and kind ~= "link"
  local forcedParty = top and top.isPartyMenu and top.battle == battle
                      and top.forceSwitch
  local canAdvance = supported and (
    (top == battle and battle.phase == "messages"
      and battle.current and (battle.msgWaiting or battle.msgPrompt))
    or (top and top.isTextBox and not top.choice
      and (top.waiting or top.done)))
  local prompt = "locked"
  if canAdvance then
    prompt = "advance"
  elseif supported and forcedParty then
    prompt = "party"
  elseif supported and top == battle and kind == "safari"
      and battle.phase == "menu" then
    prompt = "safari"
  elseif supported and top == battle and battle.phase == "mimicSelect" then
    prompt = "mimic"
  elseif supported and top == battle and battle.phase == "menu" then
    prompt = "menu"
  elseif supported and top == battle and battle.phase == "moveSelect" then
    prompt = "moves"
  end

  local party = {}
  for i, mon in ipairs(game.save.party or {}) do
    party[i] = monCopy(game.data, mon, battle.player
      and battle.player.mon == mon)
    party[i].slot = i
  end
  return {
    revision = self:_revision(battle, top),
    kind = kind,
    catchable = catchable,
    prompt = prompt,
    message = visibleMessage(battle, top),
    turn = battle.turnCount or 0,
    player = monCopy(game.data, battle.player and battle.player.mon, true),
    enemy = monCopy(game.data, battle.enemy and battle.enemy.mon, true),
    party = party,
    moves = moveCopies(game, battle),
    items = itemCopies(game, battle, catchable),
    safariBalls = battle.safari and battle.safari.balls or nil,
    mimicMoves = mimicCopies(game, battle),
    mimicIndex = battle.mimicIndex,
  }
end

local function showMessages(game, messages, onDone)
  if not messages or #messages == 0 then
    if onDone then onDone() end
    return
  end
  game.stack:push(TextBox.new(game, table.concat(messages, "\f"), onDone))
end

local function validPartyMon(game, slot)
  if type(slot) ~= "number" or slot % 1 ~= 0 then return nil end
  return game.save.party and game.save.party[slot]
end

function BattleAPI:_switch(battle, top, slot)
  local mon = validPartyMon(self.game, slot)
  if not mon then return nil, "invalid party slot" end
  if mon.hp <= 0 then return nil, "pokemon has fainted" end
  if battle.player and battle.player.mon == mon then
    return nil, "pokemon is already active"
  end
  if top and top.isPartyMenu and top.battle == battle and top.forceSwitch then
    self.game.stack:pop()
    top.onSwitch(mon)
    return true
  end
  if top ~= battle or battle.phase ~= "menu" then
    return nil, "party choice is not active"
  end
  battle:resolveSwitch(mon)
  return true
end

function BattleAPI:_useItem(battle, top, itemId, targetSlot)
  if top ~= battle or battle.phase ~= "menu" then
    return nil, "item choice is not active"
  end
  local count = self.game.save.inventory
    and self.game.save.inventory[itemId] or 0
  if count <= 0 then return nil, "item is not in the bag" end
  local isBall = ItemEffects.isBall(itemId)
  if not isBall and not ItemEffects.isBattleMedicine(itemId) then
    return nil, "item is not supported in battle"
  end
  local target
  if not isBall then
    target = validPartyMon(self.game, targetSlot)
    if not target then return nil, "invalid item target" end
  end

  local result, messages = ItemEffects.use(
    self.game.data, self.game.save, itemId, target, battle)
  if result == "ball" then
    Bag.remove(self.game.save, itemId, 1)
    battle.phase = "messages"
    battle.afterQueue = "menu"
    battle:throwBall(itemId)
    return true
  elseif result == "consumed" then
    Bag.remove(self.game.save, itemId, 1)
    battle.phase = "messages"
    battle.afterQueue = "menu"
    showMessages(self.game, messages, function() battle:itemUsed({}) end)
    return true
  elseif result == "failed" then
    showMessages(self.game, messages)
    return true
  end
  return nil, "item cannot be used here"
end

function BattleAPI:submit(intent)
  if type(intent) ~= "table" then return nil, "intent must be a table" end
  if type(intent.id) ~= "number" or intent.id % 1 ~= 0 then
    return nil, "intent id must be an integer"
  end
  if intent.id == self.lastIntentId then return nil, "duplicate intent" end

  local battle, top = activeBattle(self.game)
  if not battle then return nil, "no battle" end
  if intent.revision ~= self:_revision(battle, top) then
    return nil, "stale battle context"
  end
  local kind = battle:battleKind()
  if kind == "oldman" or kind == "link" then
    return nil, "battle kind is not controllable"
  end

  local ok, err
  if intent.kind == "safari" then
    local action = intent.action
    if kind ~= "safari" or top ~= battle or battle.phase ~= "menu" then
      return nil, "safari menu is not active"
    end
    local index = ({ ball = 1, bait = 2, rock = 3, run = 4 })[action]
    if not index then return nil, "invalid safari action" end
    battle.menuIndex = index
    battle:safariAction(action)
    ok = true
  elseif intent.kind == "mimic" then
    if top ~= battle then return nil, "mimic menu is covered" end
    ok, err = battle:chooseMimic(intent.index)
  elseif intent.kind == "fight" or intent.kind == "run" then
    if top ~= battle then return nil, "battle menu is covered" end
    ok, err = battle:chooseMenu(intent.kind)
  elseif intent.kind == "move" then
    if top ~= battle then return nil, "move menu is covered" end
    ok, err = battle:chooseMove(intent.slot)
  elseif intent.kind == "back" then
    if top ~= battle then return nil, "move menu is covered" end
    ok, err = battle:cancelMove()
  elseif intent.kind == "switch" then
    ok, err = self:_switch(battle, top, intent.slot)
  elseif intent.kind == "item" then
    ok, err = self:_useItem(battle, top, intent.item, intent.target)
  else
    return nil, "unknown battle intent"
  end
  if not ok then return nil, err end
  self.lastIntentId = intent.id
  self.signature = nil
  return true
end

return BattleAPI
