package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local DateTime = require("src.core.DateTime")
local SaveData = require("src.core.SaveData")

local stamp = os.time({ year = 2026, month = 8, day = 11, hour = 17, min = 5, sec = 0 })

local defaults = SaveData.defaultOptions()
T.eq(defaults.dateFormat, "device", "date format defaults to device locale")
T.eq(defaults.timeFormat, "device", "time format defaults to device locale")

local game = { save = { options = { dateFormat = "dmy", timeFormat = "24h" } } }
T.eq(DateTime.date(game, stamp), os.date("%d-%m-%Y", stamp),
  "explicit DMY uses day-month-year")
T.eq(DateTime.time(game, stamp), os.date("%H:%M", stamp),
  "explicit 24-hour time omits seconds")
T.eq(DateTime.dateTime(game, stamp),
  os.date("%d-%m-%Y %H:%M", stamp),
  "combined formatter composes exact date and time preferences")

game.save.options.dateFormat = "mdy"
T.eq(DateTime.date(game, stamp), os.date("%m-%d-%Y", stamp),
  "explicit MDY is available")
game.save.options.dateFormat = "ymd"
T.eq(DateTime.date(game, stamp), os.date("%Y-%m-%d", stamp),
  "explicit YMD is available")
game.save.options.timeFormat = "12h"
T.eq(DateTime.time(game, stamp), os.date("%I:%M %p", stamp),
  "explicit 12-hour time is available")

local fallback = DateTime.formatWithLocale(stamp, "device", "device", "C")
T.eq(fallback.date, os.date("%d-%m-%Y", stamp),
  "missing device locale falls back to requested DMY")
T.eq(fallback.time, os.date("%H:%M", stamp),
  "missing device locale falls back to requested 24-hour time")

local invalid = DateTime.date({}, -1)
T.eq(invalid, "----", "invalid timestamps fail closed")

T.finish("date_time")
