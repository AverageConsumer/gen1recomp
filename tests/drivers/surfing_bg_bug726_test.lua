-- Manual check that the Surfing Pikachu minigame background is the
-- ROM's metatile scroller, not the old procedural stand-in (#726).
-- The stand-in tiled wave-face foam tiles ($02/$07) over the whole sea
-- and drew the swell as two LOVE ellipses, which read as zigzag noise
-- with white blobs.  The fix ports SurfingMinigame_BGMetatileTable, the
-- WavePattern columns and the .WaveFunctions state table from
-- ../pokeyellow/engine/minigame/surfing_pikachu.asm; this driver
-- machine-checks the transcribed tables and the ride heights, then
-- parks a human in front of the water for the part only eyes can judge.
-- Needs a Yellow cache in the active identity (a sandboxed
-- POKEPORT_IDENTITY starts empty and would sit on the launcher).
--   SHOT_DIR=/tmp/shots POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 POKEPORT_DRIVER=tests/drivers/surfing_bg_bug726_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local SurfingMinigame = require("src.ui.SurfingMinigame")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- table integrity first, it needs no ROM state at all.  surf_1a is
  -- ripped as 65 tiles (src/import/RomExtractor.lua), so every tile id
  -- a metatile names must be 0..64, every pattern entry must name a
  -- metatile, and every wave state must name a pattern with plausible
  -- ride heights (the asm range is FLAT_WATER_Y $74 down to -6 tiles).
  local ok = true
  for id, mt in pairs(SurfingMinigame.BG_METATILES) do
    for i = 1, 4 do
      if type(mt[i]) ~= "number" or mt[i] < 0 or mt[i] > 64 then
        U.log("metatile", id, "slot", i, "has bad tile id", tostring(mt[i]))
        ok = false
      end
    end
  end
  check("every metatile tile id lands inside the 65-tile surf_1a sheet", ok)

  ok = true
  for id, pat in pairs(SurfingMinigame.WAVE_PATTERNS) do
    if #pat ~= 8 then ok = false U.log("pattern", id, "is not 8 rows") end
    for i = 1, 8 do
      if not SurfingMinigame.BG_METATILES[pat[i]] then
        U.log("pattern", id, "row", i, "names missing metatile",
              tostring(pat[i]))
        ok = false
      end
    end
  end
  check("every wave pattern row names a real metatile", ok)

  ok = true
  for id, step in pairs(SurfingMinigame.WAVE_STEPS) do
    if not SurfingMinigame.WAVE_PATTERNS[step[1]] then
      U.log("wave state", id, "names missing pattern", tostring(step[1]))
      ok = false
    end
    for i = 2, 3 do
      if step[i] < 116 - 6 * 8 or step[i] > 116 then
        U.log("wave state", id, "ride height", step[i], "out of range")
        ok = false
      end
    end
  end
  check("every wave state names a real pattern with sane ride heights", ok)

  -- pokeyellow data/maps/objects/SummerBeachHouse.asm: the Surfin' Dude
  -- is object_event 2, 3, so (2, 2) facing down talks to him.  He only
  -- offers the run to a party Pikachu that knows SURF.
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 50) }
  game.save.party[1].moves = { { id = "SURF", pp = 15 } }
  U.teleport(game, "SUMMER_BEACH_HOUSE", 2, 2, "down")
  U.wait(5)

  -- mash A through the pitch and the YES into the game itself
  local mg
  for _ = 1, 300 do
    local top = game.stack:top()
    if top and top.seaY then mg = top break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the minigame opened", mg ~= nil)
  if not mg then
    U.log("could not reach the minigame; nothing more to show")
    while true do coroutine.yield() end
  end

  -- the run opens on prefilled flat water: every visible column should
  -- be the open-water pattern, whose bottom rows are metatile $01
  -- (tile $0b everywhere), and Pikachu should sit on the flat waterline
  ok = true
  for c = 0, 10 do
    local col = mg.cols[c]
    if not (col and col.pat[8] == 0x01 and col.hl == 116) then ok = false end
  end
  check("the opening sea is flat open water, pattern 00 all the way", ok)
  check("Pikachu's ride line starts on the flat waterline",
        mg:seaY(68) == 100)
  U.shot(game, DIR .. "/bug726_1_flat.png")

  -- paddle up and ride until the generator has rolled some swells; the
  -- chooser leaves flat water only on a nonzero roll, so give it room
  for _ = 1, 8 do U.tap(game, "a") U.wait(3) end
  local sawSwell, seaTracks = false, true
  for _ = 1, 1500 do
    if mg.phase ~= "ride" and mg.phase ~= "air" then break end
    for c, col in pairs(mg.cols) do
      if col.hl < 116 then sawSwell = true end
    end
    -- the ride height must always come from the column under Pikachu
    local tile = math.floor((mg.distance + 68) / 8)
    local col = mg.cols[math.floor(tile / 2)]
    if col then
      local want = (tile % 2 == 0 and col.hl or col.hr) - 16
      if mg:seaY(68) ~= want then seaTracks = false end
    end
    if sawSwell and mg.distance > 400 then break end
    U.wait(1)
    if (U.frame() % 5) == 0 then U.tap(game, "a") end
  end
  check("the wave generator produced swells (ride heights above flat)",
        sawSwell)
  check("seaY always follows the generated column heights", seaTracks)
  U.shot(game, DIR .. "/bug726_2_swell.png")

  -- one jump for the air shot, then hand it over
  if mg.phase == "ride" then
    U.tap(game, "up")
    U.hold(game, "right", 20)
    U.shot(game, DIR .. "/bug726_3_air.png")
  end

  U.log("shots in", DIR, "- bug726_1_flat, bug726_2_swell, bug726_3_air")
  U.log("What to look for: the open sea is the flat speckled water tile,")
  U.log("not a diagonal zigzag field; no white ellipse blobs and no loose")
  U.log("blue squares floating on the surface; swells build from the left,")
  U.log("crest with foam and flatten out again; Pikachu sits on the wave")
  U.log("at every point of the swell; the HP strip sits in the bottom band")
  U.log("over unbroken white.  The game is still live: keep riding to the")
  U.log("goal and the sand should slide in under the coast-in before the")
  U.log("results card.")

  while true do
    coroutine.yield()
  end
end
