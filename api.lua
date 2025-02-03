
---@class LabMetadata
---@field name data.EntityID
---@field inputs data.ItemID[]
---@field item ItemMetadata?

---@class TechnologyMetadata
---@field name data.TechnologyID
---@field prototype data.TechnologyPrototype?
---@field prerequisites data.TechnologyID[]?
---@field prerequisites_to data.TechnologyID[]?
---@field unlock_packs table<data.ItemID, boolean>?

---@class ItemMetadata
---@field name data.ItemID
---@field prototype data.ItemPrototype?
---@field parents ItemTable
---@field all_parents ItemTable
---@field children ItemTable
---@field recipes table<data.RecipeID, RecipeMetadata>
---@field rocket_items ItemTable?
---@field unlock_techs TechnologyTable
---@field component_item data.ItemID?
---@field unlink table<data.ItemID, boolean>
---@field ignore_for_prod table<data.ItemID, boolean>
---@field initial_technology TechnologyMetadata
---@field starting_recipe boolean

---@class RelashionshipOptions
---@field parent_id data.ItemID
---@field child_id data.ItemID
---@field only_if_parent_enabled boolean? The relationshp will be forced only if the parent is enabled by default from the start

if scienceception_api then return end

---@class ScienceceptionAPI
scienceception_api = {
	---@type table<data.ItemID, boolean>
	pack_blacklist = {},
	---@type table<data.EntityID, boolean>
	lab_blacklist = {},
	---@type table<data.ItemID, data.ItemID>
	unlinked_pack = {},
	---@type table<data.EntityID|"all", table<data.ItemID, boolean>>
	proxy_inputs = {
		all = {}
	},
	---@type RelashionshipOptions[]
	forced_relations = {},
	---@type ItemTable
	packs = nil
}

---Forces Sceienceception to ignore a pack
---@param pack_id data.ItemID
function scienceception_api.blacklist_pack(pack_id)
	scienceception_api.pack_blacklist[pack_id] = true
end

---Forces Sceienceception to ignore a lab
---@param lab_id data.EntityID
function scienceception_api.blacklist_lab(lab_id)
	scienceception_api.lab_blacklist[lab_id] = true
end

--- Breaks the relationshp between two packs
---@param pack_id1 data.ItemID
---@param pack_id2 data.ItemID
function scienceception_api.unlink_pack(pack_id1, pack_id2)
	scienceception_api.unlinked_pack[pack_id1] = pack_id2
end

---Makes the pack act as if it was added to the specified labs output even if the actual lab prototype doesn't have it in its inputs
---@param pack_id data.ItemID
---@param labs data.EntityID[]
function scienceception_api.add_pack_to_labs(pack_id, labs)
	for _, lab in pairs(labs) do
		scienceception_api.proxy_inputs[lab] = scienceception_api.proxy_inputs[lab] or {}
		scienceception_api.proxy_inputs[lab][pack_id] = true
	end
end

---Force a pack to act as a parent (a previous pack) of another if they both are found
---@param options RelashionshipOptions
function scienceception_api.force_relashionship(options)
	table.insert(scienceception_api.forced_relations, options)
end

---Return the packs that are forced to be considered a parent of the specified pack
---@param pack_id data.ItemID
---@return ItemTable
function scienceception_api.get_forced_parents(pack_id)
	local result = {}
	for _, relation in pairs(scienceception_api.forced_relations) do
		if relation.child_id == pack_id then
			local parent = scienceception_api.packs[relation.parent_id]
			if parent then
				if relation.only_if_parent_enabled then
					if parent.starting_recipe then result[relation.parent_id] = parent end
				else
					result[relation.parent_id] = parent
				end
			end
		end
	end
	return result
end