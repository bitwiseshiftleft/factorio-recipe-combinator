local util = require "__core__.lualib.util"
local tagged_entity = require "lualib.tagged_entity"
local matrix_builder = require "lualib.matrix_builder"
local event = require "lualib.event"
local M = {}

local band = bit32.band
local bor  = bit32.bor
local ceil=math.ceil
local floor=math.floor

-- Cribbed from Circuit-Controlled Router
local HAVE_QUALITY = script.feature_flags.quality and script.feature_flags.space_travel

-- Wire definitions
local WRED   = defines.wire_type.red
local WGREEN = defines.wire_type.green
local CRED   = defines.wire_connector_id.circuit_red
local CGREEN = defines.wire_connector_id.circuit_green
local IRED   = defines.wire_connector_id.combinator_input_red
local IGREEN = defines.wire_connector_id.combinator_input_green
local ORED   = defines.wire_connector_id.combinator_output_red
local OGREEN = defines.wire_connector_id.combinator_output_green

local QUALITY = {type="virtual", name="signal-Q"}

local NGREEN = {green=true,red=false}
local NRED   = {green=false,red=true}
local NBOTH  = {green=true,red=true}
local NNONE  = {green=false,red=false}

-- Signal definitions
local EACH = {type="virtual",name="signal-each"}
local ANYTHING = {type="virtual",name="signal-anything"}
local EVERYTHING = {type="virtual",name="signal-everything"}

-- localize the matrix builder flags
local FLAG_DENSE        = matrix_builder.FLAG_DENSE
local FLAG_GREEN        = matrix_builder.FLAG_GREEN
local FLAG_RED          = matrix_builder.FLAG_RED
local FLAG_NORMAL_INPUT = matrix_builder.FLAG_NORMAL_INPUT
local FLAG_MULTIPLY     = matrix_builder.FLAG_MULTIPLY
local FLAG_NOQUAL       = matrix_builder.FLAG_NOQUAL
local FLAG_NEGATE       = matrix_builder.FLAG_NEGATE
local FLAG_MEANINGLESS  = matrix_builder.FLAG_MEANINGLESS

-- When used as a builder interface, takes input from itself
local ITSELF = "__ITSELF__"
local Builder = {}

local g_all_qualities = {}
local function cache_qualities()
  local qps = {}
  for name,p in pairs(prototypes.quality) do
    if name ~= "quality-unknown" then
      table.insert(qps,p)
    end 
  end
  table.sort(qps,function(a,b) return a.level<b.level end)
  g_all_qualities = {}
  for i,q in ipairs(qps) do
    g_all_qualities[i] = q.name
  end
end

function Builder:constant_combi(signals,description,name)
    -- Create a constant combinator with the given signals
    -- log(serpent.line(signals))
    local entity = self.surface.create_entity{
        name=name or "recipe-combinator-component-constant-combinator",
        position=self.position, force=self.force
    }
    local con = entity.get_or_create_control_behavior()
    local most_at_once = 1000
    local section = con.get_section(1)
    local filters = {}
    local j=0
    local normal=g_all_qualities[1]
    for i=1,#signals do
        local sig=signals[i]
        j=j+1
        if j>most_at_once then
            j=j-most_at_once
            section.filters = filters
            section=con.add_section()
            filters={}
        end
        filters[j] = {value=util.merge{{comparator="=",quality=normal},sig[1]},min=sig[2]}
    end
    section.filters = filters
    entity.combinator_description = description or ""
    return entity
end

function Builder:make_combi(args)
    -----------------------------------------------------------------------
    -- Make a combinator entity.
    -----------------------------------------------------------------------
    -- If args.arithmetic then it will be an arithmetic combinator (otherwise decider)
    -- If args.combinator_name the you can set the entity name; otherwise it will be
    --   a regular combinator if args.visible, ando otherwise a hidden one
    -- Set the combinator description according to args.description.
    -----------------------------------------------------------------------
    if args.arithmetic then
        name = args.combinator_name or (args.visible and "arithmetic-combinator") or "recipe-combinator-component-arithmetic-combinator"
    elseif args.selector then
        name = args.combinator_name or (args.visible and "selector-combinator") or "recipe-combinator-component-selector-combinator"
    else
        name = args.combinator_name or (args.visible and "decider-combinator") or "recipe-combinator-component-decider-combinator"
    end

    local ret = self.surface.create_entity{
        name=name, position=self.position, force=self.force,
        direction = args.orientation or orientation,
        quality = args.quality
    }
    ret.combinator_description = args.description or ""

    return ret
end

function Builder:expand_shorthand_conditions(args,is_decider)
    -- Parse out shorthand args like L=7, R=THRESHOLD or whatever
    -- into combinator condition descriptions
    local condition = {}
    local L = args.L or EACH
    local R = args.R or EACH
    if type(L) == 'table' then
        condition.first_signal = L
        condition.first_signal_networks = args.NL or NBOTH
    else
        condition.first_constant = L
        condition.first_signal_networks = NNONE
    end
    if type(R) == 'table' then
        condition.second_signal = R
        condition.second_signal_networks = args.NR or NBOTH
    elseif is_decider then
        condition.constant = R
    else
        condition.second_constant = R
    end
    return condition
end

function Builder:connect_inputs(args, combi)
    -- Connect up the inputs to a combinator according to ARGS
    -- Return the combinator entity (= combi)
    for j,args_color in ipairs({
        {args.red or {},WRED,ORED,CRED,IRED},
        {args.green or {},WGREEN,OGREEN,CGREEN,IGREEN}
    }) do
        local my_connector = combi.get_wire_connector(args_color[5])
        local wire = args_color[2]
        local their_connector
        for i,conn in ipairs(args_color[1]) do
            if conn then
                if conn == ITSELF then conn = combi end
                if     conn.type == "arithmetic-combinator"
                    or conn.type == "decider-combinator"
                    or conn.type == "selector-combinator" then
                    their_connector = conn.get_wire_connector(args_color[3],true)
                else
                    their_connector = conn.get_wire_connector(args_color[4],true)
                end
                my_connector.connect_to(their_connector,false,defines.wire_origin.script)
            end
        end
    end
    return combi
end

function Builder:decider(args)
    -- Create a decider combinator
    local combi = self:make_combi(args)

    local behavior = combi.get_or_create_control_behavior()
    for i,clause in ipairs(args.decisions or {args}) do
        local condition = self:expand_shorthand_conditions(clause,true)
        condition.comparator=clause.op
        condition.compare_type=clause.and_ and "and" or "or"
        if i > 1 then
            behavior.add_condition(condition)
        else
            behavior.set_condition(1,condition)
        end
    end
    for i,clause in ipairs(args.output or {args}) do
        local output = { networks=clause.WO or WBOTH, copy_count_from_input=not clause.set_one, signal=clause.out or EACH, constant=clause.constant or 1 }
        if i > 1 then
            behavior.add_output(output)
        else
            behavior.set_output(1,output)
        end
    end

    return self:connect_inputs(args, combi)
end

function Builder:arithmetic(args)
  -- Create an arithmetic combinator
  local combi = self:make_combi(util.merge{args,{arithmetic=true}})
  local behavior = combi.get_or_create_control_behavior()
  local params = self:expand_shorthand_conditions(args)
  params.operation=args.op or "+"
  params.output_signal=args.out or EACH
  behavior.parameters = params
  return self:connect_inputs(args, combi)
end

function Builder:selector(args)
  -- Create a selector combinator
  local combi = self:make_combi(util.merge{args,{selector=true}})
  local sqfs=nil
  if args.qual then sqfs=type(args.qual)=="table" end
  combi.get_or_create_control_behavior().parameters = {
    operation=args.op, select_max=args.select_max, index_signal=args.index,
    quality_filter=args.quality_filter,
    quality_destination_signal=args.out,
    quality_source_signal=(type(args.qual)=="table" and args.qual) or nil,
    quality_source_static=(type(args.qual)=="string" and {name=args.qual}) or nil,
    select_quality_from_signal=sqfs
  }
  return self:connect_inputs(args, combi)
end

function Builder:new(surface,position,force)
  local o = {surface=surface,position=position,force=force}
  setmetatable(o, self)
  self.__index = self
  return o
end

local function signed_lshift(x,n)
  x = bit32.lshift(x,n)
  if x >= 0x80000000 then x = x - 0x100000000 end
  return x
end


local function build_flag_matrix(builder,input,rows,prefix)
  -- TODO for UPS: deduplicate flags, so that only the meaning is duplicated
  local flag_layers = {}
  local flag_layers_as_dict = {}
  local meaning_layers = {}
  local nbits = 0
  local bitno = {}

  for _idx,row in ipairs(rows) do
    rowsig,cols = row[1],row[2]
    local rowsig_str = rowsig.type .. ":" .. rowsig.name
    local bitses = {}
    for _,colsig in ipairs(cols) do
      colsig = colsig[1] -- = 1 always
      local colsig_str = colsig.type .. ":" .. colsig.name

      -- register the column if it doesn't exist
      if not bitno[colsig_str] then
        bitno[colsig_str] = nbits
        if nbits % 32 == 0 then
          -- new layer
          flag_layers[nbits/32 + 1] = {}
          flag_layers_as_dict[nbits/32 + 1] = {}
          meaning_layers[nbits/32 + 1] = {}
        end
        table.insert(meaning_layers[floor(nbits/32)+1], {colsig, signed_lshift(1,nbits%32)})
        nbits = nbits+1
      end

      -- put it in the bitset
      local bit = bitno[colsig_str]
      local grp = 1+floor(bit/32)
      if bitses[grp] then bitses[grp] = bitses[grp] + signed_lshift(1,bit%32)
      else bitses[grp] = signed_lshift(1,bit%32)
      end
    end
    for grp,mask in pairs(bitses) do
      table.insert(flag_layers[grp],{rowsig,mask})
      flag_layers_as_dict[grp][rowsig_str] = mask
    end
  end

  -- Build combinators
  local all_ands = {}
  local idx_signal = {type="virtual", name="signal-info"}
  for layer = 1,ceil(nbits/32) do
    local flag_combi = builder:constant_combi(flag_layers[layer],      prefix.."flag"..tostring(layer))
    local flag_meaning = builder:constant_combi(meaning_layers[layer], prefix.."flag_meaning"..tostring(layer))

    -- flag != 0 and input != 0 ==> idx_signal = idx value
    local get_flags = builder:decider{
      decisions = {
        {L=EACH,NL=NGREEN,op="!=",R=0},
        {and_=true,L=EACH,NL=NRED,op="!=",R=0}
      },
      output = {{out=idx_signal,WO=NRED}},
      green = {input}, red = {flag_combi},
      description=prefix.."get_flags"..tostring(layer)
    }

    local and_flags = builder:arithmetic{
      L=idx_signal,NL=NGREEN,op="AND",R=EACH,NR=NRED,out=EACH,
      green = {get_flags}, red = {flag_meaning},
      description=prefix.."and_flags"..tostring(layer)
    }
    
    table.insert(all_ands, and_flags)
  end

  -- Last layer: all nonzero sigs
  local nonzero = builder:decider{
    decisions={{L=EACH,NL=NGREEN,op="!=",R=0}},
    output={{out=EACH,set_one=true}},
    green = all_ands,
    description = prefix.."nonzero"
  }
  return nonzero
end

g_all_modules = nil -- names of all modules
g_modules_per_category = nil -- names of only the lowest-tier module per category
local function cache_modules()
  -- Cache all modules, and also only the lowest-tier module per category
  -- TODO: ... of all qualities???
  g_all_modules = {}
  g_modules_per_category = {}
  local module_tier = {}
  local module_category_to_module = {}
  for _name,module in pairs(prototypes.get_item_filtered{{filter="type",type="module"}}) do
    table.insert(g_all_modules,module.name)
    if not module_category_to_module[module.category]
      or module.tier < module_category_to_module[module.category].tier
    then
      module_category_to_module[module.category] = module
    end
  end
  for _,module in pairs(module_category_to_module) do
    table.insert(g_modules_per_category,module.name)
  end
end

local g_spoilage_cache=nil
local function cache_spoilage()
  if g_spoilage_cache or not script.feature_flags.spoiling then
    g_spoilage_cache = {}
    return
  end
  g_spoilage_cache = {}
  for name,item in pairs(prototypes.item) do
    local ticks = item.get_spoil_ticks()
    if ticks > 0 then
      g_spoilage_cache[name] = {
        name="spoil:"..name,
        ingredients={{name=name,type="item",amount=1}},
        products=item.spoil_result
          and {{name=item.spoil_result.name,type="item",amount=1}}
          or {},
        energy=ticks/60.,
        allowed_module_categories={},
        category="recipe-combinator-spoilage-mechanic"
      }
    end
  end
end

local function init()
  cache_modules()
  cache_qualities()
  cache_spoilage()
end

local function signal_arrays_equal(t1,t2)
  if t1 == nil and t2 == nil then return true end
  if t1 == nil or t2 == nil then return false end
  if #t1 ~= #t2 then return false end
  for i=1,#t1 do
    if t1[i][1].type ~= t2[i][1].type
      or t1[i][1].name ~= t2[i][1].name
      or t1[i][2] ~= t2[i][2] then
        return false
      end
  end
  return true
end


local function build_sparse_matrix(args)
  -- given an input of the form
  -- {sig1, {{sig1a,4}, {sig1b,123}}} or similar
  -- {sig2, ...}
  -- ...
  -- build a sparse matrix which takes a single signal as input (e.g. sig1, 10)
  -- and outputs that multiple of that row of the matrix,
  -- e.g. {sig1a,40},{sig1b,1230}
  --
  -- This has latency 3.
  local builder,input,rows=args.builder,args.input,args.rows
  local prefix=args.prefix or "sparse_matrix."
  local flags_only,multiply_by_input = args.flags_only,args.multiply_by_input
  local entry_data,divider_data,idx_data,idx_dict = {},{},{},{}
  local columns,jdx_dict,jdx_data,jdx_count = {},{},{},{}
  local rowsig,combo,entry,divider,colsig,jdx_value
  local round_up = args.round_up
  local dividers_not_all_one = {}

  for _idx,row in ipairs(rows) do
    rowsig,combo = row[1],row[2]

    -- game.print(serpent.line(rowsig) .. ": " .. serpent.line(combo))
    local rowsig_str = rowsig.type .. ":" .. rowsig.name
    for layer,col in ipairs(combo) do
      -- "layer" meaning index of ingredient within the combo
      colsig,entry,divider = col[1],col[2],col[3]
      divider = divider or 1
      if multiply_by_input and divider ~= 1 then dividers_not_all_one[layer] = true end

      local colsig_str = colsig.type .. ":" .. colsig.name

      if not idx_data[layer] then
        -- it's the first ingredient at that index.  Initialize it
        idx_data[layer] = {}
        jdx_data[layer] = {}
        jdx_dict[layer] = {}
        idx_dict[layer] = {}
        entry_data[layer] = {}
        divider_data[layer] = {}
        jdx_count[layer] = 0
      end
      if not jdx_dict[layer][colsig_str] then
        -- first copy of this ingredient
        jdx_value = 1+jdx_count[layer]
        jdx_count[layer] = jdx_value
        jdx_data[layer][jdx_value] = {colsig,jdx_value}
        jdx_dict[layer][colsig_str] = jdx_value
      end
      jdx_value = jdx_dict[layer][colsig_str]
      table.insert(idx_data[layer], {rowsig,jdx_value})
      idx_dict[layer][rowsig_str] = jdx_value
      if not flags_only then
        table.insert(entry_data[layer], {rowsig,entry})
        table.insert(divider_data[layer], {rowsig,divider})
      end
    end
  end

  -- any point in creating buf_input?
  local any_dividers_all_one = false
  for layer = 1,#idx_data do
    if not dividers_not_all_one[layer] then
      any_dividers_all_one = true
      break
    end
  end

  round_up = (not dividers_all_one) and round_up

  -- TODO: make sure this can't be in input
  local idx_signal = {type="virtual", name="signal-info"}

  local prev_div_input,prev_mod_input
  local dividers_prev

  -- Build the combinators
  -- First, 1-cycle input buffer.  Perform div and/or mod here
  local buf_input
  if not flags_only and any_dividers_all_one then
    buf_input = builder:arithmetic{L=EACH,op="+",R=0,description=prefix.."buf",green={input}}
  end
  local first_output = nil
  for layer = 1,#idx_data do
    local idx_combi = builder:constant_combi(idx_data[layer],   prefix.."idx"..tostring(layer))
    local jdx_combi = builder:constant_combi(jdx_data[layer],   prefix.."jdx"..tostring(layer))

    local my_buf_input, mod_input

    -- divider if necessary
    if dividers_not_all_one[layer] and signal_arrays_equal(divider_data[layer],dividers_prev) then
      -- ... preferably from the cache
      my_buf_input,mod_input = prev_div_input,prev_mod_input
    elseif dividers_not_all_one[layer]  then
      local dividends = builder:constant_combi(divider_data[layer], prefix.."divctx"..tostring(layer))
      my_buf_input = builder:arithmetic{NL=NGREEN,L=EACH,op="/",NR=NRED,R=EACH,description=prefix.."div"..tostring(layer),
        green={input}, red={dividends}}
      if round_up then
        mod_input = builder:arithmetic{NL=NGREEN,L=EACH,op="%",NR=NRED,R=EACH,description=prefix.."mod"..tostring(layer),
          green={input}, red={dividends}}
      end
      prev_div_input,prev_mod_input,dividers_prev = my_buf_input,mod_input,divider_data
    else
      my_buf_input = buf_input
    end

    -- idx != 0 and input != 0 ==> idx_signal = idx value
    local get_idx = builder:decider{
      decisions = {
        {L=EACH,NL=NGREEN,op="!=",R=0},
        {and_=true,L=EACH,NL=NRED,op="!=",R=0}
      },
      output = {{out=idx_signal,WO=NRED}},
      green = {input}, red = {idx_combi},
      description=prefix.."get_idx"..tostring(layer)
    }
    if HAVE_QUALITY and args.use_qual then
      jdx_combi = builder:selector{
        op="quality-transfer",
        out=EACH,
        qual=QUALITY,
        red={args.use_qual},  green={jdx_combi},
        description=prefix.."jdx_qual"..tostring(layer)
      }
    end
    local apply_jdx = builder:decider{
      decisions = {
        {L=EACH,NL=NRED,op="=",R=idx_signal,NR=NGREEN},
      },
      output = {{out=EACH,set_one=true}},
      green = {get_idx}, red = {jdx_combi},
      description=prefix.."apply_jdx"..tostring(layer)
    }

    local this_output
    if flags_only then
      -- accumulate
      this_output = apply_jdx
    else
      local ent_combi = builder:constant_combi(entry_data[layer], prefix.."ent"..tostring(layer))
      local dotp
      if multiply_by_input then
        dotp = builder:arithmetic{
          L=EACH,NL=NGREEN,op="*",R=EACH,NR=NRED,
          out=idx_signal,
          green = {my_buf_input}, red = {ent_combi},
          description=prefix.."dotp"..tostring(layer)
        }
        if mod_input then
          -- add round-up combinator: if input % divider != 0 then +1 * dot
          local nega_ent_combi = builder:arithmetic{
            L=0,op="-",R=EACH,red={ent_combi},
            description=prefix.."negent"..tostring(layer)
          }
          local rucomb = builder:decider{
            decisions = {
              {L=EACH,NL=NGREEN,op=">",R=0},
              {and_=true,L=EACH,NL=NRED,op="!=",R=0}
            },
            output = {{out=idx_signal,WO=NRED}},
            green = {mod_input}, red = {ent_combi},
            description=prefix.."rup"..tostring(layer)
          }
          rucomb.get_wire_connector(ORED,true).connect_to(dotp.get_wire_connector(ORED,true))
          -- and a negative one, rounding away from 0
          rucomb = builder:decider{
            decisions = {
              {L=EACH,NL=NGREEN,op="<",R=0},
              {and_=true,L=EACH,NL=NRED,op="!=",R=0}
            },
            output = {{out=idx_signal,WO=NRED}},
            green = {mod_input}, red = {nega_ent_combi},
            description=prefix.."rup"..tostring(layer)
          }
          rucomb.get_wire_connector(ORED,true).connect_to(dotp.get_wire_connector(ORED,true))
        end
      else
        dotp = builder:decider{
          decisions = {
            {L=EACH,NL=NGREEN,op="!=",R=0},
            {and_=true,L=EACH,NL=NRED,op="!=",R=0}
          },
          output = {{out=idx_signal,WO=NRED}},
          green = {my_buf_input}, red = {ent_combi},
          description=prefix.."dotp"..tostring(layer)
        }
      end
      this_output = builder:arithmetic{
        L=EACH,NL=NGREEN,op="*",R=idx_signal,NR=NRED,out=EACH,
        green = {apply_jdx}, red = {dotp},
        description=prefix.."output"..tostring(layer)
      }
    end
    
    -- Connect together all the outputs
    if first_output then
      first_output.get_wire_connector(OGREEN,true).connect_to(this_output.get_wire_connector(OGREEN,true))
      first_output.get_wire_connector(ORED,true).  connect_to(this_output.get_wire_connector(ORED,  true))
    else
      first_output = this_output
    end
  end

  -- game.print("Built sparse matrix with " .. tostring(#rows) .. " rows and ".. tostring(#idx_data) .. " layers!")
  if flags_only then
    -- Have several flags but with arbitrary values
    return builder:decider{
      decisions={{L=EACH,NL=NGREEN,op="!=",R=0}},
      output={{out=EACH,set_one=true}},
      green={first_output},
      description=prefix.."nonzero"
    }
  else
    return first_output
  end
end

local MAX_LATENCY = 10 -- for defunct vs destroy latency
local DESC_DEFUNCT = "__defunct__"

local function destroy_defunct_components(entity,defunct_tick)
  local children = entity.surface.find_entities_filtered{area=entity.bounding_box}
  local combinator_types = {
    ["arithmetic-combinator"]=true,
    ["decider-combinator"]=true,
    ["selector-combinator"]=true,
    ["constant-combinator"]=true
  }
  local descr = DESC_DEFUNCT .. tostring(defunct_tick)
  for i,child in ipairs(children) do
    if string.find(child.name, '^recipe%-combinator%-component%-')
        and combinator_types[child.type] 
        and child.unit_number ~= entity.unit_number
        and child.combinator_description == descr
    then
      child.destroy()
    end
  end
end

local function check_defunction(ev)
  local tick = ev.tick
  local in_future = false
  for a_tick,entities in pairs(table.deepcopy(storage.defunct)) do
    if a_tick + MAX_LATENCY <= tick then
      for _,un in ipairs(entities) do
        local entity = game.get_entity_by_unit_number(un)
        if entity then destroy_defunct_components(entity,a_tick) end
      end
      storage.defunct[a_tick] = nil
    else
      in_future = true
    end
  end
  if not in_future then
    event.unregister_event(defines.events.on_tick, check_defunction)
  end
end

local function make_components_defunct(entity)
  local children = entity.surface.find_entities_filtered{area=entity.bounding_box}
  local combinator_types = {
    ["arithmetic-combinator"]=true,
    ["decider-combinator"]=true,
    ["selector-combinator"]=true,
    ["constant-combinator"]=true
  }
  local egreen = entity.get_wire_connector(IGREEN,true)
  local ered   = entity.get_wire_connector(IRED,  true)
  local descr = DESC_DEFUNCT .. tostring(game.tick)
  local made_any_defunct = false
  for i,child in ipairs(children) do
      if string.find(child.name, '^recipe%-combinator%-component%-') then
          if combinator_types[child.type] and child.unit_number ~= entity.unit_number then
            -- just defunct it and disconnect it from the input
            child.combinator_description = descr
            child.get_wire_connector(IGREEN,true).disconnect_from(egreen)
            child.get_wire_connector(IRED  ,true).disconnect_from(ered)
            made_any_defunct = true
          else
            child.destroy()
          end
      end
  end

  -- register to delete the defunct entities later
  if made_any_defunct then
    if storage.defunct then
      if storage.defunct[game.tick] then
        table.insert(storage.defunct[game.tick],entity.unit_number)
      else 
        storage.defunct[game.tick] = {entity.unit_number}
      end
    else
      storage.defunct = {[game.tick]={entity.unit_number}}
    end
    event.register_event(defines.events.on_tick,check_defunction)
  end
end


local function destroy_components(entity)
  local children = entity.surface.find_entities_filtered{area=entity.bounding_box}
  for i,child in ipairs(children) do
      if string.find(child.name, '^recipe%-combinator%-component%-') then
          child.destroy()
      end
  end
end


local function build_matrix_combinator(
  entity,
  matrix,
  output_quality_sig,
  output_quality_flags,
  output_selected_signal,
  output_all_inputs,
  output_all_inputs_quality,
  output_quantity_sig,
  output_quantity_flags
)
  local builder = Builder:new(entity.surface, entity.position, entity.force)

  -- Collate the matrix into a dense form
  local matrices_by_flags, valid, valid_at_all_qualities = matrix:collate()

  -- Extend out to latency 6.
  -- Stage 1: input buffer.  Connect to entity's inputs
  local input_buffer = builder:arithmetic{L=EACH,op="+",R=0,description="ri.input_buffer"}
  input_buffer.get_wire_connector(IGREEN,true).connect_to(entity.get_wire_connector(IGREEN,true))
  input_buffer.get_wire_connector(IRED,  true).connect_to(entity.get_wire_connector(IRED,  true))

  local end_of_input_stage
  local valid_combi
  local quality_buffer
  local selected_signal
  local end_of_input_stage_normal_only
  if HAVE_QUALITY then
    local valid2,nvalid2 = {},0
    local literal_quality = {}
    local decisions_getqual={}
    -- Make a combinator with valid sigs at all levels
    for idx,qual in ipairs(g_all_qualities) do
      table.insert(literal_quality,{util.merge{QUALITY,{quality=qual}},idx})
      for _,sigamt in ipairs(valid) do
        local sig = sigamt[1]
        if idx==1 or valid_at_all_qualities[sig.type..":"..sig.name] then
          nvalid2=nvalid2+1
          valid2[nvalid2] = {util.merge{sig,{quality=qual}},idx}
        end
      end
      table.insert(decisions_getqual,{NL=NGREEN,L=ANYTHING,op="=",R=idx})
      table.insert(decisions_getqual,{and_=true,NL=NRED,L=EACH,op="=",R=idx})
    end
    valid_combi = builder:constant_combi(valid2, "ri.valid")
    local quality_list = builder:constant_combi(literal_quality, "ri.quals")

    -- Stage 2: selection of one valid input
    local select_one = builder:decider{
      decisions={
        {NL=NGREEN,L=EACH,op="!=",R=0},
        {and_=true,NL=NRED,L=EACH,op="!=",R=0}
      },
      output={{out=ANYTHING,WO=NGREEN}},
      description="ri.buffer2",green={input_buffer},red={valid_combi},
      -- visible=true
    }

    -- Stage 2b a second copy, but output the quality selected instead
    local select_one_getqual = builder:decider{
      decisions={
        {NL=NGREEN,L=EACH,op="!=",R=0},
        {and_=true,NL=NRED,L=EACH,op="!=",R=0}
      },
      output={{out=ANYTHING,WO=NRED}},
      description="ri.qual2",green={input_buffer},red={valid_combi},
    }

    -- Stage 3a set quality to normal
    end_of_input_stage = builder:selector{
      op="quality-transfer", qual=g_all_qualities[0], out=EACH,
      green={select_one}, description="ri.set_normal_qual",
    }

    -- Stage 3d selected signal (original quality)
    if output_selected_signal then
      selected_signal = builder:arithmetic{
        L=EACH,op="+",R=0,green={select_one},
        description="ri.selected_signal"
      }
    else
      -- in case it's needed for quantity
      selected_signal = end_of_input_stage
    end

    -- Stage 3b extract if normal quality
    -- TODO: only create if necessory
    end_of_input_stage_normal_only = builder:selector{
      op="quality-filter", qual=g_all_qualities[0],
      red={select_one}, description="ri.check_normal_qual",
    }

    -- Stage 3c select quality
    quality_buffer = builder:decider{
      decisions=decisions_getqual,
      output={{out=EACH}},
      description="ri.getqual",green={select_one_getqual},red={quality_list},
      -- visible=true
    }
  else
    -- No quality
    -- Stage 2: selection of one valid input
    valid_combi = builder:constant_combi(valid, "ri.valid")
    local select_one = builder:decider{
      decisions={
        {NL=NGREEN,L=EACH,op="!=",R=0},
        {and_=true,NL=NRED,L=EACH,op="!=",R=0}
      },
      output={{out=ANYTHING,WO=NGREEN}},
      description="ri.buffer2",green={input_buffer},red={valid_combi}
    }
    -- Stage 3: buffer again (for parity with quality case)
    end_of_input_stage = builder:arithmetic{L=EACH,op="+",R=0,description="ri.buffer3",green={select_one}}
    selected_signal = end_of_input_stage
  end

  -- widget to connect combi's output to the main entity
  local function connect_output(combi,flags)
    if not combi then return end
    if band(flags,FLAG_RED)>0 then
      combi.get_wire_connector(ORED,true).  connect_to(entity.get_wire_connector(ORED,  true))
    end
    if band(flags,FLAG_GREEN)>0 then
      combi.get_wire_connector(OGREEN,true).connect_to(entity.get_wire_connector(OGREEN,true))
    end
  end

  for flags,matrix in pairs(matrices_by_flags) do
    local input=end_of_input_stage
    -- log("Matrix, flags="..tostring(flags)..":\n"..serpent.line(matrix))
    if HAVE_QUALITY and band(flags,FLAG_NORMAL_INPUT)>0 then
      input=end_of_input_stage_normal_only
    end
    local use_qual = quality_buffer
    if band(flags,FLAG_NOQUAL)>0 then
      use_qual = nil
    end
    if band(flags,FLAG_DENSE)>0 then
      -- TODO: add right-aliases to flag_matrix
      -- NB: doesn't support quality
      connect_output(build_flag_matrix(builder,input,matrix,"ri.matrix.flags"..tonumber(flags).."."),flags)
      -- game.print("Build flag matrix with "..tonumber(#matrix).." rows with flags="..tonumber(flags))
    else 
      connect_output(build_sparse_matrix{
        builder=builder,input=input,rows=matrix,prefix="ri.matrix.flags"..tonumber(flags)..".",
        multiply_by_input=band(flags,FLAG_MULTIPLY)>0,use_qual=use_qual,
        round_up=true -- TODO
      },flags)
      -- game.print("Build sparse matrix with "..tonumber(#matrix).." rows with flags="..tonumber(flags))
    end
  end

  -- output quality indicator
  if HAVE_QUALITY and output_quality_sig and output_quality_flags and output_quality_flags > 0 then
    local qs4
    if output_quality_sig.name == QUALITY.name
      and output_quality_sig.type == QUALITY.type then
      qs4 = builder:decider{
        decisions={{L=EACH,op="!=",R=0}},
        output={{out=EACH,set_one=true}},
        red={quality_buffer},
        description="ri.matrix.quality_buffer_4"
      }
    else
      local quality_comb = builder:constant_combi({{output_quality_sig,1}}, "ri.matrix.quality_cc")
      qs4 = builder:selector{op="quality-transfer",qual=QUALITY,out=output_quality_sig,
        red={quality_buffer},green={quality_comb},
        description="ri.matrix.quality_buffer_4"
      }
    end
    local qs5 = builder:arithmetic{L=EACH,op="+",R=0,green={qs4},description="ri.matrix.quality_buffer_5"}
    local qs6 = builder:arithmetic{L=EACH,op="+",R=0,green={qs5},description="ri.matrix.quality_buffer_6"}
    connect_output(qs6,output_quality_flags)
  end

  if output_all_inputs and output_all_inputs > 0 then
    local prev = valid_combi
    if HAVE_QUALITY and not output_all_inputs_quality then
      prev = builder:selector{op="quality-transfer",qual=g_all_qualities[1],out=EACH,
        green={prev},
        description="ri.matrix.oai_quality"
      }
    else
      prev = builder:arithmetic{L=EACH,op="+",R=0,green={prev},description="ri.matrix.input.oai_buffer1"}
    end
    prev = builder:decider{
      decisions={{L=EACH,op="!=",R=0}},
      output={{out=EACH,set_one=true}},
      green={prev},
      description="ri.matrix.oai_buffer2_set_one"
    }
    for i=3,6 do
      prev = builder:arithmetic{L=EACH,op="+",R=0,green={prev},description="ri.matrix.input.oai_buffer"..tostring(i)}
    end
    connect_output(prev,output_all_inputs)
  end

  -- output selected signal (possibly quantity only)
  if (output_selected_signal and output_selected_signal > 0)
    or (output_quantity_sig and output_quantity_flags and output_quantity_flags > 0)
  then
    local sel4 = builder:arithmetic{L=EACH,op="+",R=0,green={selected_signal},description="ri.matrix.input_buffer_4"}
    local sel5 = builder:arithmetic{L=EACH,op="+",R=0,green={sel4},description="ri.matrix.input_buffer_5"}
    if output_quantity_sig and output_quantity_flags and output_quantity_flags > 0 then
      local seln = builder:arithmetic{L=EACH,op="+",R=0,
        out=output_quantity_sig,green={sel5},
        description="ri.matrix.output_quantity"}
      connect_output(seln,output_quantity_flags)
    end
    if output_selected_signal and output_selected_signal > 0 then
      local sel6 = builder:arithmetic{L=EACH,op="+",R=0,green={sel5},description="ri.matrix.input_buffer_6"}
      connect_output(sel6,output_selected_signal)
    end
  end
end

local function build_recipe_info_combinator(args)
  -- parse args
  local entity                    = args.entity
  local force                     = entity.force
  local machines                  = args.machines or {}

  local output_allowed_modules    = args.output_allowed_modules
  local output_recipe_ingredients = args.output_recipe_ingredients
  local output_recipe_products    = args.output_recipe_products
  local output_recipe             = args.output_recipe
  local output_crafting_time      = args.output_crafting_time
  local output_crafting_time_sig  = args.output_crafting_time_sig
  local output_all_recipes        = args.output_all_recipes
  local output_crafting_machine   = args.output_crafting_machine
  local output_quality_sig        = args.output_quality_sig
  local output_quality            = args.output_quality
  local output_quantity_sig       = args.output_quantity_sig
  local output_quantity_flags     = args.output_quantity
  local output_selected           = args.output_selected
  local one_module_per_category   = args.one_module_per_category
  local output_all_inputs         = args.output_all_inputs
  local output_all_inputs_quality = HAVE_QUALITY and args.output_all_inputs_quality

  local input_item_product        = args.input_item_product
  local input_item_ingredient     = args.input_item_ingredient
  local input_fluid_product       = args.input_fluid_product
  local input_fluid_ingredient    = args.input_fluid_ingredient
  local input_recipe              = args.input_recipe
  local include_hidden            = args.include_hidden
  local include_disabled          = args.include_disabled

  local module_table = output_allowed_modules and (
    (one_module_per_category and g_modules_per_category) or g_all_modules
  ) or {}

  make_components_defunct(entity)
  local matrix = matrix_builder.MatrixBuilder:new()

  -- Set the entity's control info
  local behavior = entity.get_or_create_control_behavior()
  behavior.parameters = {first_constant=0, operation="+", second_constant=0, output_signal=nil}

  local indicator = entity.surface.create_entity{
      name="recipe-combinator-component-indicator-inserter",
      position=entity.position, entity=entity.force
  }
  indicator.inserter_filter_mode = "whitelist"
  indicator.use_filters = true
  local n_indicator = 0

  local crafting_time_scale = {}
  local absolute_time_scale = 60 -- i.e. in ticks
  local category_to_machine = {}
  local category_to_machine_proto = {}

  -- parse out the machines into speeds and categories
  for _,machine in ipairs(machines) do
    local quality = nil -- TODO
    local machine_proto = prototypes.entity[machine]
    local item_to_place = machine_proto.items_to_place_this[1]
    if item_to_place and n_indicator < 4 then
      -- add it to the indicator inserter
      n_indicator=n_indicator+1
      indicator.set_filter(n_indicator, {name=item_to_place.name, quality=quality or "normal", comparator="="})
    end
    for cat,_ in pairs(machine_proto.crafting_categories) do
      if not crafting_time_scale[cat] then
        crafting_time_scale[cat] = absolute_time_scale / machine_proto.get_crafting_speed(quality)
        category_to_machine[cat] = (item_to_place or {}).name
        category_to_machine_proto[cat] = machine_proto
      end
    end
  end

  local function index_by_item(row,item,flag_all_fluid,output_all_recipes,divider)
    -- Add a copy of row, but indexed by the item instead
    local item_sig = {type=item.type, name=item.name}
    local fluid = (item.type == "fluid") and FLAG_NORMAL_INPUT or flag_all_fluid
    local row2 = matrix:create_or_add_row(item_sig)

    divider = divider or 1

    local has_normal_qual,has_all_qual = false,false
    for flags,_ in pairs(row2.subrows_by_flags) do
      if band(flags,FLAG_NORMAL_INPUT) == 0 then
        has_all_qual = true
      else
        has_normal_qual = true
      end
    end
    if not has_all_qual and not has_normal_qual then
      -- not seen before, add recipe info
      row2:add_copy_with_flag_change(row,fluid,1,divider)
    elseif flag_all_fluid==0 and not has_all_qual then
      -- seen before but only as a fluid-input recipe
      -- e.g. steel plates in space age, with foundry taking priority over furnace
      --   There is a recipe for steel plates (cast from molten iron), but it cannot be qualitied
      --   If the user enters quality steel plate, they should get a furnace recipe instead
      
      -- Add a copy of this row ...
      row2:add_copy_with_flag_change(row,0,1,divider)

      -- .. but for the case where the input is normal, subtract this row, canceling it out
      row2:add_copy_with_flag_change(row,FLAG_NORMAL_INPUT,-1,divider)
    end
    if output_all_recipes then
      row2:set_entry(row.signal,1,bor(output_all_recipes,fluid),true,divider)
    end
  end

  -- iterate through the recipes in the given categories
  for category,_ in pairs(crafting_time_scale) do
    local machine_proto=category_to_machine_proto[category]
    local machine_has_modules = machine_proto.module_inventory_size and (machine_proto.module_inventory_size>0)
    local recipes,is_spoilage
    if category == "recipe-combinator-spoilage-mechanic" then
      recipes = g_spoilage_cache
      is_spoilage = true
    else
      recipes = prototypes.get_recipe_filtered{{filter="category",category=category}}
    end
    for name,recipe in pairs(recipes) do
      local suitable =
        string.find(name,"^parameter%-%d$") == nil
        and (is_spoilage or include_disabled or force.recipes[name].enabled)
        and (include_hidden or not recipe.hidden)
      if suitable then
        local sig = is_spoilage and {type="item",name=recipe.ingredients[1].name}
          or {type="recipe",name=recipe.name}
        local row = matrix:create_or_add_row(sig, is_spoilage or not input_recipe)
        local scaled_time = ceil(recipe.energy * crafting_time_scale[recipe.category])
        local ingredients = recipe.ingredients

        -- Are all ingredients fluid?  If so, then the recipe does not accept quality
        local all_fluid=true
        for idx=1,#ingredients do
          if ingredients[idx].type == "item" then all_fluid = false end
        end
        local flag_all_fluid = 0
        if all_fluid then flag_all_fluid = FLAG_NORMAL_INPUT end

        if output_recipe_ingredients then
          for idx=1,#ingredients do
            local ingredient=ingredients[idx]
            local fluid = (ingredient.type == "fluid") and FLAG_NOQUAL or flag_all_fluid
            row:set_entry({type=ingredient.type, name=ingredient.name},ingredient.amount,
              bor(output_recipe_ingredients,fluid))
          end
        end

        if output_all_inputs then
          row:set_entry(matrix_builder.MAKE_VALID_ANYWAY, 1, flag_all_fluid)
        end

        if output_crafting_time then
          row:set_entry(output_crafting_time_sig,scaled_time,
            bor(output_crafting_time,FLAG_NOQUAL + flag_all_fluid))
        end

        if output_recipe and not is_spoilage then
          row:set_entry(sig,1,bor(output_recipe,flag_all_fluid))
        end

        local products = recipe.products
        if output_recipe_products then
          for idx=1,#products do
            local product=products[idx]
            -- Default recipes, for specifying as an item instead of as a recipe
            local product_str = product.type .. ":" .. product.name
            local amt = product.amount or (product.amount_min + product.amount_max)/2
            local fluid = (product.type == "fluid") and FLAG_NOQUAL or flag_all_fluid
            row:set_entry({type=product.type, name=product.name},amt,
              bor(output_recipe_products,fluid))
          end
        end

        -- OK, what about module effects and other flags
        if output_crafting_machine and category_to_machine[category] then
          row:set_entry({type="item",name=category_to_machine[category]}, 1,
            bor(output_crafting_machine, FLAG_DENSE + FLAG_NOQUAL + flag_all_fluid))
        end

        -- what modules are allowed?
        if output_allowed_modules and machine_has_modules then
          for idx=1,#module_table do
            local module_name = module_table[idx]
            local module = prototypes.item[module_name]
            local cat = module.category
            local ok = ((not recipe.allowed_module_categories)
                          or recipe.allowed_module_categories[cat])
            ok = ok and ((not machine_proto.allowed_module_categories)
                          or machine_proto.allowed_module_categories[cat])
            if ok and recipe.allowed_effects then
              for eff,_value in pairs(module.module_effects) do
                if not recipe.allowed_effects[eff] then
                  ok = false
                  break
                end
              end
            end
            if ok then
              row:set_entry({type="item",name=module.name}, 1,
                bor(output_allowed_modules, FLAG_DENSE + FLAG_NOQUAL + flag_all_fluid))
            end
          end
        end

        if input_item_ingredient or input_fluid_ingredient then
          for idx=1,#ingredients do
            local is_fluid = ingredients[idx].type == "fluid"
            local fluid = is_fluid and FLAG_NORMAL_INPUT or flag_all_fluid
            if (input_item_ingredient and not is_fluid) or (input_fluid_ingredient and is_fluid) then
              index_by_item(row,ingredients[idx],fluid,output_all_recipes,ingredients[idx].amount)
            end
          end
        end
        if input_item_product or input_fluid_product then
          for idx=1,#products do
            local product = products[idx]
            local is_fluid = product.type == "fluid"
            local fluid = is_fluid and FLAG_NORMAL_INPUT or flag_all_fluid
            local amt = product.amount or (product.amount_min + product.amount_max)/2
            if (input_item_product and not is_fluid) or (input_fluid_product and is_fluid) then
              index_by_item(row,product,fluid,output_all_recipes,amt)
            end
          end
        end
      end
    end
  end

  -- go go go!
  build_matrix_combinator(entity, matrix, output_quality_sig,
    output_quality, output_selected, output_all_inputs, output_all_inputs_quality,
    output_quantity_sig, output_quantity_flags)
end

local DEFAULT_ROLLUP = {
  machines = {"assembling-machine-3"},
  input_recipe = false,
  input_ingredient_group = true,
  input_item_ingredient = true,
  input_fluid_ingredient = false,
  input_product_group = false,
  input_item_product = true,
  input_fluid_product = false,
  
  include_disabled = false,
  include_hidden = false,
  show_ingredients = true,
  show_ingredients_neg = false,
  show_ingredients_ti = true,
  show_products = true,
  show_products_neg = true,
  show_products_ti = true,
  show_time_signal = {type="virtual",name="signal-T"},
  show_recipe = true,
  show_recipe_neg = false,
  show_recipe_ti = false,
  show_time = false,
  show_time_neg = false,
  show_time_ti = false,
  show_modules = false,
  show_modules_opc = true,
  show_modules_all = false,
  show_machines = false,
  output_all_recipes = false,

  show_quality = false,
  show_quality_signal = {type="virtual",name="signal-Q"},
  show_quality_red = true,
  show_quality_green = true,

  show_quantity = false,
  show_quantity_signal = {type="virtual",name="signal-N"},
  show_quality_red = true,
  show_quality_green = true,

  show_selected = false,
  show_selected_red = true,
  show_selected_green = true,

  show_modules_red = true,
  show_modules_green = true,
  show_ingredients_red = true,
  show_ingredients_green = true,
  show_products_red = true,
  show_products_green = true,
  show_recipe_red = true,
  show_recipe_green = true,
  show_all_recipes_red = true,
  show_all_recipes_green = true,
  show_machines_red = true,
  show_machines_green = true,
  show_time_red = true,
  show_time_green = true,
  show_all_valid_inputs = false,
  show_all_valid_inputs_quality = false,
  show_all_valid_inputs_red = true,
  show_all_valid_inputs_green = true
}

local function rollup_flags(enable,ti,neg,red,green)
  return enable and (red or green) and (
      (ti and FLAG_MULTIPLY or 0)
    + (neg and FLAG_NEGATE or 0)
    + (red and FLAG_RED or 0)
    + (green and FLAG_GREEN or 0)
  )
end

local function rollup_state_to_build_args(entity, rollup)
  -- Turn a rollup state into build args
  -- the rollup state is not hierarchical, and includes state for disabled functions
  -- (eg a signal name for output time, when we aren't outputting time)
  local ru = rollup or DEFAULT_ROLLUP
  local ret = {
    entity                      = entity,
    machines                    = ru.machines,
    include_disabled            = ru.include_disabled,
    include_hidden              = ru.include_hidden,
    
    input_item_product          = ru.input_product_group and ru.input_item_product,
    input_fluid_product         = ru.input_product_group and ru.input_fluid_product,
    input_item_ingredient       = ru.input_ingredient_group and ru.input_item_ingredient,
    input_fluid_ingredient      = ru.input_ingredient_group and ru.input_fluid_ingredient,
    input_recipe                = ru.input_recipe,

    one_module_per_category     = ru.show_modules_opc,

    output_quality_sig          = rollup.show_quality and rollup.show_quality_signal,
    output_quality              = rollup_flags(ru.show_quality,false,false,
      ru.show_quality_red, ru.show_quality_green),
    output_selected              = rollup_flags(ru.show_selected,false,false,
      ru.show_selected_red, ru.show_selected_green),

    output_allowed_modules      =
      rollup_flags(ru.show_modules,false,false,
        rollup.show_modules_red, ru.show_modules_green),
    output_recipe_ingredients   =
      rollup_flags(ru.show_ingredients,ru.show_ingredients_ti,ru.show_ingredients_neg,
        rollup.show_ingredients_red,ru.show_ingredients_green),
    output_recipe_products      =
      rollup_flags(ru.show_products,ru.show_products_ti,ru.show_products_neg,
        rollup.show_products_red, ru.show_products_green),
    output_recipe               =
      rollup_flags(ru.show_recipe,ru.show_recipe_ti,ru.show_recipe_neg,
        rollup.show_recipe_red, ru.show_recipe_green),
    output_all_recipes          =
      rollup_flags(ru.show_all_recipes,ru.show_all_recipes_ti,ru.show_all_recipes_neg,
        rollup.show_all_recipes_red, ru.show_all_recipes_green),
    output_crafting_machine     =
      rollup_flags(ru.show_machines,false,false,
        rollup.show_machines_red, ru.show_machines_green),
    output_crafting_time        =
      rollup_flags(ru.show_time,ru.show_time_ti,ru.show_time_neg,
        ru.show_time_red, ru.show_time_green),
    output_all_inputs        =
      rollup_flags(ru.show_all_valid_inputs,false,false,
        ru.show_all_valid_inputs_red, ru.show_all_valid_inputs_green),
    output_quantity        =
      rollup_flags(ru.show_quantity,false,false,
        ru.show_quantity_red, ru.show_quantity_green),
    output_quantity_sig = ru.show_quantity and ru.show_quantity_signal,
    output_all_inputs_quality = ru.show_all_valid_inputs_quality,

    output_crafting_time_sig    = rollup.show_time and rollup.show_time_signal
  }
  -- game.print(serpent.line(ret))
  return ret
end

local function rebuild_combinator(combinator)
  local tags = tagged_entity.get_tags(combinator)
  build_recipe_info_combinator(rollup_state_to_build_args(combinator, tags))
end

M.Builder = Builder
M.build_recipe_info_combinator = build_recipe_info_combinator
M.init = init
M.DEFAULT_ROLLUP = DEFAULT_ROLLUP
M.destroy_components = destroy_components
M.rebuild_combinator = rebuild_combinator
return M
