-- Safe, semantic Gen 1 battle controls for mods.

local Bag = require("src.inventory.Bag")
local Damage = require("src.battle.Damage")
local ItemEffects = require("src.inventory.ItemEffects")
local TextBox = require("src.render.TextBox")
local TypeChart = require("src.battle.TypeChart")

local BattleAPI = {}
BattleAPI.__index = BattleAPI

function BattleAPI.new(game, modId)
  return setmetatable({ game = game, modId = modId, revision = 0,
    signature = nil, lastIntentId = nil }, BattleAPI)
end

local function activeBattle(game)
  local states = game and game.stack and game.stack.states or {}
  for i = #states, 1, -1 do
    if states[i].isBattleState then return states[i], states[#states] end
  end
end

local function monCopy(data, mon, active)
  if not mon then return nil end
  local def = data.pokemon[mon.species]
  return { species = mon.species,
    name = mon.nickname or (def and def.name) or mon.species,
    level = mon.level, hp = mon.hp,
    maxHp = mon.stats and mon.stats.hp or mon.hp,
    status = mon.status, active = active and true or false }
end

local function visibleMessage(battle, top)
  local source = top and top.isTextBox and top or top == battle and battle
  local lines = source and source.visibleText and source:visibleText()
  if not lines then return nil end
  local copy = {}
  for i, line in ipairs(lines) do copy[i] = tostring(line) end
  return copy
end

local function signature(game, battle, top)
  if not battle then return "none" end
  local parts = { tostring(battle), tostring(top), battle.phase or "",
    tostring(battle.turnCount or 0), tostring(#(battle.queue or {})),
    tostring(battle.current), tostring(battle.msgWaiting),
    tostring(battle.msgPrompt), tostring(battle.menuIndex),
    tostring(battle.mimicIndex),
    tostring(battle.safari and battle.safari.balls),
    tostring(battle.ghost), tostring(battle.noCatch),
    table.concat(visibleMessage(battle, top) or {}, "\n") }
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    local mon = battler and battler.mon
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon and mon.hp)
    parts[#parts + 1] = tostring(mon and mon.status)
    parts[#parts + 1] = table.concat(battler and battler.curTypes or {}, ",")
  end
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
  local nextSignature = signature(self.game, battle, top)
  if nextSignature ~= self.signature then
    self.signature = nextSignature
    self.revision = self.revision + 1
  end
  return self.revision
end

local IMMUNITY_ONLY = { SPECIAL_DAMAGE_EFFECT = true,
  SUPER_FANG_EFFECT = true, OHKO_EFFECT = true }

local function movePreview(battle, move, def)
  local record = battle.effectRecord and battle:effectRecord(def.effect)
  local power, typeMult = def.power or 0
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
  elseif not (record and record.gate)
      and (power > 0 or (record and record.accuracyChecked)) then
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
    out[slot] = { slot = slot, id = move.id, name = def.name or move.id,
      pp = move.pp,
      maxPp = (def.pp or move.pp or 0)
        + (move.ppUps or 0) * math.floor((def.pp or 0) / 5),
      type = def.type, power = def.power, accuracy = def.accuracy,
      displayPower = displayPower, hitChance = hitChance,
      effectiveness = mult,
      disabled = battle.player.disabledSlot == slot }
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
      out[#out + 1] = { id = id, name = def.name or id, count = count,
        ball = ball, needsTarget = not ball,
        catchChance = ball and catchable and battle.catchChance
          and battle:catchChance(id) or nil }
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
  local supported = kind ~= "oldman" and kind ~= "link"
  local catchable = kind == "wild" and not battle.ghost and not battle.noCatch
  local forcedParty = top and top.isPartyMenu and top.battle == battle
    and top.forceSwitch
  local canAdvance = supported and ((top == battle
      and battle.phase == "messages" and battle.current
      and (battle.msgWaiting or battle.msgPrompt))
    or (top and top.isTextBox and not top.choice
      and (top.waiting or top.done)))
  local prompt = "locked"
  if canAdvance then prompt = "advance"
  elseif supported and forcedParty then prompt = "party"
  elseif supported and top == battle and kind == "safari"
      and battle.phase == "menu" then prompt = "safari"
  elseif supported and top == battle and battle.phase == "mimicSelect" then
    prompt = "mimic"
  elseif supported and top == battle and battle.phase == "menu" then
    prompt = "menu"
  elseif supported and top == battle and battle.phase == "moveSelect" then
    prompt = "moves"
  end
  local party = {}
  for i, mon in ipairs(game.save.party or {}) do
    party[i] = monCopy(game.data, mon,
      battle.player and battle.player.mon == mon)
    party[i].slot = i
  end
  return { revision = self:_revision(battle, top), kind = kind,
    catchable = catchable, prompt = prompt,
    message = visibleMessage(battle, top), turn = battle.turnCount or 0,
    player = monCopy(game.data, battle.player and battle.player.mon, true),
    enemy = monCopy(game.data, battle.enemy and battle.enemy.mon, true),
    party = party, moves = moveCopies(game, battle),
    items = itemCopies(game, battle, catchable),
    safariBalls = battle.safari and battle.safari.balls or nil,
    mimicMoves = mimicCopies(game, battle), mimicIndex = battle.mimicIndex }
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

local function showMessages(game, messages, onDone)
  if not messages or #messages == 0 then
    if onDone then onDone() end
    return
  end
  game.stack:push(TextBox.new(game, table.concat(messages, "\f"), onDone))
end

function BattleAPI:_useItem(battle, top, itemId, targetSlot)
  if top ~= battle or battle.phase ~= "menu" then
    return nil, "item choice is not active"
  end
  local count = self.game.save.inventory
    and self.game.save.inventory[itemId] or 0
  if count <= 0 then return nil, "item is not in the bag" end
  local ball = ItemEffects.isBall(itemId)
  if not ball and not ItemEffects.isBattleMedicine(itemId) then
    return nil, "item is not supported in battle"
  end
  local target
  if not ball then
    target = validPartyMon(self.game, targetSlot)
    if not target then return nil, "invalid item target" end
  end
  local result, messages = ItemEffects.use(
    self.game.data, self.game.save, itemId, target, battle)
  if result == "ball" then
    Bag.remove(self.game.save, itemId, 1)
    battle.phase, battle.afterQueue = "messages", "menu"
    battle:throwBall(itemId)
  elseif result == "consumed" then
    Bag.remove(self.game.save, itemId, 1)
    battle.phase, battle.afterQueue = "messages", "menu"
    showMessages(self.game, messages, function() battle:itemUsed({}) end)
  elseif result == "failed" then
    showMessages(self.game, messages)
  else
    return nil, "item cannot be used here"
  end
  return true
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
    if kind ~= "safari" or top ~= battle or battle.phase ~= "menu" then
      return nil, "safari menu is not active"
    end
    local action = intent.action
    local index = ({ ball = 1, bait = 2, rock = 3, run = 4 })[action]
    if not index then return nil, "invalid safari action" end
    battle.menuIndex = index
    battle:safariAction(action)
    ok = true
  elseif intent.kind == "mimic" then
    if top ~= battle then return nil, "mimic menu is covered" end
    ok, err = battle:chooseMimic(intent.index)
  elseif intent.kind == "advance" then
    local canAdvance = (top == battle and battle.phase == "messages"
      and battle.current and (battle.msgWaiting or battle.msgPrompt))
      or (top and top.isTextBox and not top.choice
        and (top.waiting or top.done))
    if not canAdvance then return nil, "battle text is not waiting" end
    table.insert(self.game.input.pressQueue, "a")
    ok = true
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
