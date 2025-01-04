-- TODO: copy back from router control.lua
local undo = require "lualib.undo"
local event = require "lualib.event"
local gui = require "lualib.gui"
local circuit = require "lualib.circuit"
local disable_picker_dollies = require "lualib.disable_picker_dollies"
disable_picker_dollies.disable_picker_dollies()

local function name_or_ghost_name(entity)
    return ((entity.name == "entity-ghost") and entity.ghost_name) or entity.name
end

local function on_undo_applied(ev)
    -- TODO: undo pasting settings
    game.print("Event TODO: undo applied")
end

local function on_marked_for_deconstruction(ev)
    -- TODO: save undo info
    game.print("Event TODO: Marked for deconstruction")
end

local function destroy_components(entity)
    -- Destroy recipe combinator components that are children of this item
    local children = entity.surface.find_entities_filtered{area=entity.bounding_box}
    local undo_info = {}
    for i,child in ipairs(children) do
        if string.find(child.name, '^recipe%-combinator%-component%-') then
            child.destroy()
        end
    end
end

local function on_died(ev, mined_by_robot)
    local entity = ev.entity or ev.ghost
    -- TODO: save undo information so that we can rebuild it
    if entity and entity.type ~= "entity-ghost"
        and entity.name == "recipe-combinator-main"
    then
        destroy_components(entity)
    end
    game.print("Event TODO: Entity died")
end

local function on_built(ev)
    local entity = ev.created_entity
    if entity == nil then entity = ev.entity end
    -- TODO
    if entity == nil or entity.name ~= "recipe-combinator-main" then return end
    -- TODO select plants, other options ...
    circuit.build_recipe_info_combinator(entity,{"assembling-machine-3", "chemical-plant", "oil-refinery"})
end

local function on_settings_pasted(ev)
    -- TODO
    game.print("Event TODO: Settings pasted")
end

local function on_gui_opened(ev)
    if ev.gui_type ~= defines.gui_type.entity then return end
    local entity = ev.entity
    local player = game.get_player(ev.player_index)
    if not player then return end

    -- Cribbed from Cybersyn combinator
    if entity.valid and name_or_ghost_name(entity) == "recipe-combinator-main" then
        gui.open(ev.player_index, entity)
    elseif player.gui.screen[gui.WINDOW_ID] then
        gui.close(ev.player_index)
        return
    end
    game.print("Event TODO: GUI opened")
end

local filters = {{filter="name", name="recipe-combinator-main"}}
local register_event = event.register_event
register_event(defines.events.on_built_entity, on_built, filters)
register_event(defines.events.on_robot_built_entity, on_built, filters)
-- register_event(defines.events.on_pre_build, on_pre_build, filters)
register_event(defines.events.script_raised_built, on_built, filters)
register_event(defines.events.script_raised_revive, on_built, filters)

register_event(defines.events.on_entity_died, on_died, filters)
register_event(defines.events.on_player_mined_entity, on_died, filters)
register_event(defines.events.on_pre_ghost_deconstructed, on_died, filters)
register_event(defines.events.on_robot_mined_entity, on_died, filters)
register_event(defines.events.script_raised_destroy, on_died, filters)

register_event(defines.events.on_marked_for_deconstruction, on_marked_for_deconstruction, filters)
register_event(defines.events.on_undo_applied, on_undo_applied) -- no filter for this

register_event(defines.events.on_entity_settings_pasted, on_settings_pasted)
register_event(defines.events.on_gui_opened, on_gui_opened)
-- register_event(defines.events.on_player_rotated_entity, on_rotated)
