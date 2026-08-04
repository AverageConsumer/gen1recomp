-- Manual check that challenging a trainer by talking to them plays the
-- encounter sting (#764).  TalkToTrainer (pokered home/trainers.asm:88)
-- prints the before-battle text and then EngageMapTrainer ->
-- PlayTrainerMusic; the port only did that on the sight-line path, so a
-- trainer approached from the side or back went into battle in map music.
--   POKEPORT_DRIVER=tests/drivers/trainer_fanfare_bug764_test.lua POKEPORT_IDENTITY=bug764 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")

  -- pokered data/maps/objects/ViridianForest.asm: YOUNGSTER2 (the first
  -- Bug Catcher) stands at (30, 33) facing LEFT, so his sight line runs
  -- west; the cell below him, (30, 34), is outside it and lets us talk
  -- our way into the battle instead of being spotted.
  local MAP = "VIRIDIAN_FOREST"
  local TRAINER = "VIRIDIANFOREST_YOUNGSTER2"
  local STAND = { x = 30, y = 34, facing = "up" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- record every song the engine starts; wrapping keeps real playback so
  -- the human half of this check still has something to hear
  local Music = require("src.core.Music")
  local played = {}
  local realPlay = Music.play
  Music.play = function(data, song, ...)
    played[#played + 1] = song
    return realPlay(data, song, ...)
  end

  U.newGame(game)
  check("music volume is audible (save.options.musicVol)",
        (game.save.options.musicVol or 0) > 0)

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(30)

  local ow = game.overworld
  local npc
  for _, n in ipairs(ow and ow.npcs or {}) do
    if n.def and n.def.name == TRAINER then npc = n end
  end
  check("Bug Catcher object loaded on " .. MAP, npc ~= nil)
  if npc then
    check("standing on his blind side, facing him",
          ow:npcAtCell(ow.player:facingCell()) == npc)
    check("he did not spot us on the way in", not ow.engaging)
  end

  -- talk; the sting must start only once the before-battle text closes
  -- (TalkToTrainer prints first, then engages)
  played = {}
  U.tap(game, "a")
  U.wait(30)
  check("no sting while the dialogue is up", #played == 0)
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  U.shot(game, SHOT_DIR .. "/bug764_dialogue.png")

  -- close the text; a Bug Catcher is neither female-list nor evil-list,
  -- so PlayTrainerMusic lands on the male sting.  A presses both finish
  -- the typewriter and turn pages, so keep tapping until the sting lands
  -- or the drain gives up.
  local sting
  for _ = 1, 8 do
    U.tap(game, "a")
    U.wait(30)
    for _, song in ipairs(played) do
      if song:find("Music_Meet", 1, true) then sting = song end
    end
    if sting then break end
  end
  check("closing the text started an encounter sting", sting ~= nil)
  check("it is the male trainer sting", sting == "Music_MeetMaleTrainer")
  U.shot(game, SHOT_DIR .. "/bug764_transition.png")
  U.log("songs started since the A press:", table.concat(played, ", "))

  U.log("The Bug Catcher's line has just closed and the battle is opening.")
  U.log("You should have heard the male trainer sting begin the moment the")
  U.log("text box shut, carrying over the battle transition.  Before #764")
  U.log("the forest theme played straight through into the fight.  To hear")
  U.log("the sight path for comparison, lose or run, step west across his")
  U.log("eyeline, and the same sting should fire once at the \"!\" bubble.")

  while true do
    coroutine.yield()
  end
end
