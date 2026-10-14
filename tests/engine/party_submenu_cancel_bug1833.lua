-- Out of battle the per-mon submenu ends STATS/SWITCH/CANCEL: pokered
-- prints one string, PokemonMenuEntries (engine/menus/text_box.asm:504-507),
-- under whatever field moves the mon has, and start_sub_menus.asm:71-75
-- treats the last row as a real selection that leaves the party menu
-- (.exitMenu, start_sub_menus.asm:26-30) where B only returns to the list.
-- The port stopped at SWITCH (#1833).  ROM-free: drives the real PartyMenu
-- over stub game state.
--   luajit tests/engine/party_submenu_cancel_bug1833.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq, same = T.check, T.eq, T.same
love = love or require("tests.love_stub")

local PartyMenu = require("src.ui.PartyMenu")

local function newGame(moves)
  local game = {
    data = { pokemon = { LAPRAS = { name = "LAPRAS" } } },
    save = {
      party = { { species = "LAPRAS", hp = 50, stats = { hp = 50 },
                  level = 30, moves = moves } },
      inventory = {}, options = {}, flags = {},
    },
    overworld = { map = { def = { tileset = "OVERWORLD" },
                          id = "PALLET_TOWN" },
                  dark = false },
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  return game
end

local function press(pm, btn)
  pm.game.input.queue = { [btn] = true }
  pm:update(1 / 60)
  pm.game.input.queue = {}
end

local function actions(items)
  local out = {}
  for i, item in ipairs(items or {}) do out[i] = item.action end
  return out
end

local game = newGame({ { id = "TACKLE", pp = 35 } })
local cancelled = false
local pm = PartyMenu.new(game, { onCancel = function() cancelled = true end })
game.stack:push(pm)
press(pm, "a")
check(pm.submenu, "A on a party mon opens the submenu")
same(actions(pm.subItems), { "stats", "switch", "cancel" },
     "the plain list is PokemonMenuEntries in full (#1833)")
eq(pm.subItems[3].label, "CANCEL", "CANCEL closes the list")

-- home/window.asm:46
press(pm, "up")
eq(pm.subIndex, 1, "up from STATS stays on STATS (no wrap)")
press(pm, "down")
press(pm, "down")
press(pm, "down")
eq(pm.subIndex, 3, "down stops on CANCEL (no wrap)")
press(pm, "a")
eq(#game.stack.states, 0, "choosing CANCEL leaves the party menu (.exitMenu)")
check(cancelled, "and reports the cancel to the caller")

-- B out of the submenu is the other path: back to the party list, menu up
local game2 = newGame({ { id = "TACKLE", pp = 35 } })
local pm2 = PartyMenu.new(game2, {})
game2.stack:push(pm2)
press(pm2, "a")
press(pm2, "b")
check(not pm2.submenu, "B closes the submenu")
eq(#game2.stack.states, 1, "B keeps the party menu up (start_sub_menus.asm:68-69)")

-- field moves still lead, with the three fixed rows under them
local game3 = newGame({ { id = "STRENGTH", pp = 15 }, { id = "SURF", pp = 15 } })
local pm3 = PartyMenu.new(game3, {})
game3.stack:push(pm3)
press(pm3, "a")
same(actions(pm3.subItems), { "strength", "surf", "stats", "switch", "cancel" },
     "field moves sit above the whole of PokemonMenuEntries")

-- the in-battle list is its own three-row template and is unchanged
local game4 = newGame({ { id = "SURF", pp = 15 } })
local pm4 = PartyMenu.new(game4, { battle = {}, onSwitch = function() end })
game4.stack:push(pm4)
press(pm4, "a")
same(actions(pm4.subItems), { "battle_switch", "stats", "cancel" },
     "battle keeps SwitchStatsCancelText's order (data/text_boxes.asm:33)")

-- engine/battle/core.asm:2320-2326
package.loaded["src.render.TextBox"] = { new = function() return {} end }
pm4:refuse("There's no will\nto fight!")
check(not pm4.submenu, "a refusal closes the submenu")
eq(pm4.subEdge and pm4.subEdge.lx, 12, "but keeps its box at column 11")
eq(pm4.subEdge and pm4.subEdge.top, 11, "with the top edge on row 11")
pm4:update(1 / 60)
check(pm4.subEdge == nil, "the edge goes once the list is redrawn")

T.finish()
