local util = require "__core__.lualib.util"

local empty_sheet = util.empty_sprite(1)
local empty_sheet_4 = { north=empty_sheet, south=empty_sheet, east=empty_sheet, west=empty_sheet }

local connection_points = {
    {wire={}, shadow={}},
    {wire={}, shadow={}},
    {wire={}, shadow={}},
    {wire={}, shadow={}}
}

-- Generic hidden combinator
local hidden_combinator = {
    destructible = false,
    max_health = 1,
    flags = { "not-blueprintable", "hide-alt-info", "placeable-off-grid", "not-on-map" },
    hidden = true,
    selectable_in_game = false,
    energy_source = {type = "void"},
    active_energy_usage = "1J",
    collision_box = {{-0.1,-0.1},{0.1,0.1}},
    selection_box = {{-0.1,-0.1},{0.1,0.1}},
    collision_mask = {layers={}},
    input_connection_bounding_box = {{0,0},{0,0}},
    output_connection_bounding_box = {{0,0},{0,0}},
    activity_led_offsets = {},
    rotatable = false,
    draw_circuit_wires = false,
    sprites = empty_sheet_4,
    input_connection_points = connection_points,
    output_connection_points = connection_points,
    circuit_connector_sprites = connection_points,
    activity_led_light_offsets = { {0,0},{0,0},{0,0},{0,0} },
    activity_led_sprites = empty_sheet_4,
    screen_light_offsets = { {0,0},{0,0},{0,0},{0,0} },
    activity_led_hold_time = 120,
    circuit_wire_max_distance = 9
}


-- Inserter for indicating (with its filters) what kind combinator we are
local indicator_inserter = {
    type = "inserter",
    name = "recipe-combinator-component-indicator-inserter",
    flags = { "not-blueprintable", "placeable-off-grid", "not-on-map" },
    icon_draw_specification = { shift={0,0}, scale=0.6, scale_for_many=0.7 },
    hand_base_picture   = util.empty_sprite(1),
    hand_open_picture   = util.empty_sprite(1),
    hand_closed_picture = util.empty_sprite(1),
    hand_base_shadow    = nil,
    hand_open_shadow    = nil,
    hand_closed_shadow  = nil,
    selectable_in_game = false,
    hidden = true,
    hidden_in_factoripedia = true,
    destructible = false,
    max_health = 1,
    rotatable = false,
	minable = nil,
    extension_speed = 1,
    rotation_speed = 1,
    collision_box = {{-0.3,-0.3},{0.3,0.3}},
    selection_box = {{-0.3,-0.3},{0.3,0.3}},
    draw_circuit_wires = false,
    collision_mask = {layers={}},
    energy_per_movement = "1J",
    energy_per_rotation = "1J",
    energy_source = { type = "void", },
    pickup_position = {0, 0},
    insert_position = {0, 0},
    draw_held_item = false,
    draw_inserter_arrow = false,
    chases_belt_frames = false,
    filter_count = 4,
    platform_picture = empty_sheet_4
}

local recipe_combinator = util.merge{data.raw["arithmetic-combinator"]["arithmetic-combinator"],{
    name = "recipe-combinator-main",
    factoriopedia_description = {"factoriopedia-description.recipe-combinator-main"},
    icons = {{
        icon = "__base__/graphics/icons/arithmetic-combinator.png",
        tint = {r=1,g=0.4,b=0.3,a=1}
    }},
    flags = {"get-by-unit-number"},
    minable = {mining_time = 0.5, result = "recipe-combinator-main"},
    placeable_by = {item="recipe-combinator-main",count=1},
    plus_symbol_sprites = {
        north={filename="__recipe_combinator__/graphics/rled.png",x=0},
        south={filename="__recipe_combinator__/graphics/rled.png",x=0},
        east={filename="__recipe_combinator__/graphics/rled.png",x=0},
        west={filename="__recipe_combinator__/graphics/rled.png",x=0}
    },
    sprites =  make_4way_animation_from_spritesheet{
        layers = {
            {
                scale = 0.5,
                filename = "__base__/graphics/entity/combinator/arithmetic-combinator.png",
                width = 144,
                height = 124,
                tint = {r=1,g=0.4,b=0.3,a=1},
                shift = util.by_pixel(0.5, 7.5)
            },
            {
                scale = 0.5,
                filename = "__base__/graphics/entity/combinator/arithmetic-combinator-shadow.png",
                width = 148,
                height = 156,
                shift = util.by_pixel(13.5, 24.5),
                draw_as_shadow = true
            }
        }
    },
    fast_replaceable_group = "recipe-combinator-main"
}}


data:extend{
    indicator_inserter,
    util.merge{hidden_combinator,{
        type = "arithmetic-combinator",
        name = "recipe-combinator-component-arithmetic-combinator"
    }},
    util.merge{hidden_combinator,{
        type = "decider-combinator",
        name = "recipe-combinator-component-decider-combinator"
    }},
    util.merge{hidden_combinator,{
        type = "selector-combinator",
        name = "recipe-combinator-component-selector-combinator"
    }},
    {
        type = "constant-combinator",
        name = "recipe-combinator-component-constant-combinator",
        flags = { "not-blueprintable", "hide-alt-info", "placeable-off-grid", "not-on-map" },
        destructible = false,
        max_health = 1,
        minable = nil,
        collision_box = {{-0.45,-0.45},{0.45,0.45}},
        selection_box = {{-0.5,-0.5},{0.5,0.5}},
        collision_mask = {layers={}},
        hidden = true,
        selectable_in_game = false,
        hidden_in_factoripedia = true,
        item_slot_count = 20,
        sprites = empty_sheet_4,
        circuit_wire_connection_points = connection_points,
        -- circuit_connector_sprites = connector_definitions.sprites,
        circuit_wire_max_distance = 4,
        draw_circuit_wires = false,
        activity_led_light_offsets = { {0,0},{0,0},{0,0},{0,0} }
    },
    recipe_combinator
}

if feature_flags["spoiling"] then data:extend{
    {
        type="recipe-category",
        name="recipe-combinator-spoilage-mechanic",
        hidden=true,
        hidden_in_factoripedia=true
    },
    {
        type="item",
        name="recipe-combinator-spoilage-mechanic",
        hidden_in_factoripedia=true,
        icon = "__recipe_combinator__/graphics/compost-bin.png",
        stack_size=1,
        auto_recycle=false,
        place_result="recipe-combinator-spoilage-mechanic"
    },
    {
        type="assembling-machine",
        name="recipe-combinator-spoilage-mechanic",
        crafting_categories={"recipe-combinator-spoilage-mechanic"},
        energy_usage="1J",
        energy_source={type="void"},
        crafting_speed=1,
        icon = "__recipe_combinator__/graphics/compost-bin.png",
        placeable_by = {item="recipe-combinator-spoilage-mechanic",count=1},
        hidden_in_factoripedia=true,
        factoriopedia_description = {"factoriopedia-description.recipe-combinator-spoilage-mechanic"}
    }
} end