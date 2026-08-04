-- Surfing Pikachu minigame (engine/minigame/surfing_pikachu.asm): the
-- Summer Beach House wave run.  Paddle for speed, launch off the wave,
-- spin in the air and land flat for points; a crooked landing wipes out
-- and ends the run.  The scene is built from the real ROM sheets
-- (gfx/surfing_pikachu.asm, ripped at import to
-- assets/generated/minigame/surf_1a/1b.png).
--
-- #726: the background is the original's own metatile scroller, not a
-- procedural stand-in.  SurfingPikachu1Graphics1 is copied to vChars2
-- with LCDC's BG char base unset, so BG tile id N is simply tile N of
-- surf_1a (5 tiles per row).  SurfingMinigame_ScrollAndGenerateBGMap
-- walks a jumptable of wave states, each of which hands back one
-- 8-metatile column (2x2 tiles each, so 16px wide by the 128px the BG
-- shows above the HP window) plus the two Pikachu ride heights for that
-- column.  Porting those tables verbatim is what makes the water read as
-- water: the earlier stand-in tiled the wave-face tiles ($02/$07) over
-- the whole sea and drew the swell as a LOVE ellipse, which is the
-- "messed up graphics" in the report.
--
-- Score model keeps the port's shape (ride ticks + airtime + full
-- rotations); high score persists in save.surfingHighScore for the
-- beach-house printer.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")

local SurfingMinigame = {}
SurfingMinigame.__index = SurfingMinigame
SurfingMinigame.isOpaque = true

-- SURFING_MINIGAME_CENTER_X/FLAT_WATER_Y (surfing_pikachu.asm:1-2) are OAM
-- coordinates; screen x/y are those minus OAM_X_OFS/OAM_Y_OFS.
local FLAT_WATER_Y = 116
local PIKA_X = 68          -- fixed screen x while riding (center 80, 24px pose)
local RUN_DISTANCE = 3072  -- 24 sections of 8 metatile columns
local GRAVITY = 0.14
local BG_HEIGHT = 128      -- rows the BG shows; the HP window covers the rest

-- surf_1b quads: {x, y, w, h} in sheet pixels (pose pitch is 24x24)
local B = {
  digits = { x = 0, y = 104 },              -- "0123456789", 8x8 each
  good   = { 0, 72, 32, 8 },
  yeah   = { 32, 72, 32, 8 },
  ohno   = { 80, 96, 48, 24 },
  splash = { 48, 80, 32, 24 },
  cloud  = { 96, 112, 32, 8 },
  paddle = { { 0, 80, 24, 24 }, { 24, 80, 24, 24 } },
}
-- rotation frames, 45-degree buckets clockwise from upright
local POSES = {
  [0]   = { 48, 0, 24, 24 },   -- upright ride
  [45]  = { 24, 0, 24, 24 },   -- nose down
  [90]  = { 0, 48, 24, 24 },   -- board vertical
  [135] = { 48, 48, 24, 24 },  -- tumbling
  [180] = { 72, 48, 24, 24 },  -- upside down
  [225] = { 48, 48, 24, 24 },
  [270] = { 0, 48, 24, 24 },
  [315] = { 0, 0, 24, 24 },    -- tail down
}

-- surf_1a is 5 tiles wide, so BG tile id N lives at (N%5*8, N/5*8).  The
-- only quad the scene needs by hand is the window's "HP:" label, which
-- straddles a tile boundary in the sheet.
local HP_LABEL = { 20, 40, 20, 8 }

-- SurfingMinigame_BGMetatileTable (surfing_pikachu.asm): 2x2 tiles each,
-- stored top-left, top-right, bottom-left, bottom-right.
local BG_METATILES = {
  [0x00] = { 0x00, 0x00, 0x00, 0x00 }, -- sky block (blank)
  [0x01] = { 0x0b, 0x0b, 0x0b, 0x0b }, -- open water
  [0x02] = { 0x0b, 0x02, 0x02, 0x06 },
  [0x03] = { 0x03, 0x0b, 0x07, 0x03 },
  [0x04] = { 0x06, 0x06, 0x06, 0x06 },
  [0x05] = { 0x07, 0x07, 0x07, 0x07 },
  [0x06] = { 0x06, 0x04, 0x04, 0x08 },
  [0x07] = { 0x05, 0x07, 0x08, 0x05 },
  [0x08] = { 0x0b, 0x0b, 0x11, 0x12 },
  [0x09] = { 0x0b, 0x0b, 0x13, 0x03 },
  [0x0a] = { 0x14, 0x12, 0x04, 0x08 },
  [0x0b] = { 0x13, 0x07, 0x08, 0x05 },
  [0x0c] = { 0x06, 0x14, 0x06, 0x14 }, -- unused, identical to 11
  [0x0d] = { 0x13, 0x07, 0x13, 0x07 },
  [0x0e] = { 0x08, 0x08, 0x08, 0x08 }, -- solid blue
  [0x0f] = { 0x14, 0x12, 0x14, 0x12 },
  [0x10] = { 0x0b, 0x11, 0x02, 0x14 },
  [0x11] = { 0x06, 0x14, 0x06, 0x14 },
  [0x12] = { 0x0c, 0x0c, 0x0d, 0x0d }, -- beach top block
  [0x13] = { 0x0d, 0x0d, 0x0d, 0x0d }, -- beach sand block
  [0x14] = { 0x0e, 0x0f, 0x10, 0x0b }, -- beach shore block
  [0x15] = { 0x12, 0x13, 0x12, 0x13 },
}

-- SurfingMinigameWavePattern00..1C plus SurfingMinigameBeachPattern: one
-- column of 8 metatiles, top to bottom.
local WAVE_PATTERNS = {
  [0x00] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01 },
  [0x01] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x04, 0x06 },
  [0x02] = { 0x00, 0x00, 0x00, 0x01, 0x02, 0x04, 0x06, 0x0e },
  [0x03] = { 0x00, 0x00, 0x00, 0x10, 0x11, 0x06, 0x0e, 0x0e },
  [0x04] = { 0x00, 0x00, 0x00, 0x15, 0x15, 0x0e, 0x0e, 0x0e },
  [0x05] = { 0x00, 0x00, 0x00, 0x03, 0x05, 0x07, 0x0e, 0x0e },
  [0x06] = { 0x00, 0x00, 0x00, 0x01, 0x03, 0x05, 0x07, 0x0e },
  [0x07] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x08] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x04, 0x06 },
  [0x09] = { 0x00, 0x00, 0x00, 0x01, 0x02, 0x04, 0x06, 0x0e },
  [0x0a] = { 0x00, 0x00, 0x00, 0x08, 0x0f, 0x0a, 0x0e, 0x0e },
  [0x0b] = { 0x00, 0x00, 0x00, 0x09, 0x0d, 0x0b, 0x0e, 0x0e },
  [0x0c] = { 0x00, 0x00, 0x00, 0x01, 0x03, 0x05, 0x07, 0x0e },
  [0x0d] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x0e] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x04, 0x06 },
  [0x0f] = { 0x00, 0x00, 0x00, 0x01, 0x10, 0x11, 0x06, 0x0e },
  [0x10] = { 0x00, 0x00, 0x00, 0x01, 0x15, 0x15, 0x0e, 0x0e },
  [0x11] = { 0x00, 0x00, 0x00, 0x01, 0x03, 0x05, 0x07, 0x0e },
  [0x12] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x13] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x04, 0x06 },
  [0x14] = { 0x00, 0x00, 0x00, 0x01, 0x08, 0x0f, 0x0a, 0x0e },
  [0x15] = { 0x00, 0x00, 0x00, 0x01, 0x09, 0x0d, 0x0b, 0x0e },
  [0x16] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x17] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x10, 0x11, 0x06 },
  [0x18] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x15, 0x15, 0x0e },
  [0x19] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x1a] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x08, 0x0f, 0x0a },
  [0x1b] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x09, 0x0d, 0x0b },
  [0x1c] = { 0x00, 0x00, 0x00, 0x14, 0x14, 0x14, 0x14, 0x14 },
  beach  = { 0x00, 0x00, 0x00, 0x12, 0x13, 0x13, 0x13, 0x13 },
}

-- RunSurfingMinigameRoutine's .WaveFunctions jumptable, flattened:
-- { pattern, left ride height, right ride height, what to do next }.
-- next: 0 = advance one state, 1 = reset to the chooser, 2 = stay put.
-- State 0 is SurfingMinigame_ChooseNextWaveSequence and is handled in
-- code because it rolls Random and forces the Big Kahuna near the goal.
local ADV, RESET, STAY = 0, 1, 2
local WAVE_STEPS = {
  [0x01] = { 0x13, 116, 108, ADV }, [0x02] = { 0x14, 100,  92, ADV },
  [0x03] = { 0x15,  92,  92, ADV }, [0x04] = { 0x16, 100, 108, ADV },
  [0x05] = { 0x00, 116, 116, ADV }, [0x06] = { 0x17, 116, 108, ADV },
  [0x07] = { 0x18, 100, 100, ADV }, [0x08] = { 0x19, 100, 108, ADV },
  [0x09] = { 0x00, 116, 116, ADV }, [0x0a] = { 0x00, 116, 116, ADV },
  [0x0b] = { 0x00, 116, 116, ADV }, [0x0c] = { 0x00, 116, 116, ADV },
  [0x0d] = { 0x00, 116, 116, RESET },
  [0x0e] = { 0x08, 116, 108, ADV }, [0x0f] = { 0x09, 100,  92, ADV },
  [0x10] = { 0x0a,  84,  76, ADV }, [0x11] = { 0x0b,  76,  76, ADV },
  [0x12] = { 0x0c,  84,  92, ADV }, [0x13] = { 0x0d, 100, 108, ADV },
  [0x14] = { 0x00, 116, 116, ADV }, [0x15] = { 0x00, 116, 116, ADV },
  [0x16] = { 0x00, 116, 116, ADV }, [0x17] = { 0x00, 116, 116, ADV },
  [0x18] = { 0x00, 116, 116, ADV }, [0x19] = { 0x00, 116, 116, RESET },
  [0x1a] = { 0x0e, 116, 108, ADV }, [0x1b] = { 0x0f, 100,  92, ADV },
  [0x1c] = { 0x10,  84,  84, ADV }, [0x1d] = { 0x11,  84,  92, ADV },
  [0x1e] = { 0x12, 100, 108, ADV }, [0x1f] = { 0x0e, 116, 108, ADV },
  [0x20] = { 0x0f, 100,  92, ADV }, [0x21] = { 0x10,  84,  84, ADV },
  [0x22] = { 0x11,  84,  92, ADV }, [0x23] = { 0x12, 100, 108, ADV },
  [0x24] = { 0x00, 116, 116, ADV }, [0x25] = { 0x00, 116, 116, ADV },
  [0x26] = { 0x00, 116, 116, ADV }, [0x27] = { 0x00, 116, 116, ADV },
  [0x28] = { 0x00, 116, 116, RESET },
  [0x29] = { 0x13, 116, 108, ADV }, [0x2a] = { 0x14, 100,  92, ADV },
  [0x2b] = { 0x15,  92,  92, ADV }, [0x2c] = { 0x16, 100, 108, ADV },
  [0x2d] = { 0x00, 116, 116, ADV }, [0x2e] = { 0x00, 116, 116, ADV },
  [0x2f] = { 0x00, 116, 116, ADV }, [0x30] = { 0x00, 116, 116, ADV },
  [0x31] = { 0x00, 116, 116, RESET },
  [0x32] = { 0x17, 116, 108, ADV }, [0x33] = { 0x18, 100, 100, ADV },
  [0x34] = { 0x19, 100, 108, ADV }, [0x35] = { 0x17, 116, 108, ADV },
  [0x36] = { 0x18, 100, 100, ADV }, [0x37] = { 0x19, 100, 108, ADV },
  [0x38] = { 0x17, 116, 108, ADV }, [0x39] = { 0x18, 100, 100, ADV },
  [0x3a] = { 0x19, 100, 108, ADV }, [0x3b] = { 0x00, 116, 116, ADV },
  [0x3c] = { 0x00, 116, 116, ADV }, [0x3d] = { 0x00, 116, 116, ADV },
  [0x3e] = { 0x00, 116, 116, ADV }, [0x3f] = { 0x00, 116, 116, RESET },
  [0x40] = { 0x1a, 116, 108, ADV }, [0x41] = { 0x1b, 108, 108, ADV },
  [0x42] = { 0x0e, 116, 108, ADV }, [0x43] = { 0x0f, 100,  92, ADV },
  [0x44] = { 0x10,  84,  84, ADV }, [0x45] = { 0x11,  84,  92, ADV },
  [0x46] = { 0x12, 100, 108, ADV }, [0x47] = { 0x1a, 116, 108, ADV },
  [0x48] = { 0x1b, 108, 108, ADV }, [0x49] = { 0x00, 116, 116, ADV },
  [0x4a] = { 0x00, 116, 116, ADV }, [0x4b] = { 0x00, 116, 116, ADV },
  [0x4c] = { 0x00, 116, 116, RESET },
  [0x4d] = { 0x08, 116, 108, ADV }, [0x4e] = { 0x09, 100,  92, ADV },
  [0x4f] = { 0x0a,  84,  76, ADV }, [0x50] = { 0x0b,  76,  76, ADV },
  [0x51] = { 0x0c,  84,  92, ADV }, [0x52] = { 0x0d, 100, 108, ADV },
  [0x53] = { 0x00, 116, 116, ADV }, [0x54] = { 0x1a, 116, 108, ADV },
  [0x55] = { 0x1b, 108, 108, ADV }, [0x56] = { 0x1a, 116, 108, ADV },
  [0x57] = { 0x1b, 108, 108, ADV }, [0x58] = { 0x00, 116, 116, ADV },
  [0x59] = { 0x00, 116, 116, ADV }, [0x5a] = { 0x00, 116, 116, ADV },
  [0x5b] = { 0x00, 116, 116, RESET },
  [0x5c] = { 0x0e, 116, 108, ADV }, [0x5d] = { 0x0f, 100,  92, ADV },
  [0x5e] = { 0x10,  84,  84, ADV }, [0x5f] = { 0x11,  84,  92, ADV },
  [0x60] = { 0x12, 100, 108, ADV }, [0x61] = { 0x13, 116, 108, ADV },
  [0x62] = { 0x14, 100,  92, ADV }, [0x63] = { 0x15,  92,  92, ADV },
  [0x64] = { 0x16, 100, 108, ADV }, [0x65] = { 0x00, 116, 116, ADV },
  [0x66] = { 0x00, 116, 116, ADV }, [0x67] = { 0x00, 116, 116, ADV },
  [0x68] = { 0x00, 116, 116, ADV }, [0x69] = { 0x00, 116, 116, RESET },
  -- 6a..71: the forced "Big Kahuna" finale; 71 holds flat water (its
  -- loader just rets, so the state never advances on its own).
  [0x6a] = { 0x01, 116, 108, ADV }, [0x6b] = { 0x02, 100,  92, ADV },
  [0x6c] = { 0x03,  84,  76, ADV }, [0x6d] = { 0x04,  68,  68, ADV },
  [0x6e] = { 0x05,  68,  76, ADV }, [0x6f] = { 0x06,  84,  92, ADV },
  [0x70] = { 0x07, 100, 108, ADV }, [0x71] = { 0x00, 116, 116, STAY },
  -- 72..7b: the run-out to the beach, entered by hand at the goal
  -- (SurfingMinigame_WaitToShowResults writes $72).
  [0x72] = { 0x00, 116, 116, ADV }, [0x73] = { 0x1c, 116, 116, ADV },
  [0x74] = { "beach", 116, 116, ADV }, [0x75] = { "beach", 116, 116, ADV },
  [0x76] = { "beach", 116, 116, ADV }, [0x77] = { "beach", 116, 116, ADV },
  [0x78] = { "beach", 116, 116, ADV }, [0x79] = { "beach", 116, 116, ADV },
  [0x7a] = { "beach", 116, 116, ADV }, [0x7b] = { "beach", 116, 116, RESET },
}
-- SurfingMinigame_WaveSequenceStarts
local SEQ_STARTS = { 0x01, 0x0e, 0x1a, 0x29, 0x32, 0x40, 0x4d, 0x5c }

-- the #726 table-integrity check in tests/drivers reads these; nothing
-- else should
SurfingMinigame.BG_METATILES = BG_METATILES
SurfingMinigame.WAVE_PATTERNS = WAVE_PATTERNS
SurfingMinigame.WAVE_STEPS = WAVE_STEPS

-- SGB-style zones: one sea palette over the frame plus a yellow
-- OBJ-flavored palette tracking Pikachu's tiles (rectangular attribute
-- blocks are all the SGB could do, bleed and all)
local SEA_PAL = { { 255, 255, 255 }, { 112, 184, 248 },
                  { 56, 120, 216 }, { 0, 0, 0 } }
local PIKA_PAL = { { 255, 255, 255 }, { 248, 216, 64 },
                   { 224, 144, 32 }, { 0, 0, 0 } }

local function newQuad(spec, img)
  return love.graphics.newQuad(spec[1], spec[2], spec[3], spec[4],
                               img:getDimensions())
end

function SurfingMinigame.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone }, SurfingMinigame)
  self.phase = "ride"     -- ride | air | wipeout | results
  self.t = 0
  self.distance = 0
  self.speed = 2
  self.score = 0
  self.rideTick = 0
  self.y = 0              -- air offset above the wave (positive = up)
  self.vy = 0
  self.rot = 0            -- degrees, accumulates through the air
  self.spins = 0
  self.airFrames = 0
  self.resultShown = 0
  self.banner = nil       -- {quad, frames}: GOOD!/YEAH-/Oh no..

  -- SurfingPikachuMinigame_LoadGFXAndLayout prefills the BG with flat
  -- water and only starts generating $a0 pixels (ten metatile columns)
  -- ahead of the viewport, so the run opens on calm sea.
  self.waveFn = 0
  self.cols = {}
  for c = 0, 10 do
    self.cols[c] = { pat = WAVE_PATTERNS[0x00],
                     hl = FLAT_WATER_Y, hr = FLAT_WATER_Y }
  end
  self.colTail = 10

  local function sheet(path)
    local ok, img = pcall(love.graphics.newImage, path)
    return ok and img or nil
  end
  self.bg = sheet("assets/generated/minigame/surf_1a.png")
  self.ob = sheet("assets/generated/minigame/surf_1b.png")
  if self.bg then
    self.tq = {}
    for n = 0, 64 do
      self.tq[n] = love.graphics.newQuad((n % 5) * 8, math.floor(n / 5) * 8,
        8, 8, self.bg:getDimensions())
    end
    self.hpq = newQuad(HP_LABEL, self.bg)
  end
  if self.ob then
    self.bq = {}
    for k, spec in pairs(B) do
      if spec[3] then self.bq[k] = newQuad(spec, self.ob) end
    end
    self.bq.paddle = { newQuad(B.paddle[1], self.ob),
                       newQuad(B.paddle[2], self.ob) }
    self.bq.poses = {}
    for deg, spec in pairs(POSES) do
      self.bq.poses[deg] = newQuad(spec, self.ob)
    end
    self.bq.digit = {}
    for d = 0, 9 do
      self.bq.digit[d] = love.graphics.newQuad(B.digits.x + d * 8,
        B.digits.y, 8, 8, self.ob:getDimensions())
    end
  end
  Music.play(game.data, "Music_SurfingPikachu")
  return self
end

-- SurfingMinigame_ChooseNextWaveSequence: past section $16 the finale is
-- forced, otherwise a nonzero Random picks one of eight sequence starts.
-- Either way this column itself is flat water.
function SurfingMinigame:chooseSequence()
  if math.floor(self.distance / 128) >= 0x16 then
    self.waveFn = 0x6a
  else
    local r = math.random(0, 255)
    if r ~= 0 then self.waveFn = SEQ_STARTS[((r - 1) % 8) + 1] end
  end
  return WAVE_PATTERNS[0x00], FLAT_WATER_Y, FLAT_WATER_Y
end

-- one 16px metatile column, appended on the right as the sea scrolls
function SurfingMinigame:pushColumn()
  local pat, hl, hr
  if self.waveFn == 0 then
    pat, hl, hr = self:chooseSequence()
  else
    local step = WAVE_STEPS[self.waveFn]
    if not step then
      self.waveFn = 0
      pat, hl, hr = WAVE_PATTERNS[0x00], FLAT_WATER_Y, FLAT_WATER_Y
    else
      pat, hl, hr = WAVE_PATTERNS[step[1]], step[2], step[3]
      if step[4] == ADV then self.waveFn = self.waveFn + 1
      elseif step[4] == RESET then self.waveFn = 0 end
    end
  end
  self.colTail = self.colTail + 1
  self.cols[self.colTail] = { pat = pat, hl = hl, hr = hr }
  self.cols[self.colTail - 24] = nil -- columns behind the viewport
end

-- keep the generated columns covering the viewport plus the lookahead
function SurfingMinigame:generateAhead()
  while self.colTail * 16 < self.distance + 176 do self:pushColumn() end
end

-- Pikachu's screen y for a screen x, from the per-tile-column ride
-- heights the wave states hand back (SurfingMinigame_SetPikachuHeight
-- samples the same array either side of the scroll's low bit).
function SurfingMinigame:seaY(x)
  local tile = math.floor((self.distance + x) / 8)
  local col = self.cols[math.floor(tile / 2)]
  if not col then return FLAT_WATER_Y - 16 end
  return (tile % 2 == 0 and col.hl or col.hr) - 16
end

function SurfingMinigame:finishRun()
  self.phase = "results"
  local save = self.game.save
  self.newRecord = self.score > (save.surfingHighScore or 0)
  if self.newRecord then save.surfingHighScore = self.score end
  Music.stop()
  Sound.play(self.game.data, self.newRecord and "Get_Item1" or "Ball_Poof")
end

function SurfingMinigame:update()
  local input = self.game.input
  self.t = self.t + 1
  if self.banner then
    self.banner.frames = self.banner.frames - 1
    if self.banner.frames <= 0 then self.banner = nil end
  end
  if self.phase == "results" then
    -- the sea keeps sliding under the card for a beat so the beach
    -- run-out (states $72..$7b) actually crosses the screen, like
    -- SurfingMinigame_WaitToShowResults scrolling to the sand
    if self.resultShown < 150 then
      self.distance = self.distance + 1.2
      self:generateAhead()
    end
    self.resultShown = self.resultShown + 1
    if self.resultShown > 30
       and (input:wasPressed("a") or input:wasPressed("b")) then
      self.game.stack:pop()
      if self.onDone then self.onDone(self.score) end
    end
    return
  end
  if self.phase == "wipeout" then
    self.splash = (self.splash or 0) + 1
    if self.splash > 70 then self:finishRun() end
    return
  end

  -- the wave scrolls by the current speed; the beach ends the run
  self.distance = self.distance + 0.8 + self.speed * 0.35
  self:generateAhead()
  if self.distance >= RUN_DISTANCE then
    -- rode it all the way in: distance bonus like the original's goal
    self.score = self.score + 500
    -- SurfingMinigame_WaitToShowResults hands the generator state $72 so
    -- the sand runs out under the coast-in
    self.waveFn = 0x72
    self:finishRun()
    return
  end

  if self.phase == "ride" then
    -- paddling: mash A for speed, it bleeds off on its own
    if input:wasPressed("a") and self.speed < 8 then
      self.speed = self.speed + 1
    end
    if self.t % 45 == 0 and self.speed > 2 then
      self.speed = self.speed - 1
    end
    self.rideTick = self.rideTick + 1
    if self.rideTick % 12 == 0 then self.score = self.score + 1 end
    -- launch off the lip
    if input:wasPressed("up") then
      self.phase = "air"
      self.vy = 1.6 + self.speed * 0.45
      self.rot, self.spins, self.airFrames = 0, 0, 0
      Sound.play(self.game.data, "Ledge_Jump")
    end
  elseif self.phase == "air" then
    self.airFrames = self.airFrames + 1
    self.vy = self.vy - GRAVITY
    self.y = self.y + self.vy
    -- tricks: hold either direction to spin
    local spin = (input:isDown("left") and -6 or 0)
               + (input:isDown("right") and 6 or 0)
    self.rot = self.rot + spin
    if math.abs(self.rot) >= (self.spins + 1) * 360 then
      self.spins = self.spins + 1
    end
    if self.y <= 0 and self.vy < 0 then
      self.y = 0
      local tilt = math.abs(self.rot) % 360
      if tilt <= 60 or tilt >= 300 then
        -- clean landing: airtime + full rotations pay out
        self.score = self.score + self.spins * 100
                     + math.floor(self.airFrames / 4)
        self.phase = "ride"
        self.banner = { quad = self.spins > 0 and "yeah" or "good",
                        frames = 50 }
        Sound.play(self.game.data, "Cut")
      else
        self.phase = "wipeout"
        self.splash = 0
        self.banner = { quad = "ohno", frames = 70 }
        Sound.play(self.game.data, "Faint_Fall")
      end
    end
  end
end

function SurfingMinigame:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local zones = { P.whole(SEA_PAL) }
  if self.phase ~= "wipeout" and self.phase ~= "results" then
    local tx = math.floor(PIKA_X / 8)
    local ty = math.floor(math.max(0, self.pikaScreenY or 60) / 8)
    zones[#zones + 1] = P.zone(PIKA_PAL, tx, ty, tx + 3, ty + 3)
  end
  return zones
end

function SurfingMinigame:drawScore(x, y, n)
  local s = tostring(n)
  for i = 1, #s do
    love.graphics.draw(self.ob, self.bq.digit[tonumber(s:sub(i, i))],
                       x + (i - 1) * 8, y)
  end
end

-- the BG map: metatile columns from the wave generator, scrolled by
-- distance (SurfingMinigame_ScrollAndGenerateBGMap)
function SurfingMinigame:drawBackground()
  local scx = math.floor(self.distance)
  local first = math.floor(scx / 16)
  for c = first, first + 10 do
    local col = self.cols[c]
    if col then
      local x = c * 16 - scx
      for i = 1, 8 do
        local mt = BG_METATILES[col.pat[i]]
        if mt then
          local y = (i - 1) * 16
          love.graphics.draw(self.bg, self.tq[mt[1]], x, y)
          love.graphics.draw(self.bg, self.tq[mt[2]], x + 8, y)
          love.graphics.draw(self.bg, self.tq[mt[3]], x, y + 8)
          love.graphics.draw(self.bg, self.tq[mt[4]], x + 8, y + 8)
        end
      end
    end
  end
end

function SurfingMinigame:draw()
  local haveSheets = self.bg and self.ob
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if not haveSheets then
    -- cache predates the surf sheets: plain shapes keep it playable
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("SCORE %d", self.score), 4, 4)
    love.graphics.rectangle("fill", PIKA_X, self:seaY(PIKA_X) - self.y, 16, 16)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  self:drawBackground()

  -- cloud in the sky strip
  love.graphics.draw(self.ob, self.bq.cloud, 112, 8)

  -- Pikachu rides at the height his tile column reports
  local py = self:seaY(PIKA_X) - self.y
  self.pikaScreenY = py -- the yellow SGB zone tracks this
  if self.phase == "wipeout" then
    love.graphics.draw(self.ob, self.bq.splash, PIKA_X - 4, py)
  else
    local quad
    if self.phase == "ride" and self.speed <= 2
       and self.distance < 120 then
      quad = self.bq.paddle[math.floor(self.t / 8) % 2 + 1]
    else
      local bucket = math.floor(((self.rot % 360) + 22.5) / 45) % 8 * 45
      quad = self.bq.poses[bucket] or self.bq.poses[0]
    end
    love.graphics.draw(self.ob, quad, PIKA_X, py)
  end

  -- banner beats: GOOD! / YEAH- / Oh no..
  if self.banner and self.bq[self.banner.quad] then
    love.graphics.draw(self.ob, self.bq[self.banner.quad], 60, 40)
  end

  -- the HP window sits under the BG rows ($7e into hWY puts it at y 126;
  -- tile-aligned here): "HP:" plus the sheet digits over plain white
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, BG_HEIGHT, 160, 144 - BG_HEIGHT)
  love.graphics.draw(self.bg, self.hpq, 8, BG_HEIGHT + 4)
  self:drawScore(32, BG_HEIGHT + 4, self.score)

  if self.phase == "results" then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 20, 48, 120, 48)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", 20.5, 48.5, 119, 47)
    Font.draw(Strings("SCORE %d", self.score), 32, 56)
    if self.newRecord then
      Font.draw(Strings("New record!"), 32, 68)
    else
      Font.draw(Strings("HI    %d", self.game.save.surfingHighScore or 0),
                32, 68)
    end
    if self.resultShown > 30 then
      Font.draw(Strings("A: done"), 32, 82)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return SurfingMinigame
