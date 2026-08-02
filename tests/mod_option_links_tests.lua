package.path = "./?.lua;./?/init.lua;" .. package.path

local ManagerState = require("src.mods.ManagerState")
local function profileFromAssists(get)
  local hints, details = get("hints"), get("details")
  if hints and details then return "enhanced" end
  if not hints and not details then return "purist" end
  return "custom"
end
local schema = {
  { key = "profile", type = "choice", default = "enhanced", sync = true,
    choices = { { "PURIST", "purist" }, { "ENHANCED", "enhanced" },
      { "CUSTOM", "custom" } }, sets = {
    purist = { hints = false, details = false },
    enhanced = { hints = true, details = true },
    custom = { profile = profileFromAssists },
  } },
  { key = "hints", type = "toggle", default = true, sets = {
    [false] = { profile = profileFromAssists },
    [true] = { profile = profileFromAssists },
  } },
  { key = "details", type = "toggle", default = true, sets = {
    [false] = { profile = profileFromAssists },
    [true] = { profile = profileFromAssists },
  } },
}
local loader = { modOptions = {}, optionSchemas = { gear = schema },
  events = { emit = function() end } }
local game = { save = { options = {} }, mods = loader,
  writeOptions = function() end }
local state = setmetatable({ game = game }, ManagerState)
state.goTo = function() end
state.notify = function() end

state:setOption("gear", "profile", "purist")
assert(loader.modOptions.gear.hints == false
  and loader.modOptions.gear.details == false, "purist disables assists")
state:setOption("gear", "profile", "enhanced")
assert(loader.modOptions.gear.hints == true
  and loader.modOptions.gear.details == true, "enhanced enables assists")
state:setOption("gear", "hints", false)
assert(loader.modOptions.gear.profile == "custom",
  "manual assist edits select custom")
state:setOption("gear", "details", false)
assert(loader.modOptions.gear.profile == "purist",
  "all assists off selects purist")
state:setOption("gear", "hints", true)
assert(loader.modOptions.gear.profile == "custom",
  "mixed assists select custom")
state:setOption("gear", "details", true)
assert(loader.modOptions.gear.profile == "enhanced",
  "all assists on selects enhanced")

loader.modOptions.gear = { profile = "purist", hints = true, details = true }
state:openOptions({ id = "gear" })
assert(loader.modOptions.gear.hints == false
  and loader.modOptions.gear.details == false,
  "opening options repairs an older contradictory profile")
state.optionRows[#state.optionRows].activate()
assert(loader.modOptions.gear.profile == "enhanced"
  and loader.modOptions.gear.hints == true
  and loader.modOptions.gear.details == true,
  "reset keeps profile defaults coherent")

print("mod option links: 8/8 checks passed")
