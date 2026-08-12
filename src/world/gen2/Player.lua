-- Minimal Gen 2 overworld player: tile-grid steps at 16 frames/cell.
-- Draws via shared SpriteRenderer (same 16x96 facing layout as Gen 1).

local Map = require("src.world.gen2.Map")
local Runtime = require("src.mods.Runtime")
local SpriteRenderer = require("src.render.SpriteRenderer")

local Player = {}
Player.__index = Player

local STEP_FRAMES = 16
local TURN_FRAMES = 4

-- The walking duration, exported so World can halve it for a bike step
-- (.DoStep's STEP_BIKE arm, engine/overworld/player_movement.asm).  The leg
-- cadence below deliberately does NOT scale with it: animClock keeps counting
-- at the walking rate, which is what stops a bike step flickering the legs.
Player.STEP_FRAMES = STEP_FRAMES

-- engine/overworld/map_objects.asm:1815
local JUMP_Y = {
  -4, -6, -8, -10, -11, -12, -12, -12,
  -11, -10, -9, -8, -6, -4, 0, 0,
}

function Player.new(cx, cy, facing, spriteDef)
  local self = setmetatable({
    cellX = cx, cellY = cy,
    px = cx * 16, py = cy * 16,
    facing = facing or "down",
    moving = false,
    progress = 0,
    turnTimer = 0,
    turnArmed = true,
    stepFlip = false,
    -- OBJECT_FLAGS2's IN_GRASS_F (engine/overworld/map_objects.asm:247).
    inGrass = false,
    animClock = 0,
    -- Frames this cell takes; World rewrites it per step from the STEP_* the
    -- player's state picks, and a step already under way keeps the one it
    -- started with.
    stepFrames = STEP_FRAMES,
    sprite = nil,
    spriteDef = spriteDef,
  }, Player)
  if spriteDef then
    self.sprite = SpriteRenderer.new(spriteDef, "player")
  end
  return self
end

function Player:setSprite(spriteDef)
  if spriteDef then
    self.spriteDef = spriteDef
    self.sprite = SpriteRenderer.new(spriteDef, "player")
  end
end

-- the movement.collision chain sees the boolean; a wrapper that flips it
-- rewrites ctx.reason to say why (the engine's own reasons are bounds / tile /
-- entity, the same three src/world/Collision.lua names under Gen 1), so the
-- hook stays a single-value middleware.
local function passthrough(allowed) return allowed end

-- The verdict on one step, hoisted so the hooked and unhooked paths cannot
-- drift.  World:movePlayer has already vetoed the direction by handing us a
-- refusingMap when GetMovementPermissions says no, so a side-wall veto arrives
-- here as "tile" exactly like a wall does.
local function verdict(self, map, entities, tx, ty)
  if not map:inBounds(tx, ty) then return false, "bounds" end
  if not map:isWalkable(tx, ty) then return false, "tile" end
  if entities then
    for _, e in ipairs(entities) do
      -- `passable` is the follower's escape, src/world/Collision.lua:20's
      -- name and meaning: the player walks straight through it.
      if e ~= self and not e.passable then
        if e.cellX == tx and e.cellY == ty then return false, "entity" end
        if e.moving and e.targetX == tx and e.targetY == ty then
          return false, "entity"
        end
      end
    end
  end
  return true
end

function Player:tryMove(dir, map, entities)
  if self.moving then return nil end
  if self.facing ~= dir then
    self.facing = dir
    if self.turnArmed then
      self.turnArmed = false
      self.turnTimer = TURN_FRAMES
      return "turned"
    end
  end
  if self.turnTimer > 0 then return nil end

  local d = Map.DELTA[dir]
  local tx, ty = self.cellX + d[1], self.cellY + d[2]
  local allowed, why = verdict(self, map, entities, tx, ty)
  -- Per-step hot path, guarded the way src/world/Collision.lua's canMove is:
  -- with an empty chain this costs one table lookup and no ctx allocation.
  if Runtime.wantsHook("movement.collision") then
    local ctx = { map = map, mover = self, dir = dir,
                  fromX = self.cellX, fromY = self.cellY,
                  toX = tx, toY = ty, reason = why }
    allowed = Runtime.call("movement.collision", passthrough, allowed, ctx)
    why = ctx.reason
  end
  if not allowed then
    -- World:movePlayer tells the two refusals apart: "edge" is what asks the
    -- connection table for the neighbouring map, "blocked" is a bump.
    return why == "bounds" and "edge" or "blocked"
  end
  self.targetX, self.targetY = tx, ty
  self.moving = true
  self.progress = 0
  return "moved"
end

-- Cutscene step: ignores collision so Elm walk-up / after-pick paths play.
function Player:scriptFace(dir)
  if dir then self.facing = dir end
end

function Player:scriptStep(dir)
  if self.moving then return false end
  -- A scripted step names its own STEP_* on the cart (SurfStartStep is a slow
  -- step), so it never inherits the bike's shorter one.
  self.stepFrames = STEP_FRAMES
  self.facing = dir or self.facing
  local d = Map.DELTA[self.facing]
  if not d then return false end
  self.targetX, self.targetY = self.cellX + d[1], self.cellY + d[2]
  self.moving = true
  self.progress = 0
  return true
end

-- Gen 1's name for the cell being faced (src/world/Player.lua), so a mod that
-- wraps World:interact asks one question of either generation.
function Player:facingCell()
  local d = Map.DELTA[self.facing] or Map.DELTA.down
  return self.cellX + d[1], self.cellY + d[2]
end

function Player:walkPhase()
  -- pokegold engine/overworld/map_objects.asm StepFunction_Turn: forces the
  -- walking leg frame for the whole 4-frame turn-in-place.
  if self.turnTimer > 0 then return 1 end
  if not self.moving then return 0 end
  local p = self.animClock % STEP_FRAMES
  return (p >= 4 and p < 12) and 1 or 0
end

function Player:update()
  if self.turnTimer > 0 then
    self.turnTimer = self.turnTimer - 1
  end
  if not self.moving then
    -- Re-arm turn-in-place once a poll finds no held direction (caller
    -- clears this while a dir is held; we only set it from idle).
    return false
  end
  self.progress = self.progress + 1
  self.animClock = self.animClock + 1
  -- Interpolate toward the TARGET cell rather than one cell along the facing:
  -- a ledge hop (World:tryLedgeJump, the cart's STEP_LEDGE) is a two-cell move
  -- and the facing-delta math walked only half of it, leaving the sprite a
  -- cell behind where the grid said the player was.
  local frames = self.stepFrames or STEP_FRAMES
  local adv = math.floor(self.progress * 16 / frames)
  local dx = (self.targetX or self.cellX) - self.cellX
  local dy = (self.targetY or self.cellY) - self.cellY
  self.px = self.cellX * 16 + dx * adv
  self.py = self.cellY * 16 + dy * adv
  if self.jumping then
    -- engine/overworld/map_objects.asm:1815
    local idx = math.floor((self.progress - 1) / 2) + 1
    if idx < 1 then idx = 1 end
    if idx > #JUMP_Y then idx = #JUMP_Y end
    self.spriteYOffset = JUMP_Y[idx]
  end
  if self.progress >= frames then
    self.cellX, self.cellY = self.targetX, self.targetY
    self.targetX, self.targetY = nil, nil
    self.px, self.py = self.cellX * 16, self.cellY * 16
    self.moving = false
    self.jumping = nil
    self.spriteYOffset = 0
    self.stepFlip = not self.stepFlip
    return true
  end
  return false
end

function Player:draw(ox, oy, scale)
  local G = love.graphics
  -- OBJECT_SPRITE_Y_OFFSET: added to the OBJ's y as it is written to OAM, so
  -- it moves the sprite without moving the player off the tile they are
  -- standing on.  StepFunction_GotBite's `xor 1` rod bob and the fly take-off
  -- lift both ride this one byte.
  local yOffset = self.spriteYOffset or 0
  if self.jumping then
    -- engine/overworld/map_objects.asm:1995
    local gx = ox + self.px * scale
    local gy = oy + self.py * scale
    local s = 16 * scale
    G.setColor(0, 0, 0, 0.4)
    G.ellipse("fill", gx + s * 0.5, gy + s * 0.85, s * 0.35, s * 0.12)
    G.setColor(1, 1, 1, 1)
  end
  if self.sprite then
    G.push()
    G.translate(ox, oy)
    G.scale(scale, scale)
    -- Chris is PAL_OW_RED; World:applyPalettes keeps the SpriteRenderer's
    -- OBJ palette current.
    self.sprite:draw(
      self.px, self.py + yOffset, 0, 0,
      self.facing, self:walkPhase(), self.stepFlip)
    G.pop()
    return
  end
  -- Fallback rectangle if sprites.lua is missing from an old cache.
  local x = ox + self.px * scale
  local y = oy + (self.py + yOffset) * scale
  local s = 16 * scale
  G.setColor(0.95, 0.35, 0.25, 1)
  G.rectangle("fill", x + s * 0.15, y + s * 0.1, s * 0.7, s * 0.85, 2, 2)
  G.setColor(1, 0.9, 0.55, 1)
  local notch = s * 0.22
  if self.facing == "up" then
    G.rectangle("fill", x + s * 0.5 - notch / 2, y + s * 0.05, notch, notch)
  elseif self.facing == "down" then
    G.rectangle("fill", x + s * 0.5 - notch / 2, y + s * 0.7, notch, notch)
  elseif self.facing == "left" then
    G.rectangle("fill", x + s * 0.05, y + s * 0.4, notch, notch)
  else
    G.rectangle("fill", x + s * 0.75, y + s * 0.4, notch, notch)
  end
  G.setColor(1, 1, 1, 1)
end

return Player
