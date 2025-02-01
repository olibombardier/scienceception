local math2d = require("math2d")

local lib = {}

--Taken from the quality mod
function lib.get_prototype(base_type, name)
  for type_name in pairs(defines.prototypes[base_type]) do
    local prototypes = data.raw[type_name]
    if prototypes and prototypes[name] then
      return prototypes[name]
    end
  end
end

--Taken from the quality mod
function lib.get_item_localised_name(name)
  local item = lib.get_prototype("item", name)
  if not item then return end
  if item.localised_name then
    return item.localised_name
  end
  local prototype
  local type_name = "item"
  if item.place_result then
    prototype = lib.get_prototype("entity", item.place_result)
    type_name = "entity"
  elseif item.place_as_equipment_result then
    prototype = lib.get_prototype("equipment", item.place_as_equipment_result)
    type_name = "equipment"
  elseif item.place_as_tile then
    -- Tiles with variations don't have a localised name
    local tile_prototype = data.raw.tile[item.place_as_tile.result]
    if tile_prototype and tile_prototype.localised_name then
      prototype = tile_prototype
      type_name = "tile"
    end
  end
  return prototype and prototype.localised_name or {type_name.."-name."..name}
end

function lib.split_string(input, separator)
  local result = {}
  for str in string.gmatch(input, "([^" .. separator .. "]+)") do
    table.insert(result, str)
  end

  return result
end

function lib.read_pairs_list(input, source)
  local result = {}
  for _, pair in pairs(lib.split_string(input, ';')) do
    local new_pair = lib.split_string(pair, ',')
    if table_size(new_pair) ~= 2 then
      error(pair .. " should be a ',' separated pair in setting " .. source)
    end
    table.insert(result, new_pair)
  end
  return result
end

function lib.insert_unique(table, key, value)
	if table[key] ~= nil then return false end
	table[key] = value
	return true
end

function lib.shallowcopy(table)
  local result = {}
  for k, v in pairs (table) do
    result[k] = v
  end

  return result
end

---@param prototype data.TechnologyPrototype | data.ItemPrototype
---@param source_pack_icon data.IconData[]
---@return data.IconData[]
---@overload fun(prototype: data.TechnologyPrototype | data.ItemPrototype)
function lib.make_prod_icon_from_prototype(prototype, source_pack_icon)
  ---@type data.IconData[]
  local result = {}
  if prototype.icon then
    result = util.technology_icon_constant_recipe_productivity(prototype.icon)
  else
    result = table.deepcopy(prototype.icons --[=[@as data.IconData[]]=])
    table.insert(result,{
      icon = "__core__/graphics/icons/technology/constants/constant-mining-productivity.png",
      icon_size = 128,
      scale = 0.5,
      shift = {50, 50}
    })
  end
  if source_pack_icon then
    for _, icon in pairs(source_pack_icon) do
      local new_layer = table.deepcopy(icon)
      new_layer.scale = (new_layer.scale and new_layer.scale * 0.55) or 0.55
      if new_layer.shift then
        new_layer.shift = math2d.position.add(new_layer.shift, {-40, -40})
      else
        new_layer.shift = {-40, -40}
      end
      table.insert(result, new_layer)
    end
  end
  return result
end

return lib