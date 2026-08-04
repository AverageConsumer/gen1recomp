-- Real-time check of the credits roll vs Music_Credits (#703).
-- The song is a fixed 5880-frame program (audio/music/credits.asm: tempo 140,
-- no loop), so on hardware it outlasts THE END by ~12s.  Our roll ran 135
-- frames short of pokered because Credits:update skipped DisplayCreditsMon's
-- three CreditsCopyTileMapToVRAM calls (each `jp Delay3`, 9 frames per mon
-- screen, 15 mon screens); that stretched the overhang to ~14.3s and made the
-- music look too fast.  This driver plays the whole roll in real time (~98s,
-- do NOT set POKEPORT_SPEED: the ear half needs the real clock), counts the
-- fixed frames itself, and leaves the screen on THE END with the theme still
-- going so a listener can judge the tail.
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/credits_overhang_bug703_test.lua POKEPORT_IDENTITY=bug703 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  if os.getenv("POKEPORT_SPEED") then
    U.log("warning: POKEPORT_SPEED is set; the listening half of this run",
          "is meaningless at any speed but 1")
  end
  local opts = game.save and game.save.options
  if opts and opts.musicVolume == 0 then
    U.log("warning: options music volume is 0, nothing will be audible")
  end

  -- the roll ends in an autosave; put the user's save back afterwards
  local prevSave = love.filesystem.read("save.lua")

  U.teleport(game, "HALL_OF_FAME", 4, 2, "right")
  game.save.party = { { species = "PIKACHU", level = 81 } }
  game.overworld.runner:run({ { "record_hall_of_fame" } })
  U.wait(2)

  -- A through the induction until the credits state is on top; the full
  -- hall-of-fame walk takes well over 60 taps, so give it real room
  local Credits = require("src.ui.Credits")
  local credits
  for _ = 1, 2000 do
    local top = game.stack:top()
    if getmetatable(top) == Credits then credits = top break end
    U.tap(game, "a")
    U.wait(2)
  end
  if not check("credits state reached", credits ~= nil) then
    while true do coroutine.yield() end
  end

  -- Frame accounting, one fixed step per sample.  From the frame Music_Credits
  -- starts (phase leaves "white") pokered reaches the end of THE END's fade at
  -- 128 + 35 screens + 16 + 20 = 5154 frames; the 15 mon screens each spend
  -- 9 frames in mon_prep (the Delay3 x3) before their 27-frame wipe.
  -- no screenshots inside this loop: U.shot yields extra fixed steps of its
  -- own and would silently skew the count
  local musicStart, theEndAt, prepFrames = nil, nil, 0
  for f = 1, 7000 do
    U.wait(1)
    local phase = credits.phase
    if not musicStart and phase ~= "white" then musicStart = f end
    if phase == "mon_prep" then prepFrames = prepFrames + 1 end
    if phase == "end_hold" then theEndAt = f break end
  end

  check("mon_prep ran 9 frames on each of the 15 mon screens (135 total)",
        prepFrames == 135)
  check("THE END finishes fading 5154 frames after the music starts",
        musicStart ~= nil and theEndAt ~= nil
          and theEndAt - musicStart == 5154)
  U.log("music started at driver frame", musicStart,
        "THE END done at", theEndAt, "mon_prep frames", prepFrames)
  U.shot(game, DIR .. "/bug703_the_end.png")

  -- Music_Credits is 5880 frames long, so from here the theme has
  -- 5880 - 5154 = 726 frames (~12.1s) left.  That overhang is authentic:
  -- the original does the same on hardware, and this fix only removed the
  -- extra 2.2s our shortened roll had added on top of it.
  U.log("listen: the theme should keep playing about 12 seconds past this")
  U.wait(726)
  U.log("the song should be ending right about now; silence after this",
        "point is correct, the program has no loop")
  U.wait(120)

  if prevSave then
    love.filesystem.write("save.lua", prevSave)
  else
    love.filesystem.remove("save.lua")
  end
  U.log("done; screen stays on THE END (A or B would soft-reset)")
  while true do
    coroutine.yield()
  end
end
