require("__scienceception__.api")

if mods["tenebris"] then
	scienceception_api.add_pack_to_labs("bioluminescent-science-pack", {"all"})
end

if mods["janus"] then
	scienceception_api.add_pack_to_labs("janus-time-science-pack", {"all"})
end

if mods["EditorExtensions"] then
	scienceception_api.blacklist_lab("ee-super-lab")
end

if mods["Cerys-Moon-of-Fulgora"] then
	scienceception_api.blacklist_lab("cerys-lab-dummy")
	scienceception_api.blacklist_lab("cerys-lab")
	scienceception_api.blacklist_pack("cerys-science-pack")
	scienceception_api.blacklist_pack("fulgoran-cryogenics-progress")
end