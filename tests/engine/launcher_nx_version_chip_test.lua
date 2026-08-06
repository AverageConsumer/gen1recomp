-- Switch launcher shows the running engine version in the header (NX only).
-- Desktop/Android/iOS must not paint that chip.

local function read(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

local src = read("src/import/LauncherView.lua")

assert(src:find('local Version = require%("src%.core%.Version"%)')
  or src:find('require%("src%.core%.Version"%)'),
  "LauncherView must require Version")

assert(src:find("imp%.isNX", 1, false), "version chip must gate on isNX")

-- The chip is inside an isNX block and prints Version.engine (layout between
-- the chip and the settings gear may change; anchor on the Switch-only comment).
local nxBlock = src:match(
  "Switch%-only: show the running app version.-if imp%.isNX then(.-)end")
assert(nxBlock, "expected Switch-only version chip in the header row")
assert(nxBlock:find("Version%.engine", 1, false), "chip must show Version.engine")
assert(nxBlock:find('"v"', 1, true) or nxBlock:find('"v" %.%.', 1, false),
  "chip label should be a v-prefixed version")

print("ok — Switch launcher version chip is NX-gated and uses Version.engine")
