-- Party-submenu field-move placement (#792, the duplicate of #768's second
-- half).  In the original, DisplayFieldMoveMonMenu (engine/menus/
-- text_box.asm) grows the box upward one row per field move and prints the
-- move names ABOVE PokemonMenuEntries ("STATS/SWITCH/CANCEL"), while
-- GetMonFieldMoves (engine/menus/text_box.asm, called from
-- start_sub_menus.asm) walks wPartyMon1Moves in slot order -- so a mon
-- with STRENGTH in slot 3 and SURF in slot 4 shows STRENGTH then SURF on
-- top, with STATS/SWITCH closing the list.  The port used to build the
-- submenu as STATS/SWITCH first and tack the field moves on the bottom.
-- ROM-free: drives the real PartyMenu over stub game state.
--   luajit tests/engine/party_fieldmove_order_bug792.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq, same = T.check, T.eq, T.same
love = love or require("tests.love_stub")

local PartyMenu = require("src.ui.PartyMenu")

-- minimal stack/input doubles matching the StateStack and Input surfaces,
-- plus an overworld stub: PALLET_TOWN's OVERWORLD tileset passes
-- CheckIfInOutsideMap, and the badges cover the list-time HM gates
local function newGame(moves, inventory)
  local game = {
    data = { pokemon = { LAPRAS = { name = "LAPRAS" },
                         PIKACHU = { name = "PIKACHU" } } },
    save = {
      party = { { species = "LAPRAS", hp = 50, stats = { hp = 50 },
                  level = 30, moves = moves } },
      inventory = inventory or {},
      options = {}, flags = {},
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

-- one fixed step with A on its edge: opens the per-mon submenu
local function openSubmenu(pm)
  pm.game.input.queue = { a = true }
  pm:update(1 / 60)
  pm.game.input.queue = {}
end

local function actions(items)
  local out = {}
  for i, item in ipairs(items or {}) do out[i] = item.action end
  return out
end

-- The report's own example: Lapras with STRENGTH in slot 3 and SURF in
-- slot 4.  HM-number order would put SURF (HM03) ahead of STRENGTH (HM04);
-- only the mon's move-list order puts STRENGTH first, and both sit above
-- STATS/SWITCH.
local game = newGame(
  { { id = "WATER_GUN", pp = 25 }, { id = "BODY_SLAM", pp = 15 },
    { id = "STRENGTH", pp = 15 }, { id = "SURF", pp = 15 } },
  { RAINBOWBADGE = true, SOULBADGE = true })
local pm = PartyMenu.new(game, {})
game.stack:push(pm)
openSubmenu(pm)
check(pm.submenu, "A on a party mon opens the submenu")
same(actions(pm.subItems), { "strength", "surf", "stats", "switch" },
     "field moves sit above STATS/SWITCH in move-list order (#792)")
eq(pm.subItems[1].label, "STRENGTH", "slot 3's STRENGTH leads the submenu")
eq(pm.subItems[2].label, "SURF", "slot 4's SURF follows it")

-- a mon whose moves are not field moves gets the plain STATS/SWITCH list
local plain = newGame({ { id = "TACKLE", pp = 35 } })
local pm2 = PartyMenu.new(plain, {})
plain.stack:push(pm2)
openSubmenu(pm2)
same(actions(pm2.subItems), { "stats", "switch" },
     "no field moves: the submenu is just STATS/SWITCH")

-- the badge gates still filter the list: the same Lapras without the
-- badges keeps its moves but shows none of them
local noBadges = newGame(
  { { id = "STRENGTH", pp = 15 }, { id = "SURF", pp = 15 } })
local pm3 = PartyMenu.new(noBadges, {})
noBadges.stack:push(pm3)
openSubmenu(pm3)
same(actions(pm3.subItems), { "stats", "switch" },
     "ungated badges keep the HM moves out of the submenu")

T.finish("party_fieldmove_order_bug792")
