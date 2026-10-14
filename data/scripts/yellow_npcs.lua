local M = {}

local function push(game, text, done, opts)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, text, done, opts))
end

local function happiness(game)
  return game.save.pikachuHappiness or 90
end

-- home/map_objects.asm:114
local function starterAlive(game)
  local Follower = require("src.world.PikachuFollower")
  for _, mon in ipairs(game.save.party or {}) do
    if Follower.isStarterPikachu(game.save, mon) and (mon.hp or 0) > 0 then
      return true
    end
  end
  return false
end

local function run(ow, rows, npc, done)
  ow.runner:run(rows, { npc = npc, onDone = done })
end

local function ownedCount(game)
  local owned = 0
  local dex = game.save.pokedex
  for _ in pairs(dex and dex.owned or {}) do owned = owned + 1 end
  return owned
end

local sharedChairman = require("data.scripts.story2")
  .POKEMON_FAN_CLUB.talk.TEXT_POKEMONFANCLUB_CHAIRMAN

M.PEWTER_POKECENTER = {
  talk = {
    -- scripts/PewterPokecenter_2.asm:1
    TEXT_PEWTERPOKECENTER_COOLTRAINER_F = {
      { "face_player" },
      { "show_text", "_PewterPokecenterText3" },
    },
  },
}

-- scripts/CeladonMansion1F_2.asm:47
local GRANNY_BANDS = {
  { 51, "_CeladonMansion1Text7" }, { 101, "_CeladonMansion1Text8" },
  { 131, "_CeladonMansion1Text9" }, { 161, "_CeladonMansion1Text10" },
  { 201, "_CeladonMansion1Text11" }, { 255, "_CeladonMansion1Text12" },
}

M.CELADON_MANSION_1F = {
  talk = {
    -- scripts/CeladonMansion1F.asm:20
    TEXT_CELADONMANSION1F_GRANNY = function(game, ow, npc, done)
      local rows = { { "face_player" },
                     { "show_text", "_CeladonMansion1Text2" } }
      local cry = false
      if starterAlive(game) then
        local h = happiness(game)
        local band = "_CeladonMansion1Text12"
        for _, b in ipairs(GRANNY_BANDS) do
          if h < b[1] then band = b[2] break end
        end
        rows[#rows + 1] = { "show_text", "_CeladonMansion1Text6" }
        rows[#rows + 1] = { "show_text", band }
      end
      -- scripts/CeladonMansion1F.asm:24
      if happiness(game) >= 251 then
        cry = true
        rows[#rows + 1] = { "wait", 50 }
      end
      run(ow, rows, npc, function()
        if cry then
          require("src.core.Sound").playCry(game.data, "PIKACHU", 23)
        end
        if done then done() end
      end)
    end,
  },
}

M.MUSEUM_2F = {
  talk = {
    -- scripts/Museum2F.asm:31
    TEXT_MUSEUM2F_HIKER = function(game, ow, npc, done)
      local key = "_Museum2FHikerText"
      if starterAlive(game) then
        key = happiness(game) >= 101 and "_Museum2FPikachuText2"
          or "_Museum2FPikachuText1"
      end
      run(ow, { { "face_player" }, { "show_text", key } }, npc, done)
    end,
  },
}

M.PEWTER_GYM = {
  talk = {
    -- scripts/PewterGym.asm:181
    TEXT_PEWTERGYM_GYM_GUIDE = function(game, ow, npc, done)
      local rows = { { "face_player" } }
      if game.save.flags.EVENT_BEAT_BROCK then
        rows[#rows + 1] = { "show_text", "_PewterGymGuidePostBattleText" }
        return run(ow, rows, npc, done)
      end
      rows[#rows + 1] = { "ask", "_PewterGymGuidePreAdviceText" }
      rows[#rows + 1] = { "jump_if_false", "free" }
      if starterAlive(game) then
        -- scripts/PewterGym.asm:193
        rows[#rows + 1] = { "show_text", "_PewterGymGuyText" }
        rows[#rows + 1] = { "jump", "end" }
      else
        rows[#rows + 1] = { "show_text", "_PewterGymGuideBeginAdviceText" }
        rows[#rows + 1] = { "jump", "advice" }
      end
      rows[#rows + 1] = { "label", "free" }
      rows[#rows + 1] = { "show_text", "_PewterGymGuideFreeServiceText" }
      rows[#rows + 1] = { "label", "advice" }
      rows[#rows + 1] = { "show_text", "_PewterGymGuideAdviceText" }
      rows[#rows + 1] = { "label", "end" }
      run(ow, rows, npc, done)
    end,
  },
}

M.CELADON_MANSION_3F = {
  talk = {
    -- scripts/CeladonMansion3F.asm:23
    TEXT_CELADONMANSION3F_PROGRAMMER = function(game, ow, npc, done)
      local key = ownedCount(game) >= 150 and "_CeladonMansion3FProgrammerText2"
        or "_CeladonMansion3FProgrammerText"
      run(ow, { { "face_player" }, { "show_text", key } }, npc, done)
    end,
    -- scripts/CeladonMansion3F.asm:104
    TEXT_CELADONMANSION3F_WRITER = function(game, ow, npc, done)
      local key = ownedCount(game) >= 150 and "_CeladonMansion3FWriterText2"
        or "_CeladonMansion3FWriterText"
      run(ow, { { "face_player" }, { "show_text", key } }, npc, done)
    end,
  },
}

local function fanText(yellowKey, ownBoast, otherBoast, normalKey, betterKey)
  return function(game, ow, npc, done)
    local flags = game.save.flags
    local rows = { { "face_player" } }
    if flags.EVENT_LEFT_FANCLUB_AFTER_BIKE_VOUCHER then
      rows[#rows + 1] = { "show_text", yellowKey }
    elseif flags[ownBoast] then
      rows[#rows + 1] = { "clear_flag", ownBoast }
      rows[#rows + 1] = { "show_text", betterKey }
    else
      rows[#rows + 1] = { "set_flag", otherBoast }
      rows[#rows + 1] = { "show_text", normalKey }
    end
    run(ow, rows, npc, done)
  end
end

local function printPortrait(game, mon)
  local Printer = require("src.core.Printer")
  local Strings = require("src.core.Strings")
  -- engine/printer/printer.asm:345
  local saved, err = Printer.save("fanclub_portrait", 160, 144, function()
    require("src.ui.PrinterMonStats").render(game, mon)
  end)
  return saved and (Strings("Printed!\f") .. Printer.savedWhereText(saved))
    or Strings("Printer error!\n%s", tostring(err))
end

M.POKEMON_FAN_CLUB = {
  talk = {
    -- scripts/PokemonFanClub.asm:81
    TEXT_POKEMONFANCLUB_CLEFAIRY_FAN = fanText("_PokemonFanClubClefairyFanText",
      "EVENT_PIKACHU_FAN_BOAST", "EVENT_SEEL_FAN_BOAST",
      "_PokemonFanClubClefairyFanNormalText", "_PokemonFanClubClefairyFanBetterText"),
    -- scripts/PokemonFanClub.asm:115
    TEXT_POKEMONFANCLUB_SEEL_FAN = fanText("_PokemonFanClubSeelFanText",
      "EVENT_SEEL_FAN_BOAST", "EVENT_PIKACHU_FAN_BOAST",
      "_PokemonFanClubSeelFanNormalText", "_PokemonFanClubSeelFanBetterText"),
    -- scripts/PokemonFanClub.asm:175
    TEXT_POKEMONFANCLUB_CHAIRMAN = function(game, ow, npc, done)
      if not game.save.flags.EVENT_LEFT_FANCLUB_AFTER_BIKE_VOUCHER then
        return run(ow, sharedChairman, npc, done)
      end
      local t = game.data.text
      if npc and npc.facePlayer then npc:facePlayer(ow.player) end
      local function finish(key)
        push(game, t[key], done)
      end
      push(game, t.FanClubChairPrintText1, nil, { choice = function(yes)
        if not yes then return finish("FanClubChairPrintText2") end
        local PartyMenu = require("src.ui.PartyMenu")
        game.stack:push(PartyMenu.new(game, {
          pickOnly = true,
          onCancel = function() finish("FanClubChairPrintText2") end,
          onSwitch = function(mon)
            push(game, printPortrait(game, mon), function()
              finish("FanClubChairPrintText3")
            end)
          end,
        }))
      end })
    end,
  },
  -- engine/events/hidden_events/fanclub_pictures.asm:1
  onInteract = function(game, ow, fx, fy)
    if fy ~= 0 or (fx ~= 1 and fx ~= 6) then return false end
    local species = fx == 1 and "RAPIDASH" or "FEAROW"
    local key = fx == 1 and "_FanClubPicture1Text" or "_FanClubPicture2Text"
    local def = game.data.pokemon[species]
    local PicBox = require("src.ui.PicBox")
    game.stack:push(PicBox.new(game, def and def.spriteFront or "",
      game.data.text[key]))
    return true
  end,
}

return M
