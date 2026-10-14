local Assets = require("src.render.Assets")

local TileAtlas = {}

local quads = setmetatable({}, { __mode = "k" })

function TileAtlas.image(path)
  return Assets.image(path)
end

function TileAtlas.draw(img, id, x, y)
  local w, h = img:getDimensions()
  if id >= (w / 8) * (h / 8) then return end
  local set = quads[img]
  if not set then
    set = {}
    quads[img] = set
  end
  local q = set[id]
  if not q then
    local perRow = w / 8
    q = love.graphics.newQuad((id % perRow) * 8, math.floor(id / perRow) * 8,
      8, 8, w, h)
    set[id] = q
  end
  love.graphics.draw(img, q, x, y)
end

-- engine/printer/printer.asm:734
function TileAtlas.box(img, ids, tx, ty, rows, cols)
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      TileAtlas.draw(img, ids[r * cols + c + 1], (tx + c) * 8, (ty + r) * 8)
    end
  end
end

return TileAtlas
