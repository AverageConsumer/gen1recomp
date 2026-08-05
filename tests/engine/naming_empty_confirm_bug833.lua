-- Empty confirm on the naming screen (#833).  DisplayNamingScreen seeds
-- wStringBuffer with '@' (engine/menus/naming_screen.asm), so a name the
-- player never typed reads back as the terminator, and every caller checks
-- that first byte: AskName falls through to .declinedNickname and copies the
-- species name over the nick slot (vanilla's "un-nicknamed", which this port
-- models as mon.nickname == nil, src/save_convert/GenSave.lua), while
-- DisplayNameRaterScreen takes .playerCancelled and keeps the old nickname.
-- Nothing in the original invents a letter, so NamingScreen:confirm must hand
-- the caller "" rather than the literal "A" when nothing was typed -- both via
-- START and via the ED cell.  The two fallbacks that are load bearing stay:
-- presets[1] for player/rival naming (oak_speech2.asm ChoosePlayerName never
-- accepts an empty name) and opts.default for the Name Rater cancel.
--   luajit tests/engine/naming_empty_confirm_bug833.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- NamingScreen reaches for Sound at the top of the module; seeding
-- package.loaded before it loads keeps the suite ROM-free and silent.
package.loaded["src.core.Sound"] = { play = function() end }

local NamingScreen = require("src.ui.NamingScreen")

-- The three things the screen touches: a stack it pops itself off, an input
-- queue that is exactly one fixed step of edges, and a non-nil `data` for the
-- click cue.
local function newGame()
  local game = { data = {} }
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

-- builds a pushed screen plus a `result` table the onDone writes into
local function newScreen(opts)
  local game = newGame()
  local result = { fired = false, name = nil }
  opts = opts or {}
  opts.onDone = function(n)
    result.fired = true
    result.name = n
  end
  local ns = NamingScreen.new(game, opts)
  game.stack:push(ns)
  return ns, game, result
end

-- one fixed step with `btn` on its edge
local function press(ns, game, btn)
  game.input.queue = { [btn] = true }
  ns:update(1 / 60)
  game.input.queue = {}
end

-- the ED cell's coordinates on whatever grid the screen is showing
local function edCell(ns)
  for r, row in ipairs(ns:grid()) do
    for c, cell in ipairs(row) do
      if cell == "ED" then return r, c end
    end
  end
  return nil, nil
end

-- ---------------------------------------------------------------- START, nothing typed
-- The nickname callers (BattleState caught-mon, Commands gift/starter) push
-- the screen with only title/maxLen/onDone: no presets, no default.
local ns, game, res = newScreen({ title = "NICK?", maxLen = 10 })
press(ns, game, "start")
check(res.fired, "START confirms an untyped name")
eq(res.name, "", "START with nothing typed delivers the empty name")
check(res.name ~= "A", "an untyped confirm does not invent the letter A (#833)")
eq(#game.stack.states, 0, "confirm pops the naming screen")

-- the caller-shaped guard both nickname sites use
local mon = {}
if res.name and #res.name > 0 then mon.nickname = res.name end
check(mon.nickname == nil,
      "an empty name leaves the mon un-nicknamed, so evolution can rename it")

-- ---------------------------------------------------------------- ED cell, nothing typed
ns, game, res = newScreen({ title = "NICK?", maxLen = 10 })
local edRow, edCol = edCell(ns)
eq(edRow, 5, "ED sits on row 5 of the vanilla grid (data/text/alphabets.asm)")
eq(edCol, 9, "ED is the last cell of that row")
ns.row, ns.col = edRow, edCol
press(ns, game, "a")
check(res.fired, "A on the ED cell confirms")
eq(res.name, "", "ED with nothing typed delivers the empty name too")

-- ---------------------------------------------------------------- typed names are untouched
ns, game, res = newScreen({ title = "NICK?", maxLen = 10 })
ns.row, ns.col = 1, 1 -- "A"
press(ns, game, "a")
press(ns, game, "start")
eq(res.name, "A", "a genuinely typed A still comes back as A")

-- ---------------------------------------------------------------- presets fallback (player / rival)
-- ChoosePlayerName / ChooseRivalName (engine/movie/oak_speech/oak_speech2.asm)
-- compare wStringBuffer to '@' and re-open rather than accept an empty name;
-- the port answers the same need with its presets fallback, which #833 must
-- not disturb.
ns, game, res = newScreen({ title = "YOUR NAME?", maxLen = 7, presets = { "RED", "ASH" } })
press(ns, game, "start")
eq(res.name, "RED", "an empty confirm with presets still yields presets[1]")

-- ---------------------------------------------------------------- default fallback (Name Rater)
-- DisplayNameRaterScreen jumps to .playerCancelled on '@' and keeps the
-- existing nickname; data/scripts/story4.lua passes it as opts.default.
ns, game, res = newScreen({ title = "RATTATA's name?", maxLen = 10, default = "SPLASH" })
press(ns, game, "start")
eq(res.name, "SPLASH", "an empty confirm with a default keeps the old nickname")

T.finish("naming_empty_confirm_bug833")
