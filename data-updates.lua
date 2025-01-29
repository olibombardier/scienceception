local update_data = require("main")

if not settings.startup["scienceception-final-fixes"].value then
	update_data()
end
