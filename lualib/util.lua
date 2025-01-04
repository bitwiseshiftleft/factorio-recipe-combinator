M = {}

local function format_power(w)
    -- TODO: seems like this should be standard
    local unit = ""
    if w >= 1e12 then
        w = w / 1e12
        unit = "T"
    elseif w >= 1e9 then
        w = w / 1e9
        unit = "G"
    elseif w >= 1e6 then
        w = w / 1e6
        unit = "M"
    elseif w >= 1e3 then
        w = w / 1e3
        unit = "k"
    end
    if w == math.floor(w) then
        return string.format("%d %sW", w, unit)
    else
        return string.format("%.2f %sW", w, unit)
    end
end

local function vector_add(v1,v2) return {x=v1.x+v2.x, y=v1.y+v2.y} end
local function vector_sub(v1,v2) return {x=v1.x-v2.x, y=v1.y-v2.y} end

local function name_or_ghost_name(entity)
    if entity.name == "entity-ghost" then
        return entity.ghost_name
    else
        return entity.name
    end
end

M.name_or_ghost_name = name_or_ghost_name
M.format_power = format_power
M.vector_add = vector_add
M.vector_sub = vector_sub

return M