-- The launcher's UI kit: pagination bounds, viewport-derived page size, and
-- the text safety rules.  These replace the two FlexLove engine tests
-- (flexlove_wheel_scroll_dt0, launcher_save_slot_overlap_bug748), whose
-- subjects -- a scroll manager fed dt = 0 and an auto-height propagation bug
-- -- no longer exist: there is no scrolling and no layout engine.
--
-- What DOES need guarding now is the property the whole performance claim
-- rests on: a list draws at most one page of rows regardless of how many
-- items it holds, and the page arithmetic never walks off either end.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")

-- ---------------------------------------------------------------- page math
-- pageBounds(page, total, perPage) -> first, last, clampedPage, pages
do
  local first, last, page, pages = Kit.pageBounds(1, 38, 5)
  T.eq(first, 1, "page 1 starts at item 1")
  T.eq(last, 5, "page 1 ends at perPage")
  T.eq(page, 1, "page 1 is in range")
  T.eq(pages, 8, "38 items at 5 per page is 8 pages")

  first, last = Kit.pageBounds(8, 38, 5)
  T.eq(first, 36, "the last page starts after the full ones")
  T.eq(last, 38, "the last page stops at the item count, not at perPage")

  -- Out of range in both directions clamps rather than producing a window
  -- that would index past the list (the launcher repages lists underneath
  -- the user: a refresh can shrink an index from 38 mods to 2).
  local _, _, low = Kit.pageBounds(0, 38, 5)
  T.eq(low, 1, "page 0 clamps up to 1")
  local f2, l2, high, p2 = Kit.pageBounds(99, 38, 5)
  T.eq(high, 8, "a page past the end clamps to the last page")
  T.eq(p2, 8, "the page count is unchanged by clamping")
  T.check(l2 >= f2, "a clamped window is never inverted")

  -- An empty list still has one page, and draws no rows.
  local ef, el, ep, epages = Kit.pageBounds(1, 0, 5)
  T.eq(epages, 1, "an empty list still reports one page")
  T.eq(ep, 1, "an empty list sits on page 1")
  T.check(el < ef, "an empty page yields an empty row range")

  -- THE INVARIANT: no page ever yields more rows than perPage.
  for total = 0, 40 do
    for per = 1, 7 do
      local _, _, _, np = Kit.pageBounds(1, total, per)
      for p = 1, np do
        local a, b = Kit.pageBounds(p, total, per)
        T.check(b - a + 1 <= per,
          ("page %d of %d (total %d) draws at most %d rows"):format(p, np, total, per))
        T.check(b <= total, "a page never runs past the item count")
      end
    end
  end
end

-- ------------------------------------------------------- viewport page size
-- rowsThatFit derives perPage from the real viewport, which is what lets a
-- tall window show more rows and a phone fewer with no scrolling either way.
do
  -- n rows need n*rowH + (n-1)*gap pixels.
  T.eq(Kit.rowsThatFit(200, 80, 20, 1, 20), 2, "200px fits two 80px rows + one gap")
  T.eq(Kit.rowsThatFit(180, 80, 20, 1, 20), 2, "exactly two rows still fit")
  T.eq(Kit.rowsThatFit(179, 80, 20, 1, 20), 1, "one pixel short drops to one row")
  T.eq(Kit.rowsThatFit(0, 80, 20, 1, 20), 1,
    "a collapsed viewport still shows one row rather than none")
  T.eq(Kit.rowsThatFit(-500, 80, 20, 1, 20), 1,
    "a negative budget cannot produce a negative page size")
  T.eq(Kit.rowsThatFit(100000, 80, 20, 1, 12), 12, "the cap is honoured")
end

-- ------------------------------------------------------------- text safety
-- Truncation must move whole codepoints.  LOVE's Font:getWidth raises
-- "UTF-8 decoding error" on a string cut through a multi-byte sequence, and
-- the launcher lists mod names from third-party indexes -- this crashed the
-- first frame on a Japanese listing.
do
  -- A font stub that REFUSES malformed UTF-8, the way LOVE's does.
  local font = {}
  function font:getWidth(s)
    local i = 1
    while i <= #s do
      local b = s:byte(i)
      local n = (b < 0x80 and 1) or (b >= 0xF0 and 4) or (b >= 0xE0 and 3)
        or (b >= 0xC0 and 2) or nil
      if not n then error("UTF-8 decoding error: unexpected continuation", 0) end
      for k = 1, n - 1 do
        local c = s:byte(i + k)
        if not c or c < 0x80 or c >= 0xC0 then
          error("UTF-8 decoding error: Not enough space", 0)
        end
      end
      i = i + n
    end
    -- 10px per codepoint, whatever its byte length
    local count = 0
    i = 1
    while i <= #s do
      local b = s:byte(i)
      i = i + ((b < 0x80 and 1) or (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or 2)
      count = count + 1
    end
    return count * 10
  end

  local jp = "ポケットモンスター"   -- 9 codepoints, 27 bytes
  local ok, cut = pcall(Theme.ellipsize, font, jp, 55)
  T.check(ok, "ellipsize does not raise on multi-byte text: " .. tostring(cut))
  T.check(font:getWidth(cut) <= 55 + 1e-9, "the result fits the budget")
  local ok2 = pcall(font.getWidth, font, cut)
  T.check(ok2, "the truncated string is still valid UTF-8")

  local okL, cutL = pcall(Theme.ellipsizeLeft, font, jp, 55)
  T.check(okL, "ellipsizeLeft does not raise on multi-byte text")
  T.check(pcall(font.getWidth, font, cutL),
    "the left-truncated string is still valid UTF-8")

  T.eq(Theme.ellipsize(font, jp, 0), "",
    "a zero budget means nothing fits, not everything fits")
  T.eq(Theme.ellipsize(font, "abc", 999), "abc",
    "text that already fits is returned untouched")
end

T.finish("ui_kit_pagination")
