-- In-game Gold SAVE with no launcher slot must leave a file CONTINUE can see.
--
--   POKEPORT_GAME=gold POKEPORT_IDENTITY=gold-bug1107 \
--     POKEPORT_DRIVER=tests/drivers/gold_save_slot_bug1107_test.lua love .

local U = require("tests.drivers.util")
local SaveData = require("src.core.SaveData")

return function(game)
  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  local before = SaveData.listSlots("gold")
  local hadFile = false
  for _, slot in ipairs(before) do
    if slot.exists then hadFile = true break end
  end
  if not hadFile then
    local opts = SaveData.loadOptions()
    opts.saveSlots = opts.saveSlots or {}
    opts.saveSlots.gold = nil
    SaveData.saveOptions(opts)
    SaveData.resetSlotState()
  end

  local ok, err = game:writeSave()
  if not ok then
    U.log("FAIL gold writeSave:", tostring(err))
  else
    local after = SaveData.listSlots("gold")
    local found, path
    for _, slot in ipairs(after) do
      if slot.exists then
        found = slot.id
        path = SaveData.slotDiskPath("gold", slot.id)
        break
      end
    end
    if found then
      U.log("PASS gold save is launcher-visible:", found, path or "")
    else
      U.log("FAIL gold save wrote but listSlots has no file")
    end
  end

  while true do
    coroutine.yield()
  end
end
