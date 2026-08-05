-- Manual check that a Pikachu taking the field says the short "Pika!" (#837).
-- pokeyellow engine/battle/core.asm SendOutMon .starterPikachu (:1807-1817)
-- voices PikachuCry11, or PikachuCry37 when IsPlayerPikachuAsleepInParty; the
-- port called PlayCry bare and got clip 1, the long title "Pikachuuu"
-- (engine/movie/title.asm:146).  Never add POKEPORT_SPEED here: it scales the
-- logic clock and not audio, so the cries stop lining up with what you see.
--   POKEPORT_DRIVER=tests/drivers/pika_entrance_cry_bug837_test.lua POKEPORT_IDENTITY=bug837 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Sound = require("src.core.Sound")
  local GameVersion = require("src.core.GameVersion")
  local BattleState = require("src.battle.BattleState")

  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function idle()
    while true do coroutine.yield() end
  end

  -- Red and Blue carry no PCM clips at all (RomExtractor extractPikachuCries
  -- only runs on Yellow), so playPikaCry returns nil there and every Pikachu
  -- keeps its chip cry from CryData: nothing below is observable off Yellow.
  local audio = game.data.audio
  local clips = audio and audio.pikaCries
  local onYellow = check("running Yellow", GameVersion.isYellow())
  local haveClips = check("the cache carries the PCM clip set",
                          type(clips) == "number")
  if not (onYellow and haveClips) then
    U.log("Import a Yellow ROM and rerun with POKEPORT_VERSION=yellow.  On Red")
    U.log("and Blue there is no voiced Pikachu to get wrong.")
    idle()
  end
  -- NUM_PIKA_CRIES is 42 (pokeyellow constants/music_constants.asm), and the
  -- importer writes cry_01..cry_42.wav in PikachuCriesPointerTable order, so
  -- clip 37 existing is what makes the asleep case reachable at all.
  check("clip 37 fits inside the " .. tostring(clips) .. " clips extracted",
        clips >= 37)

  -- resolve the two asset keys for real: a missing or unreadable wav makes
  -- playPikaCry return nil and the cry falls through to the chip cry, which
  -- is a different wrong sound from the one this issue is about.  Stopped in
  -- the same frame, so neither is audible here.
  local function resolves(n)
    local src = Sound.playPikaCry(game.data, n)
    if src then src:stop() end
    return src ~= nil
  end
  check("pika_cries/cry_11.wav loads", resolves(11))
  check("pika_cries/cry_37.wav loads", resolves(37))

  local opts = game.save.options or {}
  check("sfxVol is not muted (it reads " .. tostring(opts.sfxVol) .. ")",
        (opts.sfxVol or 0) > 0)
  check("PIKACHU VOL is not muted (it reads " .. tostring(opts.pikaVol) .. ")",
        (opts.pikaVol or 0) > 0)

  -- Sound.playPikaCry emits "sound.played" with name = "PIKACHU_PCM_<n>";
  -- this is the same feed mods read and tests/mod_audio_tests.lua subscribes
  -- to, so the number below is the clip the engine actually asked for.
  local heardCries = {}
  local events = game.mods and game.mods.events
  if not check("the sound.played feed is live", events ~= nil and events.on ~= nil) then
    idle()
  end
  events:on("sound.played", function(p)
    if p and p.kind == "cry" then heardCries[#heardCries + 1] = p.name end
  end, nil, "bug837driver")

  game.save.party = {
    Pokemon.new(game.data, "PIKACHU", 20),
    Pokemon.new(game.data, "CHARMANDER", 20),
  }
  game.save.player.name = "RED"
  check("PIKACHU leads the party", game.save.party[1].species == "PIKACHU")

  -- Route 1 so the handoff below has tall grass in reach.  The route sign
  -- sits at (9, 27) (pokered data/maps/objects/Route1.asm bg_event), and the
  -- cell under it is the open path you read it from.
  local MAP = "ROUTE_1"
  local STAND = { x = 9, y = 28, facing = "up" }
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  if not check("the overworld is up on " .. MAP, ow ~= nil) then idle() end

  -- a map edit or a mod can wall that cell off; widen out to any free
  -- walkable neighbour rather than stranding the player inside scenery
  local function freeNear(map, x, y)
    for r = 1, 6 do
      for dy = -r, r do
        for dx = -r, r do
          local cx, cy = x + dx, y + dy
          if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)
             and not ow:npcAtCell(cx, cy) then
            return cx, cy
          end
        end
      end
    end
    return nil
  end
  if not ow.map:isWalkableCell(STAND.x, STAND.y) then
    local cx, cy = freeNear(ow.map, STAND.x, STAND.y)
    if cx then
      U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
            cx, cy)
      U.teleport(game, MAP, cx, cy, STAND.facing)
      U.wait(10)
      ow = game.overworld
    end
  end
  check("the player is standing somewhere walkable",
        ow.map:isWalkableCell(ow.player.cellX, ow.player.cellY))

  -- Push the encounter rather than walking into grass: the cry under test is
  -- the player's own send-out, and a stepped encounter would put the wild
  -- rolls and a second cry ahead of it.  RATTATA keeps the enemy's cry a chip
  -- cry, so it can never be confused with the PCM clip being checked.
  local function runEntrance(asleep, label, shotPath)
    for i = #heardCries, 1, -1 do heardCries[i] = nil end
    game.save.party[1].status = asleep and "SLP" or nil
    local wild = BattleState.newWild(game, "RATTATA", 3)
    wild.onFinish = function() end
    game.overworld:pushBattle(wild)
    local pcm
    for _ = 1, 500 do
      for _, name in ipairs(heardCries) do
        if name:find("PIKACHU_PCM_", 1, true) == 1 then pcm = name end
      end
      if pcm then break end
      U.tap(game, "a")
      U.wait(3)
    end
    U.log(label .. " recorded:", table.concat(heardCries, ", "))
    if shotPath then U.shot(game, shotPath) end
    return pcm, wild
  end

  -- asleep first, so the run ends on the everyday case and what is ringing
  -- during the handoff is the clip the issue is really about
  local slept = runEntrance(true, "asleep send-out",
                            DIR .. "/bug837_1_asleep.png")
  check("an asleep PIKACHU is sent out with PCM clip 37 (PikachuCry37)",
        slept == "PIKACHU_PCM_37")

  U.teleport(game, MAP, ow.player.cellX, ow.player.cellY, STAND.facing)
  U.wait(10)
  local awake = runEntrance(false, "awake send-out",
                            DIR .. "/bug837_2_awake.png")
  check("a healthy PIKACHU is sent out with PCM clip 11 (PikachuCry11)",
        awake == "PIKACHU_PCM_11")
  check("clip 1, the long title-screen cry, is not what was played",
        awake ~= "PIKACHU_PCM_1")

  U.log("You are in the second battle, the one with PIKACHU awake.  The cry")
  U.log("as it grew out of the ball should be the short bright \"Pika!\", the")
  U.log("same one you hear pressing START on the Yellow title screen.  The bug")
  U.log("played the other title cry instead: the long drawn-out \"Pikachuuu\"")
  U.log("that opens the title, roughly a second and a half of it, which is")
  U.log("easy to miss as merely slow rather than wrong.  Run away and walk")
  U.log("into the grass north of here for as many more send-outs as you like;")
  U.log("put PIKACHU to sleep and it turns into the sleepy clip 37 instead.")
  U.log("Screenshots of both entrances are in " .. DIR .. ".")

  idle()
end
