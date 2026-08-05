-- The super effective / not very effective hit sounds played at the wrong
-- pitch, so the weak-sounding hit landed on the weakness (#826).  pokered
-- PlayApplyingAttackSound (engine/battle/animations.asm) sets
-- wFrequencyModifier with the sound, and audio/engine_2.asm
-- Audio2_ApplyFrequencyModifier adds it to the noise channel's polynomial
-- counter.  Ears only, so never under POKEPORT_SPEED -- the pitch is the test.
--   POKEPORT_DRIVER=tests/drivers/hit_sfx_bug826_test.lua POKEPORT_IDENTITY=bug826 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local ChipSynth = require("src.core.ChipSynth")
  local TypeChart = require("src.battle.TypeChart")
  local Sound = require("src.core.Sound")

  -- GOLEM is ROCK/GROUND, so one attacker covers both ends of the routine
  -- with no switching: WATER_GUN is 2x on each type and EMBER is 0.5x on
  -- ROCK.  SPLASH on the foe keeps the lead alive for as many replays as
  -- the listener wants.
  local FOE, FOE_LEVEL = "GOLEM", 60
  local LEAD, LEAD_LEVEL = "BULBASAUR", 25
  local WEAK_MOVE, STRONG_MOVE = "EMBER", "WATER_GUN"
  -- PlayApplyingAttackSound's wFrequencyModifier per sound, and the
  -- polynomial-counter byte of each program's first note (audio/sfx/
  -- {damage,super_effective,not_very_effective}.asm) before and after it.
  local SOUNDS = {
    { name = "Damage",             pitch = 0x20, raw = 0x44, want = 0x64 },
    { name = "Super_Effective",    pitch = 0xe0, raw = 0x34, want = 0x14 },
    { name = "Not_Very_Effective", pitch = 0x50, raw = 0x55, want = 0xa5 },
  }

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function hex(v) return v and ("$%02x"):format(v) or "nil" end

  -- ---- data the moment depends on ----------------------------------------
  local sfx = game.data.audio and game.data.audio.sfx or {}
  for _, row in ipairs(SOUNDS) do
    local def = sfx[row.name]
    check(row.name .. " resolves to a chip program in the generated audio",
          type(def) == "table" and def.address ~= nil and def.bank ~= nil)
  end
  local moveWeak, moveStrong = game.data.moves[WEAK_MOVE], game.data.moves[STRONG_MOVE]
  local foeDef = game.data.pokemon[FOE]
  check(WEAK_MOVE .. " and " .. STRONG_MOVE .. " resolve in the move table",
        moveWeak ~= nil and moveStrong ~= nil)
  check(FOE .. " resolves with a dual type", foeDef ~= nil and #foeDef.types == 2)
  local weakMult, strongMult
  if moveWeak and moveStrong and foeDef then
    weakMult = TypeChart.effectiveness(moveWeak.type, foeDef.types)
    strongMult = TypeChart.effectiveness(moveStrong.type, foeDef.types)
    U.log(("%s on %s is x%.1f, %s is x%.1f (the x10 scale Damage.lua uses)")
            :format(WEAK_MOVE, FOE, weakMult / 10, STRONG_MOVE, strongMult / 10))
  end
  check(WEAK_MOVE .. " is the resisted side of the pair", (weakMult or 10) < 10)
  check(STRONG_MOVE .. " is the super effective side", (strongMult or 10) > 10)

  local vol = game.save.options and game.save.options.sfxVol
  check("sfx volume is up (" .. tostring(vol) .. "/7)", (vol or 0) > 0)
  if (vol or 0) == 0 then
    U.log("with sfxVol 0 both hits are silent and this run proves nothing;",
          "raise it in OPTION and start over")
  end

  -- ---- the synth half: does the modifier reach the noise channel? ---------
  -- Sample each program once at offset 0 and again at its own modifier.  A
  -- port that drops wFrequencyModifier reports the same byte twice, which is
  -- the whole of #826: unpitched, Super_Effective ends duller than
  -- Not_Very_Effective ends.
  local function firstNoise(header, offset)
    if not header then return nil end
    local engine = ChipSynth.newEngine(game.data, header, {
      sfx = true, allowLoops = false, frequencyOffset = offset,
    })
    for _, channel in ipairs(engine.channels) do
      channel:sample()
      local event = channel.event
      if event and event.noiseParameter then return event.noiseParameter end
    end
    return nil
  end
  for _, row in ipairs(SOUNDS) do
    local bare = firstNoise(sfx[row.name], 0)
    local pitched = firstNoise(sfx[row.name], row.pitch)
    check(("%s reads NR43 %s unmodified, as in the asm")
            :format(row.name, hex(row.raw)), bare == row.raw)
    check(("...and %s once %s is applied"):format(hex(row.want), hex(row.pitch)),
          pitched == row.want)
    U.log(("%s: %s -> %s, shift clock %d -> %d (higher shift = duller)")
            :format(row.name, hex(bare), hex(pitched),
                    math.floor((bare or 0) / 16), math.floor((pitched or 0) / 16)))
  end

  -- ---- the battle half: what does a hit row actually carry? ---------------
  -- Offscreen scratch turn, no animation timing in the way.  The row has to
  -- name the sound AND its modifier byte, and must not carry a tempo byte:
  -- Audio2_note_length skips Audio2_SetSfxTempo on CHAN8 (`cp CHAN8 / jr z,
  -- .skip`), so the hardware never retimes these three.
  -- the move is handed in whole, so the party lead keeps both its slots for
  -- the live battle below
  local function rowSfx(moveId)
    local scratch = BattleState.newWild(game, FOE, FOE_LEVEL)
    scratch.onFinish = function() end
    -- Damage.accuracyRoll is `rng(0, 255) < acc` (src/battle/Damage.lua:105),
    -- so the roll has to be pinned LOW to guarantee a hit.  Pinning it high
    -- misses every time, the row never gets a .hit, and this scan reads nil.
    scratch.rng = function(lo) return lo end
    scratch:performMove(scratch.player, scratch.enemy, { id = moveId, pp = 20 })
    for _, row in ipairs(scratch.queue) do
      if row.hit and row.hit.sfx then return row.hit.sfx end
    end
    return nil
  end
  do
    local lead = Pokemon.new(game.data, LEAD, LEAD_LEVEL)
    lead.moves = {
      { id = WEAK_MOVE, pp = 25, maxPP = 25 },
      { id = STRONG_MOVE, pp = 25, maxPP = 25 },
    }
    game.save.party = { lead }
    for _, case in ipairs({
      { move = STRONG_MOVE, want = "Super_Effective", pitch = 0xe0 },
      { move = WEAK_MOVE, want = "Not_Very_Effective", pitch = 0x50 },
    }) do
      local row = rowSfx(case.move)
      check(case.move .. " queues a hit sound with its modifier",
            type(row) == "table" and row.sound == case.want
            and row.pitch == case.pitch)
      check("...and no tempo byte, the way CHAN8 ignores one",
            type(row) == "table" and row.tempo == nil)
      U.log(("%s -> %s pitch %s"):format(case.move,
            type(row) == "table" and tostring(row.sound) or tostring(row),
            type(row) == "table" and hex(row.pitch) or "nil"))
    end
  end

  -- ---- reach the moment ---------------------------------------------------
  -- ROUTE_1 is open field (data/generated/maps.lua ROUTE_1); the stand cell
  -- is read back off the loaded map, and a map edit degrades to the first
  -- free cell instead of dropping the player into a wall.
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local map = game.overworld.map
  if not map:isWalkableCell(5, 5) then
    local fx, fy
    for cy = 0, map.heightCells - 1 do
      for cx = 0, map.widthCells - 1 do
        if map:isWalkableCell(cx, cy) then fx, fy = cx, cy break end
      end
      if fx then break end
    end
    if fx then
      U.log("cell (5, 5) is not walkable, standing on", fx, fy)
      U.teleport(game, "ROUTE_1", fx, fy, "down")
      U.wait(10)
    end
  end
  local ow = game.overworld
  check("player stands on a walkable ROUTE_1 cell",
        ow.map:isWalkableCell(ow.player.cellX, ow.player.cellY))

  -- listen in on the real playback path so the log can tell "the fix is not
  -- wired to the battle" from "the fix is wired but you did not like it"
  local heard = {}
  local realPlayMove = Sound.playMove
  Sound.playMove = function(data, anim)
    if type(anim) == "table" and anim.sound then
      for _, row in ipairs(SOUNDS) do
        if anim.sound == row.name then
          heard[#heard + 1] = { sound = anim.sound, pitch = anim.pitch }
        end
      end
    end
    return realPlayMove(data, anim)
  end

  local function mashUntil(cond, max)
    for _ = 1, max or 160 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return cond()
  end

  local function newFight()
    local battle = BattleState.newWild(game, FOE, FOE_LEVEL)
    battle.onFinish = function(result) ow:afterBattle(result, battle) end
    -- SPLASH so the foe's turn cannot end the run, or drown the hit under a
    -- damage sound of its own
    battle.enemy.mon.moves = { { id = "SPLASH", pp = 40, maxPP = 40 } }
    battle.enemy.curMoves = battle.enemy.mon.moves
    ow:pushBattle(battle)
    U.wait(220) -- the send-out intro plays before the menu is reachable
    mashUntil(function() return battle.phase == "menu" end)
    return battle
  end

  local battle = newFight()
  check("the wild " .. FOE .. " battle reached its FIGHT menu",
        battle.phase == "menu")
  U.shot(game, DIR .. "/bug826_menu.png")

  -- slot 1 first: the resisted hit, so the pair is heard weak then strong
  local function swing(slotDown, label)
    local before = #heard
    U.tap(game, "a") -- FIGHT
    U.wait(16)
    if slotDown then U.tap(game, "down"); U.wait(8) end
    U.tap(game, "a")
    for frame = 1, 1200 do
      if battle.phase == "menu" and #battle.queue == 0 and not battle.draining then
        break
      end
      if not battle.draining and frame % 8 == 0 then U.tap(game, "a") end
      U.wait(1)
    end
    local row = heard[before + 1]
    U.log(("%s played %s at pitch %s"):format(label,
          row and row.sound or "nothing",
          row and hex(row.pitch) or "nil"))
    return row
  end

  local weakHeard = swing(false, WEAK_MOVE)
  U.shot(game, DIR .. "/bug826_not_very_effective.png")
  local strongHeard = swing(true, STRONG_MOVE)
  U.shot(game, DIR .. "/bug826_super_effective.png")
  check("the resisted hit reached the mixer as Not_Very_Effective $50",
        weakHeard ~= nil and weakHeard.sound == "Not_Very_Effective"
        and weakHeard.pitch == 0x50)
  check("the super effective hit reached it as Super_Effective $e0",
        strongHeard ~= nil and strongHeard.sound == "Super_Effective"
        and strongHeard.pitch == 0xe0)
  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))

  -- ---- hand the pad over --------------------------------------------------
  Sound.playMove = realPlayMove
  if battle.phase ~= "menu" then
    U.log("(the menu did not come back on its own: mash A to reach FIGHT)")
  end
  U.log("Both hits have already sounded once. GOLEM is still standing and")
  U.log("EMBER and WATER_GUN sit in slots 1 and 2, so play them back to back")
  U.log("as often as you like.")
  U.log("WATER_GUN, under \"It's super effective!\", should be the brighter")
  U.log("and sharper of the two -- a high crack. EMBER, under \"It's not very")
  U.log("effective...\", should be a low dull rumble underneath it.")
  U.log("The near miss to listen for: the two are close in brightness, or the")
  U.log("crack lands on EMBER and the thud on WATER_GUN. That is the modifier")
  U.log("going missing again, and it is what #826 sounded like.")
  U.log("The neutral hit changed too: any move that is neither, on any foe,")
  U.log("is now a shade duller than it used to be, and that is correct.")

  while true do
    coroutine.yield()
  end
end
