-- Parity: a player send-out zeroes both battle cursors (#737).  SendOutMon
-- (engine/battle/core.asm:1733-1735) clears wBattleAndStartSavedMenuItem and,
-- with the same hli/hl pair, wPlayerMoveListIndex behind it (wram.asm:242-244),
-- so the menu reopens on FIGHT and the move list on the first slot.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local S = require("tests.harness").suite("parity switch cursor reset")
local eq = S.eq

local pressed = {}
local save = SaveData.newGame()
save.party = {
  Pokemon.new(Data, "BULBASAUR", 10),
  Pokemon.new(Data, "PIDGEY", 10),
}
local game = {
  data = Data,
  save = save,
  input = {
    wasPressed = function(_, key) return pressed[key] == true end,
    isDown = function(_, key) return pressed[key] == true end,
  },
  stack = { push = function() end, pop = function() end, top = function() end },
}
local battle = BattleState.newWild(game, "RATTATA", 3)
battle.phase = "menu"
battle.menuIndex = 4
battle.moveIndex = 3

battle:resolveSwitch(save.party[2])
for i = 1, 4000 do
  if battle.phase == "menu" then break end
  pressed.a = (i % 4 == 0)
  battle:update(1 / 60)
  pressed.a = nil
end

eq(battle.moveIndex, 1, "the move cursor is back on the first slot")
eq(battle.menuIndex, 1, "the battle menu is back on FIGHT")

S.finish()
