-- T4: the gameplay pointer seam and source-safe mod input (#807), through
-- the public mod API.
--
-- Two seams under test.  "input.pointer" delivers uncaptured gameplay
-- touch and mouse events to hook subscribers, with the on-screen touch
-- controls keeping first refusal.  mod.input taps and holds GB buttons as
-- per-mod Input sources, so no mod can clear a hold it does not own.
-- Both are driven the way main.lua drives them -- through Game's own
-- handlers, against the real Input and TouchControls singletons -- so a
-- green run means the wiring, not just the buses.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local TouchControls = require("src.core.TouchControls")
local Runtime = require("src.mods.Runtime")

-- a Game stand-in that resolves the real methods (Game is the boot
-- singleton, so its handlers expect to be their own self)
local function fakeGame(loader, data)
  return setmetatable({ input = Input, mods = loader, data = data },
    { __index = Game })
end

-- ------- fixture mods

-- the watcher journals every pointer event it sees and exports its own
-- mod.input facade, so the suite drives exactly the surface a mod
-- compiles against; the peer exists to prove cross-mod token refusal
local FIXTURES = {
  ["mods/fix_pointer_watcher/manifest.json"] = [[{
    "id": "fix_pointer_watcher",
    "name": "Fixture Pointer Watcher",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/fix_pointer_watcher/main.lua"] = [[
    local mod = ...
    local seen = {}
    mod.exports.seen = seen
    mod.hooks:wrap("input.pointer", function(nextFn, game, ev)
      seen[#seen + 1] = { phase = ev.phase, source = ev.source, id = ev.id,
        x = ev.x, y = ev.y, dx = ev.dx, dy = ev.dy,
        pressure = ev.pressure, button = ev.button }
      return nextFn(game, ev)
    end)
    mod.exports.input = mod.input
  ]],
  ["mods/fix_pointer_peer/manifest.json"] = [[{
    "id": "fix_pointer_peer",
    "name": "Fixture Pointer Peer",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/fix_pointer_peer/main.lua"] = [[
    local mod = ...
    mod.exports.input = mod.input
  ]],
}

-- ------- no-mod parity: the pointer path costs nothing unsubscribed

do
  local run = T.sdk.loadNone({})
  Input:init()
  TouchControls:init()
  local game = fakeGame(run.loader, run.data)
  T.eq(Runtime.wantsHook("input.pointer"), false,
    "no subscriber: wantsHook(\"input.pointer\") is false")
  Game.touchpressed(game, 1, 50, 60, 0, 0, 1)
  Game.touchmoved(game, 1, 55, 66, 5, 6, 1)
  Game.touchreleased(game, 1, 55, 66, 0, 0, 1)
  Game.mousepressed(game, 10, 10, 1, false)
  Game.mousemoved(game, 12, 12, 2, 2, false)
  Game.mousereleased(game, 12, 12, 1, false)
  Game.cancelPointers(game)
  T.eq(game.modPointers, nil,
    "no subscriber: the pointer path allocates no tracking state")
  run.release()
end

-- ------- the subscribed path, through the loader-created mod API

local run = T.sdk.loadMods(
  { "mods/fix_pointer_watcher", "mods/fix_pointer_peer" },
  { fs = T.sdk.memfs(FIXTURES) })
T.eq(#run.errors, 0,
  "the fixture mods load clean (" .. tostring(run.errors[1]) .. ")")

local watcher = run.loader.exports.fix_pointer_watcher
local peer = run.loader.exports.fix_pointer_peer
local seen = watcher.seen
local game = fakeGame(run.loader, run.data)

Input:init()
TouchControls:init()

local function wipe()
  for i = #seen, 1, -1 do seen[i] = nil end
end

-- one pressed/moved/released sequence per outside touch
do
  wipe()
  Game.touchpressed(game, 7, 100, 120, 0, 0, 0.5)
  Game.touchmoved(game, 7, 110, 125, 10, 5, 0.5)
  Game.touchreleased(game, 7, 110, 125, 0, 0, 0.5)
  T.eq(#seen, 3, "an outside touch is one pressed/moved/released sequence")
  T.eq(seen[1].phase, "pressed", "the sequence begins with pressed")
  T.eq(seen[1].source, "touch", "a finger reports source touch")
  T.eq(seen[1].id, 7, "the touch id rides the payload")
  T.eq(seen[1].x, 100, "coordinates are the LOVE window units handed in")
  T.eq(seen[1].pressure, 0.5, "pressure rides the payload when present")
  T.eq(seen[2].phase, "moved", "then moved")
  T.eq(seen[2].dx, 10, "moved carries the event deltas")
  T.eq(seen[3].phase, "released", "then released")
  T.eq(game.modPointers[7], nil, "a released pointer leaves no record")

  -- press+release inside one logic tick still yields both events: the
  -- seam is event-driven, not sampled at the step boundary
  wipe()
  Game.touchpressed(game, 8, 10, 10, 0, 0, 1)
  Game.touchreleased(game, 8, 10, 10, 0, 0, 1)
  T.eq(#seen, 2, "press+release inside one tick delivers both events")
  T.eq(seen[1].phase, "pressed", "...pressed first")
  T.eq(seen[2].phase, "released", "...released second")
end

-- multi-id drags stay per-pointer
do
  wipe()
  Game.touchpressed(game, "t1", 40, 40, 0, 0, 1)
  Game.touchpressed(game, "t2", 200, 90, 0, 0, 1)
  Game.touchmoved(game, "t1", 45, 44, 5, 4, 1)
  Game.touchmoved(game, "t2", 210, 80, 10, -10, 1)
  Game.touchreleased(game, "t2", 210, 80, 0, 0, 1)
  Game.touchreleased(game, "t1", 45, 44, 0, 0, 1)
  T.eq(#seen, 6, "two concurrent touches interleave without cross-talk")
  T.eq(seen[3].id, "t1", "each moved names its own pointer")
  T.eq(seen[4].id, "t2", "...and only its own pointer")
  T.eq(seen[5].id, "t2", "release order follows the fingers, not the presses")
  T.eq(seen[5].phase, "released", "t2 released first")
  T.eq(seen[6].id, "t1", "t1 released second")
  T.eq(next(game.modPointers), nil, "all records are gone after both lifts")
end

-- the virtual pad keeps first refusal
do
  -- force the overlay live the way a phone would have it; img is only
  -- tested for truthiness on the input path (soft_reset_bug563 idiom)
  TouchControls.active, TouchControls.enabled = true, true
  TouchControls.img = { stub = true }
  local L = TouchControls:layout()

  wipe()
  Game.touchpressed(game, 21, L.a.cx, L.a.cy)
  T.eq(Input:isDown("a"), true, "the overlay captured the touch and holds A")
  Game.touchmoved(game, 21, L.a.cx + 4, L.a.cy + 4)
  Game.touchreleased(game, 21, L.a.cx + 4, L.a.cy + 4)
  T.eq(Input:isDown("a"), false, "lifting the finger releases A")
  T.eq(#seen, 0, "a touch that begins on a virtual control never reaches mods")

  -- begins outside, wanders across A: stays mod-visible, never presses A
  wipe()
  Game.touchpressed(game, 22, 5, 5)
  Game.touchmoved(game, 22, L.a.cx, L.a.cy)
  T.eq(Input:isDown("a"), false, "crossing a control mid-drag never presses it")
  Game.touchreleased(game, 22, L.a.cx, L.a.cy)
  T.eq(#seen, 3, "a touch that begins outside stays mod-visible throughout")
  T.eq(seen[2].dx, L.a.cx - 5, "deltas derive from the last seen position "
    .. "when the event carries none")

  TouchControls.active = false
  TouchControls.img = nil
  TouchControls:reset()
end

-- real mouse events, and the synthesized istouch twins that must not fire
do
  wipe()
  Game.mousepressed(game, 30, 30, 1, true)
  Game.mousemoved(game, 31, 31, 1, 1, true)
  Game.mousereleased(game, 31, 31, 1, true)
  T.eq(#seen, 0, "synthesized istouch mouse twins never reach the hook")

  Game.mousepressed(game, 30, 30, 1, false)
  Game.mousemoved(game, 34, 32, 4, 2, false)
  Game.mousereleased(game, 34, 32, 1, false)
  T.eq(#seen, 3, "a real mouse reaches the hook without POKEPORT_TOUCH")
  T.eq(seen[1].source, "mouse", "the mouse reports source mouse")
  T.eq(seen[1].id, "mouse", "...under the fixed id mouse")
  T.eq(seen[1].button, 1, "pressed carries the button")
  T.eq(seen[2].dx, 4, "moved carries the event deltas")
  T.eq(seen[3].phase, "released", "the lifecycle closes with released")
  T.eq(game.modPointers.mouse, nil, "the mouse record is gone after release")
end

-- focus loss cancels every live mod-visible pointer
do
  wipe()
  Game.touchpressed(game, 40, 70, 80, 0, 0, 1)
  Game.focus(game, false)
  T.eq(#seen, 2, "focus loss follows the pressed with exactly one more event")
  T.eq(seen[2].phase, "cancelled", "...a cancelled")
  T.eq(seen[2].id, 40, "...for the pointer that was alive")
  T.eq(seen[2].x, 70, "...at its last seen position")
  T.eq(game.modPointers, nil, "cancel clears the tracking state")
end

-- ------- mod.input: tap is one edge, no held state

do
  Input:init()
  watcher.input:tap(game, "a")
  T.eq(Input:isDown("a"), false, "tap holds nothing before the step")
  Input:step()
  T.eq(Input:wasPressed("a"), true, "tap queues exactly one wasPressed edge")
  T.eq(Input:isDown("a"), false, "the edge carries no held state")
  Input:step()
  T.eq(Input:wasPressed("a"), false, "the edge lasts exactly one step")
  T.eq(Input:isDown("a"), false, "and still nothing is held")
end

-- mod.input: a press token holds across steps and respects other sources

do
  Input:init()
  local token = watcher.input:press(game, "b")
  Input:step()
  T.eq(Input:wasPressed("b"), true, "press queues the edge")
  T.eq(Input:isDown("b"), true, "and holds the button")
  Input:step()
  T.eq(Input:isDown("b"), true, "the hold survives steps until release")
  -- the keyboard joins on the same button (X is a default B binding)
  Input:keypressed("x")
  Input:step()
  T.eq(watcher.input:release(token), true, "release honors this mod's token")
  T.eq(Input:isDown("b"), true,
    "releasing the mod token leaves the keyboard's hold alone")
  T.eq(watcher.input:release(token), false, "release is idempotent")
  T.eq(Input:isDown("b"), true, "a second release changes nothing")
  Input:keyreleased("x")
  T.eq(Input:isDown("b"), false, "the keyboard's own release ends the hold")
end

-- mod.input: one mod cannot release another mod's press

do
  Input:init()
  local token = watcher.input:press(game, "start")
  T.eq(peer.input:release(token), false,
    "a mod cannot release another mod's token")
  T.eq(Input:isDown("start"), true, "the refused release drops nothing")
  T.eq(watcher.input:release(token), true, "the owning mod still can")
  T.eq(Input:isDown("start"), false, "and then the button is up")
  T.raises(function() watcher.input:tap(game, "quit") end,
    "unknown GB button", "unknown buttons are refused")
end

-- mod.input: input recovery retires outstanding tokens

do
  Input:init()
  local token = watcher.input:press(game, "a")
  T.eq(Input:isDown("a"), true, "the hold is live before recovery")
  Game.recoverInput(game, "joystickadded")
  T.eq(Input:isDown("a"), false,
    "input recovery drops mod holds with every other source")
  T.eq(watcher.input:release(token), false,
    "recovery retires the outstanding token")
end

-- ------- cleanup: entry-chunk rollback releases what the chunk pressed

do
  local BROKEN = {
    ["mods/fix_pointer_broken/manifest.json"] = [[{
      "id": "fix_pointer_broken",
      "name": "Fixture Pointer Broken",
      "version": "1.0.0",
      "entry": "main.lua",
      "api": 2
    }]],
    ["mods/fix_pointer_broken/main.lua"] = [[
      local mod = ...
      mod.input:press(FIX_POINTER_GAME, "select")
      error("entry chunk exploded")
    ]],
  }
  Input:init()
  _G.FIX_POINTER_GAME = { input = Input }
  local broken = T.sdk.loadMods({ "mods/fix_pointer_broken" },
    { fs = T.sdk.memfs(BROKEN) })
  _G.FIX_POINTER_GAME = nil
  T.check(#broken.errors > 0, "the throwing entry chunk is reported")
  T.eq(Input:isDown("select"), false,
    "entry-chunk rollback releases the mod's outstanding holds")
  broken.release()
end

-- ------- cleanup: hot reload retires the old loader's holds (LAST: it
-- replaces the buses, so the watcher's subscription dies with it)

do
  Input:init()
  local token = watcher.input:press(game, "up")
  T.eq(Input:isDown("up"), true, "the hold is live before the reload")
  -- a fresh fixture dataset for the reload's re-merge, with the inherited
  -- Data:reloadGenerated shadowed out: it would read data/generated, and
  -- this tier is ROM-free
  local rdata = T.fixtures.fresh()
  rawset(rdata, "reloadGenerated", function() end)
  local rgame = fakeGame(run.loader, rdata)
  require("src.dev.HotReload").run(rgame, { fs = T.sdk.memfs({}) })
  T.eq(Input:isDown("up"), false, "hot reload retires the old loader's holds")
  T.eq(watcher.input:release(token), false,
    "a token from before the reload is refused, not re-released")
end

run.release()

T.finish("pointer_input")
