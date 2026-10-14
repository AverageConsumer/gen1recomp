-- engine/battle/animations.asm:452-473 (#1881)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local AnimPlayer = require("src.battle.AnimPlayer")

local function row(marker)
  return { seq = { { effect = "SE_DARK_SCREEN_FLASH", sound = marker } } }
end

local data = { moveAnims = {
  AMNESIA   = row("player_amnesia"),
  REST      = row("player_rest"),
  CONF_ANIM = row("enemy_conf"),
  SLP_ANIM  = row("enemy_slp"),
}, idEffects = {} }

local function firstSound(moveId, attackerIsPlayer)
  local p = AnimPlayer.new(data)
  p:start(moveId, attackerIsPlayer)
  for _, ev in ipairs(p.events) do
    if ev.sound then return ev.sound end
  end
end

T.eq(firstSound("AMNESIA", false), "enemy_conf",
  "the foe's Amnesia plays CONF_ANIM, not a coord-flipped AmnesiaAnim")
T.eq(firstSound("REST", false), "enemy_slp",
  "the foe's Rest plays SLP_ANIM")
T.eq(firstSound("AMNESIA", true), "player_amnesia",
  "the player's Amnesia keeps its own row")
T.eq(firstSound("REST", true), "player_rest",
  "the player's Rest keeps its own row")
T.eq(firstSound("CONF_ANIM", false), "enemy_conf",
  "the status-check ids are untouched")
