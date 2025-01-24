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

return lib