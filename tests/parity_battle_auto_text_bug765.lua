-- Parity test: battle pages whose ROM tail is `text_end` / `done` hand off
-- with no button press (#765).  Only TX_PROMPT_BUTTON writes the '▼' and
-- runs ManualTextScroll (home/text.asm:434-446); a TX_END tail returns
-- straight out of PrintText (home/text.asm:328-334).  The used-move line
-- (engine/battle/used_move_text.asm EndUsedMove1Text..EndUsedMove5Text) and
-- the item-use line (ItemUseText00, engine/items/item_effects.asm) are both
-- of that kind, so a sayAuto row must flow into the next queue row untouched
-- while a plain say page still waits on A/B like PromptText.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity battle auto text (#765)")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local Timing = require("src.core.Timing")

-- Silence audio: BattleState reaches both modules through require() at the
-- call site, so patching the fields here is what the battle ends up calling.
Sound.playCry = function() end
Sound.play = function() end
Sound.playMove = function() end
Sound.playMoveCry = function() end
Sound.stopLoop = function() end
Music.playBattle = function() end
Music.play = function() end

-- stub stack + input, like the other headless battle probes
local press = {}
local function makeGame(party)
  local save = SaveData.newGame()
  save.party = party
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return { data = Data, save = save, stack = stack,
           input = { wasPressed = function(_, b) return press[b] == true end,
                     isDown = function(_, b) return press[b] == true end } }
end

local game = makeGame({ Pokemon.new(Data, "BULBASAUR", 50) })
local battle = BattleState.newWild(game, "RATTATA", 2)
battle.onFinish = function() end
battle:enter()

-- strip the intro so the queue under test is exactly what gets inserted;
-- afterQueue is cleared so a drained queue between probes cannot flip the
-- phase to "menu" and stop update() from pumping messages
battle.queue = {}
battle.current = nil
battle.introSlide = 0
battle.phase = "messages"
battle.afterQueue = nil

-- ------------------------------------------------- auto page, no delay
local ran = false
battle:sayAuto("AUTO PAGE")
battle:act(function() ran = true end)

local promptedDuringAuto = false
for _ = 1, 300 do
  if ran then break end
  if battle.msgPrompt then promptedDuringAuto = true end
  battle:update(1 / 60)
end
check(ran, "an auto page hands off to the next row with no button")
check(not promptedDuringAuto, "the prompt flag never rises on an auto page")
eq(battle.msgHold, true,
   "the finished auto page stays held for drawTextArea (#296)")

-- ------------------------------------------------- auto page, autoDelay
local ran2, typedFrame, ranFrame = false, nil, nil
battle:sayAuto("HELD PAGE", 30)
battle:act(function() ran2 = true end)
for f = 1, 600 do
  battle:update(1 / 60)
  if not typedFrame and battle.current
     and battle.charIndex >= battle.total then
    typedFrame = f
  end
  if ran2 then ranFrame = f break end
end
check(ran2, "the delayed auto page still hands off by itself")
check(typedFrame ~= nil and ranFrame ~= nil
      and ranFrame - typedFrame >= 30,
      "autoDelay holds the finished page for its frame count first")

-- ------------------------------------------------- plain page still prompts
battle:say("PROMPT PAGE")
local prompted = false
for _ = 1, 300 do
  battle:update(1 / 60)
  if battle.msgPrompt then prompted = true break end
end
check(prompted, "a plain page still raises the blinking prompt (#317)")
-- PromptText runs ProtectedDelay3 before ManualTextScroll watches the
-- joypad (home/text.asm:213-217), so pay that hold before pressing
for _ = 1, Timing.TEXT_PRE_ADVANCE do battle:update(1 / 60) end
check(battle.current ~= nil, "and the page holds on screen with no button")
press.a = true
battle:update(1 / 60)
press.a = false
eq(battle.msgPrompt, nil, "the A press clears the prompt")
eq(battle.current, nil, "and dismisses the page")

S.finish()
