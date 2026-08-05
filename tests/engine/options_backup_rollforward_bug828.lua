-- #828, the revert half: after the launcher's OG -> WIDE toggle, a play
-- session rewrites options.lua with byte-identical content (play() re-stamps
-- an unchanged lastVersion, SaveData.save flushes the attached table, and
-- SaveSerializer's key-sorted encode makes equal tables equal bytes), so
-- saveOptions' conditional pre-write roll skips and options.lua.bak kept the
-- PRE-change file all session.  Android and Steam Deck end sessions with a
-- hard teardown (HostShell.restart restartApp kill / AppImage execv) that can
-- eat the main file, and loadOptions then promoted that stale backup: the
-- reported "launcher-only persists, going in-game reverts".  The fix rolls
-- the backup forward to the just-verified bytes after every landed write;
-- this suite pins that at-rest invariant.  ROM-free (T2 engine tier), same
-- injected-fs shape as tests/engine/options_write_readback_bug828.lua, where
-- these checks should eventually fold in.
--   luajit tests/engine/options_backup_rollforward_bug828.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")

local OPTIONS = "options.lua"
local BAK = OPTIONS .. ".bak"
local TMP = OPTIONS .. ".tmp"

-- In-memory love.filesystem stub, the { getInfo, read, write, remove } shape
-- SaveData.persistFs accepts.  `dropping` is mutable so one fs can serve a
-- healthy session and then a write that reports success without landing.
local function memfs()
  local files = {}
  local fs
  fs = {
    files = files,
    dropping = false,
    write = function(path, content)
      if fs.dropping then return true end
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
  return fs
end

-- ---- at rest, the backup holds the newest verified bytes

local fs = memfs()
SaveData.saveOptions({ battleLayout = "wide" }, fs)
check(fs.files[BAK] ~= nil, "the very first verified write already leaves a backup")
eq(fs.files[BAK], fs.files[OPTIONS],
  "after a verified write the backup equals the main file (#828 roll-forward)")
check(fs.files[TMP] == nil, "the staged witness is still dropped after verification")

-- ---- the reported session, write for write
-- Launcher toggles OG -> WIDE, then two rewrites whose bytes match the file
-- on disk: RomImporter:play re-stamping the same lastVersion (#835) and the
-- in-game SaveData.save flush of the attached, unchanged table.  Both go
-- through loadOptions first, exactly as the shipping callers do, so the
-- encoder sees identical tables and the conditional pre-roll skips.
local live = memfs()
SaveData.saveOptions({ battleLayout = "og", lastVersion = "red" }, live)

local toggled = SaveData.loadOptions(live)
toggled.battleLayout = "wide"
SaveData.saveOptions(toggled, live)
local wideBytes = live.files[OPTIONS]

local stamped = SaveData.loadOptions(live)
stamped.lastVersion = "red"
SaveData.saveOptions(stamped, live)
eq(live.files[OPTIONS], wideBytes,
  "the play() lastVersion re-stamp is a byte-identical rewrite (sorted encode)")
SaveData.saveOptions(SaveData.loadOptions(live), live)
eq(live.files[OPTIONS], wideBytes, "the in-game flush is byte-identical too")

eq(live.files[BAK], wideBytes,
  "identical rewrites still carry the backup forward past the skipped pre-roll")

-- the hard teardown eats the main file; recovery must answer the toggle
live.files[OPTIONS] = nil
eq(SaveData.loadOptions(live).battleLayout, "wide",
  "a lost main file recovers to WIDE, not the pre-toggle OG backup (#828)")
check(live.files[OPTIONS] ~= nil, "and the main file is healed from that copy")

-- ---- a write that does not land must not poison the backup
-- The roll-forward has to sit AFTER the readback verification: if the bytes
-- never reached disk (the #828 external-storage failure mode) the backup
-- keeps the last state that verifiably did.
local flaky = memfs()
SaveData.saveOptions({ battleLayout = "wide" }, flaky)
local verified = flaky.files[BAK]
flaky.dropping = true
eq(SaveData.saveOptions({ battleLayout = "og" }, flaky), nil,
  "the vanished write still reports failure")
flaky.dropping = false
eq(flaky.files[BAK], verified,
  "a write that never landed leaves the backup at the last verified bytes")
flaky.files[OPTIONS] = nil
eq(SaveData.loadOptions(flaky).battleLayout, "wide",
  "so recovery after the failed write still answers the verified state")

T.finish("options_backup_rollforward_bug828")
