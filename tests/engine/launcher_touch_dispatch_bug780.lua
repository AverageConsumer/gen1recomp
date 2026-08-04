-- Launcher action drain (src/import/RomImporter.lua): on a phone one tap
-- lands on a save row AND on the chip drawn inside it, because FlexLove's
-- touch path has no topmost gate (EventHandler:processTouchEvents) while its
-- mouse path does.  The drain therefore drops a row's own action when a
-- control inside that row fired in the same batch, and applies #433's disarm
-- as it runs each action rather than as the view queues them -- otherwise the
-- row's select cleared the arm the same tap had set and Delete never reached
-- its second press (#780).
--   luajit tests/engine/launcher_touch_dispatch_bug780.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local clock = 1000
love.timer.getTime = function() return clock end

local RomImporter = require("src.import.RomImporter")

local function launcher()
  local self = setmetatable({}, RomImporter)
  self.ran = {}
  return self
end

local function tapDeleteChip(self, rowKey)
  -- what one Android tap on a row's Delete chip queues: the row itself, then
  -- the chip drawn on top of it
  return {
    { key = rowKey, keepArm = false, fn = function()
      table.insert(self.ran, "select")
    end },
    { key = rowKey .. "-del", keepArm = true, fn = function()
      table.insert(self.ran, "delete")
      self:pressDelete("slot", "slot2", "red", function()
        table.insert(self.ran, "deleted")
      end)
    end },
  }
end

-- ------- the chip wins the tap, and two taps delete

do
  local self = launcher()
  self:runActions(tapDeleteChip(self, "slot-red-slot2"))
  eq(self.ran[1], "delete", "the chip's action runs, not the row's select")
  eq(#self.ran, 1, "the row behind the chip is dropped from the batch")
  check(self._confirmDelete ~= nil, "the first tap leaves Delete armed")

  self:runActions(tapDeleteChip(self, "slot-red-slot2"))
  eq(self.ran[3], "deleted", "the second tap on the same chip commits")
  eq(self._confirmDelete, nil, "the arm is spent")
end

-- ------- a tap on the row itself still selects, and still disarms

do
  local self = launcher()
  self:pressDelete("slot", "slot2", "red", function() end)
  check(self._confirmDelete ~= nil, "armed")
  self:runActions({
    { key = "slot-red-slot2", keepArm = false, fn = function()
      table.insert(self.ran, "select")
    end },
  })
  eq(self.ran[1], "select", "a tap on empty row area selects the slot")
  eq(self._confirmDelete, nil, "and disarms the pending Delete (#433)")
end

-- ------- a sibling row's chip does not swallow another row

do
  local self = launcher()
  self:runActions({
    { key = "slot-red-slot1", keepArm = false, fn = function()
      table.insert(self.ran, "row1")
    end },
    { key = "slot-red-slot10-del", keepArm = true, fn = function()
      table.insert(self.ran, "del10")
    end },
  })
  eq(self.ran[1], "row1", "slot1 is not a prefix-key parent of slot10")
  eq(self.ran[2], "del10", "and slot10's chip still runs")
end

-- ------- a failing action does not sink the rest of the batch

do
  local self = launcher()
  self:runActions({
    { key = "a", keepArm = false, fn = function() error("boom") end },
    { key = "b", keepArm = false, fn = function()
      table.insert(self.ran, "b")
    end },
  })
  eq(self.ran[1], "b", "the queue drains past a handler that threw")
end

print("launcher touch dispatch (#780) ok")
