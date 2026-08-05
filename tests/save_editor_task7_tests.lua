-- Headless tests for the save editor's Events + Dex behaviour.
-- Run from repo root: luajit tests/save_editor_task7_tests.lua
-- (also chained from tests/run_save_editor_tests.lua so CI covers it)
--
-- Driven through tools/save-editor/Ops.lua rather than by clicking pixel
-- coordinates: the rules worth protecting here are the save-shape ones
-- (flags write true/nil, object toggles write true/false, owning implies
-- seen, un-seeing clears owned, wholesale clears arm before they commit),
-- and those all live in Ops.

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

local love_stub = require("tests.love_stub")
love = love_stub

local passed, failed = 0, 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

print("== save editor task 7 tests (Events + Dex) ==")

local Ops = require("Ops")
local State = require("State")
local Catalog = require("Catalog")

local function newState()
  local S = State.new()
  S.events = { "EVENT_ALPHA", "EVENT_BEAT_BROCK", "EVENT_ZETA" }
  S.cat = { species = { "BULBASAUR", "CHARMANDER", "SQUIRTLE", "PIKACHU" },
            items = {}, moves = {} }
  S.save = {
    flags = {}, defeatedTrainers = {}, itemsTaken = {}, objectToggles = {},
    party = {}, boxes = {},
  }
  return S
end

-- Events --------------------------------------------------------------

do
  local S = newState()

  Ops.setFlag(S, "EVENT_ALPHA", true)
  eq(S.save.flags.EVENT_ALPHA, true, "setFlag on writes true")
  check(S.dirty, "setFlag dirties the save")
  check(S.status:match("EVENT_ALPHA") ~= nil, "setFlag names the flag it changed")

  Ops.setFlag(S, "EVENT_ALPHA", false)
  eq(S.save.flags.EVENT_ALPHA, nil,
     "setFlag off writes nil, not false (a false flag would still serialize)")
end

do
  local S = newState()

  Ops.setKey(S, "defeatedTrainers", "PEWTER_GYM_obj_1", true)
  eq(S.save.defeatedTrainers.PEWTER_GYM_obj_1, true, "setKey marks a trainer beaten")
  Ops.setKey(S, "defeatedTrainers", "PEWTER_GYM_obj_1", false)
  eq(S.save.defeatedTrainers.PEWTER_GYM_obj_1, nil, "setKey off clears the entry")

  Ops.setKey(S, "itemsTaken", "VIRIDIAN_FOREST_obj_3", true)
  eq(S.save.itemsTaken.VIRIDIAN_FOREST_obj_3, true, "setKey works for itemsTaken too")

  -- setKey creates the table when a save predates it
  S.save.newTable = nil
  Ops.setKey(S, "newTable", "k", true)
  eq(S.save.newTable.k, true, "setKey creates a missing table")
end

do
  -- object toggles are an explicit true/false override, NOT presence/absence:
  -- false means "this object is hidden", which is different from "no override"
  local S = newState()
  Ops.setToggle(S, "CELADON_CITY", "gym_guide", true)
  eq(S.save.objectToggles.CELADON_CITY.gym_guide, true, "setToggle on writes true")
  Ops.setToggle(S, "CELADON_CITY", "gym_guide", false)
  eq(S.save.objectToggles.CELADON_CITY.gym_guide, false,
     "setToggle off writes false, not nil")
end

do
  -- clearing a whole key table is destructive: arm, then commit
  local S = newState()
  S.save.defeatedTrainers = { a = true, b = true, c = true }
  S.dirty = false

  check(Ops.clearTable(S, "defeatedTrainers", "trainers") == false,
        "clearTable arms on the first call")
  eq(count(S.save.defeatedTrainers), 3, "an armed clear has not cleared anything")
  check(S.status:match("Clear all 3") ~= nil, "the arming message counts the entries")
  eq(Ops.armLabel(S, "clear-defeatedTrainers", "Clear all trainers"), "Confirm?",
     "an armed clear relabels its button")

  check(Ops.clearTable(S, "defeatedTrainers", "trainers") == true,
        "clearTable commits on the second call")
  eq(count(S.save.defeatedTrainers), 0, "the committed clear empties the table")
  check(S.dirty, "the committed clear dirties the save")

  S.dirty = false
  check(Ops.clearTable(S, "defeatedTrainers", "trainers") == false,
        "clearing an already-empty table is a no-op")
  check(S.dirty == false, "a no-op clear does not dirty the save")
  check(S.status:match("already empty") ~= nil, "a no-op clear explains itself")
end

-- Dex -----------------------------------------------------------------

do
  local S = newState()
  local dex = Ops.dex(S)
  check(type(dex.seen) == "table" and type(dex.owned) == "table",
        "Ops.dex creates the seen/owned tables")

  Ops.dexSeen(S, "BULBASAUR", true)
  eq(dex.seen.BULBASAUR, true, "dexSeen marks seen")
  eq(dex.owned.BULBASAUR, nil, "seeing alone does not own")

  Ops.dexOwned(S, "CHARMANDER", true)
  eq(dex.owned.CHARMANDER, true, "dexOwned marks owned")
  eq(dex.seen.CHARMANDER, true, "owning implies having seen")

  Ops.dexSeen(S, "CHARMANDER", false)
  eq(dex.seen.CHARMANDER, nil, "un-seeing clears seen")
  eq(dex.owned.CHARMANDER, nil, "un-seeing also clears owned (can't own the unseen)")
end

do
  local S = newState()
  local seen, owned, total = Ops.dexCounts(S)
  eq(seen, 0, "a fresh dex has seen nothing")
  eq(owned, 0, "a fresh dex owns nothing")
  eq(total, #S.cat.species, "dexCounts reports the catalog size")

  Ops.dexSeeAll(S)
  seen, owned = Ops.dexCounts(S)
  eq(seen, #S.cat.species, "dexSeeAll marks every species seen")
  eq(owned, 0, "dexSeeAll does not own anything")

  Ops.dexOwnAll(S)
  seen, owned = Ops.dexCounts(S)
  eq(owned, #S.cat.species, "dexOwnAll marks every species owned")
  eq(seen, #S.cat.species, "dexOwnAll leaves everything seen too")
end

do
  -- stamping from the save's own mons, party and boxes both
  local S = newState()
  S.save.party = { { species = "PIKACHU" } }
  S.save.boxes = { { { species = "SQUIRTLE" } } }

  Ops.dexStamp(S)
  local dex = Ops.dex(S)
  eq(dex.owned.PIKACHU, true, "dexStamp owns party mons")
  eq(dex.owned.SQUIRTLE, true, "dexStamp owns box mons")
  eq(dex.seen.PIKACHU, true, "dexStamp marks stamped mons seen")
  check(S.status:match("2 more") ~= nil, "dexStamp reports how many it added")

  S.dirty = false
  check(Ops.dexStamp(S) == false, "a second dexStamp with nothing new is a no-op")
  check(S.dirty == false, "a no-op dexStamp does not dirty the save")
end

do
  -- wiping the dex is destructive: arm, then commit
  local S = newState()
  Ops.dexOwnAll(S)
  S.dirty = false

  check(Ops.dexClear(S) == false, "dexClear arms on the first call")
  local _, owned = Ops.dexCounts(S)
  eq(owned, #S.cat.species, "an armed dexClear has not wiped anything")
  eq(Ops.armLabel(S, "dex-clear", "Wipe dex"), "Confirm?",
     "an armed dexClear relabels its button")

  check(Ops.dexClear(S) == true, "dexClear commits on the second call")
  local seen2, owned2 = Ops.dexCounts(S)
  eq(seen2, 0, "the committed dexClear clears seen")
  eq(owned2, 0, "the committed dexClear clears owned")
  check(S.dirty, "the committed dexClear dirties the save")
end

do
  -- doing anything else disarms a pending confirmation: an unrelated click
  -- must never become the second half of a destructive one
  local S = newState()
  Ops.dexOwnAll(S)
  Ops.dexClear(S)
  eq(S.armed, "dex-clear", "dexClear left the button armed")
  Ops.dexSeen(S, "PIKACHU", true)
  eq(S.armed, nil, "an unrelated mutation disarms the pending confirmation")
  local _, owned = Ops.dexCounts(S)
  check(owned > 0, "the dex was not wiped by the unrelated click")
end

-- Dex sort -----------------------------------------------------------

do
  -- Ops.dexList orders the grid by the active mode.  This block drives the
  -- real generated data (State.new alone carries no Data), so the vanilla
  -- 1-151 numbering is what the "dex" mode asserts against.
  local Data = require("src.core.Data")
  Data:load()
  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = require("src.core.SaveData").newGame()

  -- default mode is "dex": number order
  eq(S.dexSort, "dex", "a fresh state sorts the dex by number by default")
  local byDex = Ops.dexList(S)
  eq(#byDex, #S.cat.species, "dexList covers every species")
  eq(byDex[1], "BULBASAUR", "dex order starts at #1")
  eq(byDex[4], "CHARMANDER", "dex order puts Charmander fourth")
  eq(byDex[25], "PIKACHU", "dex order puts Pikachu at #25")
  eq(byDex[151], "MEW", "dex order ends at #151")

  -- "name" mode: alphabetical by display name
  Ops.dexSort(S, "name")
  eq(S.dexSort, "name", "dexSort switches the mode")
  local byName = Ops.dexList(S)
  eq(#byName, #S.cat.species, "the name sort covers every species too")
  eq(byName[1], "ABRA", "the name sort leads with ABRA")
  local sorted = true
  for i = 2, #byName do
    local a = S.data.pokemon[byName[i - 1]]
    local b = S.data.pokemon[byName[i]]
    local an = (a and a.name or byName[i - 1]):lower()
    local bn = (b and b.name or byName[i]):lower()
    if an > bn then sorted = false break end
  end
  check(sorted, "the name sort is alphabetical over display names")
  local mi = nil
  for i, id in ipairs(byName) do
    if id == "MEW" then mi = i
    elseif id == "MR_MIME" and mi then
      check(i > mi, "MEW sorts before MR.MIME in the name sort")
    end
  end
  local fIdx, mIdx = nil, nil
  for i, id in ipairs(byName) do
    if id == "NIDORAN_F" then fIdx = i elseif id == "NIDORAN_M" then mIdx = i end
  end
  check(fIdx and mIdx and fIdx < mIdx, "NIDORAN_F sorts before NIDORAN_M")

  -- switching back to the number order restores the original sequence
  Ops.dexSort(S, "dex")
  local back = Ops.dexList(S)
  eq(back[1], "BULBASAUR", "switching back restores number order")
end

do
  -- the switch is view-only: it resets the grid scroll but never dirties the
  -- save, and a re-click on the active mode is a narrated no-op
  local S = newState()
  S.data = { pokemon = { BULBASAUR = { dex = 1, name = "BULBASAUR" },
                         CHARMANDER = { dex = 4, name = "CHARMANDER" },
                         PIKACHU = { dex = 25, name = "PIKACHU" },
                         SQUIRTLE = { dex = 7, name = "SQUIRTLE" } } }
  S.cat = { species = { "BULBASAUR", "CHARMANDER", "SQUIRTLE", "PIKACHU" },
            items = {}, moves = {} }
  S.dexOffset = 9
  S.dirty = false

  check(Ops.dexSort(S, "name") == true, "dexSort switches the mode without dirtying")
  eq(S.dirty, false, "a sort never dirties the save")
  eq(S.dexOffset, 0, "changing the sort resets the grid scroll")
  eq(S.status, "", "a sort leaves the status bar alone")

  S.dexOffset = 4
  check(Ops.dexSort(S, "name") == false, "re-clicking the active mode is a no-op")
  eq(S.dexOffset, 4, "a no-op sort leaves the scroll alone")
  eq(S.dirty, false, "a no-op sort does not dirty either")
  eq(S.status, "", "a no-op sort does not narrate either")

  check(Ops.dexSort(S, "bogus") == false, "an unknown mode is refused")
  eq(S.dexSort, "name", "a refused mode leaves the sort unchanged")

  -- the keyed list sorts against this mini dataset too
  local byDex = Ops.dexList(S)
  eq(byDex[1], "BULBASAUR", "mini-catalog dex order is #1 first")
  eq(byDex[2], "CHARMANDER", "mini-catalog dex order is #4 second")
  Ops.dexSort(S, "name")
  eq(Ops.dexList(S)[1], "BULBASAUR", "mini-catalog name order leads with BULBASAUR")
end

do
  -- robustness: a mod-shaped partial record (no name, no dex) must not crash
  -- the sort or disappear from the grid -- it just sorts last
  local S = newState()
  S.data = { pokemon = { BULBASAUR = { dex = 1, name = "BULBASAUR" },
                         PARTIAL = { baseStats = { hp = 40 } } } }
  S.cat = { species = { "BULBASAUR", "PARTIAL" }, items = {}, moves = {} }

  local byDex = Ops.dexList(S)
  eq(#byDex, 2, "a partial record still appears in the dex order")
  eq(byDex[2], "PARTIAL", "a record without a dex number sorts last")

  Ops.dexSort(S, "name")
  local byName = Ops.dexList(S)
  eq(#byName, 2, "a partial record still appears in the name order")
  eq(byName[2], "PARTIAL", "a record without a name sorts last, by its id")

  -- and with no data/catalog at all, the list degrades to empty, not nil
  local bare = State.new()
  eq(#Ops.dexList(bare), 0, "a state with no catalog yields an empty list")
end

print(string.format("save editor task 7 tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
