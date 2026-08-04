-- #774: packager archive checks must never pipe an `unzip -Z1` listing
-- straight into `grep -q`.  grep -q exits on the first match, unzip takes
-- SIGPIPE (141), and under the scripts' `set -o pipefail` the pipeline
-- reports 141 -- so an `if` guard reads a real match as "no match".  For
-- build_android.sh's generated-data guard that failed open on exactly the
-- archive it exists to reject (one carrying the user's extracted ROM
-- data).  The fix everywhere is to capture the listing once and grep the
-- captured text (build.sh, pack_love.sh, build_ios.sh, build_android.sh
-- all do); this suite keeps the class of bug from regressing.  The
-- `unzip -p ... Version.lua | grep` readbacks are fine -- a 1.4 KB single
-- write fits the pipe buffer, so unzip returns before grep can close the
-- read end -- and the scan below deliberately matches only -Z1 listings.
-- Self-contained: luajit tests/engine/build_zip_pipe_guard_bug774.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function listShellFiles()
  local out = {}
  local p = io.popen('find scripts -name "*.sh" -type f')
  if not p then return out end
  for line in p:lines() do
    out[#out + 1] = line
  end
  p:close()
  table.sort(out)
  return out
end

-- ------------------------------------------------------------- static scan
-- Join backslash continuations first: the buggy form in build_android.sh
-- spread the pipeline across two lines.
local scripts = listShellFiles()
check(#scripts > 0, "found shell scripts under scripts/ to scan")

local violations = {}
for _, file in ipairs(scripts) do
  local body = readFile(file)
  if body then
    local joined = body:gsub("\\\n%s*", " ")
    if joined:find("unzip %-Z1[^\n|]*|%s*grep %-%a*q") then
      violations[#violations + 1] = file
    end
  end
end

check(#violations == 0,
  "no script pipes an unzip -Z1 listing into grep -q (#774: pipefail turns"
    .. " the SIGPIPE into an inverted guard)"
    .. (#violations > 0 and (":\n  " .. table.concat(violations, "\n  ")) or ""))

-- --------------------------------------------------------- replay the guard
-- Run build_android.sh's own forbidden-content pattern, in the captured
-- form the script now uses, over a throwaway archive that really does
-- carry a data/generated entry, and over a clean one.  This pins the
-- capture-then-grep idiom's behavior rather than trusting the scan alone.
local androidBody = readFile("scripts/build_android.sh") or ""
local pattern = androidBody:match("grep %-Eq '([^']*generated[^']*)'")
check(pattern ~= nil,
  "build_android.sh still greps a generated-data pattern over the listing")

local function haveCommand(name)
  local probe = io.popen("command -v " .. name .. " 2>/dev/null")
  if not probe then return false end
  local out = probe:read("*a")
  probe:close()
  return out ~= nil and out:match("%S") ~= nil
end

if pattern and haveCommand("zip") and haveCommand("unzip")
    and haveCommand("bash") then
  local tmpDir = (os.getenv("TMPDIR") or "/tmp"):gsub("[/\\]+$", "")
  local stage = ("%s/pokeport_bug774_%d_%d"):format(
    tmpDir, os.time(), math.random(1, 999999))
  os.execute(('mkdir -p "%s/pay/data/generated"'):format(stage))
  os.execute(('touch "%s/pay/data/generated/x.lua" "%s/pay/main.lua"')
    :format(stage, stage))
  os.execute(('cd "%s/pay" && zip -qr ../bad.love .'):format(stage))
  os.execute(('cd "%s/pay" && zip -qr ../clean.love main.lua'):format(stage))

  local function guardVerdict(archive)
    -- exactly the script's shape: pipefail on, listing captured once,
    -- grep runs over the captured text so nothing can take a SIGPIPE
    local cmd = ("bash -c 'set -euo pipefail\n"
      .. 'archive_entries="$(unzip -Z1 "%s")"\n'
      .. "if grep -Eq '\\''%s'\\'' <<< \"$archive_entries\"; then"
      .. " echo CAUGHT; else echo CLEAN; fi' 2>/dev/null"):format(
        archive, pattern)
    local p = io.popen(cmd)
    if not p then return nil end
    local out = p:read("*a") or ""
    p:close()
    return out:match("%S+")
  end

  check(guardVerdict(stage .. "/bad.love") == "CAUGHT",
    "the captured-listing guard rejects an archive carrying data/generated"
      .. " (#774: the piped form let this ship in an APK)")
  check(guardVerdict(stage .. "/clean.love") == "CLEAN",
    "the captured-listing guard passes an archive without generated data")

  os.execute(('rm -rf "%s"'):format(stage))
else
  print("[#774] zip/unzip/bash not all present: guard replay skipped,"
    .. " the static scan above still ran")
end

T.finish()
