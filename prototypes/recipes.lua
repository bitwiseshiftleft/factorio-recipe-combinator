local have_cube = mods["Ultracube"] ~= nil

data:extend{{
    type = "recipe",
    name = "recipe-combinator-main",
    enabled = false,
    ingredients = {
        {type="item",name="arithmetic-combinator",  amount=1},
        {type="item",name="decider-combinator",     amount=1},
        {type="item",name="selector-combinator",    amount=1},
        {type="item",name="constant-combinator",    amount=1}
    },
    energy_required = 30,
    results = {{type="item", name="recipe-combinator-main", amount=1}},
    category = have_cube and "cube-fabricator-handcraft" or "crafting"
}}
