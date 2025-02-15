---@class PrerequisiteBranch
---@field parents ItemTable
---@field end_tech TechnologyMetadata

local sci_utils = require("sci_utils")
local item_metadata = require("item-metadata")

local debug = false
local function log_debug(text)
	if debug then log(text) end
end

local prefix = "scienceception-"

---Generates an intermediate item that will replace the product and a new recipe the pack from it
---@param pack ItemMetadata
---@param product data.ProductPrototype
local function generate_intermediate_item(pack, product)
	if pack.component_item then 
		product.name = pack.component_item
	end --
	
	
	local localised_pack_name =  sci_utils.get_item_localised_name(pack.name)

	---@type data.ItemPrototype
	local intermediate = table.deepcopy(data.raw["tool"][pack.name])
	intermediate.type = "item"
	intermediate.localised_name = {"item-name.scienceception-pack-component", localised_pack_name}
	intermediate.localised_description = {"item-description.scienceception-pack-component", pack.name}
	intermediate.name = pack.name .. "-component"

	local base_icon =
	{
		icon = "__scienceception__/graphics/icons/pack-component-base.png",
		icon_size = 64
	}
	if intermediate.icons then
		for _, icon_data in intermediate.icons do
			icon_data.scale = (icon_data.scale or 1) * 0.3
		end
		table.insert(intermediate.icons, 1, base_icon)
	else
		intermediate.icons = {
			base_icon,
			{
				icon = intermediate.icon,
				icon_size = intermediate.icon_size,
				scale = 0.3,
				draw_background = true
			}
		}
	end

	product.name = intermediate.name

	--Recipe
	---@type data.RecipePrototype
	local recipe = {
		type = "recipe",
		name = pack.name,
		localised_name = localised_pack_name,
		enabled = false,
		energy_required = 1,
		ingredients = {{type = "item", name = intermediate.name, amount=1}},
		results = {{type="item", name = pack.name, amount=1}},
		allow_productivity = true,
		main_product = pack.name
	}
	if data.raw["recipe"][recipe.name] then
		recipe.name = recipe.name .. "-from-component"
		localised_name = {"recipe-name.scienceception-from-component", localised_pack_name}
	end

	pack.component_item = intermediate.name
	pack.recipes[recipe.name] = item_metadata.create_recipe_metadata(recipe.name)
	pack.recipes[recipe.name].prototype = recipe

	--TODO: furnace??? Here or in other function

	for _, rocket_item in pairs(pack.rocket_items) do
		for _, tech in pairs(rocket_item.unlock_techs) do
			table.insert(tech.prototype.effects, {
				type = "unlock-recipe",
				recipe = recipe.name
			})
		end
	end

	data:extend({intermediate, recipe})
end

---@param pack ItemMetadata
---@param tech data.TechnologyPrototype
---@param visited table<string, boolean>?
---@param stoppers table<string, boolean>?
---@return ItemTable?
local function process_tech_prerequisites(pack, packs, tech, visited, stoppers)
	visited = visited or {}
	stoppers = stoppers or {}
	if visited[tech.name] then return {} end
	visited[tech.name] = true

	if tech.prerequisites == nil then return {} end
	
	---@type ItemTable
	local result = {}

	for _, prerequisite_id in pairs(tech.prerequisites) do
		if visited[prerequisite_id] then goto continue end
		if pack.unlock_techs[prerequisite_id] then return nil end --Means we are on a branch that depends on the pack itself
		local stop_search = false
		local branch_stoppers = table.deepcopy(stoppers)
		for _, other in pairs(packs) do
			if other.unlock_techs[prerequisite_id] then --Match
				if pack.unlink[other.name] or stoppers[other.name] then
					stop_search = true
				else
					result[other.name] = other
					for parent_id, parent in pairs(scienceception_api.get_forced_parents(other.name)) do
						--Add the parents forced through the API of the matched pack
						result[parent_id] = parent
					end

					for stopper in pairs(other.unlink) do
						branch_stoppers[stopper] = true
					end
				end
			end
		end
		if not stop_search then
			local prerequisite = data.raw["technology"][prerequisite_id]
			if prerequisite == nil then
				log(tech.name .. "'s prerequisite " .. prerequisite_id .. "doesn't exists.")
			else
				local prerequisite_result = process_tech_prerequisites(pack, packs, prerequisite, visited, branch_stoppers)
				if prerequisite_result == nil then return nil end
				for k, v in pairs(prerequisite_result) do
					result[k] = v
				end
			end
		end
		::continue::
	end

	return result
end

---@param ingredients data.ResearchIngredient[]
---@param pack ItemMetadata
---@param labs LabMetadata[]
---@return data.ResearchIngredient[]?
local function filter_ingredients(ingredients, pack, labs)
	local available_labs = item_metadata.filter_lab_by_inputs(labs, ingredients)
	if table_size(available_labs) == 0 then --No lab match the required packs
		-- find labs that fits parents and self
		local new_ingredients = {{pack.name, 1}}
		for parent, _ in pairs(pack.all_parents) do table.insert(new_ingredients, {parent, 1}) end
		available_labs = item_metadata.filter_lab_by_inputs(labs, new_ingredients)
		
		if table_size(available_labs) == 0 then
			-- OR find self
			new_ingredients = {{pack.name, 1}}
			available_labs = item_metadata.filter_lab_by_inputs(labs, new_ingredients)
			
			if table_size(available_labs) == 0 then
				-- OR find lab that fits parents
				new_ingredients = {}
				for parent, _ in pairs(pack.all_parents) do table.insert(new_ingredients, {parent, 1}) end
				available_labs = item_metadata.filter_lab_by_inputs(labs, new_ingredients)
				
				-- OR cancel research
				if table_size(available_labs) == 0 then return nil end
			end
		end
		-- Reomve incompatible packs
		local _, lab = next(available_labs, nil) -- We arbitrarly take the first lab
		new_ingredients = {}
		for _, ingredient in pairs(ingredients) do
			for _, input in pairs(lab.inputs) do
				if input == ingredient[1] then table.insert(new_ingredients, ingredient)
				end
			end
		end
		ingredients = new_ingredients
	end

	return ingredients
end

---@param pack ItemMetadata
---@param childs ItemTable
---@param labs table<data.EntityId, LabMetadata>
---@param start_level int
---@param end_level int|string
---@param bonus int
---@param options {prerequisites: data.TechnologyID[]?, from: string?}?
---@return data.TechnologyPrototype
local function create_prod_research(pack, childs, labs, start_level, end_level, bonus, options)

	---@type data.ResearchIngredient[]
	local ingredients = {{pack.name, 1}}

	for child, _ in pairs(childs) do sci_utils.add_research_ingredient(ingredients, child) end
	for parent, _ in pairs(pack.all_parents) do sci_utils.add_research_ingredient(ingredients, parent) end

	local prerequisites = {}
	local from = ""
	---@type data.LocalisedString
	local description = {"technology-description.scienceception-science-pack-productivity", pack.name }
	if options then
		prerequisites = options.prerequisites or {}
		if options.from then 
			description = {"technology-description.scienceception-science-pack-productivity-from", pack.name, options.from, sci_utils.get_item_localised_name(pack.name)}
			from = options.from .. "-" 
		end
	end

	if table_size(prerequisites) == 0 then
		for _, child in pairs(childs) do
			if child.initial_technology then table.insert(prerequisites, child.initial_technology.name) end
		end
	end
	
	local effects = {}
	for recipe_id, recipe in pairs(pack.recipes) do
		if recipe.prototype.allow_productivity then
			table.insert(effects, {
				type = "change-recipe-productivity",
				recipe = recipe_id,
				change = bonus / 100
			})
		end
	end
		
	if table_size(effects) == 0 then
		return
	end

	ingredients = filter_ingredients(ingredients, pack, labs)
	if ingredients == nil then return end
	
	local formula = settings.startup["scienceception-prod-count-formula"].value --[[@as string]]
	if start_level > 1 then
		formula = formula:gsub("[Ll]", "(L+" .. start_level - 1 ..")")
	end

	---@type data.TechnologyPrototype
	local tech = {
		type = "technology",
		name = prefix .. pack.name .. "-productivity-" .. from .. start_level,
		localised_name = {"technology-name.scienceception-science-pack-productivity", sci_utils.get_item_localised_name(pack.name) },
		localised_description = description,
		order = "scienceception-prod-" .. pack.name,
		unit = {
			count_formula = formula,
			time = settings.startup["scienceception-prod-research-time"].value --[[@as int]],
			ingredients = ingredients
		},
		prerequisites = prerequisites,
		effects = effects
	}

	if end_level == "infinite" or end_level == 0 then
		tech.max_level = "infinite"
	elseif end_level > start_level then
		tech.max_level = end_level - start_level
	else
		tech.max_level = end_level
	end
	
	---@type data.IconData[]
	local source_icons = nil

	if options and options.from then
		local source_pack = childs[options.from].prototype
		if source_pack then 
			if source_pack.icon then
				source_icons = {{
					icon = source_pack.icon,
					icon_size = source_pack.icon_size or 64
				}}
			else
				source_icons = source_pack.icons
			end
		end
	end

	if scienceception_api.forced_research_icon[pack.name] then
		tech.icons = sci_utils.make_prod_icon(scienceception_api.forced_research_icon[pack.name], source_icons)
	elseif pack.initial_technology then
		tech.icons = sci_utils.make_prod_icon(pack.initial_technology.prototype, source_icons)
	else
		local base_item = data.raw["tool"][pack.name]
		tech.icons = sci_utils.make_prod_icon(base_item, source_icons)
	end
	
	data:extend({tech})
	return tech
end

local function update_data()
	local labs = item_metadata.get_lab_data()
	
	local packs = item_metadata.get_metadata_from_items(labs)
	scienceception_api.packs = packs
	
	local packs_to_unlink = sci_utils.read_pairs_list(settings.startup["scienceception-unlink-packs"].value, "scienceception-unlink-packs")
	local ignore_for_prod_research_dep = sci_utils.read_pairs_list(settings.startup["scienceception-ignore-for-prod-prerequisites"].value, "scienceception-ignore-for-prod-prerequisites")

	for _, pair in pairs(packs_to_unlink) do
		local pack1 = packs[pair[1]]
		local pack2 = packs[pair[2]]
		if pack1 and pack2 then
			pack1.unlink[pack2.name] = true
			pack2.unlink[pack1.name] = true
			log_debug(pack1.name .. " should not link with " .. pack2.name)
		end
	end
	for pack_id1, pack_id2 in pairs(scienceception_api) do
		local pack1 = packs[pack_id1]
		local pack2 = packs[pack_id2]
		if pack1 and pack2 then
			pack1.unlink[pack2.name] = true
			pack2.unlink[pack1.name] = true
			log_debug(pack1.name .. " should not link with " .. pack2.name)
		end
	end

	for _, pair in pairs(ignore_for_prod_research_dep) do
		local pack1 = packs[pair[1]]
		local pack2 = packs[pair[2]]
		if pack1 and pack2 then
			pack1.ignore_for_prod[pack2.name] = true
			pack2.ignore_for_prod[pack1.name] = true
			log_debug(pack1.name .. " will ignore " .. pack2.name .. "for prod research.")
		end
	end

	log_debug(">>>> Processing packs dependencies")
	for _, pack in pairs(packs) do
		log_debug("    - " .. pack.name)
		---@type PrerequisiteBranch[]
		local branches = {}
		for _, tech in pairs(pack.unlock_techs) do
			log_debug("        - " .. tech.name)
			local parents = process_tech_prerequisites(pack, packs, tech.prototype)
			if parents then
				table.insert(branches, {
					parents = parents,
					end_tech = tech
				})
			else
				log_debug("         x " .. tech.name .. " was dependant on " .. pack.name)
			end
		end

		if table_size(branches) > 0 then
			--look for the lowest amount of total parents
			local chosen_branch = nil
			for _, branch in pairs(branches) do
				if chosen_branch == nil or table_size(branch.parents) < table_size(chosen_branch) then 
					chosen_branch = branch
				end
			end
			if chosen_branch then
				pack.initial_technology = chosen_branch.end_tech
				for parent_id, parent in pairs(chosen_branch.parents) do
					pack.parents[parent_id] = parent
					packs[parent_id].children[pack.name] = pack
					log_debug("           " .. parent_id .. " is a parent of " .. pack.name)
				end
				for parent_id, parent in pairs(scienceception_api.get_forced_parents(pack.name)) do
					pack.parents[parent_id] = parent
					packs[parent_id].children[pack.name] = pack
					log_debug("           " .. parent_id .. " is a forced parent of " .. pack.name)
				end
			end
		end
	end

	local parents_to_remove = {}
	local children_to_remove = {}

	local do_parent_removal = settings.startup["scienceception-recipe-changes"].value == "direct-parent"
	for _, pack in pairs(packs) do
		pack.all_parents = sci_utils.shallowcopy(pack.parents)
		
		if do_parent_removal then
			for parent, _ in pairs(pack.parents) do
				for grandparent, _ in pairs(packs[parent].parents) do
					if pack.parents[grandparent] then
						table.insert(parents_to_remove, {pack, grandparent})
					end
				end
			end
		end
		
		for child, _ in pairs(pack.children) do
			for grandchild, _ in pairs(packs[child].children) do
				if pack.children[grandchild] then
					table.insert(children_to_remove, {pack, grandchild})
				end
			end
		end
	end

	for _, removal in pairs(parents_to_remove) do
		removal[1].parents[removal[2]] = nil
	end

	for _, removal in pairs(children_to_remove) do
		removal[1].children[removal[2]] = nil
	end

	if settings.startup["scienceception-recipe-changes"].value ~= "no-changes" then
		--Create intermediate items
		for _, pack in pairs(packs) do
			if pack.rocket_items and table_size(pack.parents) > 0 then
				for _, rocket_item in pairs(pack.rocket_items) do
					for _, product in pairs(rocket_item.prototype.rocket_launch_products) do
						if product.name == pack.name then generate_intermediate_item(pack, product) end
					end
				end
			end
		end
		
		--Update recipes
		log_debug(">>>> Updating packs' recipes")
		for _, pack in pairs(packs) do
			for recipe_id, _ in pairs(pack.recipes) do
				local recipe = data.raw["recipe"][recipe_id]
				local amount = 1
				for _, result in pairs(recipe.results) do
					if result.name == pack.name then amount = result.amount end
				end
				for _, ingredient in pairs(recipe.ingredients) do
					if ingredient.name == pack.name and ingredient.amount then amount = amount - ingredient.amount end
				end
				amount = math.max(amount, 1)
				
				for parent, _ in pairs(pack.parents) do
					for _, ingredient in pairs(recipe.ingredients) do
						if ingredient.name == parent.name then
							ingredient.amount = ingredient.amount + amount
							log_debug("Added " .. amount .. " x " .. parent .. " to existing ingredient in " .. recipe.name)
							goto continue
						end
					end
					table.insert(recipe.ingredients, {type="item", name=parent, amount=amount})
					log_debug("Added " .. amount .. " x " .. parent .. " as an ingredient in " .. recipe.name)
					::continue::
				end
			end
		end
	end

	if not settings.startup["scienceception-make-prod-researches"].value then return end

	--Add productivity techs
	log_debug(">>>> Adding productivity researches")

	local max_level = settings.startup["scienceception-prod-research-max"].value --[[@as int]]
	local additional_per_child = settings.startup["scienceception-prod-child-additional-level"].value --[[@as int]]
	local normal_bonus = settings.startup["scienceception-prod-research-effect"].value --[[@as int]]
	local maximum_bonus = settings.startup["scienceception-prod-maximum-bonus"].value --[[@as int]]
	
	for _, pack in pairs(packs) do
		log_debug("Making prod research for " .. pack.name)
		
		for to_ignore in pairs(pack.ignore_for_prod) do 
			pack.children[to_ignore] = nil
		end
		
		local child_count = table_size(pack.children)

		if child_count == 0 and settings.startup["scienceception-make-prod-for-leaves"].value then
			create_prod_research(pack, {[pack.name] = pack}, labs, 1, max_level, normal_bonus)
		elseif child_count == 1 then
			create_prod_research(pack, pack.children, labs, 1, max_level, normal_bonus)
		elseif child_count > 1 then
			local total_child_bonus = child_count * additional_per_child * normal_bonus
			local child_bonus = normal_bonus
			local child_levels = additional_per_child

			if total_child_bonus > maximum_bonus then
				child_levels = math.floor(maximum_bonus / (child_bonus * child_count))
				if child_levels == 0 then
					child_levels = 1
					child_bonus = math.floor(maximum_bonus / child_count)
					if child_bonus == 0 then child_levels = 0 end
				end
			end

			---@type ItemTable
			local prerequisites = nil
			if child_levels > 0 then
				prerequisites = {}
				for child_id, child in pairs(pack.children) do
					local children = {}
					children[child_id] = child
					local intermediate_tech = create_prod_research(pack, children, labs, 1, child_levels, child_bonus, {from = child_id})
					table.insert(prerequisites, intermediate_tech.name)
				end
			end
			total_child_bonus = child_count * child_levels * child_bonus

			local remains = (child_levels * child_bonus * child_count) % normal_bonus
			if maximum_bonus - total_child_bonus < normal_bonus then remains = maximum_bonus - total_child_bonus end
			if remains ~= 0 then
				--Intermediate level to round up
				child_levels = child_levels + 1
				local intermediate_tech = create_prod_research(pack, pack.children, labs, child_levels, child_levels, remains, {prerequisites = prerequisites})
				prerequisites = {intermediate_tech.name}
				total_child_bonus = total_child_bonus + remains
			end

			--Remaining normal level with all prerequisites
			local total_levels = math.min(max_level, child_levels + math.floor((maximum_bonus - total_child_bonus) / normal_bonus))
			if total_levels > child_levels or max_level == 0 then
				create_prod_research(pack, pack.children, labs, child_levels + 1, total_levels, normal_bonus, {prerequisites = prerequisites})
			end
		end
	end
end

return update_data