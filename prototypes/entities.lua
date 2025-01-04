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

data:extend{
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
    util.merge{data.raw["arithmetic-combinator"]["arithmetic-combinator"],{
        name = "recipe-combinator-main",
        icons = {{
            icon = "__base__/graphics/icons/arithmetic-combinator.png",
            tint = {r=1,g=0.7,b=0.5,a=1}
        }},
        sprites =  make_4way_animation_from_spritesheet{
            layers = {
                {
                    scale = 0.5,
                    filename = "__base__/graphics/entity/combinator/arithmetic-combinator.png",
                    width = 144,
                    height = 124,
                    tint = {r=1,g=0.7,b=0.5,a=1},
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
}
