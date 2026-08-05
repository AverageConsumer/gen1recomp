-- #828: launcher settings "reset" on Android and Steam Deck, with nothing in
-- the log.  Every options write is a WHOLE-FILE rewrite out of the caller's
-- table (src/core/SaveData.lua saveOptions), so a filesystem that reports a
-- successful write without the bytes surviving -- an external-storage volume
-- that went away mid-session (conf.lua sets t.externalstorage on Android), a
-- read-only or full save dir -- is indistinguishable from "the launcher never
-- saved at all".  saveOptions therefore reads the file back and fails loudly.
--
-- This suite pins that contract against injected filesystem stubs, the same
-- { getInfo, read, write, remove } shape tests/engine/save_slots.lua and
-- tests/engine/save_file_io_tests.lua use.  It is ROM-free (T2 engine tier).
--
-- What it does NOT do: prove #828 is fixed.  The launcher -> options.lua ->
-- bootGame chain already round-trips correctly on desktop, so the readback is
-- instrumentation for the two platforms that report the loss, and the real
-- verification is a platform run (see the issue).  What is testable here is
-- that a silent no-op write is now reported instead of swallowed.
--   luajit tests/engine/options_write_readback_bug828.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Logger = require("src.core.Logger")
local SaveData = require("src.core.SaveData")

local OPTIONS = "options.lua"

-- An in-memory love.filesystem stub.  `mode` decides what write() does with
-- the bytes AFTER reporting success, which is the whole point of the suite:
--   "honest"    -- stores them (a working save dir)
--   "drop"      -- reports true, stores nothing (the volume vanished)
--   "truncate"  -- reports true, stores a short prefix (a full save dir)
--   "fail"      -- reports false plus an error string (the pre-existing path)
local function memfs(mode)
  local files = {}
  return {
    files = files,
    write = function(path, content)
      if mode == "fail" then return false, "no space left on device" end
      if mode == "drop" then return true end
      if mode == "truncate" then
        files[path] = tostring(content):sub(1, 16)
        return true
      end
      files[path] = content
      return true
    end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] ~= nil then return { type = "file" } end
      return nil
    end,
  }
end

-- SaveData.persistFs hands an injected fs straight back only when it differs
-- from love.filesystem, so the suite never touches the real save directory.
local function logged(pattern)
  for i = #Logger.history, 1, -1 do
    if Logger.history[i]:find(pattern, 1, true) then return Logger.history[i] end
  end
  return nil
end

-- ---- the write that lands: unchanged success contract

local fs = memfs("honest")
local saved = SaveData.saveOptions({ battleLayout = "wide" }, fs)
check(saved ~= nil, "a write that lands returns the merged options table")
eq(saved and saved.battleLayout, "wide", "the caller's key survives the merge")
eq(saved and saved.textSpeed ~= nil, true, "defaults are filled in around it")
check(fs.files[OPTIONS] ~= nil, "options.lua is written to the injected fs")

local loaded = SaveData.loadOptions(fs)
eq(loaded and loaded.battleLayout, "wide",
  "loadOptions reads back what saveOptions wrote (the launcher -> game hop)")

-- ---- the write that silently does not land: the #828 failure mode

local dropMark = #Logger.history
local dropped = SaveData.saveOptions({ battleLayout = "wide" }, memfs("drop"))
eq(dropped, nil, "a write that reports success but stores nothing returns nil")
check(logged("options save did not land"),
  "the vanished write is logged, so the next Android report can carry it")
check(#Logger.history > dropMark, "a log line was actually emitted")

-- ---- a partial write is just as lost, and just as loud

local truncated = SaveData.saveOptions({ battleLayout = "wide" }, memfs("truncate"))
eq(truncated, nil, "a truncated write is treated as a failed write")
check(logged("options save did not land"), "the truncated write is logged too")

-- ---- the pre-existing honest failure still behaves exactly as before

local failMark = #Logger.history
local failed = SaveData.saveOptions({ battleLayout = "wide" }, memfs("fail"))
eq(failed, nil, "a write that returns false still returns nil")
check(logged("options save failed"),
  "the false-return path keeps its own distinct log line")
check(#Logger.history > failMark, "the false-return path still logs")

-- A dropped write must not be reported through the false-return message:
-- the two are different diagnoses and the platform reports need to tell
-- them apart.
local last = Logger.history[#Logger.history]
check(last and last:find("options save failed", 1, true) ~= nil,
  "the last failure logged is the false-return one, not the readback one")

-- ---- an interrupted write no longer resets every setting
-- The launcher wrote WIDE and a later write dies partway through (the
-- process replaced by HostShell.restart on the way back to the launcher, an
-- external-storage flush that never happened), leaving a corrupt
-- options.lua.  loadOptions must promote the staged/backup copy instead of
-- answering defaults, which is what "closing the game reset all my
-- settings" looked like.
local live = memfs("honest")
SaveData.saveOptions({ battleLayout = "wide" }, live)
SaveData.saveOptions({ battleLayout = "wide", textSpeed = 1 }, live)
check(live.files[OPTIONS .. ".bak"] ~= nil,
  "the previous good options.lua is rolled aside before the rewrite")
check(live.files[OPTIONS .. ".tmp"] == nil,
  "the staged witness is dropped once the main write is verified")
live.files[OPTIONS] = "return { battleLayout = "   -- died mid-rewrite
local healed = SaveData.loadOptions(live)
eq(healed and healed.battleLayout, "wide",
  "a corrupt options.lua is recovered from the rolled-aside copy")
check(live.files[OPTIONS] ~= "return { battleLayout = ",
  "the main options file is healed from the copy that parsed")

-- ---- a lost main file must recover to the NEWEST verified write
-- The platforms that lose options.lua do it on the hard teardown out of a
-- game session (HostShell.restart's restartApp kill on Android, execv on a
-- SteamOS AppImage), after rewrites whose bytes matched the file already on
-- disk: play()'s lastVersion stamp and the in-game save flush re-encode the
-- same table, and the key-sorted encoder makes those byte-identical, so the
-- conditional pre-write roll skips them.  The backup is therefore rolled
-- forward after every verified write; otherwise recovery handed back the
-- file from BEFORE the launcher's change, which is exactly the reported
-- "set BATTLE LAYOUT to WIDE, go in game, close, and it is OG again" (#828).
local lost = memfs("honest")
SaveData.saveOptions({ battleLayout = "og", lastVersion = "red" }, lost)
local editedOpts = SaveData.loadOptions(lost)
editedOpts.battleLayout = "wide"
SaveData.saveOptions(editedOpts, lost)              -- the launcher's toggle
local replay = SaveData.loadOptions(lost)
replay.lastVersion = "red"                          -- play() re-stamps the same value
SaveData.saveOptions(replay, lost)                  -- byte-identical rewrite
SaveData.saveOptions(SaveData.loadOptions(lost), lost)  -- in-game save flush, identical too
lost.files[OPTIONS] = nil                           -- the platform ate the main file
local promoted = SaveData.loadOptions(lost)
eq(promoted.battleLayout, "wide",
  "a lost main file recovers to the newest verified write, not the "
  .. "pre-change backup (#828)")

local gone = memfs("honest")
SaveData.saveOptions({ battleLayout = "wide" }, gone)
gone.files[OPTIONS] = nil
gone.files[OPTIONS .. ".bak"] = nil
gone.files[OPTIONS .. ".tmp"] = nil
eq(SaveData.loadOptions(gone).battleLayout,
  SaveData.defaultOptions().battleLayout,
  "with no copy left the defaults are still the answer")

-- ---- the reported sequence end to end: launcher setting -> play -> quit
-- #828 as the reporter walks it (issue steps 2-7, and the "so its partly
-- fixed" comment): change BATTLE LAYOUT from OG to WIDE in the launcher, go
-- in game, close, reopen the launcher.  Every options write is a whole-file
-- rewrite out of the caller's table (saveOptions above), so the only thing
-- keeping the launcher's key alive across a game-side write is WHEN the game
-- took its copy: SaveData.load re-attaches a fresh loadOptions() to the save
-- it just read (src/core/SaveData.lua:1108, and SaveData.newGame does the
-- same at :1458), which is after the launcher's last write because
-- RomImporter:play hands off only once the settings modal has saved
-- (src/import/LauncherSettings.lua open/save, src/import/RomImporter.lua
-- play).  This pins that ordering: it is the invariant, not the merge, that
-- makes the launcher's change survive.
local hop = memfs("honest")
SaveData.saveOptions({ battleLayout = "og" }, hop)

-- launcher: the gear menu's edited table, persisted on close
local launcherOpts = SaveData.loadOptions(hop)
launcherOpts.battleLayout = "wide"
launcherOpts.lastVersion = "blue"     -- #835 rides the same file
SaveData.saveOptions(launcherOpts, hop)

-- boot: the game's copy is taken here, never earlier
local gameOpts = SaveData.loadOptions(hop)
eq(gameOpts.battleLayout, "wide",
  "the game boots on the value the launcher just wrote")

-- play: an in-game OPTION menu change writes the whole table back
gameOpts.textSpeed = 1
check(SaveData.saveOptions(gameOpts, hop) ~= nil, "the game-side write lands")

local reopened = SaveData.loadOptions(hop)
eq(reopened.battleLayout, "wide",
  "the launcher's BATTLE LAYOUT survives a game-side options write (#828)")
eq(reopened.textSpeed, 1, "and the in-game change is persisted alongside it")
eq(reopened.lastVersion, "blue",
  "launcher-only keys the game never reads are carried through its write")

-- The corollary, and the reason the copy has to come from loadOptions: a
-- caller that writes a partial literal instead of a loaded table drops every
-- key it does not mention, because mergeOptions only fills DEFAULTS in around
-- what it is handed (SaveData.mergeOptions).  Nothing on the boot path does
-- this today; the assertion is the guard rail if someone shortcuts it.
SaveData.saveOptions({ battleLayout = "og" }, hop)
eq(SaveData.loadOptions(hop).lastVersion, nil,
  "a partial write drops launcher-only keys, so the game must write the "
  .. "table loadOptions handed it")

-- Known gap, deliberately not asserted: a copy taken BEFORE the launcher's
-- write and flushed after it still wins, because saveOptions merges only
-- modOptions from disk and every other key is last-writer-wins.  Measured,
-- not guessed (og beats a newer wide).  No shipping path holds an options
-- table across a launcher write -- HostShell.restart replaces the process on
-- the way back to the launcher (#785, #575) and LauncherSettings.open notes
-- its own cached table is only true while its modal covers the launcher --
-- so closing that gap needs a three-way merge (baseline vs caller vs disk),
-- not a straight "disk wins", which would throw away real in-game changes.

T.finish("options_write_readback_bug828")
