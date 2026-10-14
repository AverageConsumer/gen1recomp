-- engine/menus/start_sub_menus.asm:330-345, home/window.asm:119-206
--   luajit tests/engine/bag_use_toss_hollow_cursor_2063.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }
package.loaded["src.core.Music"] = { playMap = function() end }
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done, opts)
    return { textBox = true, text = text, done = done, opts = opts }
  end,
  soundOpts = function() return nil end,
}
package.loaded["src.ui.BagMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local Menu = require("src.ui.Menu")
require("src.ui.Screens").invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")

local Data = Fixtures.fresh()
Data.items.BICYCLE = { id = "BICYCLE", index = 6, name = "BICYCLE", price = 0,
                       keyItem = true }
Data.text = Data.text or {}
Data.text._GotOnBicycleText1 = "{PLAYER} got on the{DONE}"
Data.text._GotOnBicycleText2 = "{RAM:wStringBuffer}!{PROMPT}"
Data.text._GotOffBicycleText1 = "{PLAYER} got off{DONE}"
Data.text._GotOffBicycleText2 = "the {RAM:wStringBuffer}.{PROMPT}"
Data.items.FIX_POTION = Data.items.FIX_POTION
  or { id = "FIX_POTION", index = 20, name = "FIX POTION", price = 300 }
local tmMove = next(Data.moves)
Data.items.FIX_TM = { id = "FIX_TM", index = 201, name = "TM01", price = 3000,
                      machine = { move = tmMove, kind = "TM" } }

local function freshGame()
  local game = {
    data = Data,
    save = {
      party = {},
      player = { name = "RED", id = 1 },
      inventory = {},
      options = {},
      flags = {},
      money = 0,
    },
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = { pressed = nil }
  function game.input:wasPressed(b) return self.pressed == b end
  function game.input:isDown() return false end
  game.overworld = { map = { id = "FIX_TOWN", def = { tileset = "OVERWORLD" } },
                     player = { surfing = false } }
  Bag.add(game.save, "FIX_POTION", 3)
  Bag.add(game.save, "BICYCLE", 1)
  Bag.add(game.save, "FIX_TM", 1)
  return game
end

local function rowFor(list, pred)
  for i, r in ipairs(list.items) do
    if pred(r) then return i end
  end
  return nil
end

local function openOn(game, pred, opts)
  local list = BagMenu.new(game, opts or {})
  game.stack:push(list)
  local row = rowFor(list, pred)
  if not row then return nil end
  list.index = row
  return list
end

local function pressA(game, list)
  game.input.pressed = "a"
  list:update(1 / 60)
  game.input.pressed = nil
end

local function byId(id)
  return function(r) return r.value == id end
end
local isCancelRow = function(r) return r.cancel == true end

do
  local game = freshGame()
  local list = openOn(game, byId("FIX_POTION"))
  if check(list ~= nil, "the bag opened on an ordinary item") then
    check(list.hollowIndex == nil, "the row starts on the filled '▶'")
    local chosen = list.index
    pressA(game, list)
    check(getmetatable(game.stack:top()) == Menu, "the USE/TOSS box is up")
    eq(list.hollowIndex, chosen,
       "and the chosen row wears the hollow '▷' behind it")

    game.stack:pop()
    list:update(1 / 60)
    check(list.hollowIndex == nil,
          "the filled '▶' comes back once the list owns input again")
  end
end

do
  local game = freshGame()
  local list = openOn(game, byId("FIX_TM"))
  if check(list ~= nil, "the bag opened on the TM row") then
    check(list.index > 1, "which is not the first row")
    pressA(game, list)
    eq(list.hollowIndex, list.index, "the TM's own row goes hollow")
  end
end

-- engine/menus/start_sub_menus.asm:361
local function useLeavesBox(id, label)
  local game = freshGame()
  local list = openOn(game, byId(id))
  if not check(list ~= nil, label .. ": the bag opened on the row") then return end
  pressA(game, list)
  local box = game.stack:top()
  if not check(getmetatable(box) == Menu, label .. ": the USE/TOSS box is up") then return end
  eq(box.index, 1, label .. ": the cursor sits on USE")
  game.input.pressed = "a"
  box:update(1 / 60)
  game.input.pressed = nil
  check(game.stack:top() ~= box, label .. ": USE takes the box off the stack")
  check(game.stack:top() and game.stack:top().textBox,
        label .. ": the use flow prints its text")
  check(list.optionBox == box, label .. ": the box stays painted under the text")
  eq(box.hollowIndex, 1, label .. ": with the hollow '▷' left on USE")
  local drawn = false
  local realDraw = box.draw
  box.draw = function(self) drawn = true end
  list.drawItemBox = function() end
  list:draw()
  list.drawItemBox = nil
  box.draw = realDraw
  check(drawn, label .. ": drawing the list repaints the leftover box")
  game.stack:pop()
  drawn = false
  box.draw = function(self) drawn = true end
  list.drawItemBox = function() end
  list:draw()
  list.drawItemBox = nil
  box.draw = realDraw
  check(not drawn, label .. ": the first frame back on the list has no box")
  check(list.optionBox == nil, label .. ": the redraw erases it before any update")
  check(list.hollowIndex == nil, label .. ": and the list's '▶' is filled again")
  list:update(1 / 60)
  check(list.optionBox == nil, label .. ": the list's next update keeps it erased")
end
useLeavesBox("FIX_TM", "TM booted-up text")
useLeavesBox("FIX_POTION", "potion refusal text")

-- engine/menus/start_sub_menus.asm:416
do
  local game = freshGame()
  local list = openOn(game, byId("FIX_TM"))
  if check(list ~= nil, "TM YES: the bag opened on the TM row") then
    pressA(game, list)
    local box = game.stack:top()
    game.input.pressed = "a"
    box:update(1 / 60)
    game.input.pressed = nil
    local text = game.stack:top()
    check(list.optionBox == box, "TM YES: the box is painted under the prompt")
    local Screens = require("src.ui.Screens")
    local realPush, pushed = Screens.push, nil
    Screens.push = function(g, id)
      pushed = id
      g.stack:push({ partyMenu = true })
    end
    local choice = text and text.opts and text.opts.choice
    if check(choice ~= nil, "TM YES: the prompt carries the YES/NO choice") then
      choice(true)
    end
    Screens.push = realPush
    eq(pushed, "PartyMenu", "TM YES: the party menu opens")
    check(list.optionBox == nil, "TM YES: the party menu wipes the leftover box")
  end
end

-- CANCEL exits like B and never opens the box (home/list_menu.asm:105-110)
do
  local game = freshGame()
  local list = openOn(game, isCancelRow)
  if check(list ~= nil, "the bag opened on CANCEL") then
    pressA(game, list)
    check(list.hollowIndex == nil, "CANCEL leaves no hollow cursor behind")
    check(getmetatable(game.stack:top()) ~= Menu, "and opens no option box")
  end
end

-- the BICYCLE skips the box entirely (start_sub_menus.asm:340-342) #1705
do
  local game = freshGame()
  local list = openOn(game, byId("BICYCLE"))
  if check(list ~= nil, "the bag opened on the BICYCLE row") then
    pressA(game, list)
    check(list.hollowIndex == nil, "the bike's row keeps the filled '▶'")
    eq(game.save.onBike, true, "and the one press still mounted")
  end
end

-- the in-battle bag has no option box either (core.asm:2210-2234)
do
  local game = freshGame()
  local battle = { isBattle = true }
  local list = openOn(game, byId("FIX_TM"), { battle = battle })
  if check(list ~= nil, "the bag opened mid-battle") then
    pressA(game, list)
    check(list.hollowIndex == nil, "the in-battle row keeps the filled '▶'")
    check(getmetatable(game.stack:top()) ~= Menu, "and no USE/TOSS box appeared")
  end
end

-- ListMenu:update returns before the clear (parity_J, core.asm:2210)
do
  local game = freshGame()
  local ListMenu = require("src.ui.ListMenu")
  local list = ListMenu.new(game, "ITEMS", {
    { value = "POKE_BALL", label = "POKé BALL", count = 50 },
  }, { itemBox = true, script = function(l) l.hollowIndex = l.index end })
  game.stack:push(list)
  list:update(1 / 60)
  eq(list.hollowIndex, 1, "the scripted auto-A's hollow '▷' survives update")
end

package.loaded["src.core.Sound"] = nil
package.loaded["src.core.Music"] = nil
package.loaded["src.render.TextBox"] = nil
package.loaded["src.ui.BagMenu"] = nil
require("src.ui.Screens").invalidate()

T.finish()
