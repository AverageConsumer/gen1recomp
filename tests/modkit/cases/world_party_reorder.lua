-- Public party-ordering contract over an idle overworld fixture. No ROM data
-- is needed, so companion UIs exercise this seam in the normal mod-SDK tier.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("mod world party reorder")
local StateStack = require("src.core.StateStack")
local WorldAPI = require("src.world.WorldAPI")

local first = { species = "BULBASAUR" }
local second = { species = "CHARMANDER" }
local runner = { running = false }
function runner:isRunning() return self.running end

local ow = {
  isOverworld = true,
  map = { id = "PALLET_TOWN" },
  player = { moving = false, inputLocked = false },
  runner = runner,
  scriptMoves = {},
}
local stack = setmetatable({ states = { ow } }, { __index = StateStack })
local game = {
  data = {},
  save = { party = { first, second } },
  stack = stack,
  overworld = ow,
}
local api = WorldAPI.new(game, "fixture")

T.check(api:canReorderParty(), "idle free roam allows party reordering")

local Sound = require("src.core.Sound")
local realPlay, played = Sound.play
Sound.play = function(_, name) played = name end
T.check(api:reorderParty(1, 2) == true, "valid slots reorder")
Sound.play = realPlay
T.check(game.save.party[1] == second and game.save.party[2] == first,
  "the live party is swapped")
T.eq(played, "Swap", "the normal party swap sound is used")

local value, err = api:reorderParty(1.5, 2)
T.check(value == nil and err == "invalid party slot",
  "non-integer slots are rejected")
value, err = api:reorderParty("1", 2)
T.check(value == nil and err == "invalid party slot",
  "string slots are rejected")

stack:push({ screenId = "SomeMenu" })
T.check(not api:canReorderParty(), "a screen above the world blocks reordering")
value, err = api:reorderParty(1, 2)
T.check(value == nil and err == "world is busy",
  "reordering refuses while another screen owns input")
stack:pop()

ow.player.moving = true
T.check(not api:canReorderParty(), "movement blocks reordering")
ow.player.moving = false
runner.running = true
T.check(not api:canReorderParty(), "scripts block reordering")
runner.running = false
ow.transitioning = true
T.check(not api:canReorderParty(), "map transitions block reordering")

T.finish()
