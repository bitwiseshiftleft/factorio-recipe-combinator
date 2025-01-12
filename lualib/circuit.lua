local util = require "__core__.lualib.util"
local M = {}

local band = bit32.band
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
    local most_at_once = 1000
    local section = con.get_section(1)
    local filters = {}
    local j=0
    for i=1,#signals do
        local sig=signals[i]
        j=j+1
        if j>most_at_once then
            j=j-most_at_once
            section.filters = filters
            section=con.add_section()
        end
        filters[j] = {value={type=sig[1].type,name=sig[1].name,comparator="=",quality="normal"},
           min=sig[2]}
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

local function signed_lshift(x,n)
  x = bit32.lshift(x,n)
  if x >= 0x80000000 then x = x - 0x100000000 end
  return x
end

local function build_flag_matrix(builder,input,rows,prefix,aliases)
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

  -- Apply aliases
  for _,alias in ipairs(aliases) do
    local from = alias[1]
    local to = alias[2]
    local to_str = to.type .. ":" .. to.name
    for layer = 1,ceil(nbits/32) do
      if flag_layers_as_dict[layer][to_str] then
        table.insert(flag_layers[layer],{from,flag_layers_as_dict[layer][to_str]})
      end
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


local inverses_cache = {}
local function div_mod_2_32(x,y)
  -- Returns z such that, as int32_t's, (z*y) % (1<<32) = x
  -- y must be odd
  local z
  if inverses_cache[y] then z = inverses_cache[y]
  else
    z = band(y,3) -- low 2 bits of x
    z = band(z * band(2-y*z,-1), 0xFFFF)
    z = band(z * band(2-y*z,-1), 0xFFFF)
    z = band(z * band(2-y*z,-1), 0xFFFF)
    z = band(z * band(2-y*z,-1), -1) -- fine because z < 2^16 going into this step
    inverses_cache[y] = z
  end
  -- multiply z = x*z.
  z = band(
    band(z*band(x,0xFFFF),-1) +
    band(z*bit32.rshift(x,16),0xFFFF)*0x10000,
  -1)
  if z >= 0x80000000 then z = z - 0x100000000 end
  return z
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

local function init()
  cache_modules()
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
  --
  -- When multiple rows are the same (e.g. indexed by a recipe and also
  -- by one of its products), this might be more efficient using aliases
  -- In that case, pass the aliases as {sig1_alias, sig1}
  -- to indicate that sig1_alias's row should be the same as sig1's row
  local builder,input,rows=args.builder,args.input,args.rows
  local prefix,aliases=(args.prefix or "sparse_matrix."),(args.aliases or {})
  local flags_only,multiply_by_input = args.flags_only,args.multiply_by_input
  local entry_data,entry_dict,idx_data,idx_dict = {},{},{},{}
  local columns,jdx_dict,jdx_data,jdx_count = {},{},{},{}
  local rowsig,combo,entry,colsig,jdx_value

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
        jdx_data[layer][jdx_value] = {colsig,1+2*jdx_value}
        jdx_dict[layer][colsig_str] = jdx_value
      end
      jdx_value = jdx_dict[layer][colsig_str]
      if jdx_value > 1 then
        table.insert(idx_data[layer], {rowsig,jdx_value-1})
        idx_dict[layer][rowsig_str] = jdx_value-1
      end
      local ent = div_mod_2_32(entry,1+2*jdx_value)
      if not flags_only then
        table.insert(entry_data[layer], {rowsig,ent})
        -- put in the dict too so we can get it in aliases
        entry_dict[layer][rowsig_str] = ent
      end
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
      if (not flags_only) and entry_dict[layer][to_str] then
        table.insert(entry_data[layer],{from,entry_dict[layer][to_str]})
      end
    end
  end

  -- TODO: make sure it can't be in input
  local idx_signal = {type="virtual", name="signal-info"}

  -- Build the combinators
  -- First, 1-cycle input buffer
  local buf_input
  if not flags_only then
    buf_input = builder:arithmetic{L=EACH,op="+",R=0,description=prefix.."buf",green={input}}
  end
  local first_output = nil
  for layer = 1,#idx_data do
    local idx_combi = builder:constant_combi(idx_data[layer],   prefix.."idx"..tostring(layer))
    local jdx_combi = builder:constant_combi(jdx_data[layer],   prefix.."jdx"..tostring(layer))

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

    local this_output
    if flags_only then
      -- accumulate
      this_output = apply_idx
    else
      local ent_combi = builder:constant_combi(entry_data[layer], prefix.."ent"..tostring(layer))
      local dotp
      if multiply_by_input then
        dotp = builder:arithmetic{
          L=EACH,NL=NGREEN,op="*",R=EACH,NR=NRED,
          out=idx_signal,
          green = {buf_input}, red = {ent_combi},
          description=prefix.."dotp"..tostring(layer)
        }
      else
        dotp = builder:decider{
          decisions = {
            {L=EACH,NL=NGREEN,op="!=",R=0},
            {and_=true,L=EACH,NL=NRED,op="!=",R=0}
          },
          output = {{out=idx_signal,WO=NRED}},
          green = {buf_input}, red = {ent_combi},
          description=prefix.."dotp"..tostring(layer)
        }
      end
      this_output = builder:arithmetic{
        L=EACH,NL=NGREEN,op="*",R=idx_signal,NR=NRED,out=EACH,
        green = {apply_idx}, red = {dotp},
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

local function build_recipe_info_combinator(args)
  -- parse args
  local entity                    = args.entity
  local machines                  = args.machines
  local output_allowed_modules    = args.output_allowed_modules
  local output_recipe_ingredients = args.output_recipe_ingredients
  local output_recipe_products    = args.output_recipe_products
  local alias_recipe_products     = args.alias_recipe_products
  local alias_recipe_ingredients  = args.alias_recipe_ingredients
  local output_crafting_machine   = args.output_crafting_machine

  local one_module_per_category   = true

  local builder = Builder:new(entity.surface, entity.position, entity.force)
  local aliases,naliases,aliases_dict = {},0,{}

  -- Set the entity's control info
  local behavior = entity.get_or_create_control_behavior()
  behavior.parameters = {first_constant=0, operation="+", second_constant=0, output_signal=nil}

  local crafting_time_scale = {}
  local absolute_time_scale = 60 -- i.e. in ticks
  local category_to_machine = {}
  local category_to_machine_proto = {}

  -- parse out the machines into speeds and categories
  for _,machine in ipairs(machines) do
    local quality = nil -- TODO
    local machine_proto = prototypes.entity[machine]
    for cat,_ in pairs(machine_proto.crafting_categories) do
      if not crafting_time_scale[cat] then
        crafting_time_scale[cat] = absolute_time_scale / machine_proto.get_crafting_speed(quality)
        category_to_machine[cat] = (machine_proto.items_to_place_this[1] or {}).name
        category_to_machine_proto[cat] = machine
      end
    end
  end

  local crafting_time_output = {type="virtual", name="signal-T"} -- TODO: get from config
  local matrix,nmatrix = {},0
  local valid,nvalid = {},0
  local flags,nflags = {},0
  local module_category_to_module = {}

  local function alias(item,recipe)
    local item_str = item.type .. ":" .. item.name
    if not aliases_dict[item_str] then
      aliases_dict[item_str] = recipe
      naliases=naliases+1
      aliases[naliases] = {{type=item.type,name=item.name},sig}
      nvalid=nvalid+1
      valid[nvalid] = {{type=item.type,name=item.name},1}
    end
  end

  -- iterate through the recipes in the given categories
  for category,_ in pairs(crafting_time_scale) do
    local machine_proto=category_to_machine_proto[category]
    local machine_has_modules = machine_proto.module_inventory_size and (machine_proto.module_inventory_size>0)
    for name,recipe in pairs(prototypes.get_recipe_filtered{{filter="category",category=category}}) do
      local sig = {type="recipe",name=recipe.name}
      nvalid=nvalid+1
      valid[nvalid] = {sig,1}

      local scaled_time = ceil(recipe.energy * crafting_time_scale[recipe.category])
      local linear_combo = {}
      local ncombo=0
      -- TODO: deal with probabilities?

      ncombo=ncombo+1
      linear_combo[ncombo]={crafting_time_output,scaled_time}

      if output_recipe_products or alias_recipe_products then
        local products = recipe.products
        for idx=1,#products do
          local product=products[idx]
          -- Default recipes, for specifying as an item instead of as a recipe
          -- TODO: is this the logic the game engine uses to assign them?
          local product_str = product.type .. ":" .. product.name
          if alias_recipe_products then alias(product,recipe) end
          if output_recipe_products then
            local amt = product.amount or (product.amount_min + product.amount_max)/2
            ncombo=ncombo+1
            linear_combo[ncombo]={{type=product.type, name=product.name},-amt}
          end
        end
      end

      if output_recipe_ingredients or alias_recipe_ingredients then
        local ingredients=recipe.ingredients
        for idx=1,#ingredients do
          local ingredient=ingredients[idx]
          if alias_recipe_ingredients then alias(ingredient,recipe) end
          if output_recipe_ingredients then
            ncombo=ncombo+1
            linear_combo[ncombo]={{type=ingredient.type, name=ingredient.name},ingredient.amount}
          end
        end
      end

      if ncombo > 0 then
        nmatrix=nmatrix+1
        matrix[nmatrix]={sig,linear_combo}
      end

      -- OK, what about module effects and other flags
      local the_flags    = {}
      local mflags = 0

      if output_crafting_machine and category_to_machine[category] then
        mflags=mflags+1
        the_flags[mflags] = {type="item",name=category_to_machine[category]}
      end

      -- what modules are allowed?
      if output_allowed_modules and machine_has_modules then
        for idx=1,#g_modules_per_category do
          local module_name=g_modules_per_category[i]
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
            mflags=mflags+1
            the_flags[mflags] = {type="item",name=module.name}
          end
        end
      end

      nflags=nflags+1
      flags[nflags] = {sig,the_flags}
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

  -- widget to connect combi's output to the main entity
  local function connect_output(combi)
    if not combi then return end
    combi.get_wire_connector(OGREEN,true).connect_to(entity.get_wire_connector(OGREEN,true))
    combi.get_wire_connector(ORED,true).  connect_to(entity.get_wire_connector(ORED,  true))
  end

  if nmatrix > 0 then
    connect_output(build_sparse_matrix{
      builder=builder,input=buffer2,rows=matrix,prefix="ri.matrix.",aliases=aliases
    })
  end

  -- TODO: add right-aliases to flag_matrix
  if nflags > 0 then
    connect_output(build_flag_matrix(builder,buffer2,flags,"ri.flag.",aliases))
  end
end

M.Builder = Builder
M.build_recipe_info_combinator = build_recipe_info_combinator
M.init = init
return M
