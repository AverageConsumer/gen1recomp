-- engine/menus/main_menu.asm:357
package.path = "./?.lua;./?/init.lua;" .. package.path

local love = _G.love or require("tests.love_stub")
_G.love = love

local S = require("tests.harness").suite("continue info layout")
local check, eq = S.check, S.eq

local Font = require("src.render.Font")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local TitleState = require("src.ui.TitleState")

local savedGetInfo = love.filesystem.getInfo
local savedLoad = SaveData.load
local savedDraw, savedBox = Font.draw, Font.drawBox

local owned = {}
for i = 1, 151 do owned[i] = true end
local inventory = {}
for _, id in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE",
    "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE",
    "EARTHBADGE" }) do
  inventory[id] = 1
end
local fakeSave = {
  player = { name = "RED" },
  inventory = inventory,
  pokedex = { owned = owned },
  playTime = 47 * 3600 + 27 * 60,
}

love.filesystem.getInfo = function() return { type = "file" } end
SaveData.load = function() return fakeSave end

local stack = setmetatable({}, { __index = StateStack })
stack:init()
local game = { data = {}, stack = stack }
local title = TitleState.new(game, {})
title.game = game
title:openMenu()
local menu = game.stack:top()
check(menu and menu.items and menu.items[1], "main menu opened with items")
menu.items[1].onSelect()
local info = game.stack:top()
check(info and info ~= menu and info.draw, "CONTINUE pushed the info window")

local drawn = {}
Font.draw = function(text, x, y) drawn[#drawn + 1] = { text, x, y } end
Font.drawBox = function() end
local ok, err = pcall(function() info:draw() end)
Font.draw, Font.drawBox = savedDraw, savedBox
love.filesystem.getInfo = savedGetInfo
SaveData.load = savedLoad
check(ok, "ContinueInfo:draw runs: " .. tostring(err))

local function at(text)
  for _, d in ipairs(drawn) do
    if d[1] == text then return d[2], d[3] end
  end
end

local bx, by = at(" 8")
eq(bx, 17 * 8, "badge count starts at hlcoord 17 (main_menu.asm:370)")
eq(by, 11 * 8, "badge count on row 11")
local dx, dy = at("151")
eq(dx, 16 * 8, "dex count starts at hlcoord 16 (main_menu.asm:372)")
eq(dy, 13 * 8, "dex count on row 13")
local tx, ty = at(" 47<COLON>27")
eq(tx, 13 * 8, "play time starts at hlcoord 13 (main_menu.asm:374)")
eq(ty, 15 * 8, "play time on row 15")
eq(bx + 2 * 8, tx + 6 * 8, "badge count ends flush with the play time")
eq(dx + 3 * 8, tx + 6 * 8, "dex count ends flush with the play time")

S.finish()
