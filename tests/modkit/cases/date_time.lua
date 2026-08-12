package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local FIXTURE = {
  ["mods/date_probe/manifest.json"] = [[{
    "id": "date_probe",
    "name": "Date Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/date_probe/main.lua"] = [[
    local mod = ...
    mod.exports.datetime = mod.datetime
  ]],
}

local run = T.sdk.loadMods({ "mods/date_probe" }, { fs = T.sdk.memfs(FIXTURE) })
T.eq(#run.errors, 0, "fixture mod loads cleanly")
local datetime = run.loader.exports.date_probe.datetime
T.eq(type(datetime), "table", "mod object exposes datetime formatting")
T.eq(type(datetime.date), "function", "public formatter exposes date")
T.eq(type(datetime.time), "function", "public formatter exposes time")
T.eq(type(datetime.dateTime), "function", "public formatter exposes date-time")

local stamp = os.time({ year = 2026, month = 8, day = 11, hour = 17, min = 5, sec = 0 })
local game = { save = { options = { dateFormat = "dmy", timeFormat = "24h" } } }
T.eq(datetime:date(game, stamp), os.date("%d-%m-%Y", stamp),
  "mod date follows current global engine preference")
T.eq(datetime:time(game, stamp), os.date("%H:%M", stamp),
  "mod time follows current global engine preference")
T.eq(datetime:dateTime(game, stamp), os.date("%d-%m-%Y %H:%M", stamp),
  "mod date-time composes the same preference")

run.release()
T.finish("date_time")
