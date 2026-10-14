-- Seafoam Islands boulder/current puzzle wiring + the Vermilion Gym
-- locked door (map-enter hooks; the mechanics themselves live in
-- src/world/OverworldController.lua driven by field.seafoam and the
-- trash can data).
--
-- Sources: scripts/SeafoamIslands1F.asm / B1F.asm / B3F.asm / B4F.asm
-- (currents, holes), scripts/VermilionGym.asm (VermilionGymSetDoorTile:
-- the door block at (2,2) is $24 until EVENT_2ND_LOCK_OPENED, then $5).
--
-- The 1F->B1F->B2F->B3F->B4F boulder cascade is fully data-driven via
-- field.seafoam (SEAFOAM_ISLANDS_1F/B1F/B3F holes+holeDestination and
-- B3F's pluggedByHolesOn) plus the generic
-- OverworldState:boulderIntoHole in src/world/OverworldController.lua;
-- no per-map onEnter hook is needed for the boulders.

local M = {}

M.VERMILION_GYM = {
  onEnter = function(game, ow)
    if not game.save.flags.EVENT_2ND_LOCK_OPENED then
      ow:replaceBlock(2, 2, 36) -- $24: the closed double door
    end
  end,
}

-- The PLAYER falling down those same holes (#599).  field.seafoam's holes
-- carry only the BOULDER's object cell on the floor below (landsAt), not
-- the player's landing, so the player's landing is spelled out here: it
-- comes from data/maps/special_warps.asm DungeonWarpList/DungeonWarpData,
-- which the importer does not extract.  Same shape as MANSION_HOLES in
-- data/scripts/story6.lua and VICTORY_ROAD_3F.onStep in
-- data/scripts/story.lua; CAVERN $22 is a walkable tile, so the fall has
-- to be an onStep, not a collision block.
--
-- Sources: scripts/SeafoamIslands1F.asm Seafoam1HolesCoords (17,6)/(24,6),
-- B1F.asm Seafoam2HolesCoords (18,6)/(23,6), B2F.asm Seafoam3HolesCoords
-- (19,6)/(22,6), B3F.asm Seafoam4HolesCoords (3,16)/(6,16).  Each floor
-- sets wDungeonWarpDestinationMap and calls IsPlayerOnDungeonWarp, and
-- wCoordIndex picks that floor's DungeonWarpData row.  Unconditional in
-- the original: a plugged hole still drops the player.  The B3F and B4F
-- landings are water; the CheckForceBikeOrSurf pass after the drop
-- (OverworldState:checkForcedMovement) mounts SURF on arrival.
local HOLE_FALLS = {
  SEAFOAM_ISLANDS_1F  = { { 17, 6, "SEAFOAM_ISLANDS_B1F", 18, 7 },
                          { 24, 6, "SEAFOAM_ISLANDS_B1F", 23, 7 } },
  SEAFOAM_ISLANDS_B1F = { { 18, 6, "SEAFOAM_ISLANDS_B2F", 19, 7 },
                          { 23, 6, "SEAFOAM_ISLANDS_B2F", 22, 7 } },
  SEAFOAM_ISLANDS_B2F = { { 19, 6, "SEAFOAM_ISLANDS_B3F", 18, 7 },
                          { 22, 6, "SEAFOAM_ISLANDS_B3F", 19, 7 } },
  SEAFOAM_ISLANDS_B3F = { {  3, 16, "SEAFOAM_ISLANDS_B4F", 4, 14 },
                          {  6, 16, "SEAFOAM_ISLANDS_B4F", 5, 14 } },
}

for mapId, holes in pairs(HOLE_FALLS) do
  M[mapId] = M[mapId] or {}
  M[mapId].onStep = function(game, ow, x, y)
    for _, h in ipairs(holes) do
      if x == h[1] and y == h[2] then
        ow:fallThroughHole(h[3], h[4], h[5], ow.player.facing)
        return true
      end
    end
    return false
  end
end

-- scripts/SeafoamIslands1F.asm:3
M.SEAFOAM_ISLANDS_1F.onEnter = function(game)
  game.save.flags.EVENT_IN_SEAFOAM_ISLANDS = true
end

-- scripts/Route20.asm:2-49
M.ROUTE_20 = {
  onEnter = function(game, ow)
    local f = game.save.flags
    if not f.EVENT_IN_SEAFOAM_ISLANDS then return end
    f.EVENT_IN_SEAFOAM_ISLANDS = nil
    local Commands = require("src.script.Commands")
    local ctx = { game = game, save = game.save, overworld = ow }
    if not (f.EVENT_SEAFOAM3_BOULDER1_DOWN_HOLE
            and f.EVENT_SEAFOAM3_BOULDER2_DOWN_HOLE) then
      Commands.show_object(ctx, "SEAFOAM_ISLANDS_1F", "SEAFOAMISLANDS1F_BOULDER1")
      Commands.show_object(ctx, "SEAFOAM_ISLANDS_1F", "SEAFOAMISLANDS1F_BOULDER2")
      for _, o in ipairs({
        { "SEAFOAM_ISLANDS_B1F", "SEAFOAMISLANDSB1F_BOULDER1" },
        { "SEAFOAM_ISLANDS_B1F", "SEAFOAMISLANDSB1F_BOULDER2" },
        { "SEAFOAM_ISLANDS_B2F", "SEAFOAMISLANDSB2F_BOULDER1" },
        { "SEAFOAM_ISLANDS_B2F", "SEAFOAMISLANDSB2F_BOULDER2" },
        { "SEAFOAM_ISLANDS_B3F", "SEAFOAMISLANDSB3F_BOULDER5" },
        { "SEAFOAM_ISLANDS_B3F", "SEAFOAMISLANDSB3F_BOULDER6" },
      }) do
        Commands.hide_object(ctx, o[1], o[2])
      end
    end
    if f.EVENT_SEAFOAM4_BOULDER1_DOWN_HOLE
       and f.EVENT_SEAFOAM4_BOULDER2_DOWN_HOLE then
      return
    end
    Commands.show_object(ctx, "SEAFOAM_ISLANDS_B3F", "SEAFOAMISLANDSB3F_BOULDER2")
    Commands.show_object(ctx, "SEAFOAM_ISLANDS_B3F", "SEAFOAMISLANDSB3F_BOULDER3")
    Commands.hide_object(ctx, "SEAFOAM_ISLANDS_B4F", "SEAFOAMISLANDSB4F_BOULDER1")
    Commands.hide_object(ctx, "SEAFOAM_ISLANDS_B4F", "SEAFOAMISLANDSB4F_BOULDER2")
  end,
}

return M
