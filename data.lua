require("__scienceception__.api")

--In case automation science pack are unlocked from the start and not a trigger tech
scienceception_api.force_relashionship({
	parent_id = "automation-science-pack",
	child_id = "logistic-science-pack",
	only_if_parent_enabled = true,
})

if mods["tenebris"] then
	scienceception_api.add_pack_to_labs("bioluminescent-science-pack", {"all"})
end

if mods["janus"] then
	scienceception_api.add_pack_to_labs("janus-time-science-pack", {"all"})
end

if mods["EditorExtensions"] then
	scienceception_api.blacklist_lab("ee-super-lab")
end

if mods["Cerys-Moon-of-Fulgora"] then --Forcing Cerys packs to have science packs as ingredient creates a softlock
	scienceception_api.blacklist_lab("cerys-lab-dummy")
	scienceception_api.blacklist_lab("cerys-lab")
	scienceception_api.blacklist_pack("cerys-science-pack")
	scienceception_api.blacklist_pack("fulgoran-cryogenics-progress")
end