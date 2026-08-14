-- GameActivity exposes an optional Android host seam without requiring any
-- host implementation (or its native libraries) in the stock build.
-- Self-contained: luajit tests/engine/android_host_extension_test.lua
local path = "mobile/android/love/src/main/java/org/love2d/android/GameActivity.java"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local function check(value, message)
  if not value then error(message, 2) end
end

local function position(text)
  local p = source:find(text, 1, true)
  check(p, "missing: " .. text)
  return p
end

check(source:find("protected String[] getHostLibraries()", 1, true),
  "host libraries are an overridable protected extension")
check(source:find("return new String[0];", 1, true),
  "the vanilla host library list is empty")

local cpp = position('libraries[0] = "c++_shared";')
local mpg = position('libraries[1] = "mpg123";')
local openal = position('libraries[2] = "openal";')
local host = position("System.arraycopy(hostLibraries, 0, libraries, 3, hostLibraries.length);")
local love = position('libraries[libraries.length - 1] = "love";')
check(cpp < mpg and mpg < openal and openal < host and host < love,
  "optional libraries load after dependencies while liblove remains last")

for _, hook in ipairs({
  "onHostCreateBeforeSDL", "onHostCreateAfterSDL", "onHostResume",
  "onHostPause", "onHostDestroy",
}) do
  check(source:find("protected void " .. hook, 1, true),
    hook .. " is a protected extension hook")
end

check(position("onHostCreateBeforeSDL(savedInstanceState);") <
      position("super.onCreate(savedInstanceState);") and
      position("super.onCreate(savedInstanceState);") <
      position("onHostCreateAfterSDL(savedInstanceState);"),
  "create hooks bracket SDL creation")
check(position("super.onResume();") < position("onHostResume();"),
  "resume hook runs after SDL resumes")
check(position("onHostPause();") < position("super.onPause();"),
  "pause hook runs before SDL pauses")
check(position("onHostDestroy();") < position("super.onDestroy();"),
  "destroy hook runs before SDL destruction")

check(source:find("DisplayManager.DisplayListener", 1, true)
    and source:find("registerDisplayListener", 1, true)
    and source:find("unregisterDisplayListener", 1, true),
  "secondary displays are monitored while the activity is active")
check(position("registerCompanionDisplayObservers();") <
      position("setupSecondaryDisplay();"),
  "secondary display monitoring starts before initial discovery")
check(source:find("onDisplayAdded(int displayId) { rebindSecondaryDisplay(); }", 1, true)
    and source:find("onDisplayRemoved(int displayId) { rebindSecondaryDisplay(); }", 1, true),
  "display hotplug re-evaluates the preferred companion target")

check(not source:lower():find("openxr", 1, true),
  "generic Android activity must not require OpenXR")
check(not source:find("QuestActivity", 1, true) and
      not source:find("QuestBridge", 1, true),
  "generic Android activity must not require Quest classes")

-- Required mod files use Android's Storage Access Framework, which works with
-- Android 13 scoped storage without broad media/storage permissions. Keep the
-- native destination distinct so it cannot be consumed as a game ROM.
check(source:find('PICKED_REQUIRED_IMPORT_FILENAME = "picked_required_import.bin"',
  1, true), "required imports use their own Android picker destination")
check(source:find("showRequiredImportFilePicker", 1, true),
  "Android exposes a required-import picker entry point")
check(source:find("Intent.ACTION_OPEN_DOCUMENT", 1, true)
    and source:find("Intent.FLAG_GRANT_READ_URI_PERMISSION", 1, true),
  "Android 13 uses SAF with an explicit read grant")

local systemPath = "mobile/android/love/src/jni/love/src/modules/system/System.cpp"
local systemFile = assert(io.open(systemPath, "rb"))
local system = systemFile:read("*a")
systemFile:close()
check(system:find('strcmp(kind, "required_import")', 1, true)
    and system:find('dest = "picked_required_import.bin"', 1, true)
    and system:find('return "rom,mod,sav,required_import"', 1, true),
  "native Android bridge advertises and routes required imports")

print("android_host_extension_test: ok")
