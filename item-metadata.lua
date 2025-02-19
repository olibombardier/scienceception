local sci_util = require("sci_utils")
require("__scienceception__.api")

local item_metadata = {}

---@class GetDataOptions
---@field get_prototypes boolean
---@field get_recipes boolean
---@field get_unlock_techs boolean
---@field table_mask string[] limits witch tables of data.raw are looked into
---@field furnace boolean

---@alias ItemTable table<data.ItemID, ItemMetadata>
---@alias TechnologyTable table<data.TechnologyID, TechnologyMetadata>

---@class RecipeMetadata
---@field name data.RecipeID
---@field prototype data.RecipePrototype
---@field unlock_techs TechnologyTable
---@field enabled boolean

---@return table<data.EntityID, LabMetadata>
function item_metadata.get_lab_data()
  ---@type table<data.EntityID, LabMetadata>
  local result = {}

  for entity_id, lab in pairs(data.raw["lab"]) do
    if not scienceception_api.lab_blacklist[entity_id] then
      result[entity_id] = {
        name = entity_id,
        inputs = table.deepcopy(lab.inputs)
      }
      if scienceception_api.proxy_inputs[entity_id] then
        for _, input in pairs(scienceception_api.proxy_inputs[entity_id]) do
          table.insert(result[entity_id], input)
        end
      end
      for _, input in pairs(scienceception_api.proxy_inputs["all"]) do
        table.insert(result[entity_id], input)
      end
    end
  end
  return result
end

---Returns a list of labs that contain at least the specified inputs
---@param labs table<data.EntityID, LabMetadata>
---@param ingredients data.ResearchIngredient[]
---@return table<data.EntityID, LabMetadata>
function item_metadata.filter_lab_by_inputs(labs, ingredients)
  local result = {}

  ---TODO proxy inputs

  for lab_id, lab in pairs(labs) do
    for _, ingredient in pairs(ingredients) do
      for _, lab_input in pairs(lab.inputs) do
        if lab_input == ingredient[1] then goto pack_found end
      end
      goto continue
      ::pack_found::
    end
    result[lab_id] = lab

    ::continue::
  end

  return result
end

---creates an empty item metadata with the specified id
---@param item_id data.ItemID
---@return ItemMetadata
function item_metadata.create_item_metadata(item_id)
  return {
    name = item_id,
    prototype = nil,
    parents = {},
    children = {},
    recipes = {},
    unlock_techs = {},
    unlink = {},
    ignore_for_prod = {},
    initial_technology = nil,
    starting_recipe = false
  }
end

---creates an empty recipe metadata with the specified id
---@param recipe_id data.RecipeID
---@return RecipeMetadata
function item_metadata.create_recipe_metadata(recipe_id)
  return {
    name = recipe_id,
    prototype = data.raw["recipe"][recipe_id],
    unlock_techs = {}, --Doit être pour chaque recette
    furnace = false,
  }
end

---@param labs table<data.EntityID, LabMetadata>
---@return ItemTable
function item_metadata.get_metadata_from_items(labs)
  
  ---@type ItemTable
  local result = {}
  ---@type ItemTable
  local all_items = {}

  local pack_ids = {}
  for _, lab in pairs(labs) do
    for _, input in pairs(lab.inputs) do
      if not scienceception_api.pack_blacklist[input] then
        pack_ids[input] = input
      end
    end
  end

  for _, item_id in pairs(pack_ids) do
    result[item_id] = item_metadata.create_item_metadata(item_id)
    all_items[item_id] = result[item_id]
  end
  
  --item prototypes for packs, labs and items returning packs from orbit
  for category in pairs(defines.prototypes.item) do
    if data.raw[category] then
      for item_id, prototype in pairs(data.raw[category]) do
        ---@cast prototype data.ItemPrototype
        if result[item_id] then
          result[item_id].prototype = prototype
          all_items[item_id] = result[item_id]
        end
        if prototype.place_result and labs[prototype.place_result] then --Lab placing items
          local lab_id = prototype.place_result
          labs[lab_id].item = item_metadata.create_item_metadata(item_id)
          all_items[item_id] = labs[lab_id].item
        end
        if prototype.rocket_launch_products then --Items returning packs when sent to orbit
          for _, launch_product in pairs(prototype.rocket_launch_products) do
            local product = result[launch_product.name]
            if product then
              product.rocket_items = product.rocket_items or {}
              product.rocket_items[item_id] = item_metadata.create_item_metadata(item_id)
              all_items[item_id] = product.rocket_items[item_id]
              all_items[item_id].prototype = prototype
            end
          end
        end
      end
    end
  end
  
  -- recipes
  ---@type table<data.RecipeID, RecipeMetadata>
  local all_recipes = {}
  for recipe_id, prototype in pairs(data.raw["recipe"]) do
    if prototype.results then
      for _, result in pairs(prototype.results) do
        if result.type == "item" and all_items[result.name] and (not result.ignored_by_stats or result.ignored_by_stats < result.amount) then 
          if all_recipes[recipe_id] == nil then --So items can share the same recipe object
            all_recipes[recipe_id] = item_metadata.create_recipe_metadata(recipe_id)
            --TODO: check if recipe's category is used for furnaces
          end
          all_items[result.name].recipes[recipe_id] = all_recipes[recipe_id]
          if prototype.enabled then
            all_items[result.name].starting_recipe = true
          end
        end
      end
    end
  end

  -- techs
  ---@type table<data.TechnologyID, TechnologyMetadata>
  local all_techs = {}
  for tech_id, prototype in pairs(data.raw["technology"]) do
    if prototype.effects then
      for _, effect in pairs(prototype.effects) do
        if effect.type == "unlock-recipe" and all_recipes[effect.recipe] then
          if all_techs[tech_id] == nil then
            all_techs[tech_id] = {
              name = tech_id,
              prototype = prototype
            }
          end
          all_recipes[effect.recipe].unlock_techs[tech_id] = all_techs[tech_id]
        end
      end
    end
    
    if prototype.research_trigger and prototype.research_trigger.type == "send-item-to-orbit" and all_items[prototype.research_trigger.item] then
      for pack_id, pack in pairs(result) do
        if pack.rocket_items and pack.rocket_items[prototype.research_trigger.item] then
          if all_techs[tech_id] == nil then
            all_techs[tech_id] = {
              name = tech_id,
              prototype = prototype
            }
          end
          pack.unlock_techs[tech_id] = all_techs[tech_id]
          all_items[prototype.research_trigger.item].unlock_techs[tech_id] = all_techs[tech_id]
        end
      end
    end
  end

  -- Merge item techs with their recipes
  for _, item in pairs(all_items) do
    for _, recipe in pairs(item.recipes) do
      for tech_id, tech in pairs(recipe.unlock_techs) do
        item.unlock_techs[tech_id] = tech
      end
    end
  end
  -- Merge item techs with their rocket items
  for _, item in pairs(all_items) do
    if item.rocket_items then
      for _, rocket_item in pairs(item.rocket_items) do
        for tech_id, tech in pairs(rocket_item.unlock_techs) do
          item.unlock_techs[tech_id] = tech
        end
      end
    end
  end

  return result
end

return item_metadata