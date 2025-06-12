local M = {}

local function disable_picker_dollies()
    if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["add_blacklist_name"] then
        local to_blacklist = {"recipe-combinator-main"}
        for _,other in ipairs(to_blacklist) do
            remote.call("PickerDollies", "add_blacklist_name", other, true)
        end
    end
end

M.disable_picker_dollies = disable_picker_dollies
return M
