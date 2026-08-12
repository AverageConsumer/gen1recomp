-- Public read-only Pokemon icon presentation delegates to the same resolver
-- PartyMenu uses, so content registrations and pokemon.icon hooks compose.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local PartyMenu = require("src.ui.PartyMenu")

local FIXTURE = {
  ["mods/icon_probe/manifest.json"] = [[{
    "id": "icon_probe",
    "name": "Icon Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/icon_probe/main.lua"] = [[
    local mod = ...
    mod.exports.icon = mod.ui.PokemonIcon
  ]],
}

local run = T.sdk.loadMods({ "mods/icon_probe" }, { fs = T.sdk.memfs(FIXTURE) })
T.eq(#run.errors, 0, "fixture mod loads cleanly")
local icon = run.loader.exports.icon_probe.icon
T.eq(type(icon), "table", "mod.ui exposes the PokemonIcon helper")
T.eq(type(icon.draw), "function", "PokemonIcon exposes a draw operation")

local original = PartyMenu.drawIcon
local call
PartyMenu.drawIcon = function(game, mon, x, y, selected, counter)
  call = { game = game, mon = mon, x = x, y = y,
    selected = selected, counter = counter }
end

local game = { data = {} }
local drawn, code = icon.draw(game, {
  species = "PIKACHU", hp = 4, maxHp = 10,
}, 8, 16, { selected = true, counter = 7 })
T.eq(drawn, true, "valid detached Pokemon summary is drawable")
T.eq(code, nil, "valid summary has no rejection code")
T.check(call and call.game == game, "helper delegates with the live game")
T.eq(call.mon.species, "PIKACHU", "species reaches the shared party resolver")
T.eq(call.mon.hp, 4, "captured current HP reaches icon animation semantics")
T.eq(call.mon.stats.hp, 10, "captured maximum HP reaches icon animation semantics")
T.eq(call.selected, true, "selection state is presentation-only")
T.eq(call.counter, 7, "animation counter is presentation-only")

call = nil
local bad, badCode = icon.draw(game, {
  species = "PIKACHU", hp = 11, maxHp = 10,
}, 0, 0)
T.eq(bad, false, "invalid detached summary fails closed")
T.eq(badCode, "invalid_pokemon_preview", "invalid summary has a stable error")
T.eq(call, nil, "invalid summary never reaches renderer internals")

PartyMenu.drawIcon = original
run.release()

T.finish("pokemon_icon")
