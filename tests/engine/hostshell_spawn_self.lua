package.path = "./?.lua;./?/init.lua;" .. package.path

local osName, fused, command = "Windows", true, nil
love = {
  system = { getOS = function() return osName end },
  filesystem = {
    getExecutablePath = function() return "C:\\Game\\gen1recomp.exe" end,
    getSource = function() return "C:\\Source\\gen1recomp" end,
    isFused = function() return fused end,
  },
}
package.loaded["src.core.Platform"] = { canSpawnProcess = function() return true end }
local execute = os.execute
os.execute = function(value) command = value return 0 end

local HostShell = require("src.core.HostShell")
assert(HostShell.spawnSelfDetached({ "--display-companion=50000,token" }))
assert(command:find('start "" /b ', 1, true)
  and command:find('"C:\\Game\\gen1recomp.exe"', 1, true),
  "Windows launches the fused app detached")

osName, fused = "Linux", false
assert(HostShell.spawnSelfDetached({ "--display-companion=50000,token" }))
assert(command:find("'C:\\Source\\gen1recomp'", 1, true)
  and command:sub(-1) == "&", "Linux source runs include the game folder")

osName, fused = "OS X", true
assert(HostShell.spawnSelfDetached({ "--display-companion=50000,token" }))
assert(not command:find("start", 1, true) and command:sub(-1) == "&",
  "macOS uses the same detached POSIX path")
os.execute = execute
print("spawn self detached: ok")
