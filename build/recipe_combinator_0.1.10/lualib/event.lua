local M = {}

-- Cribbed from miniloaders event dispatcher
local handlers_for = {}
local function dispatch(event)
    for handler in pairs(handlers_for[event.name]) do
        handler(event)
    end
end

register_event = function(event, handler, filters)
    local handlers = handlers_for[event]
    if not handlers then
      handlers = {}
      handlers_for[event] = handlers
    end

    if not next(handlers) then
      script.on_event(event, dispatch, filters)
    end

    handlers[handler] = true
end

unregister_event = function(event, handler)
    local handlers = handlers_for[event]
    if not handlers then return end
    handlers[handler] = nil
    if not next(handlers) then
      script.on_event(event, nil)
    end
end

M.register_event = register_event
M.unregister_event = unregister_event

return M