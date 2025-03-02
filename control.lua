
local tagged_entity = require "lualib.tagged_entity"
local event = require "lualib.event"
local gui = require "lualib.gui"
local circuit = require "lualib.circuit"
local myutil = require "lualib.util"

circuit.init()

tagged_entity.tag_handlers["recipe-combinator-main"] = function(entity,tags)
    if tags == nil then
        tags = circuit.DEFAULT_ROLLUP
        tagged_entity.set_tags(entity,tags)
    end
    circuit.rebuild_combinator(entity)
end

tagged_entity.paste_settings_handlers["recipe-combinator-main"] = function(ev)
    local entity = ev.destination
    if not entity then return end
    local control = entity.get_or_create_control_behavior()
    control.parameters = {operation="+"}
end

local function on_died(ev, mined_by_robot)
    local entity = ev.entity or ev.ghost
    -- TODO: save undo information so that we can rebuild it
    if entity and entity.type ~= "entity-ghost"
        and entity.name == "recipe-combinator-main"
    then
        circuit.destroy_components(entity)
        -- Close players' windows
        for _,player in pairs(game.players) do
            if player.gui.screen[gui.WINDOW_ID] then
                gui.close(ev.player_index, true)
            end
        end
    end
    tagged_entity.clear_tags(ev.entity)
end

local function on_gui_opened(ev)
    if ev.gui_type ~= defines.gui_type.entity then return end
    local entity = ev.entity
    local player = game.get_player(ev.player_index)
    if not player then return end

    -- Cribbed from Cybersyn combinator
    if entity.valid and myutil.name_or_ghost_name(entity) == "recipe-combinator-main" then
        gui.open(ev.player_index, entity)
    elseif player.gui.screen[gui.WINDOW_ID] then
        gui.close(ev.player_index)
        return
    end
end

local function on_gui_closed(ev)
    -- TODO: this only supports closing of one window; need to support sub-windows for pickers etc.
    if not ev.element then return end
    if ev.element.name ~= gui.WINDOW_ID then return end
    local player = game.get_player(ev.player_index)
    if not player then return end
    if player.gui.screen[gui.WINDOW_ID] then
        gui.close(ev.player_index)
    end
end

local function rebuild_limited_combinators(force)
    for u,tags in pairs(tagged_entity.my_storage()) do
        if tags["include_disabled"] == false then
            local entity = game.get_entity_by_unit_number(u)
            if entity then circuit.rebuild_combinator(entity) end
        end
    end
    event.unregister_event(defines.events.on_tick, rebuild_limited_combinators)
end

local register_event = event.register_event
local function on_research_finished(ev)
    register_event(defines.events.on_tick, rebuild_limited_combinators)
end

local filters = {{filter="name", name="recipe-combinator-main"}}

register_event(defines.events.on_entity_died, on_died, filters)
register_event(defines.events.on_player_mined_entity, on_died, filters)
register_event(defines.events.on_pre_ghost_deconstructed, on_died, filters)
register_event(defines.events.on_robot_mined_entity, on_died, filters)
register_event(defines.events.script_raised_destroy, on_died, filters)

register_event(defines.events.on_gui_opened, on_gui_opened)
register_event(defines.events.on_gui_closed, on_gui_closed)
register_event(defines.events.on_research_finished, on_research_finished)
register_event(defines.events.on_technology_effects_reset, on_research_finished)
-- register_event(defines.events.on_player_rotated_entity, on_rotated)
