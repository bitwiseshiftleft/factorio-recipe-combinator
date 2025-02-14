M = {}

local function name_or_ghost_name(entity)
    if entity.name == "entity-ghost" then
        return entity.ghost_name
    else
        return entity.name
    end
end

local function find_entity_or_ghost(surface,name,position,force)
    -- find an entity or ghost with the given parameters
    local search = surface.find_entities_filtered{
        ghost_name=name, position=position, force=force, limit=1
    }
    if search and search[1] then return search[1] end
    search = surface.find_entities_filtered{
        name=name, position=position, force=force, limit=1
    }
    if search and search[1] then return search[1] end
    return nil
end

M.find_entity_or_ghost = find_entity_or_ghost
M.name_or_ghost_name = name_or_ghost_name

return M