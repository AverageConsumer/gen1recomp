-- Manual check of both bag-full pickup refusals (#872): an item ball must
-- refuse with _NoMoreRoomForItemText (pokered scripts/pick_up_item.asm
-- .BagFull), never the Toss-screen _CantCarryMoreText, and a hidden item
-- announces the find first, then _HiddenItemBagFullText (hidden_items.asm).
-- Run without POKEPORT_SPEED -- the box paging under test is timing-honest.
--   POKEPORT_DRIVER=tests/drivers/bag_full_pickup_bug872_test.lua POKEPORT_IDENTITY=bug872 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local Bag = require("src.inventory.Bag")
  local GameVersion = require("src.core.GameVersion")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local MAP = "VIRIDIAN_FOREST"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- neither refusal plays a jingle, but the human will want the normal
  -- pickup sound as a contrast, so warn when it would be muted
  local opts = game.save.options or {}
  if (opts.sfxVol or 7) == 0 then
    U.log("note: sfxVol is 0, so a successful pickup afterwards will be",
          "silent; the refusal boxes themselves are unaffected")
  end

  -- a real fresh game, so the save has a player name and clean flags
  U.newGame(game)
  local save = game.save

  -- Empty the bag, then refill to exactly capacity with ids that are NOT
  -- POTION: Bag.add succeeds by quantity for an id already in a slot
  -- (src/inventory/Bag.lua), which would mask the bug, and both test
  -- targets below hand out POTION.  Badges share save.inventory but are
  -- not bag slots, so they are left alone.
  for _, id in ipairs({ unpack(Bag.order(save)) }) do
    Bag.remove(save, id, save.inventory[id] or 1)
  end
  local ids = {}
  for id in pairs(game.data.items) do
    if not Bag.isBadge(id) and id ~= "POTION" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    if Bag.slots(save) >= Bag.capacity(game.data) then break end
    Bag.add(save, id, 1, game.data)
  end
  check(("bag is full (%d/%d slots) and holds no POTION")
          :format(Bag.slots(save), Bag.capacity(game.data)),
        Bag.slots(save) >= Bag.capacity(game.data)
        and not save.inventory.POTION)

  -- first target: the Potion item ball.  pokered
  -- data/maps/objects/ViridianForest.asm:36 puts it at walk cell (12, 29)
  -- (object_event 12, 29, SPRITE_POKE_BALL ... POTION), free floor below.
  local BALL = { x = 12, y = 29 }
  U.teleport(game, MAP, BALL.x, BALL.y + 1, "left")
  U.wait(10)

  local function isBall(n)
    return n and n.def and n.def.item and n.def.item ~= "0" and n.def.item ~= 0
  end
  local ow = game.overworld
  local ball = ow:npcAtCell(BALL.x, BALL.y)
  if not isBall(ball) then
    -- a map edit or mod moved the object: take any item ball on the map
    -- and stand on a free walkable neighbour instead
    ball = nil
    for _, n in ipairs(ow.npcs or {}) do
      if isBall(n) then ball = n break end
    end
    if ball then
      local sides = {
        { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
      }
      for _, s in ipairs(sides) do
        local cx, cy = ball.cellX + s[1], ball.cellY + s[2]
        if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
          U.log(("ball not at (%d, %d); using the one at (%d, %d)")
                  :format(BALL.x, BALL.y, ball.cellX, ball.cellY))
          -- teleport facing away, the tap below still does the turn
          U.teleport(game, MAP, cx, cy, s[3] == "left" and "right" or "left")
          U.wait(10)
          BALL.x, BALL.y = ball.cellX, ball.cellY
          break
        end
      end
    end
  end
  check("an item ball is loaded on " .. MAP, ball ~= nil)
  local ballItem = ball and ball.def.item or "POTION"

  -- turn toward the ball ourselves (a one-frame press only turns when the
  -- player faces elsewhere, src/world/Player.lua), then trigger the talk
  ow = game.overworld
  local dx, dy = BALL.x - ow.player.cellX, BALL.y - ow.player.cellY
  local dir = (dy < 0 and "up") or (dy > 0 and "down")
              or (dx < 0 and "left") or "right"
  U.tap(game, dir)
  U.wait(10)
  local fx, fy = game.overworld.player:facingCell()
  check("player turned to face the ball",
        game.overworld:npcAtCell(fx, fy) == ball)
  U.tap(game, "a")
  U.wait(30)

  local function readPages()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return nil end
    local pages = {}
    for _, page in ipairs(top.pages or {}) do
      pages[#pages + 1] = table.concat(page, " / ")
    end
    return pages
  end
  local function closeBox()
    for _ = 1, 8 do
      if getmetatable(game.stack:top()) ~= TextBox then break end
      U.tap(game, "a")
      U.wait(25)
    end
  end

  local pages = readPages()
  check("A on the full-bag ball opened a text box", pages ~= nil)
  if pages then
    local all = table.concat(pages, " || ")
    U.log("ball refusal reads:", all)
    check("it is the pickup refusal, not the Toss line",
          all:find("No more room", 1, true) ~= nil
          and all:find("can't carry", 1, true) == nil)
    if GameVersion.isYellow() then
      check("Yellow announces the find, then refuses on page 2",
            #pages == 2
            and pages[1]:find(ballItem, 1, true) ~= nil
            and pages[2]:find("No more room", 1, true) ~= nil)
    else
      check("Red/Blue refuse in one page with no found line",
            #pages == 1 and pages[1]:find("found", 1, true) == nil)
    end
    U.shot(game, SHOT_DIR .. "/bug872_ball_refusal.png")
  end
  closeBox()

  -- the refusal must leave the world untouched so the pickup can be
  -- retried after tossing something
  check("the ball is still standing there",
        game.overworld:npcAtCell(BALL.x, BALL.y) == ball)
  check("itemsTaken was not marked",
        not (save.itemsTaken and ball and save.itemsTaken[ball.id]))
  check("the item stayed out of the bag", not save.inventory[ballItem])

  -- second target: the hidden POTION.  pokered
  -- data/events/hidden_item_coords.asm:8 puts it at (x=1, y=18) on
  -- VIRIDIAN_FOREST; Game.data.field.hiddenItems carries the same spot.
  local hidden
  local list = (game.data.field.hiddenItems or {})[MAP] or {}
  for _, h in ipairs(list) do
    if h.x == 1 and h.y == 18 then hidden = h break end
  end
  hidden = hidden or list[1]
  check("a hidden item exists on " .. MAP, hidden ~= nil)

  local stood = false
  if hidden then
    -- {dx, dy, facing} from the hidden cell to a stand cell that looks
    -- back at it; the spot itself is usually an unwalkable tree tile
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = hidden.x + s[1], hidden.y + s[2]
      local m = game.overworld.map
      if m:isWalkableCell(cx, cy) and not game.overworld:npcAtCell(cx, cy) then
        U.teleport(game, MAP, cx, cy, s[3] == "left" and "right" or "left")
        U.wait(10)
        U.tap(game, s[3])
        U.wait(10)
        local hfx, hfy = game.overworld.player:facingCell()
        if hfx == hidden.x and hfy == hidden.y then stood = true break end
      end
    end
  end
  check("standing against the hidden spot", stood)

  U.tap(game, "a")
  U.wait(30)
  pages = readPages()
  check("A on the full-bag hidden spot opened a text box", pages ~= nil)
  if pages then
    local all = table.concat(pages, " || ")
    U.log("hidden refusal reads:", all)
    check("the found line comes first",
          #pages == 2 and pages[1]:find("found", 1, true) ~= nil
          and (not hidden or pages[1]:find(
                 (game.data.items[hidden.item] or {}).name or hidden.item,
                 1, true) ~= nil))
    check("then the hidden-item bag-full line, not the Toss line",
          #pages == 2
          and pages[2]:find("no more room", 1, true) ~= nil
          and pages[2]:find("other items", 1, true) ~= nil
          and all:find("can't carry", 1, true) == nil)
    U.shot(game, SHOT_DIR .. "/bug872_hidden_refusal.png")
  end
  closeBox()

  local key = hidden and (MAP .. "_" .. hidden.x .. "_" .. hidden.y)
  check("the hidden spot can still be prompted again",
        not (key and save.hiddenTaken and save.hiddenTaken[key]))
  check("the hidden item stayed out of the bag",
        not (hidden and save.inventory[hidden.item]))

  U.log("You are still facing the hidden spot with a full bag; pressing A")
  U.log("should say the item was found, then that there is no more room for")
  U.log("other items, and never the bag screen's \"can't carry\" wording.")
  U.log("Toss something and both spots should hand their item over normally.")

  while true do
    coroutine.yield()
  end
end
