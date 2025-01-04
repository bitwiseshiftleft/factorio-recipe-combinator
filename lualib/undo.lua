local event = require "lualib.event"
local myutil = require "lualib.util"
local M = {}

local undo_info_to_be_attached = {}
local function attach_undo_info(ev)
    -- Fires on the tick after any relevant undo-able event occurs
    -- attaches undo_info_to_be_attached to the undo stack

    for undoer,info in pairs(undo_info_to_be_attached) do
        local stack = game.players[undoer[1]].undo_redo_stack
        local name = undoer[2]
        local surface_index = undoer[3]
        local position = undoer[4]
        local found = false

        -- game.print("Adding undo information: "..serpent.line(info))
        for idx = 1,stack.get_undo_item_count() do
            local item = stack.get_undo_item(idx)
            for jdx,subitem in ipairs(item) do
                if subitem.type == "removed-entity"
                    and subitem.surface_index == surface_index
                    and subitem.target.name == name
                    and subitem.target.position.x == position.x
                    and subitem.target.position.y == position.y
                then
                    -- game.print("Found item at idx,jdx,info = "..serpent.line({idx,jdx,info}))
                    stack.set_undo_tag(idx, jdx, "router_restore_connections", info)
                    found = true
                end
            end
            if found then break end
        end
        -- if not found then
        --     game.print("Undo info not found: "..serpent.line({undoer,info})) -- TODO remove
        -- end
    end
    undo_info_to_be_attached = {} -- hopefully we attached them all?

    -- Remove ourselves until future undo-able events occur
    event.unregister_event(defines.events.on_tick, attach_undo_info)
end

local function add_undo_destroy_info(player_index, entity, undo_info)
    -- Adds the given undo_info, which must be a string -> AnyBasic table, to the given entity
    undo_info_to_be_attached[{player_index, myutil.name_or_ghost_name(entity), entity.surface.index, entity.position}] = undo_info
    event.register_event(defines.events.on_tick, attach_undo_info) -- to fire next tick
end

local function get_undo_restore_connections(subitem)
    -- Returns the item's undo info.router_restore_connections
    if subitem.type ~= "removed-entity" then return {} end
    if subitem.tags and subitem.tags.router_restore_connections then
        -- normally they're stored in the tags
        return subitem.tags.router_restore_connections
    else
        -- possibly we are in the editor, and we have deleted the item but then undone it in the same tick
        -- check through the undo info not yet attached
        for undoer,info in pairs(undo_info_to_be_attached) do
            local name = undoer[2]
            local surface_index = undoer[3]
            local position = undoer[4]
            if subitem.surface_index == surface_index
                and subitem.target.name == name
                and subitem.target.position.x == position.x
                and subitem.target.position.y == position.y
            then return info end
        end
    end
    return {}
end

M.add_undo_destroy_info = add_undo_destroy_info
M.get_undo_restore_connections = get_undo_restore_connections

return M
