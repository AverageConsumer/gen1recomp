-- pokered/engine/battle/animations.asm:1118
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local AnimPlayer = require("src.battle.AnimPlayer")
local water = { effect = "SE_WATER_DROPLETS_EVERYWHERE", sound = "SURF" }
local columns = { subanim = "COLUMNS", tileset = 0, delay = 6, sound = "HYDRO_PUMP" }
local data = {
  tilesheets = { [0] = { tiles = 79 }, [1] = { tiles = 64 } },
  moveAnims = {
    SURF = { seq = { water, columns } },
    MIST = { seq = { { effect = "SE_LIGHT_SCREEN_PALETTE" }, water,
      { effect = "SE_RESET_SCREEN_PALETTE" } } },
    TOXIC = { seq = { water,
      { subanim = "COLUMNS", tileset = 1, delay = 6, sound = "TOXIC" } } },
  },
  subanims = { COLUMNS = { type = "NORMAL", blocks = {
    { block = "COLUMN", coord = "BASE", mode = 0 },
  } } },
  frameBlocks = { COLUMN = { { x = 0, y = 0, tile = 5 } } },
  baseCoords = { BASE = { x = 120, y = 40 } },
  idEffects = {},
}

for _, id in ipairs({ "SURF", "MIST", "TOXIC" }) do
  for _, side in ipairs({ true, false }) do
    local label = id .. (side and " player" or " enemy")
    local p = AnimPlayer.new(data)
    p:start(id, side)
    local nextLoad = id == "TOXIC" and 9 or 10
    local nextSound, firstSound
    for _, ev in ipairs(p.events) do
      if ev.sound == "SURF" then firstSound = ev.frame end
      if ev.sound == "HYDRO_PUMP" or ev.sound == "TOXIC" then nextSound = ev.frame end
    end
    T.eq(firstSound, 0, label .. " sound precedes own tile load")
    if id ~= "MIST" then
      T.eq(nextSound, 138 + nextLoad, label .. " next sound includes both tile loads")
    end
    T.eq(p.steps[1].dur, 10, label .. " own tileset load lasts ten ticks")
    T.eq(#p.steps[1].sprites, 0, label .. " own tileset load has no droplets")
    local visible, clear = 0, 0
    for tick = 0, 137 do
      local st = p.steps[p.stepIndex]
      T.check(st ~= nil, label .. " water row includes tick " .. tick)
      local n = st and #st.sprites or 0
      if tick < 10 then
        T.eq(n, 0, label .. " load tick " .. tick .. " is blank")
      elseif (tick - 10) % 2 == 0 then
        T.check(n > 0, label .. " droplet pass visible at tick " .. tick)
        visible = visible + (n > 0 and 1 or 0)
        if st then
          T.eq(st.dur, 1, label .. " droplet pass lasts one tick")
          T.eq(st.sprites[1] and st.sprites[1].y, (visible % 2 == 1) and 16 or 24,
            label .. " preserves alternating row origin")
          if visible == 1 then
            T.eq(st.sprites[1] and st.sprites[1].x, 11, label .. " first pass X progression")
          elseif visible == 64 then
            T.eq(st.sprites[1] and st.sprites[1].x, 11, label .. " last pass X progression")
            local last = st.sprites[#st.sprites]
            T.eq(last and last.x, 170, label .. " last pass final X")
            T.eq(last and last.y, 104, label .. " last pass final Y")
          end
        end
      else
        T.eq(n, 0, label .. " cleanup wait is blank at tick " .. tick)
        clear = clear + (n == 0 and 1 or 0)
      end
      p:update()
    end
    T.eq(visible, 64, label .. " displays all 64 droplet passes")
    T.eq(clear, 64, label .. " clears sprites after all 64 passes")
    if id == "MIST" then
      T.check(p:isDone(), label .. " has no redundant trailing cleanup tick")
    else
      local nextStep = p.steps[p.stepIndex]
      T.eq(nextStep and nextStep.dur, nextLoad, label .. " next row immediately loads its tiles")
      T.eq(nextStep and #nextStep.sprites, 0, label .. " next row load is blank")
      for _ = 1, nextLoad do p:update() end
      T.eq(p.elapsed, 138 + nextLoad, label .. " following block begins after its load")
      nextStep = p.steps[p.stepIndex]
      T.eq(nextStep and nextStep.sprites[1] and nextStep.sprites[1].tile, 5,
        label .. " reaches following subanimation")
    end
  end
end

T.finish("Surf droplet timing 2613")
