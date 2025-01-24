local sci_utils = require("sci_utils")
local item_metadata = require("item-metadata")

local debug = false
local function log_debug(text)
	if debug then log(text) end
end

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
	intermediate.localised_name = {"item-name.pack-component", localised_pack_name}
	intermediate.localised_description = {"item-description.pack-component", pack.name}
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
		localised_name = {"recipe-name.from-component" ,localised_pack_name}
		--TODO new icon
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
local function process_tech_prerequisites(pack, packs, tech, visited, stoppers)
	visited = visited or {}
	stoppers = stoppers or {}
	if visited[tech.name] then return end
	visited[tech.name] = true
	if tech.prerequisites == nil then return
	end
	
	for _, prerequisite_id in pairs(tech.prerequisites) do
		local stop_search = false
		local branch_stoppers = table.deepcopy(stoppers)
		for _, other in pairs(packs) do
			if other.unlock_techs[prerequisite_id] then
				if pack.unlink[other.name] or stoppers[other.name] then
					stop_search = true
				else 
					pack.parents[other.name] = other
					other.children[pack.name] = pack
					
					for stopper in pairs(other.unlink) do
						branch_stoppers[stopper] = true
					end
					
					log_debug(pack.name .. " is a child of " .. other.name)
				end
			end
		end
		if not stop_search then
			local prerequisite = data.raw["technology"][prerequisite_id]
			if prerequisite == nil then
				log(tech.name .. "'s prerequisite " .. prerequisite_id .. "doesn't exists.")
			else
				process_tech_prerequisites(pack, packs, prerequisite, visited, branch_stoppers)
			end
		end
	end
end

local function update_data()
	local labs = item_metadata.get_lab_data()
	
	if mods["Cerys-Moon-of-Fulgora"] then
		labs["cerys-lab-dummy"] = nil
	end

	local packs = item_metadata.get_metadata_from_items(labs)

	local packs_to_unlink = sci_utils.read_pairs_list(settings.startup["scienceception-unlink-packs"].value, "scienceception-unlink-packs")
	local ignore_for_prod_research_dep = sci_utils.read_pairs_list(settings.startup["scienceception-ignore-for-prod-prerequisites"].value, "scienceception-ignore-for-prod-prerequisites")
	
	

	--Get settings for packs
	for _, pair in pairs(packs_to_unlink) do
		local pack1 = packs[pair[1]]
		local pack2 = packs[pair[2]]
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
		for _, tech in pairs(pack.unlock_techs) do
			log_debug("   - " .. pack.name)
			process_tech_prerequisites(pack, packs, tech.prototype)
		end
	end

	local parents_to_remove = {}
	local children_to_remove = {}

	local do_parent_removal = not settings.startup["scienceception-include-parents-recursively"].value
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
			for parent, _ in pairs(pack.parents) do 
				table.insert(recipe.ingredients, {type="item", name=parent, amount=amount})
				log_debug("Added " .. amount .. " x " .. parent .. " as an ingredient in " .. recipe.name)
			end
		end
	end

	if not settings.startup["scienceception-make-prod-researches"].value then return end

	--Add productivity techs
	log_debug(">>>> Adding productivity researches")
	for _, pack in pairs(packs) do
		log_debug("Making prod research for " .. pack.name)
		local ingredients = {{pack.name, 1}}
		
		for to_ignore in pairs(pack.ignore_for_prod) do 
			pack.children[to_ignore] = nil
		end
		
		if table_size(pack.children) == 0 and not settings.startup["scienceception-make-prod-for-leaves"].value then 
			goto continue 
		end
		for child, _ in pairs(pack.children) do table.insert(ingredients, {child, 1}) end
		for parent, _ in pairs(pack.all_parents) do table.insert(ingredients, {parent, 1}) end
		
		local prerequisites = {}
		if table_size(pack.children) == 0 then
			--TODO: Handle when multiple research lead to the same packs
			local initial_tech_index = next(pack.unlock_techs)
			if initial_tech_index then prerequisites = {initial_tech_index} end
		else
			for _, child in pairs(pack.children) do
				local initial_tech_index = next(child.unlock_techs)
				if initial_tech_index then table.insert(prerequisites, initial_tech_index) end
			end
		end
		
		local available_labs = item_metadata.filter_lab_by_inputs(labs, ingredients)
		
		-- TODO put in a function so can be used for spred research
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
					if table_size(available_labs) == 0 then goto continue end
				end
			end
			-- Reomve incompatible packs (TODO?: find a way to select a good lab to support)
			local _, lab = next(available_labs, nil)
			new_ingredients = {}
			for _, ingredient in pairs(ingredients) do
				for _, input in pairs(lab.inputs) do
					if input == ingredient[1] then table.insert(new_ingredients, ingredient)
					end
				end
			end
			ingredients = new_ingredients
		end
		
		
		local effects = {}
		for recipe, _ in pairs(pack.recipes) do
			table.insert(effects, {
				type = "change-recipe-productivity",
				recipe = recipe,
				change = settings.startup["scienceception-prod-research-effect"].value / 100
			})
		end
		
		---@type data.TechnologyPrototype
		local tech = {
			type = "technology",
			name = pack.name .. "-productivity-1",
			localised_name = {"technology-name.science-pack-productivity", sci_utils.get_item_localised_name(pack.name) },
			localised_description = {"technology-description.science-pack-productivity", pack.name },
			order = "scienceception-prod-" .. pack.name,
			unit = {
				count_formula = settings.startup["scienceception-prod-count-formula"].value,
				time = 60,
				ingredients = ingredients
			},
			max_level = settings.startup["scienceception-prod-research-max"].value,
			prerequisites = prerequisites,
			effects = effects
		}
		
		--TOOD: What to do when multiple tech unlock to the same pack?
		if pack.unlock_techs[1] then
			tech.icons = util.technology_icon_constant_recipe_productivity(pack.unlock_techs[1].icon)
		else
			local base_item = data.raw["tool"][pack.name]
			tech.icons = util.technology_icon_constant_recipe_productivity(base_item.icon)
			tech.icons[1].icon_size = base_item.icon_size
		end
		
		data:extend({tech})
		::continue:: --Skip this research
	end

	--TODO maybe:
	-- If the productivity research prerequisites first levels should be spread with less prerequisites in case where there are multiple parents prerequisites (bool, spread-prerequisites)
end

return update_data