local util = require "__core__.lualib.util"
local myutil = require "lualib.util"
local M = {}


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
local THRESHOLD = {type="virtual",name="router-signal-threshold"}
local DEFAULT = {type="virtual",name="router-signal-default"}
local ZERO = {type="virtual",name="signal-0"}
local SIGC = {type="virtual",name="signal-C"}

local LINK  = {type="virtual",name="router-signal-link"}
local LEAF  = {type="virtual",name="router-signal-leaf"}
local POWER = LEAF -- I guess

local READ_ALL = defines.control_behavior.transport_belt.content_read_mode.entire_belt_hold

-- When used as a builder interface, takes input from itself
local ITSELF = "__ITSELF__"
local Builder = {}

function Builder:constant_combi(signals,description)
    -- Create a constant combinator with the given signals
    local entity = self.surface.create_entity{
        name="router-component-hidden-constant-combinator",
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

function Builder:make_blinken_combi(args)
    -----------------------------------------------------------------------
    -- Make a combinator entity.
    -----------------------------------------------------------------------
    -- If args.arithmetic then it will be an arithmetic combinator (otherwise decider)
    -- If args.combinator_name the you can set the entity name; otherwise it will be
    --   a regular combinator if args.visible, ando otherwise a hidden one
    -- If it's hidden, and args.blinken is truthy, then it will still have visible
    --   blinkenlights.  Blinkenlight combinators will be laid out in a grid with
    --   pseudorandom colors according to the builder's blinken settings
    -- Set the combinator description according to args.description.
    -----------------------------------------------------------------------
    local blinken = args.blinken
    local blinken_suffix = blinken and "-blinken" or ""

    if args.arithmetic then
        name = args.combinator_name or (args.visible and "arithmetic-combinator") or "router-component-arithmetic-combinator" .. blinken_suffix
    else
        name = args.combinator_name or (args.visible and "decider-combinator") or "router-component-decider-combinator" .. blinken_suffix
    end
    
    -- Lay out blinkenlights on a grid
    local x_offset, y_offset, orientation = 0
    if args.blinken then
        x_offset = self.blinken_base_x + self.blinken_offset_x*self.blinken_xi
        y_offset = self.blinken_base_y + self.blinken_offset_y*self.blinken_yi
        self.blinken_xi = self.blinken_xi + 1
        if self.blinken_xi >= self.blinken_cols then
            self.blinken_xi = 0
            self.blinken_yi = self.blinken_yi + 1
        end

        -- arbitrary
        orientation = (self.rngstate*4) % 16
        self.rngstate = bit32.bxor(bit32.lrotate(self.rngstate,3),self.rngstate + 0xb96e43d2)
    else
        x_offset = 0
        y_offset = 0
    end

    local ret = self.surface.create_entity{
        name=name, position=myutil.vector_add(self.position,{x=x_offset,y=y_offset}), force=self.force,
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
    local combi = self:make_blinken_combi(args)

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
    local combi = self:make_blinken_combi(util.merge{args,{arithmetic=true}})
    local behavior = combi.get_or_create_control_behavior()
    local params = self:expand_shorthand_conditions(args)
    params.operation=args.op or "+"
    params.output_signal=args.out or EACH
    behavior.parameters = params
    return self:connect_inputs(args, combi)
end

function Builder:new(surface,position,force)
    local o = {surface=surface,position=position,force=force}
    setmetatable(o, self)
    self.__index = self
    self.blinken_xi = 0
    self.blinken_yi = 0
    self.blinken_cols = 8
    self.blinken_base_x = 0
    self.blinken_base_y = 0
    self.blinken_offset_x = 0
    self.blinken_offset_y = 0
    self.rngstate = 0x6ff4cd3d
    return o
end

function Builder:create_or_find_entity(args)
    -- TODO: do we have issues with direction or whatever here?
    local position = args.position or self.position
    
    -- Is it already there?
    local entity = self.surface.find_entity(args.name,position)
    if entity then return entity end

    -- Is it a ghost?
    entity = self.surface.find_entities_filtered{
        ghost_name=args.name,
        position=position,
        force=self.force,
        limit=1
    }
    if entity and entity[1] then
        -- un-ghost it
        local a,e,c = entity[1].revive()
        return e
    end

    -- Nope, create it
    return self.surface.create_entity(
        util.merge({{position=position,force=self.force}, args})
    )
end

-- Make a circuit that draws power, and outputs on GREEN based on power.
-- The outputs are based on the offset arg
--   (offset ^ INT_MIN) if power; offset if no power
--   default offset = INT_MIN
local function power_consumption_combi(builder,size, prefix, suffix, orientation, offset, quality)
    local name = "router-component-"..size.."-"..prefix.."power-combinator-"..suffix
    local c1 = builder:arithmetic{
        combinator_name=name,op="+",L=-0x80000000,R=POWER,out=POWER,red={ITSELF},
        orientation = orientation, description="Power consumer",
        quality = quality
    }
    local c2 = builder:arithmetic{op="+",L=offset or -0x80000000,R=POWER,out=POWER,red={c1}, description="Power consumer checker"}
    c1.get_wire_connector(OGREEN,true).connect_to(c2.get_wire_connector(OGREEN,true))
    return c2
end

-- 
local function fixup_power_consumption(builder, entity, name)
    local c1o,c1,c2
    for _,e in ipairs(entity.surface.find_entities_filtered{
        type="arithmetic-combinator",
        area=entity.bounding_box,
        force=builder.force
    }) do
        if string.find(e.name,"power%-combinator") then
            c1o = e
        elseif e.combinator_description == "Power consumer checker" then
            c2 = e
        end
    end
    if c1o and c2 then
        local c1 = builder:arithmetic{
            combinator_name=name,op="+",L=-0x80000000,R=POWER,out=POWER,red={ITSELF},
            orientation = orientation, description="Power consumer",
            quality = entity.quality
        }
        c1.get_wire_connector(ORED,true).connect_to(c2.get_wire_connector(IRED,true))
        c1.get_wire_connector(OGREEN,true).connect_to(c2.get_wire_connector(OGREEN,true))
        c1o.destroy()
        return true
    end
    return false
end
    
-- Smart router heat-equation leakage factor.
--
-- The greater this is, the greater the equilibrium value on the wires will be, and the further
-- signals will propagate throughout the network.
--
-- The smaller this is, the faster the network will equilibrate.
local LEAK_FACTOR = 64

local function set_jam_scale(builder,entity,new_jam_scale)
    -- Update a router to set the scale for the number of items in its buffer at which it is
    -- considered jammed.  Multiplied by a constant, currently 16 (or rather -16 because it's
    -- added to the item count)
    for _,e in ipairs(entity.surface.find_entities_filtered{
        type="constant-combinator",
        area=entity.bounding_box,
        force=builder.force
    }) do
        if e.combinator_description == "jammed scale" then
            e.get_or_create_control_behavior().get_section(1).set_slot(1,
                {value=util.merge{SIGC,{comparator="=",quality="normal"}},
                 min=-16*new_jam_scale}
            )
        end
    end
end

local function create_smart_comms(builder,prefix,chest,input_belts,input_loaders,output_loaders,lamps,jam_scale,size,quality)
    ------------------------------------------------------------------------------
    -- Create communications system for a smart router.
    ------------------------------------------------------------------------------

    -- Set up the builder's blinkendata
    builder.blinken_cols = 6
    builder.blinken_base_x = 0.43
    builder.blinken_base_y = 0.38
    builder.blinken_offset_x = 0.08
    builder.blinken_offset_y = 0.070

    ------------------------------------------------------------------------------
    -- Disable the input loaders if too much stuff is in the chest (it's jammed)
    -- FUTURE: in v0.1, individual input belts could jam without jamming the whole router
    --   Should we preserve this behavior in v2?  Probably not worth?
    --   But the new behavior probably makes the whole network more vulnerable to jamming.
    ------------------------------------------------------------------------------
    for _,b in ipairs(input_belts) do
        local control = b.get_or_create_control_behavior()
        control.read_contents = true
        control.read_contents_mode = READ_ALL
        -- FUTURE: enable/disable the belt on low power for show, or maybe that's too expensive?
    end
    local jammed = builder:arithmetic{L=EACH,NL=NGREEN,R=0,out=SIGC,green={chest},description="jammed"}
    local jam_scale = builder:constant_combi({{SIGC,-16*jam_scale}},"jammed scale")

    local power = power_consumption_combi(builder,size,prefix,"smart",builder.orientation,offset,quality)
    local power2 = builder:arithmetic{L=EACH,op="+",R=0,green={power},description="power buffer"} -- hopefully helps UPS?
    power2.get_wire_connector(OGREEN,true).connect_to(jammed.get_wire_connector(OGREEN,true))

    jam_scale.get_wire_connector(CGREEN,true).connect_to(jammed.get_wire_connector(OGREEN,true))
    for _,l in ipairs(input_loaders) do
        local control = l.get_or_create_control_behavior()
        control.circuit_enable_disable = true
        control.circuit_condition = {first_signal = SIGC, comparator="<", second_signal=POWER}
        l.get_wire_connector(CGREEN,true).connect_to(jammed.get_wire_connector(OGREEN,true))
    end

    ------------------------------------------------------------------------------
    -- Signal transmission
    ------------------------------------------------------------------------------
    local LARGE = 0x3fffffff

    -- == BIGMASK if in chest inventory, 0 if not
    local inventory_large = builder:arithmetic{blinken=true,NL=NGREEN,op="OR",R=LARGE,green={chest},description="inventory large mask"}

     -- negative: current and incoming inventory.  Will get extra green connected to it from the ports
    -- local demand_holdover_2 = builder:arithmetic{blinken=true,op="+",R=0,description="demand holdover 2"}
    local INV_SCALE=-4 -- TODO: -2 results in slight overdelivery, -4 probably underdelivery
    local scaled_inv = builder:arithmetic{blinken=true,op="*",R=INV_SCALE,red=input_belts,description="scaled inventory"}
    chest.get_wire_connector(CRED,true).connect_to(scaled_inv.get_wire_connector(IRED,true))
    local my_demand = builder:decider{
        blinken=true,
        decisions={{L=EACH, op=">", R=0}},
        red={scaled_inv},
        description="demand if positive"
    }
    local claimed = builder:decider{
        blinken=true,
        decisions={{L=EACH, op=">", R=0}},
        description="claimed",
        output={{set_one=true,signal=EACH}}
    }
    claimed.get_wire_connector(IGREEN,true).connect_to(my_demand.get_wire_connector(IGREEN,true))
    local nega_average_demand = builder:arithmetic{
        blinken=true,L=EACH,op="/",R=-4,
        description="nega average demand"
    }
    nega_average_demand.get_wire_connector(IGREEN,true).connect_to(my_demand.get_wire_connector(IGREEN,true))

    local nega_driver = nil
    for i,loader in ipairs(output_loaders) do
        local lamp = lamps[i]

        -- Lightly-documented feature: also connect red to see/set inventory
        lamp.get_wire_connector(CRED,true).connect_to(scaled_inv.get_wire_connector(IRED,true))
        
        -- Set the lamp to enable when link >= 2 (one from me, one from them))
        local control = lamp.get_or_create_control_behavior()
        control.use_colors = true
        control.color_mode = defines.control_behavior.lamp.color_mode.color_mapping
        control.circuit_enable_disable = true
        control.circuit_condition = {first_signal=LINK, comparator=">", constant=64}

        -- Drive my demand * 4 ==> lamp (connected via their_demand)
        local port_driver = builder:arithmetic{blinken=true,op="*",R=LEAK_FACTOR/4,red={my_demand},description="port driver"}
        if not nega_driver then
            nega_driver = builder:arithmetic{blinken=true,op="/",L=EACH,R=-LEAK_FACTOR,red={port_driver},description="nega-driver"}
            local nega_driver_2 = builder:arithmetic{blinken=true,op="/",L=EACH,R=-LEAK_FACTOR/4,red={port_driver},description="nega-driver-2"}
            nega_driver_2.get_wire_connector(ORED,true).connect_to(nega_average_demand.get_wire_connector(IRED,true))
        end
        
        -- Combinator to hold link = 1
        local constant_link = builder:constant_combi({{LINK,1}},  "constant link")

        -- each/link = each/(LEAK+1 if unconnected, 2*LEAK+1 if connected)
        local input_link = builder:arithmetic{blinken=true,L=EACH,op="/",R=LINK,red={constant_link},green={lamp,port_driver},description="port input"}
        input_link.get_wire_connector(OGREEN,true).connect_to(my_demand.get_wire_connector(IGREEN,true))
        local buffer_link = builder:arithmetic{blinken=true,L=EACH,op="+",R=0,red={input_link},green={nega_driver},description="buffer input"}
        
        ------------------------------------------------------------------------------
        -- Output belt control
        ------------------------------------------------------------------------------
        -- red: ~(me-them)/2
        -- green = same/4
        local output_controller = builder:decider{
            blinken=true,
            decisions = {
                {NL=NGREEN, op=">", R=1},                     -- in supply
                {and_=true,NL=NRED, op=">", R=0},             -- roughly their demand > 0
                {and_=true,NL=NBOTH, op=">", R=LARGE+1},      -- roughly their demand > mine
                -- OR --
                {NL=NGREEN, op="=",  R=LARGE},                -- inventory > 0 and no demand
                {and_=true,NL=NBOTH,L=DEFAULT,op=">",R=1}     -- roughly their default > mine (with +1 because of demand signal)
            },
            output = {{set_one=true,signal=EACH}},
            green = {nega_average_demand,inventory_large,claimed},
            red = {buffer_link},
            description="output_controller"
        }

        -- Set output loader filter behavior
        loader.loader_filter_mode = "whitelist"
        local control = loader.get_or_create_control_behavior()
        control.circuit_set_filters = true
        -- control.circuit_read_transfers = true
        loader.get_wire_connector(CGREEN,true).connect_to(output_controller.get_wire_connector(OGREEN,true))

        -- local demand_holdover = builder:arithmetic{blinken=true,op="*",R=INV_SCALE,red={loader},description="demand holdover 1"}
        -- demand_holdover.get_wire_connector(ORED,true).connect_to(scaled_inv.get_wire_connector(ORED,true))
        -- demand_holdover.get_wire_connector(OGREEN,true).connect_to(demand_holdover_2.get_wire_connector(IGREEN,true))
    end
end


local function create_smart_comms_io(
    builder,size,prefix,entity,
    input_belts,input_inserters,output_loaders,
    port,indicator,threshold_trim
)
    ------------------------------------------------------------------------------
    -- Create I/O system for a smart router.
    ------------------------------------------------------------------------------
    -- First, set links and leaf to 1, and set up the indicator lamp
    indicator.get_wire_connector(CGREEN,true).connect_to(port.get_wire_connector(CGREEN,true))
    local control = indicator.get_or_create_control_behavior()
    local leafplus = builder:constant_combi({{LEAF,1},{LINK,1}},"io leaf")
    local leafminus = builder:constant_combi({{LEAF,-1}},"io leaf negative")
    indicator.get_wire_connector(CGREEN,true).connect_to(leafplus.get_wire_connector(CGREEN,true))
    indicator.get_wire_connector(CRED,true).connect_to(leafminus.get_wire_connector(CRED,true))
    control.use_colors = true
    control.color_mode = defines.control_behavior.lamp.color_mode.color_mapping
    control.circuit_enable_disable = true
    control.circuit_condition = {first_signal=LINK, comparator=">", constant=1}

    -- Create the power controller
    local quality = entity.quality
    local power = power_consumption_combi(builder,size,prefix,"io",builder.orientation,offset,quality)
    local power2 = builder:arithmetic{L=EACH,op="+",R=0,green={power},description="power buffer"} -- hopefully helps UPS?
    for _,ins in ipairs(input_inserters) do
        control = ins.get_or_create_control_behavior()
        control.circuit_enable_disable = true
        control.circuit_condition = {first_signal = POWER, comparator=">", constant=0}
    end

    -- Set input belts to read contents
    for _,belt in ipairs(input_belts) do
        control = belt.get_or_create_control_behavior()
        control.read_contents = true
        control.read_contents_mode = READ_ALL
    end

    -- Send demand to the network
    local my_nega_supply = builder:arithmetic{L=EACH,op="*",R=-(LEAK_FACTOR*3/2),red={port},green=input_belts,
        description = "io negate supply"
    }
    local my_scaled_demand = builder:arithmetic{L=EACH,op="*",R=(LEAK_FACTOR*3/2),green={entity}, description = "io scaled demand"}

    local my_demand = builder:decider{
        decisions = {{L=EACH, NL=NBOTH, op=">", R=0}},
        output = {{signal=EACH,WO=NBOTH,}},
        green = {my_scaled_demand},
        red = {my_nega_supply},
        description="my demand if positive"
    }
    my_demand.get_wire_connector(OGREEN,true).connect_to(port.get_wire_connector(CGREEN,true))

    -- Implement the threshold.
    -- First pass on positive ones, and set negative ones with -1.
    -- When my demand is >0, set threshold to -huge
    local my_demand_very_negative = builder:decider{
        decisions = {{L=EACH, NL=NRED, op=">", R=0}},
        output = {{signal=EACH,WO=NBOTH,set_one=true,constant=-0x40000000}},
        red = {my_demand},
        description="my demand if positive"
    }
    local threshold_buffer_positive = builder:decider{
        decisions = {{L=EACH, NL=NBOTH, op=">", R=0}},
        output = {{signal=EACH,WO=NBOTH},{signal=EACH,WO=NBOTH}}, -- times two seems about right
        green = {threshold_trim},
        description="threshold if positive"
    }
    local threshold_buffer_negative = builder:decider{
        decisions = {{L=EACH, NL=NBOTH, op="<", R=0}},
        output = {{signal=EACH,WO=NBOTH,set_one=true,constant=-1}},
        green = {threshold_trim},
        description="threshold if negative"
    }
    local threshold_scaled = builder:arithmetic{L=EACH,op="*",R=LEAK_FACTOR/4,
        green={threshold_buffer_negative,threshold_buffer_positive},
        description="threshold multiplier"
    }

    -- Calculate net demand of the network
    local net_network_demand = builder:arithmetic{
        L=EACH,NL=NGREEN,op="-",R=EACH,NR=NRED,
        green = {my_demand}, -- and the network, since it is tied to green
        red = {my_demand},
        description="net demand"
    }

    -- It's worth sending if it's above the threshold, and the threshold is positive.
    local worth_sending = builder:decider{
        decisions = {
            {L=EACH, NL=NGREEN, op=">=", R=EACH, NR=NRED},
            {and_=true, L=EACH, NL=NRED, op=">", R=0},
            -- or no threshold is set
            {L=EACH, NL=NGREEN, op=">=", R=THRESHOLD, NR=NRED},
            {and_=true, L=THRESHOLD, NL=NRED, op=">", R=0},
            {and_=true, L=EACH, NL=NRED, op="=", R=0},
        },
        output = {{signal=EACH,set_one=true}},
        green = {net_network_demand},
        red = {threshold_scaled,my_demand_very_negative},
        description="worth sending"
    }

    -- For each good which is worth sending but not in stock, set output to -1
    local block_not_in_stock = builder:decider{
        decisions = {
            {L=EACH, NL=NGREEN, op=">", R=0},
            {and_=true, L=EACH, NL=NRED, op="=", R=0}
        },
        output = {{signal=EACH,set_one=true,constant=-1}},
        green = {worth_sending},
        red = {port},
        description="block not in stock"
    }
    for _,ldr in ipairs(output_loaders) do
        ldr.get_wire_connector(CGREEN,true).connect_to(worth_sending.get_wire_connector(OGREEN,true))
        ldr.get_wire_connector(CRED,true).connect_to(block_not_in_stock.get_wire_connector(ORED,true))
        ldr.loader_filter_mode = "whitelist"
        control = ldr.get_or_create_control_behavior()
        control.circuit_set_filters = true
    end
end

-- Construct module
M.create_smart_comms = create_smart_comms
M.set_jam_scale = set_jam_scale
M.create_smart_comms_io = create_smart_comms_io
M.power_consumption_combi = power_consumption_combi
M.fixup_power_consumption = fixup_power_consumption
M.RED = CRED
M.GREEN = CGREEN
M.DEFAULT = DEFAULT
M.INPUT = INPUT
M.OUTPUT = OUTPUT
M.POWER = POWER
M.EACH = EACH
M.ANYTHING = ANYTHING
M.EVERYTHING = EVERYTHING
M.Builder = Builder
M.LINK = LINK
M.LEAF = LEAF
M.ZERO = ZERO
M.DEMAND_FACTOR = DEMAND_FACTOR
M.THRESHOLD = THRESHOLD

return M
