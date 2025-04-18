local have_cube = mods["Ultracube"] ~= nil
local tech = data.raw.technology[
    have_cube and "cube-advanced-combinatorics"
    or "advanced-combinators"
]
table.insert(tech.effects,{
    type = "unlock-recipe",
    recipe = "recipe-combinator-main"
})
