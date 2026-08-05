-- Parity test: getting on SURF ends the bike (#846).
--
-- pokered keeps walking / biking / surfing in ONE state byte,
-- wWalkBikeSurfState.  ItemUseSurfboard (engine/items/item_effects.asm)
-- copies the old state aside, refuses when it is already 2, and on a
-- successful mount does `ld a, 2 / ld [wWalkBikeSurfState], a ; change
-- player state to surfing` followed by PlayDefaultMusic -- the bike state
-- is overwritten, so no bike can survive a surf: not its 8-frame step
-- cadence, not its theme.  The port splits that byte into two independent
-- flags (Game.save.onBike and player.surfing) and nothing used to clear
-- the first when the second went up, so a player who surfed off the bike
-- paddled at bike speed with Music_BikeRiding still playing.
--
-- The mirror direction is explicit in the same asm file: ItemUseBicycle
-- opens `ld a, [wWalkBikeSurfState] / cp 2 ; is the player surfing? /
-- jp z, ItemUseNotTime`, so the bag cannot re-raise the bike on water.
--
-- Self-contained; run via `luajit tests/parity_surf_clears_bike_bug846.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity surf clears bike")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game        = require("src.core.Game")
local Input       = require("src.core.Input")
local ItemEffects = require("src.inventory.ItemEffects")
local Music       = require("src.core.Music")
local Pokemon     = require("src.pokemon.Pokemon")
local Renderer    = require("src.render.Renderer")
local SaveData    = require("src.core.SaveData")
local StateStack  = require("src.core.StateStack")
local OW          = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.overworld = OW

-- tests/parity_bills_pc.lua swaps the OverworldController chunk's TextBox
-- upvalue for a stub and never puts it back, and run_tests.lua runs every
-- parity suite from one file: point it back at the real module so trySurf
-- pushes a real box here (same guard as parity_field_move_layering.lua).
local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end
setUpvalue(OW.trySurf, "TextBox", require("src.render.TextBox"))

local function frame(btns)
  Input.pressed = {}
  for _, b in ipairs(btns or {}) do Input.pressed[b] = true; Input.state[b] = true end
  StateStack:update(1 / 60)
  for _, b in ipairs(btns or {}) do Input.state[b] = false end
end

local function popAll() while Game.stack:top() do Game.stack:pop() end end

local function pushOW(mapId, x, y, facing)
  popAll()
  Game.stack:push(OW, mapId, x, y, facing)
  return Game.stack:top()
end

local function mkMon(species, ...)
  local m = Pokemon.new(Data, species, 20)
  m.moves = {}
  for _, id in ipairs({ ... }) do m.moves[#m.moves + 1] = { id = id, pp = 15 } end
  return m
end

-- Music.play no-ops on the headless audio stub, so the song the bike/surf
-- override actually resolves to is only observable by intercepting it
-- (the Music.playMap stub pattern in parity_seam_walk_anim.lua)
local playedSong
local realPlay = Music.play
Music.play = function(_, song) playedSong = song end

local bikeSong = Music.special(Data, "bike")
local surfSong = Music.special(Data, "surf")
check(bikeSong ~= nil and surfSong ~= nil and bikeSong ~= surfSong,
      "the bike and surf themes are two distinct songs")

-- =====================================================================
-- control: on land, onBike really does buy the halved step cadence, so
-- the assertion after the mount below is not vacuous
-- =====================================================================
local ow = pushOW("PALLET_TOWN", 5, 6, "up")
local p = ow.player
eq(p.stepFrames, 16, "a walking step is 16 frames")
eq(p.bikeStepFrames, 8, "the bicycle doubles walking speed (8 frames)")
Game.save.onBike = true
p.turnTimer = 0
p.stepFramesCur = nil
eq(p:tryMove("up", ow.map, ow.entities), "moved", "riding north out of the spawn cell")
eq(p.stepFramesCur, p.bikeStepFrames, "onBike hands out the bike cadence on land")

-- =====================================================================
-- the mount: bike state is gone the moment the got-on text closes, and
-- the first step onto the water is a WALK-length step, not a bike one
-- =====================================================================
ow = pushOW("PALLET_TOWN", 4, 13, "down")
p = ow.player
p.surfing = false
Game.save.onBike = true
Game.save.party = { mkMon("SQUIRTLE", "SURF") }
-- HM03's badge gate (FieldDefaults hmBadges): without it partyKnows("SURF")
-- refuses and trySurf never prints anything
Game.save.inventory.SOULBADGE = true
check(ow:partyKnows("SURF") ~= nil, "the party can use SURF here")
check(ow.map:isWaterCell(4, 14), "Pallet's south shore faces water at (4,14)")

-- what is playing when the mount starts: the bike override over the
-- outdoor Pallet theme
Music.playMap(Data, "PALLET_TOWN", true, false)
eq(playedSong, bikeSong, "the bike theme plays while riding through Pallet")

p.stepFramesCur = nil
ow:trySurf(4, 14, nil)
local box = Game.stack:top()
check(box ~= nil and box.pages ~= nil, "SURF prints _SurfingGotOnText")
local guard = 0
while Game.stack:top() == box and guard < 400 do
  guard = guard + 1
  frame({ "a" })
end
check(Game.stack:top() ~= box, "the got-on text closes")

eq(p.surfing, true, "the mount raises the surf state")
eq(Game.save.onBike, false,
   "ItemUseSurfboard writes surfing OVER the bike state, so the bike ends (#846)")
eq(playedSong, surfSong,
   "PlayDefaultMusic after the mount picks the surf theme, not the bike theme")

-- the blink carries the mount forward onto the water; let that scripted
-- step land (it is queued through scriptMove, which drives the entity
-- directly and never touches Player:tryMove)
guard = 0
while (Game.stack:top() ~= ow or p.moving or #ow.scriptMoves > 0) and guard < 240 do
  guard = guard + 1
  frame({})
end
eq(Game.stack:top(), ow, "the mount ends back on the map")
eq(p.cellY, 14, "the mount steps forward onto the water")

-- the symptom in #846: the first paddled step the player takes.  It runs
-- through Player:tryMove, which reads Game.save.onBike for its step
-- length -- a stale bike flag paddles at 8 frames per cell.
check(ow.map:isWaterCell(4, 15), "the next cell south is water too")
p.turnTimer = 0
p.stepFramesCur = nil
eq(p:tryMove("down", ow.map, ow.entities), "moved", "paddling south from (4,14)")
eq(p.stepFramesCur, p.stepFrames,
   "the paddled step uses the walk cadence, the exact symptom in #846")
check(p.stepFramesCur ~= p.bikeStepFrames, "no bike cadence survives onto the water")

-- =====================================================================
-- the mirror hole: the bag cannot put the bike back on under a surfer
-- (ItemUseBicycle's `cp 2` -> jp z, ItemUseNotTime), or the bug returns
-- by another route
-- =====================================================================
local save = SaveData.newGame()
local surfingOw = { player = { surfing = true } }
local result, msgs = ItemEffects.use(Data, save, "BICYCLE", nil, false, nil, surfingOw)
eq(result, "failed", "the BICYCLE is refused while surfing")
check(result ~= "bicycle", "a surfing BICYCLE never reaches the mount path")
check(msgs and msgs[1] and msgs[1]:find("isn't the", 1, true) ~= nil,
      "the surfing BICYCLE refusal uses the OAK 'not the time' text")

local landOw = { player = { surfing = false } }
eq((ItemEffects.use(Data, save, "BICYCLE", nil, false, nil, landOw)), "bicycle",
   "the BICYCLE still mounts normally on land")

Music.play = realPlay
popAll()
S.finish()
