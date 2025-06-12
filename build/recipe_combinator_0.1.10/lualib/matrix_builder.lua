

local band = bit32.band
local bor  = bit32.bor

local M = {}

-- Placeholder: cause something to be a valid input even if there is no info to show
local MAKE_VALID_ANYWAY = {type="MAKE_VALID_ANYWAY", name="MAKE_VALID_ANYWAY"}

local HAVE_QUALITY = script.feature_flags.quality and script.feature_flags.space_travel

-- Supported matrix flags
-- FLAG_DENSE: use a dense flags-matrix layout.  Better for modules.
-- Can't support multiply or quality.  All entries must be 1
local FLAG_DENSE          = 1

-- FLAG_MULTIPLY: multiply this entry by the input quantity
local FLAG_MULTIPLY       = 2

-- FLAG_NOQUAL: this output's quality isn't based on the input quality
local FLAG_NOQUAL         = 4
if not HAVE_QUALITY then FLAG_NOQUAL = 0 end

-- FLAG_NORMAL_INPUT: this row is only valid if the input has normal quality (e.g. a fluid)
local FLAG_NORMAL_INPUT   = 8
if not HAVE_QUALITY then FLAG_NORMAL_INPUT = 0 end

-- FLAG_RED: output this info on the red wire (TODO)
-- FLAG_GREEN: output this info on the green wire (TODO)
local FLAG_RED,FLAG_GREEN = 16,32

-- FLAG_NEGATE: causes elements added to be negated
-- This flag doesn't stay in the flags field: it gets applied immediately
local FLAG_NEGATE         = 1024

-- FLAG_MEANINGLESS: doesn't mean anything, useful for separating rows with different divisors.
local FLAG_MEANINGLESS    = 2048

local MatrixBuilderRow = {}
function MatrixBuilderRow:new(signal)
  local o = { signal = signal, subrows_by_flags = {} }
  setmetatable(o, self)
  self.__index = self
  return o
end

function MatrixBuilderRow:set_entry(output_signal,value,flags,add,divider)
    divider = divider or 1
    if band(flags,FLAG_MULTIPLY) == 0 then divider = 1 end
    value = value or 1
    flags = flags or 0
    if band(flags, FLAG_NEGATE) > 0 then
        flags = flags-FLAG_NEGATE
        value = -value
    end
    local sigstr = output_signal.type .. ":" .. output_signal.name
    while true do
        local subrow = self.subrows_by_flags[flags]
        if not subrow then
            subrow = {}
            self.subrows_by_flags[flags] = subrow
        end
        if subrow[sigstr] then
            if add and subrow[sigstr][3] ~= divider then
                flags = flags + FLAG_MEANINGLESS
                -- continue
            elseif add then
                subrow[sigstr][2] = value + subrow[sigstr][2]
                return
            else
                subrow[sigstr][2] = value
                subrow[sigstr][3] = divider
                return
            end
        else
            subrow[sigstr] = {output_signal,value,divider}
            return
        end
    end
end

function MatrixBuilderRow:is_empty()
    return next(self.subrows_by_flags) == nil
end

function MatrixBuilderRow:copy()
    local ret = MatrixBuilderRow:new(self.signal)
    ret.subrows_by_flags = table.deepcopy(self.subrows_by_flags)
    return ret
end

function MatrixBuilderRow:add_copy_with_flag_change(other,or_flags,multiplier,divider)
    -- self += multiplier * other, but shift entries of other by ORing their flags with or_flags
    or_flags = or_flags or 0
    multiplier = multiplier or 1
    divider = divider or 1
    if band(or_flags, FLAG_NEGATE) > 0 then
        or_flags = or_flags - flag_negate
        multiplier = -multiplier
    end
    for flags,subrow in pairs(other.subrows_by_flags) do
        local new_flags = bor(flags,or_flags)
        local new_divider = (band(new_flags, FLAG_MULTIPLY) ~= 0 and divider) or 1
        local target = self.subrows_by_flags[new_flags]
        if not target then
            target = {}
            self.subrows_by_flags[new_flags] = target
        end
        for sigstr,sigvals in pairs(subrow) do
            if target[sigstr] then
                if target[sigstr][3] == new_divider or band(new_flags, FLAG_MULTIPLY) == 0 then
                    -- consistent dividers, just add
                    target[sigstr][2] = target[sigstr][2] + multiplier * sigvals[2]
                else
                    -- inconsistent dividers: add with arbitrary flag
                    self:set_entry(sigvals[1],multiplier*sigvals[2],new_flags,true,new_divider)
                end
            else
                target[sigstr] = {sigvals[1],  multiplier * sigvals[2], new_divider}
            end
        end
    end
end

local MatrixBuilder = {}
function MatrixBuilder:new()
  local o = { rows_by_signal = {} }
  setmetatable(o, self)
  self.__index = self
  return o
end

-- Given a signal, create a new MatrixBuilder row, or return one
-- If nocommit, then don't add it to the matrix
function MatrixBuilder:create_or_add_row(signal, nocommit)
  local sigstr = signal.type .. ":" .. signal.name
  local the_row
  if nocommit then
    the_row = MatrixBuilderRow:new(signal)
  elseif self.rows_by_signal[sigstr] then
    the_row = self.rows_by_signal[sigstr]
  else
    the_row = MatrixBuilderRow:new(signal)
    self.rows_by_signal[sigstr] = the_row
  end 
  return the_row
end

-- Convert the matrix builder to tables of the form
-- flags => [ {row_sig, [{col_sig, value}]} ],
-- { {valid,1} },
-- sigstr => valid at all qualities
function MatrixBuilder:collate()
    local matrix = {}
    local vaaq = {}
    local valid = {}
    local added_to_valid = {}
    for rowstr_,row in pairs(self.rows_by_signal) do
        -- Move dense flags to sparse if they're not 1
        local rowcopy
        for flags,subrow in pairs(row.subrows_by_flags) do
            if band(flags,FLAG_DENSE) > 0 then
                for colstr,sigval in pairs(subrow) do
                    if sigval[2] ~= 0 and sigval[2] ~= 1 then
                        if rowcopy == nil then rowcopy = row:copy() end
                        rowcopy:set_entry(sigval[1],sigval[2],flags-FLAG_DENSE,true)
                        rowcopy:set_entry(sigval[1],0,flags)
                    end
                end
            end
        end
        if rowcopy then row = rowcopy end

        -- Next, collate the row
        for flags,subrow in pairs(row.subrows_by_flags) do
            local nonempty = false
            local ret_flags
            local subrow_collated = {}
            local is_valid_anyway = false
            for colstr_,sigval in pairs(subrow) do
                if sigval[1].type == MAKE_VALID_ANYWAY.type then
                    is_valid_anyway = true
                elseif sigval[2] ~= 0 then
                    table.insert(subrow_collated,sigval)
                end
            end
            if #subrow_collated > 0 or is_valid_anyway then
                if not ret_flags then
                    if not matrix[flags] then matrix[flags] = {} end
                    ret_flags = matrix[flags]
                end
                table.insert(ret_flags,{row.signal,subrow_collated})

                -- Add it to the valid array
                local sigstr = row.signal.type .. ":" .. row.signal.name
                if not added_to_valid[sigstr] then
                    table.insert(valid,{row.signal,1})
                    added_to_valid[sigstr] = true
                end
                if HAVE_QUALITY and band(FLAG_NORMAL_INPUT,flags) == 0 then
                    vaaq[sigstr] = true
                end
            end
        end
    end
    return matrix,valid,vaaq
end

M.FLAG_DENSE         = FLAG_DENSE
M.FLAG_MULTIPLY      = FLAG_MULTIPLY
M.FLAG_NOQUAL        = FLAG_NOQUAL
M.FLAG_NORMAL_INPUT  = FLAG_NORMAL_INPUT
M.FLAG_RED           = FLAG_RED
M.FLAG_GREEN         = FLAG_GREEN
M.FLAG_NEGATE        = FLAG_NEGATE
M.FLAG_MEANINGLESS   = FLAG_MEANINGLESS
M.MAKE_VALID_ANYWAY  = MAKE_VALID_ANYWAY
M.MatrixBuilder      = MatrixBuilder

return M