-- engine/items/item_effects.asm:1656-1663

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }
package.loaded["src.core.Music"] = { playMap = function() end }
package.loaded["src.world.PikachuFollower"] = { modifyHappiness = function() end }
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done, opts)
    return { textBox = true, text = text, done = done, opts = opts }
  end,
  soundOpts = function() return nil end,
  strip = function(s) return s end,
}
package.loaded["src.ui.BagMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
require("src.ui.Screens").invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")

local Data = Fixtures.fresh()
Data.items.DIRE_HIT = Data.items.DIRE_HIT
  or { id = "DIRE_HIT", index = 58, name = "DIRE HIT", price = 650 }
Data.items.X_ATTACK = Data.items.X_ATTACK
  or { id = "X_ATTACK", index = 65, name = "X ATTACK", price = 500 }

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
  Bag.add(game.save, "DIRE_HIT", 1)
  Bag.add(game.save, "X_ATTACK", 1)
  return game
end

local function freshBattle()
  local battle = {
    kind = "wild",
    player = {
      name = "AAA", isPlayer = true, stages = {},
      mon = { species = "PIKACHU", level = 10, hp = 30,
              stats = { hp = 30, attack = 20, defense = 20, speed = 20, special = 20 } },
    },
    enemy = {
      name = "BBB", stages = {},
      mon = { species = "PIDGEY", level = 10, hp = 30,
              stats = { hp = 30, attack = 20, defense = 20, speed = 20, special = 20 } },
    },
  }
  function battle:itemUsed(msgs, o) self.used = { msgs = msgs, opts = o } end
  return battle
end

local function useInBattle(id)
  local game = freshGame()
  local battle = freshBattle()
  local list = BagMenu.new(game, { battle = battle })
  game.stack:push(list)
  for i, r in ipairs(list.items) do
    if r.value == id then list.index = i end
  end
  game.input.pressed = "a"
  list:update(1 / 60)
  game.input.pressed = nil
  return game, battle, list
end

for _, id in ipairs({ "DIRE_HIT", "X_ATTACK" }) do
  local game, battle, list = useInBattle(id)
  local box = game.stack:top()
  if check(box and box.textBox, id .. ": the used line prints") then
    eq(game.stack.states[#game.stack.states - 1], list,
       id .. ": over the still-open bag")
    eq(list.hollowIndex, list.index, id .. ": with the hollow cursor on the row")
    check(battle.used == nil, id .. ": the turn is not spent yet")
    game.stack:pop()
    box.done()
    check(game.stack:top() ~= list, id .. ": the bag closes after the text")
    check(battle.used ~= nil, id .. ": then the battle takes the turn")
    local left = 0
    for _, r in ipairs(Bag.rows(game.save, Data)) do
      if r.id == id then left = left + (r.qty or r.count or 1) end
    end
    eq(left, 0, id .. ": and the item is gone")
  end
end

T.finish("battle item text over bag 2926")
