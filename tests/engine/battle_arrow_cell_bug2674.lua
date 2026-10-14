-- home/text.asm:262
package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local SPACE = 0x7F
local LAST = Font.encode("Z")[1]
T.check(LAST ~= SPACE, "fixture charmap encodes the 18th glyph")

local function newBattle(opts)
  opts = opts or {}
  local save = SaveData.newGame()
  save.player.name = "RED"
  save.party = { Pokemon.new(Data, "FIXMON_A", 10, function(_, b) return b end) }
  if opts.gold then save.version, save.generation = "gold", 2 end
  if opts.wide then save.options = save.options or {}; save.options.battleLayout = "wide" end
  local pressA = false
  local game = {
    data = Data, save = save,
    stack = { top = function() return nil end, push = function() end },
    input = { wasPressed = function(_, k) return pressA and (k == "a") end,
              isDown = function() return false end },
  }
  local battle = BattleState.newWild(game, "FIXMON_C", 10)
  battle.queue, battle.nextInsert = {}, 0
  battle.phase = "messages"
  return battle, function(v) pressA = v end
end

local function step(battle, until_)
  for _ = 1, 2000 do
    if until_() then return true end
    battle:updateQueue()
    battle:tickTextScroll()
  end
  return until_()
end

local function drawnAt(battle, frame)
  battle.frame = frame
  local real, realBox = Font.drawCode, Font.drawBox
  local hits = {}
  Font.drawCode = function(code, x, y) hits[#hits + 1] = { code = code, x = x, y = y } end
  Font.drawBox = function() end
  local ok, err = pcall(function() battle:drawTextArea() end)
  Font.drawCode, Font.drawBox = real, realBox
  T.check(ok, "drawTextArea runs (" .. tostring(err) .. ")")
  local at, row, arrow = {}, 0, false
  for _, h in ipairs(hits) do
    if h.y == 128 then row = row + 1 end
    if h.x == 144 and h.y == 128 then
      if h.code == 0xEE then arrow = true else at[#at + 1] = h.code end
    end
  end
  return at, row, arrow
end

local TEXT = "YOUR DEX IS\nENTIRELY COMPLETEZ\vCONGRATULATIONSZ"

do
  local battle, setA = newBattle()
  battle.queue[1] = { text = TEXT }
  T.check(step(battle, function() return battle.msgWaiting end),
    "red reaches the cont wait under an 18-tile line")
  T.eq(battle.shown[2] and battle.shown[2][18], LAST,
    "red bottom line's 18th glyph is typed")
  battle.msgPreWait = 0
  local lit, row, arrow = drawnAt(battle, 0)
  T.check(row >= 17, "the bottom line is drawn")
  T.eq(#lit, 0, "red arrow replaces the 18th glyph while lit")
  T.check(arrow, "the arrow sits in tile (18,16), home/text.asm:440")
  local dark, rowDark = drawnAt(battle, 30)
  T.check(rowDark >= 17, "the bottom line is drawn on blink-off")
  T.eq(#dark, 0, "red blink-off shows a blank cell, not the glyph")
  setA(true)
  battle:updateQueue()
  setA(false)
  T.eq(battle.msgWaiting, nil, "red A clears the cont wait")
  T.eq(battle.shown[1] and battle.shown[1][18], SPACE,
    "red cont leaves a space in the scrolled line")
end

do
  local battle, setA = newBattle({ gold = true })
  battle.queue[1] = { text = TEXT }
  step(battle, function() return battle.msgWaiting end)
  battle.msgPreWait = 0
  setA(true)
  battle:updateQueue()
  setA(false)
  T.eq(battle.shown[1] and battle.shown[1][18], LAST,
    "gold keeps column 18 (its arrow sits on the border row)")
end

do
  local battle, setA = newBattle({ wide = true })
  battle.queue[1] = { text = TEXT }
  step(battle, function() return battle.msgWaiting end)
  battle.msgPreWait = 0
  setA(true)
  battle:updateQueue()
  setA(false)
  T.eq(battle.shown[1] and battle.shown[1][18], LAST,
    "wide layout keeps column 18 (its arrow sits at column 36)")
end

do
  local battle, setA = newBattle()
  battle.queue[1] = { text = "ITS A TEST OF\nTHE ARROW CELLS ZZ" }
  T.check(step(battle, function() return battle.msgPrompt end),
    "a typed-out page raises the prompt arrow")
  T.eq(battle.shown[2][18], LAST, "the prompt page's 18th glyph is typed")
  local lit, row = drawnAt(battle, 0)
  T.check(row >= 17, "the prompt page's bottom line is drawn")
  T.eq(#lit, 0, "prompt arrow replaces the 18th glyph")
  battle.msgPromptWait = 0
  setA(true)
  battle:updateQueue()
  setA(false)
  T.eq(battle.msgPrompt, nil, "A dismisses the prompt")
  T.eq(battle.shown[2][18], SPACE, "PromptText writes a space over the arrow cell")
  local held = drawnAt(battle, 0)
  T.eq(held[1], SPACE, "the held page shows the blank, not the glyph")
end

do
  local battle = newBattle()
  battle.queue[1] = { text = "SHORT LINE\nSHORT TOO\vNEXT" }
  step(battle, function() return battle.msgWaiting end)
  T.check(#battle.shown[2] < 18, "a short bottom line has no 18th glyph")
  battle.msgPreWait = 0
  T.eq(#drawnAt(battle, 30), 0, "nothing drawn in the arrow cell for a short line")
end

T.finish("battle arrow cell bug 2674")
