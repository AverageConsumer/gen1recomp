-- pokeyellow data/pokemon/dex_text.asm:1088

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local calls = {}
package.loaded["src.render.Font"] = {
  draw = function(text, x, y) calls[#calls + 1] = { text = text, x = x, y = y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { code = code, x = x, y = y } end,
}
package.loaded["src.render.HudTiles"] = { statusTile = function() end }

local DexEntryMenu = require("src.ui.DexEntryMenu")

local function hasText(text)
  for _, c in ipairs(calls) do
    if c.text == text then return true end
  end
  return false
end
local function anyContains(needle)
  for _, c in ipairs(calls) do
    if type(c.text) == "string" and c.text:find(needle, 1, true) then return true end
  end
  return false
end

local game = {
  data = {
    pokemon = {
      KOFFING = {
        id = "KOFFING", name = "KOFFING", dex = 109,
        dexEntry = { kind = "POISON GAS", heightFt = 2, heightIn = 0,
                     weight = 22, text = "_KoffingDexEntry" },
      },
    },
    text = {
      _KoffingDexEntry = "In hot places, its\ninternal gases\ncould expand and\f"
        .. "explode without\nany warning. Be\nvery careful!{DONE}",
    },
    constants = { dexDigits = 3 },
  },
  save = { pokedex = { owned = { KOFFING = true } } },
}

local ns = DexEntryMenu.new(game, "KOFFING")
ns.picDelay = 0
ns.page = 2
ns:draw()
check(hasText("very careful!"), "last line is \"very careful!\"")
check(not anyContains("{DONE}"), "no {DONE} token reaches the page")
check(not hasText("very careful!."), "no <DEXEND> full stop on a @@ entry")

T.finish("dex entry without dexend 2923")
