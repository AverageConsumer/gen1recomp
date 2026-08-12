-- Herb shop intro over the Goldenrod Underground map (#1169).
-- pokegold engine/items/mart.asm:54 HerbShop, maps/GoldenrodUnderground.asm:158
--
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/herbshop_bug1169_test.lua love .

local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR")
    or "/tmp/bug1169"
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  -- maps/GoldenrodUnderground.asm:52
  world.clockDay = 0
  world.mapScenes = world.mapScenes or {}
  -- maps/GoldenrodUnderground.asm:679
  assert(world:setMap("GOLDENROD_UNDERGROUND", 6, 21, "right"),
    "setMap GOLDENROD_UNDERGROUND failed")
  U.wait(8)

  local granny
  for _, npc in ipairs(world.npcs or {}) do
    if npc.def and npc.def.sprite == "SPRITE_GRANNY" then granny = npc break end
  end
  if not granny then
    U.log("FAIL granny not on the map (need Sunday)")
  end

  local MartMenu = require("src.ui.gen2.MartMenu")
  U.tap(game, "a")
  U.wait(6)
  for _ = 1, 90 do
    if getmetatable(game.stack:top()) == MartMenu then break end
    U.tap(game, "a")
    U.wait(4)
  end
  local top = game.stack:top()
  if getmetatable(top) ~= MartMenu then
    U.log("FAIL mart did not open")
  elseif top.isOpaque then
    U.log("FAIL mart is opaque")
  else
    U.log("herb shop intro over the map")
  end
  U.shot(game, out .. "/herbshop_intro.png")
  while true do U.wait(60) end
end
