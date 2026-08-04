-- BATTLE SIZE (save.options.battleFit): "fixed" keeps the classic
-- integer-scaled letterbox, "fill" scales the battle surface to the window so
-- it fills vertically.
--
-- The bit that regresses is not the arithmetic, it is WHERE the flag is read
-- from: a battle opens party menus, the bag and text boxes on top of itself,
-- so reading it off the TOP state would snap the surface back to the fixed
-- scale for as long as one of those is up.  It is read off the whole stack,
-- the same way the wide-battle layout is.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Game = require("src.core.Game")
local BattleState = require("src.battle.BattleState")

local function battleWith(fit)
  return setmetatable({ game = { save = { options = { battleFit = fit } } } },
                      { __index = BattleState })
end

T.eq(battleWith("fill"):wantsFillScale(), true, "fill asks for the fill scale")
T.eq(battleWith("fixed"):wantsFillScale(), false, "fixed does not")
T.eq(battleWith(nil):wantsFillScale(), false, "and neither does an old save")

-- a battle with no game/options at all must not throw
T.eq(setmetatable({}, { __index = BattleState }):wantsFillScale(), false,
  "a battle with no options is fixed")

-- the stack scan
local function stack(...) return { states = { ... } } end
local overworld = {}
local fillBattle = battleWith("fill")
local fixedBattle = battleWith("fixed")
local partyMenu = {} -- no wantsFillScale at all, like every non-battle state

T.eq(Game.fillScaleInStack(stack(overworld)), false,
  "no battle in the stack means no fill")
T.eq(Game.fillScaleInStack(stack(overworld, fixedBattle)), false,
  "a fixed battle does not fill")
T.eq(Game.fillScaleInStack(stack(overworld, fillBattle)), true,
  "a fill battle does")
T.eq(Game.fillScaleInStack(stack(overworld, fillBattle, partyMenu)), true,
  "and keeps filling while a party menu sits on top of it")
T.eq(Game.fillScaleInStack(stack()), false, "an empty stack is safe")
T.eq(Game.fillScaleInStack(nil), false, "and so is no stack at all")

-- ---------------------------------------------------------------- BATTLE BG

-- What fills the voids AROUND the battle.  The battle screen itself keeps its
-- white field in every mode -- only the surround changes.
local function battleBg(bg)
  return setmetatable({ game = { save = { options = { battleBg = bg } } } },
                      { __index = BattleState })
end

T.eq(battleBg("white"):bgMode(), "white", "white is white")
T.eq(battleBg("black"):bgMode(), "black", "black is black")
T.eq(battleBg("world"):bgMode(), "world", "world is world")
T.eq(battleBg(nil):bgMode(), "white", "an old save defaults to white")
T.eq(battleBg("nonsense"):bgMode(), "white", "and so does a bad value")
T.eq(setmetatable({}, { __index = BattleState }):bgMode(), "white",
  "a battle with no options is white")

-- "world" is the only mode that drops opacity, because it is the only one
-- that needs the overworld to keep drawing underneath.
T.eq(Game.worldBgBattleDim(stack(overworld, battleBg("world"))),
     BattleState.BG_WORLD_DIM, "a world-bg battle asks for its dim")
T.eq(Game.worldBgBattleDim(stack(overworld, battleBg("white"))), nil,
  "a white-bg battle asks for none")
T.eq(Game.worldBgBattleDim(stack(overworld, battleBg("black"))), nil,
  "and neither does black")
T.eq(Game.worldBgBattleDim(stack(overworld, battleBg("world"), partyMenu)),
     BattleState.BG_WORLD_DIM,
  "the dim survives a party menu opened over the battle")
T.eq(Game.worldBgBattleDim(stack(overworld)), nil, "no battle, no dim")
T.eq(Game.worldBgBattleDim(nil), nil, "and no stack is safe")

-- #773: the same walk decides whether the dark-cave shade shift may be armed
-- for this frame.  A battle zeroes wMapPalOffset (init_battle_variables.asm),
-- so a world-bg battle over an un-flashed Rock Tunnel must suppress it.
T.check(Game.worldBgBattleInStack(stack(overworld, battleBg("world"))),
  "a world-bg battle claims the frame, so the dark shift stays off it")
T.check(not Game.worldBgBattleInStack(stack(overworld, battleBg("white"))),
  "a white-bg battle draws with no map under it and claims nothing")
T.check(Game.worldBgBattleInStack(stack(overworld, battleBg("world"), partyMenu)),
  "a menu opened over the world-bg battle does not hand the shift back")
T.check(not Game.worldBgBattleInStack(stack(overworld)),
  "a plain dark map still arms it")
T.check(not Game.worldBgBattleInStack(nil), "and no stack is safe")

T.check(BattleState.BG_WORLD_DIM > 0 and BattleState.BG_WORLD_DIM < 1,
  "the dim is a fraction, not a full blackout")

T.finish("battle fit option")
