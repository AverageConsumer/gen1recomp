-- Commands.pushBattle (src/script/Commands.lua): the shared entry point
-- for start_battle, old_man_demo, and the PALLET_TOWN Pikachu catch
-- (data/scripts/story2.lua). Every one of those call sites used to carry
-- its own copy of "if ctx.overworld.pushBattle then ... else
-- ctx.game.stack:push(battle) end"; this locks the dedup in so a future
-- edit to one call site can't silently drop the transition wipe for the
-- others.
--   luajit tests/engine/push_battle_transition.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")

local battle = { id = "the battle" }

-- Runs fn() with Logger.warn spied instead of hitting the real
-- print()/Logger.history ring buffer, and returns the last formatted
-- warning (or nil if none). pcall-wrapped so an error inside fn() still
-- restores Logger.warn before propagating -- a leaked spy would swallow
-- every later warning in the same process silently.
local function withWarnSpy(fn)
  local warned
  local origWarn = Logger.warn
  Logger.warn = function(fmt, ...) warned = string.format(fmt, ...) end
  local ok, err = pcall(fn)
  Logger.warn = origWarn
  if not ok then error(err, 0) end
  return warned
end

-- ctx.overworld has a real pushBattle: it must be used, not a bare stack
-- push, so the flash/wipe transition and the battle-theme start survive.
do
  local pushed
  local ow = { pushBattle = function(self, b) pushed = b end }
  local stackPushed
  local ctx = { overworld = ow, game = { stack = {
    push = function(_, b) stackPushed = b end } } }
  Commands.pushBattle(ctx, battle)
  eq(pushed, battle, "ctx.overworld:pushBattle is called with the battle")
  check(stackPushed == nil, "the bare stack push is not also taken")
end

-- ctx.overworld without a pushBattle method (a partial test double, per
-- BattleState:finish's "no live children" contract) falls back to a
-- bare stack push and logs, rather than silently skipping the transition.
do
  local stackPushed
  local ctx = { overworld = {}, game = { stack = {
    push = function(_, b) stackPushed = b end } } }
  local warned = withWarnSpy(function() Commands.pushBattle(ctx, battle) end)
  eq(stackPushed, battle, "falls back to ctx.game.stack:push")
  check(warned ~= nil, "the fallback logs a warning")
  check(warned and warned:find("pushBattle") ~= nil,
        "the warning names pushBattle")
end

-- ctx.overworld absent entirely (headless script tests that never set
-- one up): same fallback, no crash on the ctx.overworld.pushBattle read
-- -- and still spied, since this also takes the warning path.
do
  local stackPushed
  local ctx = { game = { stack = {
    push = function(_, b) stackPushed = b end } } }
  local warned = withWarnSpy(function() Commands.pushBattle(ctx, battle) end)
  eq(stackPushed, battle, "falls back to ctx.game.stack:push with no overworld")
  check(warned ~= nil, "this fallback also logs a warning")
end

T.finish("push_battle_transition")
