local util = require "__core__.lualib.util"
local M = {}

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

local NGREEN = {green=true,red=false}
local NRED   = {green=false,red=true}
local NBOTH  = {green=true,red=true}
local NNONE  = {green=false,red=false}

-- Signal definitions
local EACH = {type="virtual",name="signal-each"}
local ANYTHING = {type="virtual",name="signal-anything"}
local EVERYTHING = {type="virtual",name="signal-everything"}

-- When used as a builder interface, takes input from itself
local ITSELF = "__ITSELF__"
local Builder = {}

function Builder:constant_combi(signals,description)
    -- Create a constant combinator with the given signals
    local entity = self.surface.create_entity{
        name="recipe-combinator-component-constant-combinator",
        position=self.position, force=self.force
    }
    local con = entity.get_or_create_control_behavior()
    local section = con.get_section(1)
    for i,sig in ipairs(signals) do
        section.set_slot(i,{value=util.merge{sig[1],{comparator="=",quality="normal"}},min=sig[2]})
    end
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
  -- Create an arithmetic combinator
  local combi = self:make_combi(util.merge{args,{selector=true}})
  combi.get_or_create_control_behavior().parameters = {
    operation=args.op, select_max=args.select_max, index_signal=args.index
  }
  return self:connect_inputs(args, combi)
end

function Builder:new(surface,position,force)
  local o = {surface=surface,position=position,force=force}
  setmetatable(o, self)
  self.__index = self
  return o
end

local band = bit32.band

local function div_mod_2_32(x,y)
  -- Returns z such that, as int32_t's, (z*y) % (1<<32) = x
  local z = band(y,3) -- low 2 bits of x
  z = band(z * band(2-y*z,-1), 0xFFFF)
  z = band(z * band(2-y*z,-1), 0xFFFF)
  z = band(z * band(2-y*z,-1), 0xFFFF)
  z = band(z * band(2-y*z,-1), -1) -- fine because z < 2^16 going into this step
  -- multiply z = x*z.
  z = band(
    band(z*band(x,0xFFFF),-1) +
    band(z*bit32.rshift(x,16),0xFFFF)*0x10000,
  -1)
  if z >= 0x80000000 then z = z - 0x100000000 end
  return z
end

local function build_sparse_matrix(builder,input,rows,prefix,aliases)
  local columns = {}
  local rowsig,combo,entry,colsig
  local idx_data = {}
  local jdx_data = {}
  local jdx_dict = {}
  local jdx_count = {}
  local jdx_value
  local entry_data = {}
  local entry_dict = {}
  local idx_dict = {}

  prefix = prefix or "sparse_matrix."
  aliases = aliases or {}

  for _idx,row in ipairs(rows) do
    rowsig,combo = row[1],row[2]
    local rowsig_str = rowsig.type .. ":" .. rowsig.name
    for layer,col in ipairs(combo) do
      colsig,entry = col[1],col[2]
      if not idx_data[layer] then
        idx_data[layer] = {}
        jdx_data[layer] = {}
        jdx_dict[layer] = {}
        idx_dict[layer] = {}
        entry_dict[layer] = {}
        entry_data[layer] = {}
        jdx_count[layer] = 0
      end
      local colsig_str = colsig.type .. ":" .. colsig.name
      if not jdx_dict[layer][colsig_str] then
        jdx_value = 1+jdx_count[layer]
        jdx_count[layer] = jdx_value
        table.insert(jdx_data[layer], {colsig,1+2*jdx_value})
        jdx_dict[layer][colsig_str] = jdx_value
      end
      jdx_value = jdx_dict[layer][colsig_str]
      if jdx_value > 1 then
        table.insert(idx_data[layer], {rowsig,jdx_value-1})
        idx_dict[layer][rowsig_str] = jdx_value-1
      end
      local ent = div_mod_2_32(entry,1+2*jdx_value)
      table.insert(entry_data[layer], {rowsig,ent})
      -- put in the dict so we can get it in aliases
      entry_dict[layer][rowsig_str] = ent
    end
  end

  -- apply aliases
  for _,alias in ipairs(aliases) do
    local from=alias[1]
    local to=alias[2]
    for layer = 1,#idx_data do
      to_str = to.type .. ":" .. to.name
      if idx_dict[layer][to_str] then
        table.insert(idx_data[layer],{from,idx_dict[layer][to_str]})
      end
      if entry_dict[layer][to_str] then
        table.insert(entry_data[layer],{from,entry_dict[layer][to_str]})
      end
    end
  end

  -- TODO: make sure it can't be in input
  local idx_signal = {type="virtual", name="signal-info"}

  -- Build the combinators
  -- First, 1-cycle input buffer
  local buf_input = builder:arithmetic{L=EACH,op="+",R=0,description=prefix.."buf",green={input}}
  local first_output = nil
  for layer = 1,#idx_data do
    local idx_combi = builder:constant_combi(idx_data[layer],   prefix.."idx"..tostring(layer))
    local jdx_combi = builder:constant_combi(jdx_data[layer],   prefix.."jdx"..tostring(layer))
    local ent_combi = builder:constant_combi(entry_data[layer], prefix.."ent"..tostring(layer))

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
    local apply_idx = builder:selector{
      op="select", index=idx_signal, select_max=false,
      green = {get_idx}, red = {jdx_combi},
      description=prefix.."apply_jdx"..tostring(layer)
    }
    local dotp = builder:arithmetic{
      L=EACH,NL=NGREEN,op="*",R=EACH,NR=NRED,
      out=idx_signal,
      green = {buf_input}, red = {ent_combi},
      description=prefix.."dotp"..tostring(layer)
    }
    local multiply = builder:arithmetic{
      L=EACH,NL=NGREEN,op="*",R=idx_signal,NR=NRED,out=EACH,
      green = {apply_idx}, red = {dotp},
      description=prefix.."output"..tostring(layer)
    }
    if first_output then
      first_output.get_wire_connector(OGREEN,true).connect_to(multiply.get_wire_connector(OGREEN,true))
      first_output.get_wire_connector(ORED,true).  connect_to(multiply.get_wire_connector(ORED,  true))
    else first_output = multiply end
  end

  -- game.print("Built sparse matrix with " .. tostring(#idx_data) .. " layers!")
  return first_output
end


local function build_recipe_info_combinator(entity, machines)
  local builder = Builder:new(entity.surface, entity.position, entity.force)
  local aliases = {}
  local aliases_dict = {}

  -- Set the entity's control info
  local behavior = entity.get_or_create_control_behavior()
  behavior.parameters = {first_constant=0, operation="+", second_constant=0, output_signal=nil}

  local crafting_time_scale = {}
  local absolute_time_scale = 60 -- i.e. in ticks

  -- parse out the machines into speeds and categories
  for _,machine in ipairs(machines) do
    local quality = nil -- TODO
    local machine_proto = prototypes.entity[machine]
    for cat,_ in pairs(machine_proto.crafting_categories) do
      if not crafting_time_scale[cat] then
        crafting_time_scale[cat] = absolute_time_scale / machine_proto.get_crafting_speed(quality)
      end
    end
  end

  local crafting_times = {}
  local matrix = {}
  local crafting_time_output = {type="virtual", name="signal-T"} -- TODO: get from config
  local valid = {}

  -- iterate through the recipes in the given categories
  for category,_ in pairs(crafting_time_scale) do
    for name,recipe in pairs(prototypes.get_recipe_filtered{{filter="category",category=category}}) do
      local sig = {type="recipe",name=recipe.name}
      table.insert(valid,{sig,1})

      local scaled_time = math.ceil(recipe.energy * crafting_time_scale[recipe.category])
      table.insert(crafting_times,{sig,scaled_time})
      local linear_combo = {}
      -- TODO: deal with probabilities?

      for idx,product in ipairs(recipe.products) do
        -- Default recipes, for specifying as an item instead of as a recipe
        -- TODO: is this the logic the game engine uses to assign them?
        local product_str = product.type .. ":" .. product.name
        if not aliases_dict[product_str] then
          aliases_dict[product_str] = recipe
          table.insert(aliases,{{type=product.type,name=product.name},sig})
          table.insert(valid,{{type=product.type,name=product.name},1})
        end

        local amt = product.amount or (product.amount_min + product.amount_max)/2
        table.insert(linear_combo,{{type=product.type, name=product.name},-amt})
      end
      for idx,ingredient in ipairs(recipe.ingredients) do
        table.insert(linear_combo,{{type=ingredient.type, name=ingredient.name},ingredient.amount})
      end

      table.insert(matrix,{sig,linear_combo})
    end
  end
  
  -- Extend out to latency 5.
  -- Stage 1: input buffer.  Connect to entity's inputs
  local input_buffer = builder:arithmetic{L=EACH,op="+",R=0,description="ri.input_buffer"}
  input_buffer.get_wire_connector(IGREEN,true).connect_to(entity.get_wire_connector(IGREEN,true))
  input_buffer.get_wire_connector(IRED,  true).connect_to(entity.get_wire_connector(IRED,  true))

  -- Stage 2: selection of one valid input
  local valid_combi = builder:constant_combi(valid, "ri.valid")
  local buffer2 = builder:decider{
    decisions={
      {NL=NGREEN,L=EACH,op="!=",R=0},
      {and_=true,NL=NRED,L=EACH,op="!=",R=0}
    },
    output={{out=ANYTHING,WO=NGREEN}},
    description="ri.buffer2",green={input_buffer},red={valid_combi}
  }

  -- Stages 3,4: just buffer
  local buffer3 = builder:arithmetic{L=EACH,op="+",R=0,description="ri.buffer3",green={buffer2}}
  local buffer4 = builder:arithmetic{L=EACH,op="+",R=0,description="ri.buffer4",green={buffer3}}

  -- widget to connect combi's output to the main entity
  local function connect_output(combi)
    if not combi then return end
    combi.get_wire_connector(OGREEN,true).connect_to(entity.get_wire_connector(OGREEN,true))
    combi.get_wire_connector(ORED,true).  connect_to(entity.get_wire_connector(ORED,  true))
  end

  -- TODO: if ...
  connect_output(build_sparse_matrix(builder,buffer2,matrix,"ri.matrix.",aliases))

  if crafting_time_output then
    local times_combinator = builder:constant_combi(crafting_times,"ri.crafting_times")
    local output_time = builder:arithmetic{
      L=EACH,NL=NRED,op="*",R=EACH,NR=NGREEN,
      out=crafting_time_output,
      red={times_combinator},green={buffer4},
      description="ri.crafting_time_output"
    }
    connect_output(output_time)
  end
end

M.Builder = Builder
M.build_recipe_info_combinator = build_recipe_info_combinator
return M
