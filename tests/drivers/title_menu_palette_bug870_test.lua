-- Manual check of the title main menu + CONTINUE info box colors (#870):
-- both must follow the COLORS display mode (CLASSIC pea greens) instead of
-- staying a raw white trueColor hole, while gbc keeps #133's white paper /
-- black ink (pokered engine/menus/main_menu.asm RunDefaultPaletteCommand).
-- Palette shading is the moment under test, so POKEPORT_SPEED stays unset.
--   POKEPORT_DRIVER=tests/drivers/title_menu_palette_bug870_test.lua POKEPORT_IDENTITY=bug870 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local P = require("src.render.PaletteFX")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then fails = fails + 1 end
    return ok
  end

  -- Count near-white pixels in a captured frame.  CLASSIC's lightest shade
  -- is (155,188,15) and no blend of the four pea greens (or the letterbox)
  -- reaches 250+, so any white here can only be an unshaded region -- the
  -- exact white hole #870 is about.  Reads the PNG back through
  -- love.image so the check sees what actually hit the window.
  local function whiteCount(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local ok, img = pcall(function()
      return love.image.newImageData(
        love.filesystem.newFileData(bytes, "shot.png"))
    end)
    if not ok or not img then return nil end
    local n = 0
    for y = 0, img:getHeight() - 1 do
      for x = 0, img:getWidth() - 1 do
        local r, g, b = img:getPixel(x, y)
        if r > 0.98 and g > 0.98 and b > 0.98 then n = n + 1 end
      end
    end
    return n
  end

  -- A real save on disk first: hasSave in TitleState:openMenu checks the
  -- save FILE, not the in-memory table, and only then lists CONTINUE.
  -- No map coordinates anywhere in this test -- the bug lives on the title
  -- screen, before any map.
  U.newGame(game)
  check("reached the overworld", game.overworld ~= nil)
  check("save written so the menu lists CONTINUE",
        require("src.core.SaveData").save(game.save))

  -- flip COLORS the way the options screen does, then power-cycle to the
  -- title (returnToTitle skips the intro movie, unlike a cold boot)
  game.save.options.colors = "classic"
  P.applyOptions(game.save.options)
  game:returnToTitle()
  U.wait(30)

  local TitleState = require("src.ui.TitleState")
  local title = game.stack:top()
  check("back on the title screen", getmetatable(title) == TitleState)

  U.tap(game, "start")
  U.wait(10)
  local menu = game.stack:top()
  check("main menu opened and set a titleUiBox",
        menu ~= title and menu ~= nil and menu.titleUiBox ~= nil)

  -- The fix itself: the box overlay must be a GRAYS palette zone the shade
  -- shader runs on.  A colors == false zone would make Renderer:blitCanvas
  -- re-blit the rect with NO shader, so effectiveColors never substitutes
  -- the mono/inverted modes there -- the pre-#870 white hole.
  local zones = title.sgbPalettes and title:sgbPalettes(game)
  local boxZone, bare = nil, false
  for _, z in ipairs(zones or {}) do
    if z.colors == false then bare = true end
    if z.colors == P.GRAYS then boxZone = z end
  end
  check("no trueColor (colors == false) zone over the menu box", not bare)
  check("the titleUiBox rides a GRAYS palette zone", boxZone ~= nil)
  -- effectiveColors under classic substitutes CLASSIC; the trailing
  -- permute is the identity while no shade map is armed, so == holds
  check("CLASSIC substitutes the GRAYS box zone",
        P.effectiveColors(P.GRAYS) == P.CLASSIC)

  local shot1 = SHOT_DIR .. "/bug870_menu_classic.png"
  if U.shot(game, shot1) then
    local n = whiteCount(shot1)
    U.log("white pixels in the menu shot:", tostring(n))
    check("CLASSIC main menu shot has zero raw-white pixels",
          n ~= nil and n == 0)
  end

  -- with a save present CONTINUE is first, so the cursor is already on it
  U.tap(game, "a")
  U.wait(10)
  local info = game.stack:top()
  check("CONTINUE info box open with its titleUiBox",
        info ~= nil and info ~= menu and info.titleUiBox ~= nil
        and info.titleUiBox[1] == 4 and info.titleUiBox[2] == 7)

  local shot2 = SHOT_DIR .. "/bug870_info_classic.png"
  if U.shot(game, shot2) then
    local n = whiteCount(shot2)
    U.log("white pixels in the info shot:", tostring(n))
    check("CLASSIC CONTINUE info shot has zero raw-white pixels",
          n ~= nil and n == 0)
  end

  -- #133 regression gate: under gbc the GRAYS zone must pass through the
  -- shader unchanged, so the box comes back white paper / black ink while
  -- the LOGO zones keep the title colored around it
  P.applyOptions({ colors = "gbc" })
  U.wait(5)
  check("gbc leaves the GRAYS box zone alone (the #133 white box)",
        P.effectiveColors(P.GRAYS) == P.GRAYS)
  local shot3 = SHOT_DIR .. "/bug870_info_gbc.png"
  if U.shot(game, shot3) then
    local n = whiteCount(shot3)
    U.log("white pixels in the gbc shot:", tostring(n))
    check("gbc info box paper is white again", n ~= nil and n > 0)
  end

  -- the inverted modes must now invert the box with the screen too
  P.applyOptions({ colors = "og_inv" })
  U.wait(5)
  local inv = P.effectiveColors(P.GRAYS)
  check("OG INV inverts the box paper to black",
        inv ~= nil and inv[1] ~= nil and inv[1][1] == 0)
  U.shot(game, SHOT_DIR .. "/bug870_info_oginv.png")

  -- hand over in the bug's own mode
  game.save.options.colors = "classic"
  P.applyOptions(game.save.options)
  U.wait(2)

  U.log(fails == 0 and "PASS all machine checks"
        or ("FAIL " .. fails .. " machine check(s), see above"))
  U.log("The CONTINUE info box on screen is in CLASSIC now; its paper should")
  U.log("be the same pea green as the title behind it, with dark green ink,")
  U.log("just like the in-game START menu.  Before #870 this box and the")
  U.log("main menu were a pure white rectangle over the green title.")
  U.log("B backs out to the menu; OPTION flips COLORS to eyeball the rest.")

  while true do
    coroutine.yield()
  end
end
