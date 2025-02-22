-- lib for adding settings tags to entities
-- The filters get copied when settings are copied
-- They need to persist through copy/paste, upgrading, undo, redo, blueprinting, etc.

local event = require "lualib.event"
local myutil = require "lualib.util"
local M = {}

local undo_info_to_be_attached = {}
local tag_handlers = {} -- entity name --> custom handler action when tags are applied
local paste_settings_handlers = {} -- entity name --> custom handler action(event) when settings pasted
local died_handlers = {} -- entity name --> custom handler action when died

local function my_storage()
    if not storage.tags_for_entities then
        storage.tags_for_entities = {}
    end
    return storage.tags_for_entities
end

local function garbage_collect_tags()
    local sto = my_storage()
    for u,_ in pairs(table.deepcopy(sto)) do
        if not game.get_entity_by_unit_number(u) then
            sto[u] = nil
        end
    end
    event.unregister_event(defines.events.on_tick, garbage_collect_tags)
end

local function on_load()
    event.register_event(defines.events.on_tick, garbage_collect_tags)
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
    if not entity then return end
    local sto = my_storage()
    if sto[entity.unit_number] then
        sto[entity.unit_number] = nil
    end
    if entity.tags then entity.tags = nil end
end

local function handle_tag_update(entity)
    -- Apply a custom function 
    if not entity or not entity.name or not tag_handlers[entity.name] then return end
    return tag_handlers[entity.name](entity, get_tags(entity))
end

local function on_configuration_changed()
    local sto = my_storage()
    for u,_ in pairs(table.deepcopy(sto)) do
        handle_tag_update(game.get_entity_by_unit_number(u))
    end
end

local function on_built(ev)
    if ev.entity and ev.tags then
        my_storage()[ev.entity.unit_number] = table.deepcopy(ev.tags)
        handle_tag_update(ev.entity)
    elseif ev.entity and tag_handlers[ev.entity.name] then
        handle_tag_update(ev.entity)
    end
end

local function attach_undo_info(ev)
    -- Called one tick after you did something undoable
    -- Did it in the editor and there aren't any ticks?
    -- Currently, you're out of luck (TODO)
    for undoer,info in pairs(undo_info_to_be_attached) do
        local playerid,action,name,surface_index,position,found =
            undoer[1],undoer[2],undoer[3],undoer[4],undoer[5],false
        local stack = (game.players[playerid] or {}).undo_redo_stack
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
    -- log("Add undo info to entity " .. tostring(entity.unit_number) .. ": " .. serpent.line(undo_info))
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
    if not ev.source or not ev.destination then return end
    if ev.source.name == ev.destination.name then
        local old_tags = get_tags(ev.destination)
        local new_tags = get_tags(ev.source)
        if (old_tags or new_tags) and old_tags ~= new_tags then
            set_tags(ev.destination,new_tags)
            handle_tag_update(ev.destination)
        end
        add_undo_info(ev.player_index, ev.destination, "copy-entity-settings")
    end
    if paste_settings_handlers[ev.destination.name] then
        paste_settings_handlers[ev.destination.name](ev)
    end
end

local function on_undo_applied(ev)
    for _,action in ipairs(ev.actions) do
        -- log("Undo applied, action= " .. serpent.line({action}) .. ", tags = " .. serpent.line(action.tags))
        if action.tags
            and action.tags.tagged_entity_undo
            and action.tags.tagged_entity_surface_index -- not stored in action I think?
        then
            local bpe = action.target
            local surface = game.surfaces[action.tags.tagged_entity_surface_index]
            if surface then
                local entity = myutil.find_entity_or_ghost(surface,bpe.name,bpe.position)
                set_tags(entity, action.tags.tagged_entity_undo)
                handle_tag_update(entity)
            end
        end
    end
end

local function get_blueprint_center(blueprint)
    -- based on get_blueprint_bounding_box in Bunshaman Modding Library

    -- set up grid snapping
    local snap = blueprint.blueprint_snap_to_grid
    local snx,sny = 1,1
    local sox,soy = 0,0
    if snap then
        snx,sny = blueprint.blueprint_snap_to_grid.x, blueprint.blueprint_snap_to_grid.y
    end
    if blueprint.blueprint_position_relative_to_grid then
        sox,soy = blueprint.blueprint_position_relative_to_grid.x, blueprint.blueprint_position_relative_to_grid.y
    end
    local huge,min,max = math.huge,math.min,math.max
    local epsilon = 0.000001
    local minx,maxx,miny,maxy = huge,-huge,huge,-huge

    local function cell_of(x,y)
        if not snap then return x,y end
        x=sox+math.floor((x-sox)/snx)*snx
        y=soy+math.floor((x-soy)/sny)*sny
        return x,y
    end

    for _, component in ipairs(blueprint.get_blueprint_entities() or {}) do
        local selection_box = prototypes.entity[component.name].selection_box
        local xlo,ylo = selection_box.left_top.x, selection_box.left_top.y
        local xhi,yhi = selection_box.right_bottom.x, selection_box.right_bottom.y
        local x,y = component.position.x,component.position.y

        -- If a pasted entity is rotated, it will have its own extra direction
        local entity_direction = component.direction
        if entity_direction and entity_direction % 4 == 0 then
            local xc,yc = (xlo+xhi)/2,(ylo+yhi)/2
            while entity_direction >= 4 do
                xlo,ylo,xhi,yhi = xc-(yhi-yc), yc-(xhi-xc), xc+(yhi-yc), yc+(xhi-xc)
                entity_direction = entity_direction - 4     -- Rotate 90 degrees counter-clockwise
            end
        end
        xlo,ylo = cell_of(x+xlo,y+ylo)
        xhi,yhi = cell_of(x+xhi,y+yhi)
        minx,maxx,miny,maxy = min(minx,xlo),max(maxx,xhi),min(miny,ylo),max(maxy,yhi)
    end
    for _, component in ipairs(blueprint.get_blueprint_tiles() or {}) do
        local x,y = component.position.x,component.position.y
        local xlo,ylo = cell_of(x+0.0001,y+0.0001)
        local xhi,yhi = cell_of(x+0.9999,y+0.9999)
        minx,maxx,miny,maxy = min(minx,xlo),max(maxx,xhi),min(miny,ylo),max(maxy,yhi)
    end
    return cell_of((minx+maxx)/2, (miny+maxy)/2) -- I guess?
end

local function get_transform_matrix(direction,flip_horizontal,flip_vertical)
    local a,b,c,d = 1,0,0,1
    while direction >= 4 do
        a,b,c,d = -c,-d,a,b
        direction=direction-4
    end
    if flip_horizontal then a,c = -a,-c end
    if flip_vertical then b,d = -b,-d end
    return a,b,c,d
end

local function apply_transform_matrix(a,b,c,d,x,y)
    return a*x+b*y, c*x+d*y
end

local function on_pre_build(ev)
    local player = game.get_player(ev.player_index)
    if not player or not player.connected or not player.surface or not player.is_cursor_blueprint() then return end
    local surface = player.surface
    local blueprint = player.cursor_record or player.cursor_stack
    local a,b,c,d = get_transform_matrix(ev.direction,ev.flip_horizontal,ev.flip_vertical)

    if blueprint.type == "blueprint-book" then
        if player.cursor_record then
            blueprint = blueprint.contents[blueprint.get_active_index(player)]
        else
            blueprint = blueprint.get_inventory(defines.inventory.item_main)[blueprint.active_index]
        end
    end
    if not blueprint or blueprint.type ~= "blueprint" then return end

    local xc,yc = get_blueprint_center(blueprint)
    local xxc,yyc = apply_transform_matrix(a,b,c,d,xc,yc)
    local evx,evy = ev.position.x, ev.position.y

    -- Apply snapping to grid.  If there is no grid, it has size 1x1 at position 0x0
    local snx,sny = 1,1
    local sox,soy = 0,0
    if blueprint.blueprint_snap_to_grid then
        snx,sny = blueprint.blueprint_snap_to_grid.x, blueprint.blueprint_snap_to_grid.y
        if blueprint.blueprint_position_relative_to_grid then
            sox,soy = blueprint.blueprint_position_relative_to_grid.x, blueprint.blueprint_position_relative_to_grid.y
        end
        snx,sny = apply_transform_matrix(a,b,c,d,snx,sny)
        sox,soy = apply_transform_matrix(a,b,c,d,sox,soy)
        snx,sny = math.abs(snx),math.abs(sny)

        evx = snx*math.floor((evx-xxc-sox)/snx)+sox+xxc
        evy = sny*math.floor((evy-yyc-soy)/sny)+soy+yyc
    else
        evx = math.floor(evx-xxc+0.5)+xxc
        evy = math.floor(evy-yyc+0.5)+yyc
    end

    for idx,blue_ent in ipairs(blueprint.get_blueprint_entities()) do
        local x,y = blue_ent.position.x-xc, blue_ent.position.y-yc
        x,y = apply_transform_matrix(a,b,c,d,x,y)
        x,y = evx+x, evy+y
        -- game.print("Positions: " .. serpent.line({ev.position,{snx,sny},{sox,soy},{evx,evy},blue_ent.position,{xc,yc},{x,y}}))
        for _,ent in ipairs(surface.find_entities_filtered{
            area = {{x,y},{x,y}},
            name = blue_ent.name
         }) do
            if ent.name == blue_ent.name and get_tags(ent) then
                set_tags(ent, blue_ent.tags)
                handle_tag_update(ent)
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
    if not player or not player.connected then return end
  
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
        if entity and sto[entity.unit_number] then
            blueprint.set_blueprint_entity_tags(blueprint_entity.entity_number, sto[entity.unit_number])
        end
    end
end

-- TODO: add filters
local register_event = event.register_event
register_event(defines.events.on_player_mined_entity, on_player_mined_entity)
register_event(defines.events.on_built_entity, on_built)
register_event(defines.events.on_robot_built_entity, on_built)
register_event(defines.events.on_built_entity, on_built)
register_event(defines.events.on_pre_build, on_pre_build)
register_event(defines.events.on_robot_built_entity, on_built)
register_event(defines.events.on_marked_for_deconstruction, on_marked_for_deconstruction)
register_event(defines.events.on_undo_applied, on_undo_applied)
register_event(defines.events.on_redo_applied, on_redo_applied)
register_event(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)
register_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)

script.on_configuration_changed(on_configuration_changed)
script.on_load(on_load)

M.get_tags_mutable = get_tags_mutable
M.get_tags = get_tags
M.set_tags = set_tags
M.clear_tags = clear_tags
M.add_undo_info = add_undo_info
M.tag_handlers = tag_handlers
M.paste_settings_handlers = paste_settings_handlers
M.died_handlers = died_handlers
M.my_storage = my_storage
return M
