package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local boxes = {}
for i = 1, 12 do boxes[i] = {} end
boxes[1][1] = { species = "TEST", level = 5 }

local pushed
local game = {
  data = {
    pokemon = { TEST = { name = "TEST" } },
    items = { POTION = { name = "POTION" } },
    field = { pcItemCap = 50 }, text = {},
  },
  save = {
    boxes = boxes, currentBox = 1,
    party = { { species = "TEST", level = 5 },
              { species = "TEST", level = 6 } },
    pcItems = { POTION = 2 }, inventory = { POTION = 2 },
  },
  stack = { push = function(_, state) pushed = state end },
}

local box = require("src.ui.BoxMenu").new(game)
for i, kind in ipairs({ "pc_box_withdraw", "pc_box_deposit",
                         "pc_box_release", "pc_box_change" }) do
  pushed = nil
  box.items[i].onSelect()
  assert(pushed and pushed.kind == kind, kind)
end

local items = require("src.ui.PlayerPC").new(game)
for i, kind in ipairs({ "pc_item_withdraw", "pc_item_deposit",
                         "pc_item_toss" }) do
  pushed = nil
  items.items[i].onSelect()
  assert(pushed and pushed.kind == kind, kind)
end

print("PC companion kinds: ok")
