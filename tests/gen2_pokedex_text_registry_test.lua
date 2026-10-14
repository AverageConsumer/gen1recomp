-- The #DEX screen (src/ui/gen2/PokedexMenu.lua) reads its KIND label and
-- description pages from data.gen2Pokedex.entries, a table loaded straight
-- from disk before mods:load runs -- a separate table from data.pokemon,
-- the `pokemon` registry's own merge target
-- (mod.content.pokemon:patch(id, { dexEntry = ... })). Without a projection
-- step, a translation mod's #DEX text validates against the registry and
-- never reaches the screen. src/core/gen2/PokedexText.lua is that
-- projection, called once after the merge (src/core/Game2.lua). ROM-free:
--   luajit tests/gen2_pokedex_text_registry_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 pokedex text registry")
local check, eq = S.check, S.eq

local PokedexText = require("src.core.gen2.PokedexText")

-- A patched species (CYNDAQUIL, kind/text/text2 all overridden), one left
-- alone (TOTODILE, no dexEntry at all in data.pokemon -- a mod that never
-- touched it), and one gen2Pokedex has no matching data.pokemon row for
-- (UNOWN, e.g. a form gen2Pokedex tracks that the pokemon registry does not).
do
  local data = {
    pokemon = {
      CYNDAQUIL = { name = "CYNDAQUIL", dexEntry = {
        kind = "SOURIS DE FEU", text = "Page un traduite.",
        text2 = "Page deux traduite.",
      } },
      TOTODILE = { name = "TOTODILE" },
    },
    gen2Pokedex = { entries = {
      CYNDAQUIL = { id = "CYNDAQUIL", dex = 155, kind = "FIRE MOUSE",
        height = 108, weight = 170,
        text = "It is timid, and always curls itself up in a ball.",
        text2 = "If attacked, it flares up its back for protection." },
      TOTODILE = { id = "TOTODILE", dex = 158, kind = "BIG JAW",
        height = 200, weight = 200, text = "English page one.",
        text2 = "English page two." },
      UNOWN = { id = "UNOWN", dex = 201, kind = "SYMBOL",
        height = 50, weight = 50, text = "English only." },
    } },
  }

  local touched = PokedexText.apply(data)
  eq(touched, 1, "only the species a mod actually patched are touched")

  local cyndaquil = data.gen2Pokedex.entries.CYNDAQUIL
  eq(cyndaquil.kind, "SOURIS DE FEU", "kind reaches the #DEX entry")
  eq(cyndaquil.text, "Page un traduite.", "page one reaches the #DEX entry")
  eq(cyndaquil.text2, "Page deux traduite.", "page two reaches the #DEX entry")
  eq(cyndaquil.dex, 155, "dex number is untouched -- it is not translatable text")
  eq(cyndaquil.height, 108, "height is untouched -- game state, not prose")
  eq(cyndaquil.weight, 170, "weight is untouched -- game state, not prose")

  local totodile = data.gen2Pokedex.entries.TOTODILE
  eq(totodile.kind, "BIG JAW", "a species with no dexEntry patch stays in English")
  eq(totodile.text, "English page one.", "unpatched page one is untouched")

  local unown = data.gen2Pokedex.entries.UNOWN
  eq(unown.kind, "SYMBOL",
    "a #DEX entry with no data.pokemon counterpart at all is left alone")
end

-- A patch that only sets `kind` (species_kinds without species_dex_text
-- shipped, or vice versa) must not blank out the fields it did not touch.
do
  local data = {
    pokemon = { ABRA = { name = "ABRA", dexEntry = { kind = "PSY" } } },
    gen2Pokedex = { entries = {
      ABRA = { id = "ABRA", dex = 63, kind = "PSI",
        text = "English text.", text2 = "English text two." },
    } },
  }
  PokedexText.apply(data)
  local abra = data.gen2Pokedex.entries.ABRA
  eq(abra.kind, "PSY", "kind alone is applied")
  eq(abra.text, "English text.", "text is left alone when the patch omits it")
  eq(abra.text2, "English text two.", "text2 is left alone when the patch omits it")
end

do
  local data = {
    pokemon = {
      CHIKORITA = { name = "CHIKORITA", dexEntry = { height = 305, weight = 1234 } },
      BAYLEEF = { name = "BAYLEEF", dexEntry = { heightM = 1.2, weightKg = 15.8 } },
    },
    gen2Pokedex = { entries = {
      CHIKORITA = { id = "CHIKORITA", dex = 152, kind = "LEAF", height = 270, weight = 142 },
      BAYLEEF = { id = "BAYLEEF", dex = 153, kind = "LEAF", height = 311, weight = 349 },
    } },
  }
  eq(PokedexText.apply(data), 2, "native and metric size patches both count")
  local c = data.gen2Pokedex.entries.CHIKORITA
  eq(c.height, 305, "native height is applied")
  eq(c.weight, 1234, "native weight is applied")
  eq(c.kind, "LEAF", "kind untouched by a size-only patch")
  local b = data.gen2Pokedex.entries.BAYLEEF
  eq(b.height, 311, "1.2 m converts to 3'11\"")
  eq(b.weight, 348, "15.8 kg converts to tenths of a pound")
  eq(b.heightM, 1.2, "metric height is kept for the metric screen")
end

-- Missing tables at every level answer 0 rather than raising -- a Gen 1 boot,
-- or a Gold boot with no mods loaded, never calls this with a shaped table.
do
  eq(PokedexText.apply(nil), 0, "nil data does not raise")
  eq(PokedexText.apply({}), 0, "empty data does not raise")
  eq(PokedexText.apply({ gen2Pokedex = { entries = {} } }), 0,
    "no data.pokemon at all does not raise")
end

check(true, "PokedexText.apply covers the projection this fix adds")

S.finish()
