-- pokeyellow engine/events/diploma2.asm:3
-- engine/printer/printer2.asm:1
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots2924"
  local failures = 0
  local function check(label, ok, detail)
    U.log((ok and "PASS " or "FAIL ") .. label .. (detail and ("  " .. detail) or ""))
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    U.log(failures == 0 and "DONE all checks passed"
                        or ("DONE " .. failures .. " check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
  end

  U.teleport(game, "VERMILION_GYM", 4, 14, "up")
  local ow = game.overworld or game.stack:top()
  local save = game.save
  save.player.name = "AAA"
  save.playTime = 12 * 3600 + 34 * 60
  save.surfingHighScore = 1234
  local mon = Pokemon.new(game.data, "PIKACHU", 25)
  save.party = { mon }

  local pages = game.data.field.yellowPages
  check("yellowPages in cache", pages and pages.diploma and pages.hiScore and pages.monStats)
  check("trash table in cache",
    #(game.data.field.hiddenExtras.trashCans.yellowTable or {}) == 0x280)

  local function page(drawFn)
    return { isOpaque = true, update = function() end, draw = drawFn }
  end
  local Diploma = require("src.ui.Diploma")
  game.stack:push(Diploma.new(game))
  U.wait(3)
  check("diploma top", U.still(game, SHOT_DIR .. "/2924_01_yellow_diploma_top.png"))
  game.stack:pop()
  game.stack:push(page(function()
    love.graphics.push()
    love.graphics.translate(0, -144)
    Diploma.renderPrint(game)
    love.graphics.pop()
  end))
  U.wait(3)
  check("diploma bottom", U.still(game, SHOT_DIR .. "/2924_02_yellow_diploma_bottom.png"))
  game.stack:pop()
  local SurfHiScore = require("src.ui.SurfHiScore")
  game.stack:push(SurfHiScore.new(game))
  U.wait(3)
  check("hi-score page", U.still(game, SHOT_DIR .. "/2943_01_hiscore_page.png"))
  game.stack:pop()
  local PrinterMonStats = require("src.ui.PrinterMonStats")
  game.stack:push(page(function() PrinterMonStats.render(game, mon) end))
  U.wait(3)
  check("fan club portrait", U.still(game, SHOT_DIR .. "/2958_01_fanclub_portrait.png"))
  game.stack:pop()

  local flags = save.flags
  local allowed = { [1] = true, [3] = true }
  local ok = true
  for _ = 1, 40 do
    flags.EVENT_1ST_LOCK_OPENED, flags.EVENT_2ND_LOCK_OPENED = nil, nil
    save.trashPuzzle = { first = 0 }
    ow:trashCanSwitch(0)
    while game.stack:top() ~= ow do game.stack:pop() end
    local s = save.trashPuzzle.second
    if not (type(s) == "table" and allowed[s[1]] and (allowed[s[2]] or s[2] == 255)) then
      ok = false
    end
  end
  check("top-left can: second switch is below or right", ok)
  flags.EVENT_1ST_LOCK_OPENED, flags.EVENT_2ND_LOCK_OPENED = true, nil
  save.trashPuzzle = { first = 0, second = { 1, 3 } }
  ow:trashCanSwitch(3)
  while game.stack:top() ~= ow do game.stack:pop() end
  check("second entry of the pair opens the lock", flags.EVENT_2ND_LOCK_OPENED == true)
  flags.EVENT_1ST_LOCK_OPENED, flags.EVENT_2ND_LOCK_OPENED = true, nil
  save.trashPuzzle = { first = 0, second = { 1, 3 } }
  ow:trashCanSwitch(0)
  while game.stack:top() ~= ow do game.stack:pop() end
  check("same can resets the locks", not flags.EVENT_1ST_LOCK_OPENED)
  finish()
end
