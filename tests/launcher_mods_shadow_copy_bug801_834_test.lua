-- #801 / #834: what the PLAYER sees after an update over a shadow copy.
-- The tier file (launcher_mods_install_zip_test.lua) asserts which folders
-- survive installZip; this one asserts the panel-facing contracts built on
-- top of them: LauncherMods.list() must report the NEW version after a
-- replace even when a same-id copy sits under an archive-named folder that
-- enumerates first (#801, "Updated ... to X" yet the old version kept
-- loading), and uninstall()/re-import must both recover a manifest-less
-- mods/<id> debris tree left by an interrupted copy (#834, "already
-- installed" with nothing showing in the panel).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("launcher mods shadow copy #801/#834")
local eq = S.eq
local check = S.check

-- The real-world shape from the #801 report: a hand-unzipped copy kept the
-- archive's folder name.  "W" sorts before "o" in the stub's sorted
-- enumeration, so the shadow folder enumerates first -- the exact ordering
-- that made discover()'s first-id-wins dedupe resolve the stale copy.
local MOD_ID = "overworld_wild_spawns"
local SHADOW = "mods/WildsOfKanto-1.5.0"
local NEW_VERSION = "1.7.1"

local ARCHIVE = {
  [MOD_ID .. "/manifest.json"] =
    ('{"id":"%s","name":"Wilds of Kanto","version":"%s","entry":"main.lua"}')
      :format(MOD_ID, NEW_VERSION),
  [MOD_ID .. "/main.lua"] = "return function() end\n",
}

local files, dirs, arch = {}, {}, {}

local function resetFs()
  for k in pairs(files) do files[k] = nil end
  for k in pairs(dirs) do dirs[k] = nil end
  for k in pairs(arch) do arch[k] = nil end
end

local function dirChild(key, name)
  if name == nil or name == "" then return key:match("^[^/]+") end
  local prefix = name .. "/"
  if key:sub(1, #prefix) ~= prefix then return nil end
  return key:sub(#prefix + 1):match("^[^/]+")
end

local function mapInfo(map, name, kind)
  if map[name] ~= nil then return { type = kind or "file" } end
  for key in pairs(map) do
    if dirChild(key, name) then return { type = "directory" } end
  end
  return nil
end

local vfs = {}

function vfs.write(name, data)
  files[name] = data
  return true
end

function vfs.read(name)
  if arch[name] ~= nil then return arch[name] end
  return files[name]
end

function vfs.remove(name)
  files[name] = nil
  dirs[name] = nil
  return true
end

function vfs.createDirectory(name)
  dirs[name] = true
  return true
end

function vfs.getInfo(name, kind)
  local info = mapInfo(arch, name)
    or mapInfo(files, name)
    or mapInfo(dirs, name, "directory")
  if info and kind and info.type ~= kind then return nil end
  return info
end

function vfs.getDirectoryItems(name)
  local seen, items = {}, {}
  local function add(child)
    if child and not seen[child] then
      seen[child] = true
      items[#items + 1] = child
    end
  end
  for key in pairs(arch) do add(dirChild(key, name)) end
  for key in pairs(files) do add(dirChild(key, name)) end
  for key in pairs(dirs) do add(dirChild(key, name)) end
  table.sort(items)
  return items
end

function vfs.mount(_, point)
  for rel, body in pairs(ARCHIVE) do
    arch[point .. "/" .. rel] = body
  end
  return true
end

function vfs.unmount()
  for k in pairs(arch) do arch[k] = nil end
  return true
end

function vfs.newFileData(data, name)
  return { __filedata = true, data = data, name = name }
end

function vfs.getSaveDirectory()
  return "/tmp/pokeport-shadow-copy-test"
end

function vfs.getSource()
  return nil
end

local savedFs = love.filesystem
local savedCacheFs = package.loaded["src.import.CacheFs"]
local savedLauncherMods = package.loaded["src.mods.LauncherMods"]

local SaveData = require("src.core.SaveData")
local savedPortableBase = SaveData.portableBaseDir
local savedPortableFs = SaveData.portableFs

love.filesystem = vfs
package.loaded["src.import.CacheFs"] = nil
package.loaded["src.mods.LauncherMods"] = nil
-- Portable mode off: loadOptions/uninstall must stay on the stub vfs, or the
-- checkout's real save directory would leak into the test.
SaveData.portableBaseDir = function() return nil end
SaveData.portableFs = function() return nil end
local LauncherMods = require("src.mods.LauncherMods")

local function versionOf(id)
  for _, row in ipairs(LauncherMods.list()) do
    if row.id == id then return row.version end
  end
  return nil
end

-- #801: the shadow copy alone resolves as the mod (sanity for the setup),
-- and after a replace-install the panel row flips to the zip's version.
-- Pre-fix, installZip returned success but only rewrote mods/<id>; the
-- shadow folder enumerated first and list() kept answering 1.5.0 forever.
resetFs()
files[SHADOW .. "/manifest.json"] =
  ('{"id":"%s","name":"Wilds of Kanto","version":"1.5.0","entry":"main.lua"}')
    :format(MOD_ID)
files[SHADOW .. "/main.lua"] = "return function() end\n"
eq(versionOf(MOD_ID), "1.5.0", "shadow copy resolves before the update")

files["imports/mods/update.zip"] = "PK\3\4update"
local ok, err = LauncherMods.installZip("imports/mods/update.zip",
  { replace = true, expectId = MOD_ID })
check(ok == true, "replace over a shadow copy succeeds (" .. tostring(err) .. ")")
eq(err, MOD_ID, "replace reports the manifest id")
eq(versionOf(MOD_ID), NEW_VERSION,
  "list() reports the zip's version after the replace")
check(files[SHADOW .. "/manifest.json"] == nil,
  "shadow folder is gone, so no stale copy can win first-id-wins later")
eq(#LauncherMods.list(), 1, "the update leaves exactly one panel row")

-- #801: Delete from the panel must take the shadow copy with it, or the
-- next boot resurrects the mod from the odd-named folder.
resetFs()
files[SHADOW .. "/manifest.json"] = ARCHIVE[MOD_ID .. "/manifest.json"]
files["mods/" .. MOD_ID .. "/manifest.json"] = ARCHIVE[MOD_ID .. "/manifest.json"]
ok, err = LauncherMods.uninstall(MOD_ID)
check(ok == true, "uninstall succeeds with a shadow copy present ("
  .. tostring(err) .. ")")
check(files[SHADOW .. "/manifest.json"] == nil,
  "uninstall removes the same-id shadow folder too")
check(files["mods/" .. MOD_ID .. "/manifest.json"] == nil,
  "uninstall removes mods/<id>")
eq(#LauncherMods.list(), 0, "nothing is left for the panel to show")

-- #834: interrupted-copy debris (mods/<id> with no manifest.json) is
-- invisible to list() yet used to hard-block every plain re-import with
-- "a mod named '<id>' is already installed".  Both recovery paths the
-- player can reach must work: plain re-import, and Delete.
resetFs()
files["mods/" .. MOD_ID .. "/gfx/a.bin"] = "x"
eq(#LauncherMods.list(), 0, "debris tree shows no panel row")
files["imports/mods/again.zip"] = "PK\3\4again"
ok, err = LauncherMods.installZip("imports/mods/again.zip")
check(ok == true, "plain re-import over debris succeeds ("
  .. tostring(err) .. ")")
check(files["mods/" .. MOD_ID .. "/gfx/a.bin"] == nil,
  "re-import clears the debris file")
eq(versionOf(MOD_ID), NEW_VERSION, "re-import yields a listable mod")

resetFs()
files["mods/" .. MOD_ID .. "/gfx/a.bin"] = "x"
ok, err = LauncherMods.uninstall(MOD_ID)
check(ok == true, "uninstall clears a debris-only tree ("
  .. tostring(err) .. ")")
check(files["mods/" .. MOD_ID .. "/gfx/a.bin"] == nil,
  "debris file is gone after uninstall")

-- guard rail: with a healthy install and NO debris, the duplicate gate
-- still refuses a plain import with the same wording the panel shows
resetFs()
files["mods/" .. MOD_ID .. "/manifest.json"] = ARCHIVE[MOD_ID .. "/manifest.json"]
files["imports/mods/dup.zip"] = "PK\3\4dup"
ok, err = LauncherMods.installZip("imports/mods/dup.zip")
check(not ok, "healthy duplicate import is still refused")
check(tostring(err):find("already installed", 1, true),
  "refusal keeps the already installed wording")

-- Restore
love.filesystem = savedFs
SaveData.portableBaseDir = savedPortableBase
SaveData.portableFs = savedPortableFs
package.loaded["src.import.CacheFs"] = savedCacheFs
package.loaded["src.mods.LauncherMods"] = savedLauncherMods

S.finish()
