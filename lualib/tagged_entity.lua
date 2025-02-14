-- lib for adding settings tags to entities
-- The filters get copied when settings are copied
-- They need to persist through copy/paste, upgrading, undo, redo, blueprinting, etc.

local event = require "lualib.event"
local myutil = require "lualib.util"
local M = {}

local undo_info_to_be_attached = {}
local tag_handlers = {} -- entity name --> custom handler action

local function my_storage()
    if not storage.tags_for_entities then
        storage.tags_for_entities = {}
    end
    return storage.tags_for_entities
end

local function get_tags_mutable(entity)
    local sto = my_storage()
    if entity.tags then return entity.tags end
    if not sto[entity.unit_number] then sto[entity.unit_number] = {} end
    return sto[entity.unit_number]
end

local function get_tags(entity)
    return table.deepcopy(my_storage()[entity.unit_number] or entity.tags)
end

local function set_tags(entity, tags)
    if entity.name == "entity-ghost" then entity.tags = tags end
    my_storage()[entity.unit_number] = table.deepcopy(tags)
end

local function clear_tags(entity)
    local sto = my_storage()
    if sto[entity.unit_number] then
        table.remove(sto, entity.unit_number)
    end
    if entity.tags then entity.tags = nil end
end

local function handle_tag_update(entity)
    -- Apply a custom function 
    if not entity or not entity.name or not tag_handlers[entity.name] then return end
    return tag_handlers[entity.name](entity, get_tags(entity))
end

local function on_built(ev)
    if ev.entity and ev.tags then
        my_storage()[ev.entity.unit_number] = table.deepcopy(ev.tags)
        handle_tag_update(ev.entity)
    elseif ev.entity and tag_handlers[ev.entity.name] then
        handle_tag_update(ev.entity)
    end
end

local function on_pre_build(ev)
    -- TODO: add info for fast replace
    -- TODO: apply ... something when pasting a blueprint over an entity
end

local function attach_undo_info(ev)
    -- Called one tick after you did something undoable
    -- Did it in the editor and there aren't any ticks?
    -- Currently, you're out of luck (TODO)
    for undoer,info in pairs(undo_info_to_be_attached) do
        local playerid,action,name,surface,surface_index,position,found =
            undoer[1],undoer[2],undoer[3],undoer[4],undoer[5],false
        local stack = (game.players[playerid] or {}).undo_redo_stack

        -- game.print("Adding undo information: "..serpent.line(info))
        for idx = 1,stack.get_undo_item_count() do
            local item = stack.get_undo_item(idx)
            for jdx,subitem in ipairs(item) do
                if subitem.type == action
                    and subitem.surface_index == surface_index
                    and subitem.target.name == name
                    and subitem.target.position.x == position.x
                    and subitem.target.position.y == position.y
                then
                    stack.set_undo_tag(idx, jdx, "tagged_entity_undo", info)
                    stack.set_undo_tag(idx, jdx, "tagged_entity_surface_index", surface_index)
                    found = true
                end
            end
            if found then break end
        end
    end
    
    undo_info_to_be_attached = {}
    event.unregister_event(defines.events.on_tick, attach_undo_info)
end

local function add_undo_info(player_index, entity, action, undo_info)
    -- Adds the given undo_info, which must be a string -> AnyBasic table, to the given entity
    undo_info_to_be_attached[{player_index, action, myutil.name_or_ghost_name(entity), entity.surface.index, entity.position}] = undo_info
    event.register_event(defines.events.on_tick, attach_undo_info) -- to fire next tick
end

local function on_player_mined_entity(ev)
    -- 
    local player_index = ev.player_index
    if player_index and get_tags(ev.entity) then
        add_undo_info(ev.player_index, ev.entity, "removed-entity", table.deepcopy(get_tags(ev.entity)))
    end
end

local function on_marked_for_deconstruction(ev)
    -- An item was marked for deconstruction.
    -- Set up the undo info for this
    local player_index = ev.player_index
    if player_index and get_tags(ev.entity) then
        add_undo_info(ev.player_index, ev.entity, "removed-entity", table.deepcopy(get_tags(ev.entity)))
    end
end

local function on_died(ev)
    -- TODO
end

local function on_entity_settings_pasted(ev)
    local old_tags = get_tags(ev.destination)
    local new_tags = get_tags(ev.source)
    if (old_tags or new_tags) and old_tags ~= new_tags then
        game.print("Transfer tags: "..serpent.block(new_tags))
        set_tags(ev.destination,new_tags)
        handle_tag_update(ev.destination)
    end
    add_undo_info(ev.player_index, ev.destination, "copy-entity-settings")
end

local function on_undo_applied(ev)
    for _,action in ipairs(ev.actions) do
        if action.tags
            and action.tags.tagged_entity_undo
            and action.tags.tagged_entity_surface_index -- not stored in action I think?
        then
            local surface = game.surfaces[action.tags.tagged_entity_surface_index]
            if surface then
                local entity = myutil.find_entity_or_ghost(surface,bpe.name,bpe.position)
                entity.set_tags(action.tags.tagged_entity_undo)
                handle_tag_update(entity)
            end
        end
    end
end

local function on_redo_applied(ev)
    on_undo_applied(ev)
end

local function on_player_setup_blueprint(ev)
    -- Based loosely on code by Quezler
    -- from factoryplanner-is-exportable-to-fake-factorissimo
    local player = game.get_player(ev.player_index)
    assert(player)
    if not player.connected then return end
  
    local blueprint = nil

    if player.blueprint_to_setup and player.blueprint_to_setup.valid_for_read then
        blueprint = player.blueprint_to_setup
    elseif player.cursor_stack.valid_for_read and player.cursor_stack.is_blueprint then
        blueprint = player.cursor_stack
    end
  
    if not blueprint or not blueprint.is_blueprint_setup() then return end
  
    local mapping = ev.mapping.get()
    local blueprint_entities = blueprint.get_blueprint_entities()
    local sto = my_storage()
    for _, blueprint_entity in ipairs(blueprint_entities or {}) do
        local entity = mapping[blueprint_entity.entity_number]
        if entity and sto[entity] then
            blueprint.set_blueprint_entity_tags(blueprint_entity.entity_number, sto[entity])
        end
    end
end

-- TODO: add filters
local register_event = event.register_event
register_event(defines.events.on_player_mined_entity, on_player_mined_entity)
register_event(defines.events.on_built_entity, on_built)
register_event(defines.events.on_robot_built_entity, on_built)
register_event(defines.events.on_built_entity, on_built)
register_event(defines.events.on_robot_built_entity, on_built)
register_event(defines.events.on_marked_for_deconstruction, on_marked_for_deconstruction)
register_event(defines.events.on_undo_applied, on_undo_applied)
register_event(defines.events.on_redo_applied, on_redo_applied)
register_event(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)
register_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)

M.get_tags_mutable = get_tags_mutable
M.get_tags = get_tags
M.set_tags = set_tags
M.clear_tags = clear_tags
M.add_undo_info = add_undo_info
M.tag_handlers = tag_handlers
return M
