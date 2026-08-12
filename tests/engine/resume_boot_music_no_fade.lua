-- Regression test for the title-music-bleeds-into-the-map bug: Continue,
-- F2 quickload, and checkpoint-resume used to drop the player into the
-- overworld while the old song (the title screen's, or F2's previous
-- location) was still cross-fading in over Music.MAP_FADE's ~1.2s,
-- audibly wrong since the player already had control. See
-- OverworldState:setMap (src/world/OverworldController.lua) for the
-- opts.freshBoot mechanism this exercises, and Game.lua for where it's
-- set (onContinue, New Game, F2, restoreCheckpointSave) and where it's
-- deliberately not (dev tooling's reuse of opts.via == "boot").
--
-- (A)-(A4) and (C) call the real Game:restoreSave, Game:keypressed("f2"),
-- Game:restoreCheckpointSave and Console:exec("warp ...") -- SaveData.load
-- stubbed to skip the slot/persistence format -- so a dropped freshBoot at
-- any real call site fails this test, not just a hand-built opts table.
-- (D) simulates HotReload's { via = "boot" } shape instead of calling
-- through its local, unexported reloadMap.
--
-- ROM-free (fixture dataset -- FIX_TOWN/FIX_ROUTE, tests/fixture_data),
-- like tests/engine/warp_sprite_hidden_bug916.lua, so the CI headless
-- tier (no data/generated/) runs it.
--   luajit tests/engine/resume_boot_music_no_fade.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check = T.check
local eq = T.eq

local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:pause() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:setLooping() end
function Source:setVolume(v) self.volume = v end
function Source:setPitch() end
function Source:setFilter() end
function Source:getDuration() return 1 end

local made = {} -- file -> the last source built for it
love.audio = {
  newSource = function(file, mode)
    made[file] = setmetatable({ file = file, mode = mode }, Source)
    return made[file]
  end,
}

local Data = T.fixtures.fresh()
-- fixture patches that let the overworld boot and run headlessly (same
-- set tests/engine/warp_sprite_hidden_bug916.lua needs for the same reason)
Data.tilesets.FIX_OUT.tilesPerRow = 16
Data.field.flyWarps = Data.field.flyWarps or {}
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }
Data.field.waterTilesets = {}
Data.field.forcedMovement = { tiles = {} }
-- no data.audio in the fixture dataset either; synthesize just enough for
-- real Music.lua playback to run against the real FIX_TOWN/FIX_ROUTE maps
Data.audio = Data.audio or {}
Data.audio.songs = Data.audio.songs or {}
Data.audio.songs.Music_TitleScreen = { file = "title.wav" }
Data.audio.mapSongs = Data.audio.mapSongs or {}
Data.audio.mapSongs.FIX_TOWN = "Music_FixTown"
Data.audio.songs.Music_FixTown = { file = "town.wav" }
Data.audio.mapSongs.FIX_ROUTE = "Music_FixRoute"
Data.audio.songs.Music_FixRoute = { file = "route.wav" }

local Music = require("src.core.Music")
local SaveData = require("src.core.SaveData")
local Game = require("src.core.Game")
local StateStack = require("src.core.StateStack")
local OverworldState = require("src.world.OverworldController")
local Console = require("src.dev.Console")

Game.data = Data
Game.save = SaveData.newGame()
Game.save.player.name = "RED"
Game.save.player.map = "FIX_TOWN"
StateStack:init()
Game.stack = StateStack
Game.overworld = OverworldState -- set once at boot in the real game (Game.lua)
Game.input = {
  isDown = function() return false end,
  wasPressed = function() return false end,
  step = function() end, state = {}, pressQueue = {},
}
Game.renderer = {
  beginWorldPass = function() end, endWorldPass = function() end,
  beginUIPass = function() end, endUIPass = function() end,
  worldViewSize = function() return 160, 144 end,
  setSGBZones = function() end,
}

local function playing()
  for file, src in pairs(made) do
    if src.playing then return file end
  end
  return "(silence)"
end

local function finishFade()
  for _ = 1, 7 * Music.MAP_FADE do Music.update(Data) end
end

-- ===========================================================================
-- (A) The real Game:restoreSave, called the way onContinue calls it.
-- ===========================================================================
Music.play(Data, "Music_TitleScreen")
eq(playing(), "title.wav", "title screen music is playing before Continue")

local loaded = SaveData.newGame()
loaded.player.map = "FIX_TOWN"
Game:restoreSave(loaded, false, { freshBoot = true })

eq(playing(), "town.wav",
  "Continue's real restoreSave(..., {freshBoot=true}) swaps at once")

-- ===========================================================================
-- (A2) The same real Game:restoreSave with no opts at all -- its own
-- default (e.g. for any future caller that doesn't ask for freshBoot) is
-- the safe, ordinary crossfade, not a silent hard-cut.
-- ===========================================================================
Music.play(Data, "Music_TitleScreen") -- stand-in for whatever was playing
local loaded2 = SaveData.newGame()
loaded2.player.map = "FIX_TOWN"
Game:restoreSave(loaded2, false)

eq(playing(), "title.wav",
  "restoreSave(...) with no opts still fades, not an instant swap")
finishFade()
eq(playing(), "town.wav", "...landing on the loaded save's map song")

-- ===========================================================================
-- (A3) The real Game:keypressed("f2") handler, both ways it's reachable:
-- at the title screen and mid-session. SaveData.load is stubbed rather
-- than round-tripped through the in-memory love.filesystem, to isolate
-- this test from the slot/persistence format.
-- ===========================================================================
local realLoad = SaveData.load
local loaded3 = SaveData.newGame()
loaded3.player.map = "FIX_TOWN"
SaveData.load = function() return loaded3, false end

StateStack:init() -- no overworld on the stack: "at the title screen"
Music.play(Data, "Music_TitleScreen")
Game:keypressed("f2")
eq(playing(), "town.wav",
  "F2 from the title screen (overworld not on the stack) swaps at once")

StateStack:init()
StateStack.states[1] = OverworldState -- overworld already active: mid-session
Music.play(Data, "Music_TitleScreen") -- stand-in for the session's own song
Game:keypressed("f2")
eq(playing(), "town.wav",
  "F2 mid-session (a live overworld already on the stack) also swaps at once")

SaveData.load = realLoad
StateStack:init()

-- ===========================================================================
-- (A4) The real Game:restoreCheckpointSave, called the way Checkpoint.resume
-- (RFC 0006's mod.checkpoint:resume) calls it.
-- ===========================================================================
Music.play(Data, "Music_TitleScreen")
local checkpointSave = SaveData.newGame()
checkpointSave.player.map = "FIX_TOWN"
Game:restoreCheckpointSave(checkpointSave)
eq(playing(), "town.wav",
  "a title-session checkpoint resume swaps at once, no lingering title music")

StateStack:init()

-- ===========================================================================
-- (B) An ordinary warp (e.g. walking into a house) is unaffected: it still
-- cross-fades like any other map-to-map transition.
-- ===========================================================================
OverworldState:setMap("FIX_ROUTE", 3, 3, "up", {})
eq(playing(), "town.wav",
  "an ordinary warp still fades: the old song is still playing right after setMap")
finishFade()
eq(playing(), "route.wav",
  "...and lands on the new map's song once the fade completes")

-- ===========================================================================
-- (C) The real dev console `warp` verb (src/dev/Console.lua VERBS.warp).
-- ===========================================================================
Music.play(Data, "Music_TitleScreen") -- re-arm a "stale" song to prove intent
Console.new(Game):exec("warp FIX_TOWN 5 5")

eq(playing(), "title.wav",
  "Console's real `warp` verb still fades, like an ordinary warp")
finishFade()
eq(playing(), "town.wav", "...landing on the target map's song")

-- ===========================================================================
-- (D) src/dev/HotReload.lua's reloadMap opts shape, simulated (see header)
-- rather than called through: reloadMap is local/unexported, and
-- HotReload.run's full loader teardown is out of scope for this fix.
-- ===========================================================================
Music.play(Data, "Music_TitleScreen")
OverworldState:setMap("FIX_ROUTE", 3, 3, "up", { via = "boot" })
eq(playing(), "title.wav",
  "HotReload's { via = \"boot\" } setMap still fades, not an instant swap")
finishFade()
eq(playing(), "route.wav", "...landing on the reloaded map's song")

T.finish("resume_boot_music_no_fade")
