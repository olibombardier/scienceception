data:extend({
  {
    type = "bool-setting",
    name = "scienceception-final-fixes",
    setting_type = "startup",
    default_value = true,
    order = "a"
  },{
    type = "bool-setting",
    name = "scienceception-include-parents-recursively",
    setting_type = "startup",
    default_value = false,
    order = "b"
  },{
    type = "string-setting",
    name = "scienceception-unlink-packs",
    setting_type = "startup",
    default_value = "military-science-pack,cryogenic-science-pack",
    auto_trim = true,
    allow_blank = true,
    order = "c"
  },{
    type = "string-setting",
    name = "scienceception-ignore-for-prod-prerequisites",
    setting_type = "startup",
    default_value = "logistic-science-pack,military-science-pack;military-science-pack,promethium-science-pack",
    auto_trim = true,
    allow_blank = true,
    order = "d"
  },{
    type = "bool-setting",
    name = "scienceception-make-prod-researches",
    setting_type = "startup",
    default_value = true,
    order = "prod-a"
  },{
    type = "string-setting",
    name = "scienceception-prod-count-formula",
    setting_type = "startup",
    default_value = "250 + 500 * (L - 1)",
    order = "prod-b"
  },{
    type = "double-setting",
    name = "scienceception-prod-research-effect",
    setting_type = "startup",
    default_value = 10,
    minimum_value = 0,
    order = "prod-c"
  },{
    type = "int-setting",
    name = "scienceception-prod-research-time",
    setting_type = "startup",
    default_value = 45,
    minimum_value = 1,
    order = "prod-d"
  },{
    type = "int-setting",
    name = "scienceception-prod-research-max",
    setting_type = "startup",
    default_value = 5,
    minimum_value = 0,
    order = "prod-e"
  },{
    type = "int-setting",
    name = "scienceception-prod-child-additional-level",
    setting_type = "startup",
    default_value = 2,
    minimum_value = 0,
    order = "prod-f",
    hidden = true
  },{
    type = "bool-setting",
    name = "scienceception-make-prod-for-leaves",
    setting_type = "startup",
    default_value = false,
    order = "prod-g"
  },
})