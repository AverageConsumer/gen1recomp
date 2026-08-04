-- Platform capability detection for console, mobile and desktop builds.

local Platform = {}

local cached

local function compute()
  local osName = (love and love.system and love.system.getOS and love.system.getOS())
    or "Unknown"
  local nx = osName == "NX"
  local uwp = osName == "UWP"
  local mobile = osName == "Android" or osName == "iOS"
  local nativePicker = love and love.system
    and type(love.system.pickFile) == "function"
  return {
    os = osName,
    nx = nx,
    uwp = uwp,
    mobile = mobile,
    console = nx or uwp,
    hasNativePicker = nativePicker,
    canSpawnProcess = osName == "OS X" or osName == "Windows" or osName == "Linux",
    romImportMode = nx and "save-directory"
      or (nativePicker and "native-picker")
      or "desktop",
    networkValidated = not nx and not uwp,
  }
end

function Platform.detect()
  if not cached then cached = compute() end
  return cached
end

function Platform.isNX()
  return Platform.detect().nx
end

function Platform.isUWP()
  return Platform.detect().uwp
end

function Platform.romImportMode()
  return Platform.detect().romImportMode
end

function Platform.canSpawnProcess()
  return Platform.detect().canSpawnProcess
end

function Platform.networkValidated()
  return Platform.detect().networkValidated
end

-- Tests may swap love.system between cases.
function Platform._resetForTests()
  cached = nil
end

return Platform
