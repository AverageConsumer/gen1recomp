local PokedexText = {}

local M_PER_INCH = 0.0254
local KG_PER_LB = 0.45359237

local function nativeHeight(m)
  local inches = math.floor(m / M_PER_INCH + 0.5)
  return math.floor(inches / 12) * 100 + inches % 12
end

local function metricHeight(h)
  return (math.floor(h / 100) * 12 + h % 100) * M_PER_INCH
end

function PokedexText.apply(data)
  local dex = data and data.gen2Pokedex
  local pokemon = data and data.pokemon
  if not (dex and dex.entries and pokemon) then return 0 end
  local count = 0
  for species, entry in pairs(dex.entries) do
    local def = pokemon[species]
    local override = def and def.dexEntry
    if override and (override.kind or override.text or override.text2
        or override.heightM or override.weightKg
        or override.height or override.weight) then
      if override.kind then entry.kind = override.kind end
      if override.text then entry.text = override.text end
      if override.text2 then entry.text2 = override.text2 end
      if override.height then
        entry.height = override.height
        if entry.heightM then entry.heightM = metricHeight(override.height) end
      end
      if override.weight then
        entry.weight = override.weight
        if entry.weightKg then entry.weightKg = override.weight / 10 * KG_PER_LB end
      end
      if override.heightM then
        entry.heightM = override.heightM
        if not override.height then entry.height = nativeHeight(override.heightM) end
      end
      if override.weightKg then
        entry.weightKg = override.weightKg
        if not override.weight then
          entry.weight = math.floor(override.weightKg / KG_PER_LB * 10 + 0.5)
        end
      end
      count = count + 1
    end
  end
  return count
end

return PokedexText
