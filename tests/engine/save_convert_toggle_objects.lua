-- Gen1 save codec (src/save_convert/GenSave.lua) for wToggleableObjectFlags
-- (ram/wram.asm, flag_array $100): the ShowObject/HideObject persistence the
-- codec used to skip entirely, so an import resurrected both Mt Moon fossils
-- (#857) and reverted Cerulean's GUARD1/GUARD2/ROCKET swap so the officer
-- blocked the robbed-house door again (#763).  Bit numbering comes from
-- ../pokered/data/maps/toggleable_objects.asm entry order (bit set = hidden,
-- engine/overworld/toggleable_objects.asm IsObjectHidden), and the offset is
-- re-derived here from the wram walk rather than read out of GenSave.OFFSETS.
-- Also covers the Yellow-only wPikachuHappiness byte (#763, #838): the
-- 0x271C offset is pinned from the pokeyellow symbol file, not a local
-- pokeyellow checkout, so it still wants a confirmation against a real
-- emulator-written Yellow .sav.
--   luajit tests/engine/save_convert_toggle_objects.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local bit = require("bit")
local GenSave = require("src.save_convert.GenSave")
local SaveData = require("src.core.SaveData")

-- the codec crosswalks need the real dataset; CI has no ROM
local loadPokemon = loadfile("data/generated/pokemon.lua")
if not loadPokemon then
  print("save_convert_toggle_objects skipped (needs data/generated/ for the Gen1 save codec)")
  os.exit(0)
end

GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())
local toggles = loadfile("src/save_convert/data/toggle_objects.lua")()
local data = {
  pokemon = loadPokemon(),
  moves = loadfile("data/generated/moves.lua")(),
  items = loadfile("data/generated/items.lua")(),
  maps = loadfile("data/generated/maps.lua")(),
  eventFlags = loadfile("src/save_convert/data/event_flags.lua")(),
  toggleObjects = toggles,
}

-- ------------------------------------------------------------------
-- offset pins, independent of the codec's own arithmetic: wram.asm places
-- wToggleableObjectFlags 2 bytes (wPlayerCoins) past wPlayerCoins' label,
-- i.e. sav absolute 0x2852; the pokeyellow symbol file places
-- wPikachuHappiness at d46f - wMainDataStart d2f6 = 377, absolute 0x271C
-- ------------------------------------------------------------------

local OFF = GenSave.OFFSETS
eq(OFF.toggleObjectFlags, OFF.coins + 2,
   "wToggleableObjectFlags sits 2 bytes (wPlayerCoins) past O.coins")
eq(OFF.toggleObjectFlags, 0x2852, "wToggleableObjectFlags is sav byte 0x2852")
eq(OFF.pikachuHappiness, 0x271C, "wPikachuHappiness is sav byte 0x271C")

-- independent flag_array read (byte = index / 8, bit = index % 8), so nothing
-- below trusts the writer it is checking
local function flagGet(bytes, base, index)
  local byte = bytes:byte(base + math.floor(index / 8) + 1)
  return bit.band(bit.rshift(byte, index % 8), 1) == 1
end

-- ------------------------------------------------------------------
-- crosswalk <-> maps.lua contract: every named toggle entry must resolve
-- to a real object_event, or encode's itemsTaken/defeatedTrainers fold
-- (which looks the object up by name) silently misses it
-- ------------------------------------------------------------------

local entries = 0
for _, e in pairs(toggles.byBit) do
  entries = entries + 1
  local found
  for _, obj in ipairs((data.maps[e[1]] or {}).objects or {}) do
    if obj.name == e[2] then found = obj break end
  end
  check(found ~= nil, e[1] .. " has an object_event named " .. e[2])
end
-- toggleable_objects.asm has 228 rows; two are placeholders with no
-- object_event in this port (SILPHCO7F_UNUSED, the UNUSED_MAP_F4 entry)
eq(entries, 226, "the crosswalk carries every real toggle bit and no more")

-- the bits under test, straight from the crosswalk's own numbering
eq(toggles.byBit[109][2], "MTMOONB2F_DOME_FOSSIL", "bit 109 is the dome fossil")
eq(toggles.byBit[110][2], "MTMOONB2F_HELIX_FOSSIL", "bit 110 is the helix fossil")
eq(toggles.byBit[7][2], "CERULEANCITY_GUARD1", "bit 7 is the door guard")
eq(toggles.byBit[9][2], "CERULEANCITY_GUARD2", "bit 9 is the roof guard")
eq(toggles.byBit[104][2], "MTMOON1F_MOON_STONE", "bit 104 is the moon stone")

-- ------------------------------------------------------------------
-- round trip: templateless export of a save past the fossil pickup
-- (data/scripts/story2.lua hides both balls) and the Cerulean robbery
-- resolution (data/scripts/story5.lua rocketRows shows GUARD1, hides
-- GUARD2/ROCKET), plus a taken overworld item, which vanilla folds into
-- these same bits (engine/events/pick_up_item.asm)
-- ------------------------------------------------------------------

local function seedSave()
  local save = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
  save.party = { {
    species = "SQUIRTLE", level = 6, exp = 200,
    dvs = { hp = 1, attack = 2, defense = 3, speed = 4, special = 5 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 22, attack = 12, defense = 13, speed = 11, special = 12 },
    hp = 22,
    moves = { { id = "TACKLE", pp = 35, ppUps = 0 } },
    nickname = "SQ", ot = "RED", otId = save.player.id, catchRate = 45,
  } }
  return save
end

local set = seedSave()
set.objectToggles = {
  MT_MOON_B2F = {
    MTMOONB2F_DOME_FOSSIL = false,
    MTMOONB2F_HELIX_FOSSIL = false,
  },
  CERULEAN_CITY = {
    CERULEANCITY_GUARD1 = true,
    CERULEANCITY_GUARD2 = false,
  },
}
-- the moon stone rides itemsTaken (src/world/OverworldController.lua
-- force-hides picked items), never objectToggles, so encode must fold it in
set.itemsTaken = { MT_MOON_1F_obj_9 = true }

local setBytes = GenSave.encode(set, data, nil)
eq(#setBytes, GenSave.SAVE_SIZE, "the export is a 32768-byte save")

local TOG = OFF.toggleObjectFlags
check(flagGet(setBytes, TOG, 109), "the taken dome fossil is hidden (bit 109)")
check(flagGet(setBytes, TOG, 110), "the taken helix fossil is hidden (bit 110)")
check(flagGet(setBytes, TOG, 9), "the swapped-out roof guard is hidden (bit 9)")
check(not flagGet(setBytes, TOG, 7),
      "the officer now beside the door stays visible (bit 7 clear)")
check(flagGet(setBytes, TOG, 104),
      "the taken moon stone folds from itemsTaken into bit 104")

-- untouched entries fall back to their compiled-in defaults, not to zero
check(flagGet(setBytes, TOG, 0), "PALLETTOWN_OAK defaults hidden (bit 0 set)")
check(not flagGet(setBytes, TOG, 1),
      "VIRIDIANCITY_OLD_MAN_SLEEPY defaults visible (bit 1 clear)")

local back = GenSave.decode(setBytes, data)
eq(#(back.warnings or {}), 0, "the export decodes with no warnings")
local reTog = back.objectToggles
check(type(reTog) == "table", "an import populates save.objectToggles")
eq(reTog.MT_MOON_B2F.MTMOONB2F_DOME_FOSSIL, false,
   "the dome fossil stays taken across export -> import")
eq(reTog.MT_MOON_B2F.MTMOONB2F_HELIX_FOSSIL, false,
   "the helix fossil stays taken across export -> import")
eq(reTog.CERULEAN_CITY.CERULEANCITY_GUARD1, true,
   "the officer stays beside the door across export -> import")
eq(reTog.CERULEAN_CITY.CERULEANCITY_GUARD2, false,
   "the roof guard stays gone across export -> import")
eq(reTog.PALLET_TOWN.PALLETTOWN_OAK, false,
   "Oak's roaming sprite imports at its hidden default")
eq(reTog.VIRIDIAN_CITY.VIRIDIANCITY_OLD_MAN_SLEEPY, true,
   "the sleepy old man imports at his visible default")
eq(reTog.MT_MOON_1F.MTMOON1F_MOON_STONE, false,
   "the folded moon stone imports hidden too")

-- ------------------------------------------------------------------
-- Yellow starter friendship: gated on the data set's game because the
-- byte is current-map scratch in Red/Blue (see O.pikachuHappiness)
-- ------------------------------------------------------------------

check(not flagGet(setBytes, OFF.pikachuHappiness, 0)
      and setBytes:byte(OFF.pikachuHappiness + 1) == 0,
      "a Red/Blue export leaves the scratch byte at 0x271C zeroed")
eq(back.pikachuHappiness, nil, "a Red/Blue import never invents a happiness")

local dataYellow = {
  pokemon = data.pokemon, moves = data.moves, items = data.items,
  maps = data.maps, toggleObjects = toggles,
  eventFlags = loadfile("src/save_convert/data/event_flags_yellow.lua")(),
  gameVersion = "yellow",
}
local ySave = seedSave()
ySave.pikachuHappiness = 200
local yBytes = GenSave.encode(ySave, dataYellow, nil)
eq(yBytes:byte(OFF.pikachuHappiness + 1), 200,
   "pikachuHappiness = 200 reaches sav byte 0x271C")
local yBack = GenSave.decode(yBytes, dataYellow)
eq(yBack.pikachuHappiness, 200,
   "the follower's happiness survives export -> import on Yellow")

T.finish("save_convert_toggle_objects")
