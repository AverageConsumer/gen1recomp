-- Manual check that Silph Co Giovanni gets the ordinary trainer theme (#782).
-- PlayBattleMusic (audio/play_battle_music.asm) only picks
-- MUSIC_GYM_LEADER_BATTLE when wGymLeaderNo is set, and scripts/SilphCo11F.asm
-- never writes it -- only the eight gym scripts do.  The port keyed the boss
-- check on the trainer class alone, so this fight (OPP_GIOVANNI#2) borrowed
-- the Viridian Gym roster's theme, victory jingle, and Pikachu happiness bump.
-- The data half is asserted in tests/parity_battle_music_bug782.lua.
--   POKEPORT_DRIVER=tests/drivers/battle_music_bug782_test.lua POKEPORT_IDENTITY=bug782 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Music = require("src.core.Music")
  local BattleState = require("src.battle.BattleState")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local vol = game.save.options and game.save.options.musicVol
  if vol == 0 then
    U.log("music volume is 0 in options; raise it or nothing will be audible")
  end

  -- record what the engine asks the music system for; the real playback
  -- still happens underneath, so the listening half is unaffected
  local played = {}
  local realPlayBattle = Music.playBattle
  Music.playBattle = function(data, kind, trainerId)
    played[#played + 1] = { call = "battle", kind = kind }
    return realPlayBattle(data, kind, trainerId)
  end
  local realPlayVictory = Music.playVictory
  Music.playVictory = function(data, kind, trainerId)
    played[#played + 1] = { call = "victory", kind = kind }
    return realPlayVictory(data, kind, trainerId)
  end

  -- a party that can win this quickly, so the victory jingle is reachable
  game.save.party = {
    Pokemon.new(game.data, "MEWTWO", 90),
    Pokemon.new(game.data, "CHARIZARD", 80),
  }
  game.save.player.name = "RED"

  -- Giovanni's fight is a coordinate trigger, not a talk:
  -- SilphCo11FDefaultScript (pokered scripts/SilphCo11F.asm
  -- .PlayerCoordsArray) fires on (6,13) or (7,12), walks him three tiles
  -- down from his object_event spot at (6,9)
  -- (pokered data/maps/objects/SilphCo11F.asm), shows his speech and starts
  -- the battle.  The (6,13) pad sits behind the 11F card key door, which this
  -- teleported-in save has not opened (no CARD KEY, so tryCardKeyDoor never
  -- swaps the door block), so take the pad on the open side: stand on (6,12)
  -- and step east onto (7,12).
  U.teleport(game, "SILPH_CO_11F", 6, 12, "right")
  U.wait(10)
  U.hold(game, "right", 40)
  U.wait(10)

  -- Giovanni's approach, then his pre-battle text box: mash A until the
  -- battle state is on top of the stack
  local battle
  for _ = 1, 400 do
    local top = game.stack:top()
    if getmetatable(top) == BattleState and top.kind == "trainer" then
      battle = top
      break
    end
    U.tap(game, "a")
    U.wait(3)
  end

  check("the coordinate trigger engaged a trainer battle", battle ~= nil)
  if battle then
    check("the opponent is Giovanni (OPP_GIOVANNI#2)",
          battle.oppClass == "OPP_GIOVANNI" and battle.partyIndex == 2)
    check("musicKind is \"trainer\", not \"gym\"",
          battle.musicKind == "trainer")
    check("isGymLeader is unset (no Pikachu GYMLEADER happiness bump)",
          not battle.isGymLeader)
    local battleCall
    for _, p in ipairs(played) do
      if p.call == "battle" then battleCall = p.kind end
    end
    check("Music.playBattle was asked for the trainer theme",
          battleCall == "trainer")
  end

  U.log("You are in the Silph Co Giovanni fight.  The theme playing now")
  U.log("should be the ordinary Vs. Trainer battle music, not the gym-leader")
  U.log("theme this fight used to borrow.  Win it (MEWTWO 90 vs his level")
  U.log("~40 party) and the jingle at \"defeated GIOVANNI\" should be the")
  U.log("plain trainer victory fanfare, again not the gym-leader one.")
  U.log("For the correct-by-contrast case, the Viridian Gym rematch")
  U.log("(OPP_GIOVANNI#3) still keeps the gym-leader theme.")

  -- report the victory request when the win lands, then keep idling
  local reported = false
  while true do
    if not reported then
      for _, p in ipairs(played) do
        if p.call == "victory" then
          check("Music.playVictory was asked for the trainer jingle",
                p.kind == "trainer")
          reported = true
        end
      end
    end
    coroutine.yield()
  end
end
