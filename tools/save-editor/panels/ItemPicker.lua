-- Type-to-search item picker: the items panel's answer to the species
-- picker (panels/SpeciesPicker.lua), and built to the same shape on purpose.
--
-- Adding an item used to mean an inline catalog card wedged into the Items
-- tab: a search field and a scrolling list competing for height with the bag
-- and PC lists beside it, which on a phone left about three rows visible.
-- Adding a Pokemon was already a full-screen modal with the whole window to
-- work with, and there was no reason for the two to differ.
--
-- Modal is literal.  Kit hit-tests without a z-order, so App.draw raises
-- Kit.blockClicks over the chrome and the panel while this is open and lowers
-- it only for this overlay; nothing underneath can take the same tap.

local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local Picker = {}

local FIELD_ID = "item-picker"

function Picker.results(S)
  local p = S.itemPicker
  return Ops.itemSearch(S, p and p.query or "")
end

-- Enter commits the top match into whichever destination the picker was
-- opened for, which is the whole point of a search field.
function Picker.commitFirst(S, Kit)
  local hits = Picker.results(S)
  if not hits[1] then return Ops.say(S, "No item matches that") end
  return Picker.commit(S, Kit, hits[1])
end

-- One funnel for both destinations.  The picker stays OPEN after a commit:
-- stocking a save means adding several items in a row, and reopening the
-- modal per item is the kind of friction the inline card at least did not
-- have.  Escape / Close / tap-outside is the way out.
function Picker.commit(S, Kit, id)
  local p = S.itemPicker
  local dest = (p and p.dest) or "bag"
  if dest == "pc" then return Ops.addToPc(S, id) end
  return Ops.addToBag(S, id)
end

function Picker.draw(S, Kit, width, height)
  local p = S.itemPicker
  if not p then return end
  local s = Kit.scale

  -- The click that opened the picker is still the frame's click: the panel
  -- dispatches earlier in App.draw than this overlay does, so without
  -- swallowing it the scrim below would read it as a tap outside and shut the
  -- picker in the same frame it went up.
  if p.opened then
    p.opened = nil
    Kit.blockClicks = true
  end

  -- the scrim doubles as the "tap outside to cancel" target
  Theme.col(PAL.bg, 0.82)
  love.graphics.rectangle("fill", 0, 0, width, height)

  local w = math.min(width - 32 * s, 520 * s)
  local h = math.min(height - 32 * s, 560 * s)
  local x = (width - w) / 2
  local y = (height - h) / 2
  if Kit.press(0, 0, width, height) and not Kit.hit(x, y, w, h) then
    Ops.closeItemPicker(S, Kit)
    return
  end

  Kit.card(x, y, w, h)
  local pad = 18 * s
  local cx, cy = x + pad, y + pad
  local inner = w - 2 * pad

  Kit.caption(cx, cy, "ADD AN ITEM")
  local closeW = 30 * s
  if Kit.button(x + w - pad - closeW, cy - 4 * s, closeW, 26 * s, "x",
      { font = "small" }) then
    Ops.closeItemPicker(S, Kit)
    return
  end
  cy = cy + Kit.textHeight("caption") + 10 * s

  -- Destination toggle.  Which list an item lands in is the only real choice
  -- here, so it is a pair of chips at the top rather than two buttons at the
  -- bottom that each mean "commit, and also pick a destination".
  local half = (inner - 8 * s) / 2
  local destH = 30 * s
  if Kit.chip(cx, cy, half, destH, "-> BAG", p.dest ~= "pc", PAL.green, PAL.steel) then
    p.dest = "bag"
  end
  if Kit.chip(cx + half + 8 * s, cy, half, destH, "-> PC", p.dest == "pc",
      PAL.green, PAL.steel) then
    p.dest = "pc"
  end
  cy = cy + destH + 10 * s

  local fieldH = 34 * s
  p.query = Kit.textfield(FIELD_ID, cx, cy, inner, fieldH, p.query,
    "type an item id")
  cy = cy + fieldH + 10 * s

  local hits = Picker.results(S)
  local rowH = 36 * s
  local rowGap = 6 * s
  local pagerH = 30 * s
  local listH = (y + h - pad - pagerH - 10 * s) - cy
  local perPage = math.max(1, math.floor((listH + rowGap) / (rowH + rowGap)))
  p.offset = Theme.clamp(p.offset or 0, 0, math.max(0, #hits - perPage))
  -- wheel / touch drag scroll the modal list too; the shield is already
  -- lowered for this layer, so Kit.scroll works here and only here
  p.offset = Kit.scroll(cx, cy, inner, listH, p.offset, #hits, perPage)

  if #hits == 0 then
    Kit.emptyBox(cx, cy, inner, listH, "Nothing matches that.")
  else
    Kit.pushClip(cx, cy, inner, listH)
    for i = 1, perPage do
      local id = hits[p.offset + i]
      if not id then break end
      local ry = cy + (i - 1) * (rowH + rowGap)
      if Kit.row(cx, ry, inner, rowH, false, PAL.green, 9 * s) then
        Picker.commit(S, Kit, id)
      end
      -- how many the save already holds, so a second add is an informed one
      local have = (S.save.inventory and S.save.inventory[id])
        or (Ops.pcItems(S) or {})[id]
      local tail = have and ("x%d"):format(have) or ""
      local tailW = Kit.textWidth("tiny", tail)
      Kit.text("monoRow",
        Kit.ellipsize("monoRow", id, inner - tailW - 30 * s), cx + 10 * s,
        ry + (rowH - Kit.textHeight("monoRow")) / 2, PAL.text)
      if tail ~= "" then
        Kit.textRight("tiny", tail, cx + inner - 10 * s,
          ry + (rowH - Kit.textHeight("tiny")) / 2, PAL.caption)
      end
    end
    Kit.popClip()
    Kit.scrollbar(cx, cy, inner, listH, p.offset, #hits, perPage)
  end

  p.offset = Kit.pager(cx, y + h - pad - pagerH, inner, p.offset, #hits, perPage)
end

return Picker
