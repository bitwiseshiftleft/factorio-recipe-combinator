local util = require "__core__.lualib.util"
local tagged_entity = require "lualib.tagged_entity"
local matrix_builder = require "lualib.matrix_builder"
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

local function init()
  cache_modules()
  cache_qualities()
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
  local entry_data,idx_data,idx_dict = {},{},{}
  local columns,jdx_dict,jdx_data,jdx_count = {},{},{},{}
  local rowsig,combo,entry,colsig,jdx_value

  for _idx,row in ipairs(rows) do
    rowsig,combo = row[1],row[2]
    -- game.print(serpent.line(rowsig) .. ": " .. serpent.line(combo))
    local rowsig_str = rowsig.type .. ":" .. rowsig.name
    for layer,col in ipairs(combo) do
      -- "layer" meaning index of ingredient within the combo
      colsig,entry = col[1],col[2]
      local colsig_str = colsig.type .. ":" .. colsig.name

      if not idx_data[layer] then
        -- it's the first ingredient at that index.  Initialize it
        idx_data[layer] = {}
        jdx_data[layer] = {}
        jdx_dict[layer] = {}
        idx_dict[layer] = {}
        entry_data[layer] = {}
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

local function destroy_components(entity)
  -- Destroy recipe combinator components that are children of this item
  -- FIXME seemingly doesn't give the combinator back
  local children = entity.surface.find_entities_filtered{area=entity.bounding_box}
  local undo_info = {}
  for i,child in ipairs(children) do
      if string.find(child.name, '^recipe%-combinator%-component%-') then
          child.destroy()
      end
  end
end


local function build_matrix_combinator(entity, matrix)
  local builder = Builder:new(entity.surface, entity.position, entity.force)


  -- Collate the matrix into a dense form
  local matrices_by_flags, valid, valid_at_all_qualities = matrix:collate()

  -- Extend out to latency 6.
  -- Stage 1: input buffer.  Connect to entity's inputs
  local input_buffer = builder:arithmetic{L=EACH,op="+",R=0,description="ri.input_buffer"}
  input_buffer.get_wire_connector(IGREEN,true).connect_to(entity.get_wire_connector(IGREEN,true))
  input_buffer.get_wire_connector(IRED,  true).connect_to(entity.get_wire_connector(IRED,  true))

  local end_of_input_stage
  local quality_buffer
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
    local valid2_combi = builder:constant_combi(valid2, "ri.valid")
    local quality_list = builder:constant_combi(literal_quality, "ri.quals")

    -- Stage 2: selection of one valid input
    local select_one = builder:decider{
      decisions={
        {NL=NGREEN,L=EACH,op="!=",R=0},
        {and_=true,NL=NRED,L=EACH,op="!=",R=0}
      },
      output={{out=ANYTHING,WO=NGREEN}},
      description="ri.buffer2",green={input_buffer},red={valid2_combi},
      -- visible=true
    }

    -- Stage 2b a second copy, but output the quality selected instead
    local select_one_getqual = builder:decider{
      decisions={
        {NL=NGREEN,L=EACH,op="!=",R=0},
        {and_=true,NL=NRED,L=EACH,op="!=",R=0}
      },
      output={{out=ANYTHING,WO=NRED}},
      description="ri.qual2",green={input_buffer},red={valid2_combi},
    }

    -- Stage 3a set quality to normal
    end_of_input_stage = builder:selector{
      op="quality-transfer", qual=g_all_qualities[0], out=EACH,
      green={select_one}, description="ri.set_normal_qual",
    }

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
    -- Stage 2: selection of one valid input
    local valid_combi = builder:constant_combi(valid, "ri.valid")
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

  end

  -- widget to connect combi's output to the main entity
  local function connect_output(combi)
    if not combi then return end
    combi.get_wire_connector(OGREEN,true).connect_to(entity.get_wire_connector(OGREEN,true))
    combi.get_wire_connector(ORED,true).  connect_to(entity.get_wire_connector(ORED,  true))
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
      connect_output(build_flag_matrix(builder,input,matrix,"ri.matrix.flags"..tonumber(flags).."."))
      -- game.print("Build flag matrix with "..tonumber(#matrix).." rows with flags="..tonumber(flags))
    else 
      connect_output(build_sparse_matrix{
        builder=builder,input=input,rows=matrix,prefix="ri.matrix.flags"..tonumber(flags)..".",
        multiply_by_input=band(flags,FLAG_MULTIPLY)>0,use_qual=use_qual
      })
      -- game.print("Build sparse matrix with "..tonumber(#matrix).." rows with flags="..tonumber(flags))
    end
  end
end

local function build_recipe_info_combinator(args)
  -- parse args
  local entity                    = args.entity
  local machines                  = args.machines or {}
  local output_allowed_modules    = args.output_allowed_modules
  local output_recipe_ingredients = args.output_recipe_ingredients
  local output_recipe_products    = args.output_recipe_products
  local output_recipe             = args.output_recipe
  local input_recipe_products     = args.input_recipe_products
  local input_recipe_ingredients  = args.input_recipe_ingredients
  local input_recipe              = args.input_recipe
  local output_crafting_machine   = args.output_crafting_machine
  local one_module_per_category   = args.one_module_per_category
  local output_crafting_time      = args.output_crafting_time
  local output_all_recipes        = args.output_all_recipes -- TODO
  local include_hidden            = args.include_hidden
  local include_disabled          = args.include_disabled
  -- TODO: more!  Scales, red/green, etc

  local module_table = output_allowed_modules and (
    (one_module_per_category and g_modules_per_category) or g_all_modules
  ) or {}

  destroy_components(entity)
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

  local function index_by_item(row,item,flag_all_fluid)
    -- Add a copy of row, but indexed by the item instead
    local item_sig = {type=item.type, name=item.name}
    local fluid = (item.type == "fluid") and FLAG_NORMAL_INPUT or flag_all_fluid
    local row2 = matrix:create_or_add_row(item_sig)

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
      row2:add_copy_with_flag_change(row,fluid)
    elseif flag_all_fluid==0 and not has_all_qual then
      -- seen before but only as a fluid-input recipe
      -- e.g. steel plates in space age, with foundry taking priority over furnace
      --   There is a recipe for steel plates (cast from molten iron), but it cannot be qualitied
      --   If the user enters quality steel plate, they should get a furnace recipe instead
      
      -- Add a copy of this row ...
      row2:add_copy_with_flag_change(row,0)

      -- .. but for the case where the input is normal, subtract this row, canceling it out
      row2:add_copy_with_flag_change(row,FLAG_NORMAL_INPUT,-1)
    end
    if output_all_recipes then
      row2:set_entry(row.signal,1,fluid,true)
    end
  end

  -- iterate through the recipes in the given categories
  for category,_ in pairs(crafting_time_scale) do
    local machine_proto=category_to_machine_proto[category]
    local machine_has_modules = machine_proto.module_inventory_size and (machine_proto.module_inventory_size>0)
    for name,recipe in pairs(prototypes.get_recipe_filtered{{filter="category",category=category}}) do
      local suitable =
        string.find(name,"^parameter%-%d$") == nil
        and (include_disabled or recipe.enabled)
        and (include_hidden or not recipe.hidden)
      if suitable then
        local sig = {type="recipe",name=recipe.name}
        local row = matrix:create_or_add_row(sig, not input_recip)
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
            row:set_entry({type=ingredient.type, name=ingredient.name},ingredient.amount, FLAG_MULTIPLY+fluid)
          end
        end

        if output_crafting_time then
          row:set_entry(output_crafting_time,scaled_time,FLAG_MULTIPLY + FLAG_NOQUAL + flag_all_fluid)
        end

        if output_recipe then
          row:set_entry(sig,1,FLAG_MULTIPLY + flag_all_fluid)
        end

        local products = recipe.products
        if output_recipe_products then
          for idx=1,#products do
            local product=products[idx]
            -- Default recipes, for specifying as an item instead of as a recipe
            local product_str = product.type .. ":" .. product.name
            local amt = product.amount or (product.amount_min + product.amount_max)/2
            local fluid = (product.type == "fluid") and FLAG_NOQUAL or flag_all_fluid
            row:set_entry({type=product.type, name=product.name},-amt,FLAG_MULTIPLY+fluid)
          end
        end

        -- OK, what about module effects and other flags
        if output_crafting_machine and category_to_machine[category] then
          row:set_entry({type="item",name=category_to_machine[category]}, 1,
            FLAG_DENSE + FLAG_NOQUAL + flag_all_fluid)
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
              row:set_entry({type="item",name=module.name}, 1, FLAG_DENSE + FLAG_NOQUAL + flag_all_fluid)
            end
          end
        end

        if input_recipe_ingredients then
          for idx=1,#ingredients do
            index_by_item(row,ingredients[idx],flag_all_fluid)
          end
        end
        if input_recipe_products then
          for idx=1,#products do
            index_by_item(row,products[idx],flag_all_fluid)
          end
        end
      end
    end
  end

  -- go go go!
  build_matrix_combinator(entity, matrix)
end

local DEFAULT_ROLLUP = {
  machines = {"assembling-machine-3"},
  input_recipe = false,
  input_ingredients = false,
  input_product = true,
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
  show_recipe_neg = true,
  show_recipe_ti = true,
  show_time = false,
  show_time_neg = false,
  show_time_ti = true,
  show_modules = false,
  show_modules_opc = true,
  show_modules_all = false,
  show_machines = false,
  output_all_recipes = false
}

local function rollup_state_to_build_args(entity, rollup)
  -- Turn a rollup state into build args
  -- the rollup state is not hierarchical, and includes state for disabled functions
  -- (eg a signal name for output time, when we aren't outputting time)
  rollup = rollup or DEFAULT_ROLLUP
  local ret = {
    entity                      = entity,
    machines                    = rollup.machines,
    include_disabled            = rollup.include_disabled,
    include_hidden              = rollup.include_hidden,
    
    input_recipe_products       = rollup.input_product,
    input_recipe_ingredients    = rollup.input_ingredients,
    input_recipe                = rollup.input_recipe,

    output_allowed_modules      = rollup.show_modules,
    one_module_per_category     = rollup.show_modules_opc,
    output_recipe_ingredients   = rollup.show_ingredients,
    output_recipe_products      = rollup.show_products,
    output_recipe               = rollup.show_recipe,
    output_all_recipes          = rollup.show_all_recipes,
    output_crafting_machine     = rollup.show_machines,
    output_crafting_time        = rollup.show_time and rollup.show_time_signal
  }
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
