

local band = bit32.band
local bor  = bit32.bor

local M = {}
local HAVE_QUALITY = script.feature_flags.quality and script.feature_flags.space_travel

-- Supported matrix flags
-- FLAG_DENSE: use a dense flags-matrix layout.  Better for modules.
-- Can't support multiply or quality.  All entries must be 1
local FLAG_DENSE        = 1

-- FLAG_MULTIPLY: multiply this entry by the input quantity
local FLAG_MULTIPLY     = 2

-- FLAG_NOQUAL: this output's quality isn't based on the input quality
local FLAG_NOQUAL       = 4
if not HAVE_QUALITY then FLAG_NOQUAL = 0 end

-- FLAG_NORMAL_INPUT: this row is only valid if the input has normal quality (e.g. a fluid)
local FLAG_NORMAL_INPUT = 8
if not HAVE_QUALITY then FLAG_NORMAL_INPUT = 0 end

-- FLAG_RED: output this info on the red wire (TODO)
-- FLAG_GREEN: output this info on the green wire (TODO)
local FLAG_RED,FLAG_GREEN = 16,32

local MatrixBuilderRow = {}
function MatrixBuilderRow:new(signal)
  local o = { signal = signal, subrows_by_flags = {} }
  setmetatable(o, self)
  self.__index = self
  return o
end

function MatrixBuilderRow:set_entry(output_signal,value,flags,add)
  local sigstr = output_signal.type .. ":" .. output_signal.name
  flags = flags or 0
  local subrow = self.subrows_by_flags[flags]
  if not subrow then
    subrow = {}
    self.subrows_by_flags[flags] = subrow
  end
  if subrow[sigstr] then
    if add then value = value + subrow[sigstr][2] end
    subrow[sigstr][2] = value
  else
    subrow[sigstr] = {output_signal,value}
  end
end

function MatrixBuilderRow:is_empty()
    return next(self.subrows_by_flags) == nil
end

function MatrixBuilderRow:add_copy_with_flag_change(other,or_flags)
  -- self += other, but shift entries of other by ORing their flags with or_flags
  or_flags = or_flags or 0
  for flags,subrow in pairs(other.subrows_by_flags) do
    local new_flags = bor(flags,or_flags)
    if self.subrows_by_flags[new_flags] then
      local target = self.subrows_by_flags[new_flags]
      for sigstr,sigvals in pairs(subrow) do
        if target[sigstr] then
          target[sigstr][1] = target[sigstr][1] + sigvals[1]
        else
          target[sigstr] = sigvals
        end
      end
    else
      self.subrows_by_flags[new_flags] = table.deepcopy(subrow)
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
        for flags,subrow in pairs(row.subrows_by_flags) do
            local nonempty = false
            local ret_flags
            local subrow_collated = {}
            for colstr_,sigval in pairs(subrow) do
                if sigval[2] ~= 0 then
                    table.insert(subrow_collated,sigval)
                end
            end
            if #subrow_collated > 0 then
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
M.MatrixBuilder      = MatrixBuilder

return M