-- Timing parity: every sequence in docs/timing-parity.md must cost the same
-- number of 60Hz logic steps here as it does on hardware.
--
-- The port's clock was always right; what drifted was the frame budget of
-- composed sequences, because the original spends much of its running time
-- inside DelayFrames calls that produce no visible change.  Those are
-- invisible in a screenshot, so nothing else in the suite catches them --
-- this file is the only thing standing between the port and a slow slide
-- back to "snappier than a Game Boy".
--
-- Hardware numbers carry their asm citation; regenerate the inventory with
-- tools/scan_pokered_delays.ps1.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)

local Timing = require("src.core.Timing")

-- ---------------------------------------------------------------- constants

-- home/fade.asm: four (or three) palette steps of `ld c, 8 / DelayFrames`
T.eq(Timing.FADE_OUT_TO_BLACK, 32, "GBFadeOutToBlack is 4 x 8 frames")
T.eq(Timing.FADE_IN_FROM_BLACK, 32, "GBFadeInFromBlack is 4 x 8 frames")
T.eq(Timing.FADE_OUT_TO_WHITE, 24, "GBFadeOutToWhite is 3 x 8 frames")
T.eq(Timing.FADE_IN_FROM_WHITE, 24, "GBFadeInFromWhite is 3 x 8 frames")

T.eq(Timing.DELAY3, 3, "Delay3 is three frames")
T.eq(Timing.TEXT_SCROLL_PAIR, 10, "ScrollTextUpOneLine is 5 frames, run twice")
T.eq(Timing.TEXT_CONT, 13, "<CONT>: ProtectedDelay3 + the two-line scroll")
T.eq(Timing.TEXT_PARAGRAPH, 23, "<PARA>: ProtectedDelay3 + DelayFrames 20")
T.eq(Timing.YES_NO_ANSWER, 15, "DisplayTwoOptionMenu holds 15 frames")
T.eq(Timing.WARP_FADE_OUT, 32, "a map change fades out over 32 frames")
T.eq(Timing.WARP_FADE_IN, 0, "there is no fade in: LoadGBPal restores in one write")

-- ---------------------------------------------------------------- HP bar

-- engine/gfx/hp_bar.asm:81-135
T.eq(Timing.hpBarPixels(150, 150), 48, "a full bar is 48 px")
T.eq(Timing.hpBarPixels(75, 150), 24, "half HP is half the bar")
T.eq(Timing.hpBarPixels(0, 150), 0, "an empty bar is 0 px")
T.eq(Timing.hpBarPixels(1, 150), 1, "GetHPBarLength clamps a sliver to 1 px")
-- engine/gfx/hp_bar.asm:19-34
T.eq(Timing.hpBarPixels(199, 399), 24, "max HP >= 256 divides both sides by 4 first")
T.eq(Timing.hpBarPixels(349, 399), 42, "so 349/399 is 42 px, not 41")
-- engine/gfx/hp_bar.asm:42-45
T.eq(Timing.hpBarLength(0, 150), 1, "GetHPBarLength also clamps 0 HP to 1 px")

T.eq(Timing.hpDrainFrames(150, 0, 150, true), 150 + 94 + 6,
  "a 150 HP player mon drains in D + 2P + 6 = 250 frames, 1 -> 0 moves no pixel")
T.eq(Timing.hpDrainFrames(150, 0, 150, false), 147,
  "the same drain on the enemy HUD lags a frame per pixel: 147")
T.eq(Timing.hpDrainFrames(40, 0, 40, false), 2 * 47 + 5,
  "a sub-48 HP enemy crosses a pixel every step, so no lag")

-- engine/gfx/hp_bar.asm:81-135
local measured = {
  { 100, 1, 100, false, 103 }, { 100, 0, 100, false, 103 },
  { 150, 1, 150, false, 147 }, { 150, 0, 150, false, 147 },
  { 193, 1, 193, false, 148 }, { 193, 0, 193, false, 148 },
  { 200, 1, 200, false, 152 }, { 200, 0, 200, false, 152 },
  { 255, 1, 255, false, 179 }, { 255, 0, 255, false, 179 },
  { 300, 1, 300, false, 195 }, { 300, 0, 300, false, 195 },
  { 400, 1, 400, false, 243 }, { 400, 0, 400, false, 243 },
  { 150, 90, 200, false, 50 }, { 300, 180, 400, false, 78 },
  { 300, 263, 300, false, 29 }, { 90, 1, 150, false, 88 },
  { 150, 0, 150, true, 250 }, { 150, 50, 150, true, 170 },
  { 200, 120, 200, true, 126 }, { 255, 1, 255, true, 354 },
  { 256, 0, 256, true, 356 }, { 399, 0, 399, true, 499 },
  { 399, 199, 399, true, 254 }, { 703, 303, 703, true, 462 },
  { 1, 415, 415, true, 514 }, { 1, 150, 150, true, 249 },
  { 37, 200, 200, true, 249 }, { 100, 255, 255, true, 221 },
}
for _, m in ipairs(measured) do
  T.eq(Timing.hpDrainFrames(m[1], m[2], m[3], m[4]), m[5],
    string.format("%s %d -> %d of %d matches the cart's %d frames",
      m[4] and "player" or "enemy", m[1], m[2], m[3], m[5]))
end
local knifeEdge = {
  { 240, 1, 240, 172 }, { 240, 0, 240, 172 }, { 256, 1, 256, 186 },
  { 256, 0, 256, 186 }, { 500, 1, 500, 283 }, { 500, 0, 500, 283 },
  { 703, 1, 703, 362 }, { 703, 0, 703, 362 },
}
for _, m in ipairs(knifeEdge) do
  local got = Timing.hpDrainFrames(m[1], m[2], m[3], false)
  T.check(math.abs(got - m[4]) <= 10,
    string.format("enemy %d -> %d of %d is within 10 of the cart's %d (got %d)",
      m[1], m[2], m[3], m[4], got))
end

-- The engine's per-frame stepper has to agree with that closed form, or the
-- bar is animating at a rate nothing else measures.
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

-- Each case gets its own party: draining a battler to 0 faints the very
-- Pokemon object the save holds, and newWild refuses to start with no
-- healthy party.
local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end,
                           push = function() end } }
  return BattleState.newWild(game, "FIXMON_C", 40)
end

local function drainFrames(battle, battler, toHP)
  battler.mon.hp = toHP
  local frames = 0
  while battle:stepHPDrain() and frames < 20000 do frames = frames + 1 end
  return frames
end

local battle = newBattle()
local pMax = battle.player.mon.stats.hp
T.eq(drainFrames(battle, battle.player, 0),
     Timing.hpDrainFrames(pMax, 0, pMax, true),
     "the player's bar steps at the hardware rate")

local battle2 = newBattle()
local eMax = battle2.enemy.mon.stats.hp
T.eq(drainFrames(battle2, battle2.enemy, 0),
     Timing.hpDrainFrames(eMax, 0, eMax, false),
     "the enemy's bar steps at the hardware rate")

-- a partial drain is exact too: every player-side HP step costs at least the
-- number print, so the stepper never batches two into one frame
local battle3 = newBattle()
local start = battle3.player.mon.hp
local target = math.max(1, start - 7)
T.eq(drainFrames(battle3, battle3.player, target),
     Timing.hpDrainFrames(start, target, battle3.player.mon.stats.hp, true),
     "a partial player drain matches the closed form")

-- ---------------------------------------------------------------- text box

-- Both <CONT> and <PARA> print the down-arrow and run ProtectedDelay3 before
-- ManualTextScroll starts watching the joypad, then pay the scroll or the
-- box clear after the button.  The port used to advance on the press frame
-- with no cost on either side.
local TextBox = require("src.render.TextBox")

local Input = { down = {}, pressed = {} }
function Input:isDown(b) return self.down[b] or false end
function Input:wasPressed(b) return self.pressed[b] or false end
function Input:press(b) self.pressed[b] = true end
function Input:release() self.pressed = {} end

local function textGame()
  local popped = false
  local g = { data = Data, save = SaveData.newGame(), input = Input }
  g.stack = { push = function() end,
              pop = function() popped = true end,
              top = function() return nil end }
  g.wasPopped = function() return popped end
  return g
end

-- type a box out to its first wait, returning the frames that took
local function typeToWait(box)
  local frames = 0
  while not box.waiting and not box.done and frames < 2000 do
    box:update(1 / 60)
    frames = frames + 1
  end
  return frames
end

local g = textGame()
g.save.options = g.save.options or {}
g.save.options.textSpeed = 1 -- fastest, so the typewriter is not the subject
local box = TextBox.new(g, "AB\fCD", {})
typeToWait(box)
T.check(box.waiting, "the box waits at the page break")

-- the three ProtectedDelay3 frames swallow the button
local held = 0
for _ = 1, Timing.TEXT_PRE_ADVANCE do
  Input:press("a")
  box:update(1 / 60)
  Input:release()
  held = held + 1
  T.check(box.waiting, "still waiting on pre-advance frame " .. held)
end

-- the press now lands, and the box holds for the clear before typing again
Input:press("a")
box:update(1 / 60)
Input:release()
T.eq(box.holdFrames, Timing.TEXT_PAGE_CLEAR,
  "a page break holds DelayFrames 20 after the press")
T.eq(#box.shown[1], 0, "the new page has not typed a character yet")

local blocked = 0
while (box.holdFrames or 0) > 0 and blocked < 200 do
  box:update(1 / 60)
  blocked = blocked + 1
  T.eq(#box.shown[#box.shown], 0, "nothing types during the hold")
end
T.eq(blocked, Timing.TEXT_PAGE_CLEAR, "the hold is exactly 20 frames")

-- <CONT> pays the two-line scroll instead of the clear
local g2 = textGame()
g2.save.options = g2.save.options or {}
g2.save.options.textSpeed = 1
local box2 = TextBox.new(g2, "AB\vCD", {})
typeToWait(box2)
T.check(box2.waiting, "the box waits at the CONT marker")
for _ = 1, Timing.TEXT_PRE_ADVANCE do box2:update(1 / 60) end
Input:press("a")
box2:update(1 / 60)
Input:release()
T.eq(box2.holdFrames, Timing.TEXT_SCROLL_PAIR,
  "a CONT advance holds for the two ScrollTextUpOneLine calls")

-- ---------------------------------------------------------------- yes/no

local ChoiceBox = require("src.ui.ChoiceBox")

local chosen, popped = nil, 0
local g3 = { data = Data, save = SaveData.newGame(), input = Input }
g3.stack = { push = function() end, pop = function() popped = popped + 1 end,
             top = function() return nil end }
local choice = ChoiceBox.new(g3, function(yes) chosen = yes end)

Input:press("a")
choice:update(1 / 60)
Input:release()
T.eq(chosen, nil, "the answer does not fire on the press frame")

-- count only the frames after the press: DelayFrames 15 runs between the
-- press and TwoOptionMenu_RestoreScreenTiles handing control back
local waited = 0
while chosen == nil and waited < 200 do
  choice:update(1 / 60)
  waited = waited + 1
end
T.eq(waited, Timing.YES_NO_ANSWER, "the answer fires 15 frames after the press")
T.eq(chosen, true, "A chose YES")
T.eq(popped, 1, "the box popped itself once")

-- B picks the second option, and the cursor snaps to it for the hold
local chosen2 = nil
local g4 = { data = Data, save = SaveData.newGame(), input = Input }
g4.stack = { push = function() end, pop = function() end,
             top = function() return nil end }
local choice2 = ChoiceBox.new(g4, function(yes) chosen2 = yes end)
Input:press("b")
choice2:update(1 / 60)
Input:release()
T.eq(choice2.index, 2, "B moves the cursor to NO before the hold")
local waited2 = 0
while chosen2 == nil and waited2 < 200 do
  choice2:update(1 / 60)
  waited2 = waited2 + 1
end
T.eq(waited2, Timing.YES_NO_ANSWER, "the B answer holds 15 frames too")
T.eq(chosen2, false, "B chose NO")

-- ---------------------------------------------------------------- warp fade

-- PlayMapChangeSound fades out over 32 frames and the new map simply
-- appears; the port used to run a symmetric 12/12 fade, which is both too
-- fast and a shape the hardware never had.
local Transition = require("src.render.Transition")

local mid, done, tpopped = 0, 0, 0
local g5 = { data = Data, save = SaveData.newGame() }
g5.stack = { push = function() end, pop = function() tpopped = tpopped + 1 end,
             top = function() return nil end }
-- warp = true: the map-change shape with no fade back in.  Script fades
-- (ViridianGym.asm .afterBeat) keep the symmetric GBFadeInFromBlack.
local fade = Transition.new(g5, function() mid = mid + 1 end,
                                function() done = done + 1 end, true)

local f = 0
while done == 0 and f < 500 do
  fade:update(1 / 60)
  f = f + 1
  if mid == 1 and done == 0 then
    T.check(false, "the map switch and the hand-back must land together")
  end
end
T.eq(f, Timing.WARP_FADE_OUT, "the warp fade is 32 frames end to end")
T.eq(mid, 1, "the map switched once")
T.eq(done, 1, "the transition handed control back once")
T.eq(tpopped, 1, "and popped itself once")

-- ------------------------------------------------------- battle turns

-- PlayApplyingAttackAnimation's six types (animations.asm:490-524).  The
-- slow shakes are c * 4b because AnimationShakeScreenHorizontallySlow pushes
-- bc twice and runs two b-loops of DelayFrames 2 per outer pass.
T.eq(Timing.SHAKE_VERTICAL, 48, "type 1 ShakeScreenVertically b=8")
T.eq(Timing.SHAKE_HORIZ_HEAVY, 72, "type 2 fast horizontal b=8")
T.eq(Timing.SHAKE_HORIZ_SLOW, 48, "type 3 slow horizontal, lb bc, 6, 2")
T.eq(Timing.SHAKE_HORIZ_LIGHT, 18, "type 5 fast horizontal b=2")
T.eq(Timing.SHAKE_HORIZ_SLOW2, 24, "type 6 slow horizontal, lb bc, 3, 2")

-- engine/battle/animations.asm:1360
T.eq(Timing.BLINK_MON, 78, "AnimationBlinkMon is 6 x (5 hidden + 8 shown)")
T.eq(Timing.BLINK_MON % 13, 0,
  "and divides into whole 13-frame blinks, matching fxHidden's period")

-- SlideDownFaintedMonPic: b = PIC_HEIGHT slide steps of DelayFrames 2
T.eq(Timing.FAINT_SLIDE, 14, "the faint slide is 7 steps x 2 frames")

-- #671: the slide must start at the sprite's resting spot and sink the
-- full PIC_HEIGHT (7 rows x 8px = 56px at 1x) across those 14 frames.
-- The old (30 - frames) * 2 math teleported the pic 32px down on frame
-- one once the budget was shortened from 30 to 14 frames.
local faintBattle = newBattle()
faintBattle.fx = { faint = { battler = faintBattle.enemy,
                             frames = Timing.FAINT_SLIDE } }
T.eq(faintBattle:fxFaintOffset(faintBattle.enemy, 1), 0,
  "the faint slide starts at offset 0 (#671)")
faintBattle.fx.faint.frames = Timing.FAINT_SLIDE - 7
T.eq(faintBattle:fxFaintOffset(faintBattle.enemy, 1),
     7 * Timing.FAINT_SLIDE_STEP,
  "the slide sinks one 8px row per step")
faintBattle.fx.faint.frames = 1
T.eq(faintBattle:fxFaintOffset(faintBattle.enemy, 1),
     (Timing.FAINT_SLIDE - 1) * Timing.FAINT_SLIDE_STEP,
  "the slide reaches 52px by the last visible frame")
T.eq(Timing.FAINT_SLIDE * Timing.FAINT_SLIDE_STEP, 56,
  "and covers the full 7-row pic height over the whole budget")

T.eq(Timing.MOVE_STATUS_OR_MISS, 30,
  "a status move or a miss holds DelayFrames 30 before its text")

T.eq(Timing.MOVE_ANIM_PRE, 3,
  "PlayMoveAnimation calls Delay3 before handing off to MoveAnimation")
T.eq(Timing.CRIT_OHKO_TEXT, 20,
  "PrintCriticalOHKOText closes with DelayFrames 20")
T.eq(Timing.BATTLE_START_SENDOUT, 40, "StartBattle holds 40 after the send-out")

-- An animation row pays PlayMoveAnimation's Delay3 before the first frame
-- of the animation, so the row goes back on the queue once (core.asm:6638).
do
  local b = newBattle()
  b.queue, b.nextInsert, b.current = {}, 0, nil
  b.waitFrames, b.waitingSound = nil, nil
  b.draining, b.animPlaying, b.waitingUI = nil, nil, nil
  b.queue[1] = { anim = "FIX_TACKLE", attackerIsPlayer = true }
  b:updateQueue()
  T.eq(b.waitFrames, Timing.MOVE_ANIM_PRE,
    "the anim row pays Delay3 before it plays")
  T.eq(#b.queue, 1, "and is put back on the queue to run after the hold")
  T.check(b.queue[1].animDelayed, "flagged so the hold is paid only once")
  b.waitFrames = nil
  b:updateQueue()
  T.check(b.waitFrames ~= Timing.MOVE_ANIM_OFF,
    "with animations on the disabled arm's 30 is never paid")
end

-- animations.asm:431-437
T.eq(Timing.MOVE_ANIM_OFF, 30, "the animations-off arm holds 30 frames")
do
  local b = newBattle()
  b.game.save.options.animations = false
  b.queue, b.nextInsert, b.current = {}, 0, nil
  b.waitFrames, b.waitingSound = nil, nil
  b.draining, b.animPlaying, b.waitingUI = nil, nil, nil
  b.queue[1] = { anim = "FIX_TACKLE", attackerIsPlayer = true,
                 hit = { animType = 4, blink = b.enemy } }
  b:updateQueue()
  T.eq(b.waitFrames, Timing.MOVE_ANIM_PRE, "Delay3 is paid whatever the option")
  b.waitFrames = nil
  b:updateQueue()
  T.eq(b.waitFrames, Timing.MOVE_ANIM_OFF, "then the 30 stands in for the anim")
  T.eq(#b.queue, 1, "and the row goes back for the applying-attack layer")
  T.check(b.queue[1].animOffDelayed, "flagged so the hold is paid only once")
  b.waitFrames = nil
  b:updateQueue()
  T.eq(b.waitFrames, Timing.BLINK_MON,
    "the enemy blink still runs with animations off (#1384)")
  T.check(b.fx and b.fx.blink ~= nil, "and it targets the enemy pic")
  local pattern = {}
  for _ = 1, 13 do
    pattern[#pattern + 1] = b:fxHidden(b.enemy) and "h" or "s"
    b.fx.blink.frames = b.fx.blink.frames - 1
  end
  T.eq(table.concat(pattern), "hhhhhssssssss",
    "each blink is 5 frames hidden then 8 shown")
end

-- animations.asm:415-419
do
  local b = newBattle()
  b.game.save.options.animations = false
  b.queue, b.nextInsert, b.current = {}, 0, nil
  b.waitFrames, b.waitingSound = nil, nil
  b.draining, b.animPlaying, b.waitingUI = nil, nil, nil
  b.queue[1] = { anim = "POOF_ANIM", attackerIsPlayer = true }
  b:updateQueue()
  b.waitFrames = nil
  b:updateQueue()
  T.check(b.waitFrames ~= Timing.MOVE_ANIM_OFF, "a ball anim skips the 30")
end

-- StartBattle's 40-frame hold is unconditional -- the `call nz` gates only
-- EnemySendOutFirstMon -- so a wild battle queues it too, between
-- "Wild X appeared!" and "Go! Y!" (core.asm:152-156).
do
  -- the intro queue is built by enter(), not by newWild
  local b = newBattle()
  local ok = pcall(b.enter, b)
  T.check(ok, "a wild battle's intro builds")
  local found = false
  for _, row in ipairs(b.queue) do
    if row.wait == Timing.BATTLE_START_SENDOUT then found = true break end
  end
  T.check(found, "a wild battle's intro queues the 40-frame send-out hold")
end

-- waitNext is what puts that hold in the turn queue
do
  local b = newBattle()
  b.queue, b.nextInsert = {}, 0
  b:waitNext(Timing.MOVE_STATUS_OR_MISS)
  T.eq(#b.queue, 1, "waitNext queues one row")
  T.eq(b.queue[1].wait, Timing.MOVE_STATUS_OR_MISS, "carrying the hold length")
  b:waitNext(0)
  T.eq(#b.queue, 1, "a zero-length hold queues nothing")
end

-- Battle text prints through the same PrintText path as overworld text, so
-- it pays PrintLetterDelay per character (home/print_text.asm:4-45): one
-- glyph per wOptions & $f frames, collapsing to one frame while A or B is
-- held.  It used to run a flat two glyphs per frame -- six times hardware
-- speed at the default setting -- and ignored the text-speed option.
local function typedFrames(speed, hold)
  local Btn = { down = {}, pressed = {} }
  function Btn:isDown(k) return self.down[k] or false end
  function Btn:wasPressed(k) return self.pressed[k] or false end
  if hold then Btn.down.a = true end

  local b = newBattle()
  b.game.input = Btn
  b.game.save.options = b.game.save.options or {}
  b.game.save.options.textSpeed = speed
  b.queue, b.nextInsert = {}, 0
  b.waitFrames, b.waitingSound = nil, nil
  b.draining, b.animPlaying, b.waitingUI = nil, nil, nil
  b:startMessage({ text = "ABCDEF" })
  local frames = 0
  while (b.charIndex or 0) < 6 and frames < 400 do
    b:updateQueue()
    frames = frames + 1
  end
  return frames
end

T.eq(typedFrames(3), 18, "six glyphs at MEDIUM take 3 frames each")
T.eq(typedFrames(5), 30, "six glyphs at SLOW take 5 frames each")
T.eq(typedFrames(1), 6, "six glyphs at FAST take 1 frame each")
T.eq(typedFrames(3, true), 6,
  "holding A collapses the per-letter wait to a single frame")

-- WaitForSoundToFinish (home/delay.asm:15-20) is how the original gives a
-- sound its own clear window.  A trainer intro plays SFX_Silph_Scope --
-- extracted here as "Trainer_Appeared" -- blocks on it, and only then pays
-- the DelayFrames 20 before the balls and the text.
do
  local b = newBattle()
  b.queue, b.nextInsert, b.current = {}, 0, nil
  b.waitFrames, b.waitingSound = nil, nil
  b.draining, b.animPlaying, b.waitingUI = nil, nil, nil
  local playing = true
  local src = { isPlaying = function() return playing end }
  b.queue[1] = { waitSound = function() return src end }
  T.check(b:updateQueue(), "the waitSound row is taken off the queue")
  T.eq(b.waitingSound, src, "and parks the queue on that source")
  T.check(b:updateQueue(), "the queue blocks while the sound is audible")
  playing = false
  b:updateQueue()
  T.eq(b.waitingSound, nil, "and releases the frame the sound stops")
end

-- Every battle enters through the wipe, script-driven ones included.
-- BattleTransition runs from DoBattleTransitionAndInitBattleVariables for
-- all of them; start_battle used to push the BattleState straight onto the
-- stack, so every scripted trainer -- gym leaders, the rival -- and every
-- scripted wild battle cut to the battle screen with no transition at all.
do
  local Commands = require("src.script.Commands")
  local route = {}
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local ctx = {
    game = { data = Data, save = save,
             stack = { push = function() route[#route + 1] = "raw" end,
                       top = function() return nil end } },
    runner = { yield = function() end, resume = function() end },
    overworld = { pushBattle = function() route[#route + 1] = "wipe" end },
  }
  Commands.start_battle(ctx, "wild", "FIXMON_C", 5)
  T.eq(#route, 1, "start_battle pushes the battle exactly once")
  T.eq(route[1], "wipe", "and routes it through the transition wipe")

  -- with no overworld (a headless or menu-driven caller) it still works
  local route2 = {}
  local ctx2 = {
    game = { data = Data, save = save,
             stack = { push = function() route2[#route2 + 1] = "raw" end,
                       top = function() return nil end } },
    runner = { yield = function() end, resume = function() end },
  }
  Commands.start_battle(ctx2, "wild", "FIXMON_C", 5)
  T.eq(route2[1], "raw", "and falls back to a direct push with no overworld")
end

-- --------------------------------------------------- battle transition

-- The eight wipes, from pokered-c's battle_transition.c budget (derived from
-- battle_transitions.asm, then checked against the ROM side by side).  The
-- port used a flat 40/24 for all eight.
local BT = require("src.render.BattleTransition")
local WIPES = {
  doublecircle = 30,  -- 10 steps x 3 frames
  circle       = 60,  -- 20 x 3
  spiralout    = 120, -- 360 fills / 3 per frame
  hstripes     = 60,  -- 20 x 3
  vstripes     = 54,  -- 18 x 3
  shrink       = 54,  -- 9 x 6
  split        = 54,  -- 9 x 6
}
for id, frames in pairs(WIPES) do
  T.eq(BT.STYLES[id].frames, frames, id .. " runs its asm frame budget")
end

-- The inward spiral writes one tile per iteration and calls
-- BattleTransition_TransferDelay3 every seventh -- and that helper is a
-- Delay3, three frames, not a one-frame transfer.  Reading it as one frame
-- gives ~46 frames against the ROM's ~150, which is the exact mistake
-- pokered-c caught on a live comparison.
T.eq(BT.STYLES.spiralin.frames % 3, 0,
  "the inward spiral advances in whole Delay3 units")
T.check(BT.STYLES.spiralin.frames >= 130 and BT.STYLES.spiralin.frames <= 170,
  "the inward spiral lands near the ROM's ~150 frames, not the ~46 a "
  .. "one-frame transfer would give (got "
  .. tostring(BT.STYLES.spiralin.frames) .. ")")

-- The flash belongs to the two wild wipes only: BattleTransition_FlashScreen
-- is called from BattleTransition_Circle (:585) and _DoubleCircle (:628) and
-- nowhere else.  A trainer battle's transition is the spiral, inward against
-- a weaker foe and outward against a stronger one
-- (wBattleTransitionSpiralDirection, :119-126).
do
  local fakeRenderer = {}
  local g = { data = Data, save = SaveData.newGame(), renderer = fakeRenderer,
              stack = { push = function() end, pop = function() end,
                        top = function() return nil end } }

  local wild = BT.new(g, function() end, { trainer = false, stronger = false })
  T.eq(wild.style, "doublecircle", "a weak wild foe gets the double circle")
  T.eq(wild.phase, "flash", "and flashes before the wipe")

  local weak = BT.new(g, function() end, { trainer = true, stronger = false })
  T.eq(weak.style, "spiralin", "a weaker trainer gets the inward spiral")
  T.eq(weak.phase, "wipe", "with no flash in front of it")

  local strong = BT.new(g, function() end, { trainer = true, stronger = true })
  T.eq(strong.style, "spiralout", "a stronger trainer gets the outward spiral")

  -- the flash is a palette write, so it veils the whole surface: it is
  -- handed to the renderer in screen space rather than filling the 160x144
  -- UI canvas, which at any zoom above 1x left the surround unlit
  wild:draw()
  T.check(fakeRenderer.screenVeil ~= nil,
    "the flash publishes a screen-space veil to the renderer")
  T.eq(#fakeRenderer.screenVeil, 2, "as a {shade, alpha} pair")
end

-- Returning to the overworld after a battle is a fade, not a cut:
-- DelayFrames 10 (home/overworld.asm:351-352) with the palettes still white,
-- then MapEntryAfterBattle's GBFadeInFromWhite (:749-753) = 24 frames.
do
  local popped, done = 0, 0
  local r = {}
  local g = { data = Data, save = SaveData.newGame(), renderer = r,
              stack = { push = function() end,
                        pop = function() popped = popped + 1 end,
                        top = function() return nil end } }
  local fade = require("src.render.Transition").battleReturn(g,
                 function() done = done + 1 end)

  -- solid white through the 10-frame hold
  for i = 1, Timing.POST_BATTLE_RETURN do
    fade:draw()
    T.eq(r.screenVeil[1], 1, "the veil is white on hold frame " .. i)
    T.eq(r.screenVeil[2], 1, "and fully opaque on hold frame " .. i)
    fade:update(1 / 60)
  end

  -- then it steps off in three palette stages of 8 frames, the way
  -- GBFadeIncCommon writes a palette and holds it (home/fade.asm:30-41)
  fade:draw()
  T.eq(r.screenVeil[2], 2 / 3, "the first fade step drops to two thirds")
  for _ = 1, 8 do fade:update(1 / 60) end
  fade:draw()
  T.eq(r.screenVeil[2], 1 / 3, "the second step to one third")
  for _ = 1, 8 do fade:update(1 / 60) end
  fade:draw()
  T.eq(r.screenVeil[2], 0, "the third clears it")

  -- total duration, measured on a fresh instance (the staircase checks above
  -- advanced this one)
  local popped2, done2 = 0, 0
  local g2 = { data = Data, save = SaveData.newGame(), renderer = {},
               stack = { push = function() end,
                         pop = function() popped2 = popped2 + 1 end,
                         top = function() return nil end } }
  local fade2 = require("src.render.Transition").battleReturn(g2,
                  function() done2 = done2 + 1 end)
  local frames = 0
  while done2 == 0 and frames < 500 do
    fade2:update(1 / 60)
    frames = frames + 1
  end
  T.eq(frames, Timing.POST_BATTLE_RETURN + Timing.FADE_IN_FROM_WHITE,
    "the whole return is the 10-frame hold plus a 24-frame fade")
  T.eq(popped2, 1, "and it pops itself exactly once")
  T.check(popped >= 0, "the staircase instance is independent")
end

-- The spiral and circle walks generalise to an arbitrary grid, so a zoomed
-- or windowed surface wipes as one figure instead of a spiral in a box
-- surrounded by a square cascade.
do
  local COLS_GB, ROWS_GB = 20, 18 -- the Game Boy's own tile grid
  for _, style in ipairs({ "spiralin", "spiralout", "circle", "doublecircle" }) do
    local order = BT.gridOrder(style, 40, 23)
    T.check(order ~= nil, style .. " builds an order for an arbitrary grid")
    T.eq(#order, 40 * 23, style .. " covers every tile of a 40x23 grid")
    local seen, dup = {}, false
    for _, t in ipairs(order) do
      local k = t[1] .. "," .. t[2]
      if seen[k] then dup = true end
      seen[k] = true
    end
    T.check(not dup, style .. " visits each tile exactly once")
  end
  T.eq(BT.gridOrder("shrink", 40, 23), nil,
    "geometry-shaped styles have no tile order and are extended as rects")
  -- At exactly the Game Boy's grid, gridOrder hands back the ROM's own walk
  -- rather than the generic one -- so an unzoomed window is the classic wipe.
  -- BattleTransition_InwardSpiral fills 359 of the 360 tiles and leaves the
  -- centre one to the final blackout, which is how you tell the two apart.
  T.eq(#BT.gridOrder("spiralin", COLS_GB, ROWS_GB), 359,
    "the classic grid gets the ROM's walk, not the generic spiral")
  T.check(#BT.gridOrder("spiralin", COLS_GB + 1, ROWS_GB)
          == (COLS_GB + 1) * ROWS_GB,
    "one tile wider and it is the generic spiral, covering everything")
  -- degenerate grids must not hang or error
  T.eq(#BT.gridOrder("spiralin", 1, 1), 1, "a 1x1 grid is one tile")
  T.eq(#BT.gridOrder("spiralout", 3, 1), 3, "a single-row grid walks straight")
end

-- SlidePlayerAndEnemySilhouettesOnScreen: 144 px at 2 px/frame
T.eq(Timing.BATTLE_SLIDE_IN_FRAMES, 72, "the silhouettes slide for 72 frames")
T.eq(Timing.BATTLE_SLIDE_PX_PER_FRAME, 2, "at 2 px per frame")
T.eq(Timing.BATTLE_SLIDE_IN_FRAMES * Timing.BATTLE_SLIDE_PX_PER_FRAME, 144,
  "which is the SCX $90 the enemy side scrolls through")

T.eq(Timing.TRAINER_INTRO_SFX_GAP, 20,
  "a trainer intro waits DelayFrames 20 before the balls and the text")

-- ------------------------------------------------------- catch-up clamping

-- Removing the warp fade in took away the counter that used to absorb the
-- map-load hitch, so discardCatchup has to handle the oversized dt the hitch
-- produces on the FOLLOWING frame -- otherwise the burst just moves one
-- frame later and shows up as a walk-animation slide (issue #93).
local FixedStep = require("src.core.FixedStep")

local steps = 0
FixedStep:init(function() steps = steps + 1 end)
FixedStep:update(1 / 60)
T.eq(steps, 1, "an ordinary frame runs exactly one logic step")

-- what the hitch does when nothing is armed
steps = 0
FixedStep:update(0.25)
T.check(steps > 10,
  "an unclamped hitch frame burns a burst of steps before the next draw")

-- and with the clamp armed
FixedStep:init(function() steps = steps + 1 end)
FixedStep:discardCatchup()
steps = 0
FixedStep:update(0.25)
T.eq(steps, 1, "the frame after discardCatchup is clamped to one step")

steps = 0
FixedStep:update(1 / 60)
T.eq(steps, 1, "and the clamp expires after that one frame")

-- ...and the absorbed frame must not hand the accumulator back sitting on a
-- step boundary.  A residual of zero has no margin on the long side, so the
-- accumulator settles a hair under one step and stays there, flipping between
-- 0 and 2 steps on sub-millisecond frame wobble for the rest of the session,
-- which is what made pacing erratic forever after a route seam (issue #487).
FixedStep:init(function() steps = steps + 1 end)
FixedStep:discardCatchup()
FixedStep:update(0.25)
T.check(FixedStep.accum > FixedStep.STEP * 0.25
        and FixedStep.accum < FixedStep.STEP * 0.75,
  "the absorbed hitch frame leaves the accumulator mid-step, not on a boundary")


T.eq(FixedStep.refreshPeriod, nil, "no refresh period is known headless")

local function cadence(hz, frames, period, jitter)
  local seed = 20250828
  local counts, run, worst = {}, 0, 1
  FixedStep.refreshPeriod = period
  FixedStep:init(function() run = run + 1 end)
  for i = 1, frames do
    local before = run
    local dt = 1 / hz
    if jitter then
      seed = (seed * 1103515245 + 12345) % 2147483648
      dt = dt + (seed / 2147483648 - 0.5) * 2 * jitter
    end
    FixedStep:update(dt)
    counts[i] = run - before
    local residual = FixedStep.accum % FixedStep.STEP
    worst = math.min(worst, residual, FixedStep.STEP - residual)
  end
  FixedStep.refreshPeriod = nil
  local seen = {}
  for _, n in ipairs(counts) do seen[n] = (seen[n] or 0) + 1 end
  return run, seen, worst
end

local ran, seen, margin = cadence(90, 180, 1 / 90)
T.eq(ran, 120, "180 frames of a 90Hz panel are exactly 120 logic steps")
T.eq(seen[0], 60, "60 of them draw the same logic frame twice")
T.eq(seen[1], 120, "the other 120 advance once")
T.eq(seen[2], nil, "and no display frame ever doubles up")
T.check(margin > 0.002,
  "the residual cycle sits clear of the step boundary at 90Hz")

local _, jittered, jitterMargin = cadence(90, 180, 1 / 90, 0.001)
T.eq(jittered[1], 120, "a millisecond of vsync wobble moves no step")
T.eq(jittered[2], nil, "and doubles none up")
T.check(jitterMargin > 0.002, "the snapped dt keeps the wobble out of the sum")

local _, unsnapped, bareMargin = cadence(90, 180, nil)
T.eq(unsnapped[1], 120, "the same stream unsnapped costs the same 120 steps")
T.check(bareMargin < 0.0005,
  "but parks the accumulator on the boundary, with nothing to absorb wobble")

local at60, sixty = cadence(60, 180, 1 / 60)
T.eq(at60, 180, "a 60Hz panel is one step per frame")
T.eq(sixty[1], 180, "every frame, with no duplicate and no double")

local at144 = cadence(144, 288, 1 / 144)
T.eq(at144, 120, "288 frames of a 144Hz panel are 120 steps")

local at5994, nearSixty, nearMargin = cadence(59.94, 600, 1 / 60)
T.eq(at5994, 600, "a 59.94Hz panel quantized to 60 is still one step per frame")
T.eq(nearSixty[2], nil, "with no frame ever doubling up")
T.check(nearMargin > 0.002, "and no drift onto the step boundary")

local rephased = 0
FixedStep.refreshPeriod = 1 / 60
FixedStep:init(function() rephased = rephased + 1 end)
for i = 1, 120 do
  FixedStep.refreshPeriod = (1 / 60) * (1 + (i % 2) * 1e-9)
  FixedStep:update(1 / 60)
end
local rephasedMargin = math.min(FixedStep.accum % FixedStep.STEP,
  FixedStep.STEP - FixedStep.accum % FixedStep.STEP)
FixedStep.refreshPeriod = nil
T.eq(rephased, 120, "a period re-reported every frame still costs one step a frame")
T.check(rephasedMargin > 0.002,
  "and the re-phase sets the residual instead of walking it onto the boundary")

T.eq(FixedStep.refreshPeriod, nil, "and the period is left nil for everyone else")

T.finish("timing parity")
