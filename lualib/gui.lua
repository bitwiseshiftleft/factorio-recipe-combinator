local flib_gui = require "__flib__.gui"
local util = require "__core__.lualib.util"
local circuit = require "lualib.circuit"
local tagged_entity = require "lualib.tagged_entity"

local M = {}
local WINDOW_ID = "recipe-combinator-window"
local HAVE_QUALITY = script.feature_flags.quality and script.feature_flags.space_travel

handlers = {}

-- Significant fractions cribbed from Cybersyn Combinator
local function close(player_index, silent)
  if not player_index then return end
  local player = game.get_player(player_index)
  if not player then return end
  local screen = player.gui.screen
  if not screen or not screen[WINDOW_ID] then return end
  screen[WINDOW_ID].destroy()

  -- Play closing sound
  if not silent then
    player.play_sound { path = "entity-close/recipe-combinator-main" }
  end
end

handlers.close = function (ev)
  if ev.player_index then close(ev.player_index) end
end

local prefix = "recipe-combinator_"
local regex_prefix = "^recipe%-combinator_"
local function rollup_gui_state(window)
  -- Roll up the state of the active GUI into a table.  Don't simplify it yet
  local stack = {window}
  local ret = {}
  while #stack > 0 do
    local top = stack[#stack]
    table.remove(stack)
    for _,child in ipairs(top.children) do
      if child then table.insert(stack,child) end
    end
    if top.type == "radiobutton" or top.type == "checkbox" then
      ret[string.gsub(top.name,regex_prefix,"")] = top.state
    elseif top.type == "choose-elem-button" and top.elem_value then
      ret[string.gsub(top.name,regex_prefix,"")] = top.elem_value
    end
  end

  local machines,machines2 = {},{}
  for name,val in pairs(ret) do
    if string.match(name,"^machine%d+$") then
      local idx = tonumber(string.gsub(name,"^machine",""),10)
      if machines[val] == nil or machines[val] > idx then machines[val] = idx end
      ret[name] = nil
    end
  end
  for machine,prio in pairs(machines) do
    table.insert(machines2,{machine,prio})
  end
  table.sort(machines2,function(a,b) return a[2]<b[2] end)
  machines = {}
  for _,machine in ipairs(machines2) do
    table.insert(machines,machine[1])
  end
  ret.machines = machines

  return ret
end

local function rebuild_active_combinator(player_index)
  -- is everything still valid?
  if not player_index then return end
  local player = game.get_player(player_index)
  if not player then return end
  local screen = player.gui.screen
  if not screen or not screen[WINDOW_ID] then return end
  local window = screen[WINDOW_ID]
  if not window.tags or not window.tags.unit_number then return end
  local entity = game.get_entity_by_unit_number(window.tags.unit_number)
  if not entity then return end

  local rollup = rollup_gui_state(window)
  tagged_entity.set_tags(entity, rollup)
  circuit.rebuild_combinator(entity)
end

handlers.radio = function(ev)
  local elt = ev.element
  if not elt.state then return end -- how are we getting its state change if it's not true?
  for _,child in ipairs(elt.parent.children) do
    if child ~= elt and child.type == "radiobutton" then
      child.state = false
    end
  end
  rebuild_active_combinator(ev.player_index)
end

handlers.elem = function(ev)
  rebuild_active_combinator(ev.player_index)
end

handlers.machine_prio = function(ev)
  local elt = ev.element
  local row = elt.parent
  local rows = row.parent
  local lastrow = rows.children[#rows.children]
  local lastcol = lastrow.children[#lastrow.children]
  if lastcol.elem_value then
    -- add a new element
    if #lastrow.children == 10 then
      _,lastrow = flib_gui.add(rows,{type="flow",style="recipe-combinator_unpadded_horizontal_flow"})
    end
    flib_gui.add(lastrow,{
        type="choose-elem-button",elem_type="entity",style="recipe-combinator_machine_picker",
        elem_filters={{filter="crafting-machine"}}, entity=nil,
        name=prefix.."machine"..tostring(#rows.children*10 + #lastrow.children - 9),
        handler = { [defines.events.on_gui_elem_changed] = handlers.machine_prio }
    })
  else
    -- remove empty elements
    while true do
      local arow,prev
      if #lastrow.children <= 1 and #rows.children <= 1 then break end
      if #lastrow.children <= 1 then
        arow = rows.children[#rows.children-1]
        prev = arow.children[#arow.children]
      else
        prev = lastrow.children[#lastrow.children-1]
      end
      if prev.elem_value == nil then
        lastrow.children[#lastrow.children].destroy()
        if #lastrow.children == 0 then
          lastrow.destroy()
          lastrow = arow
        end
      else
        break
      end
    end
  end
  rebuild_active_combinator(ev.player_index)
end

local checkbox_header = "recipe-combinator_checkbox_header"
handlers.check = function(ev)
  local elt = ev.element
  local state = elt.state
  if elt.style.name == checkbox_header then
    for _,child in ipairs(elt.parent.children) do
      if child ~= elt then
        child.enabled = state
      end
    end
  end
  rebuild_active_combinator(ev.player_index)
end

local function checkbox(box, load, enabled)
  local box2 = util.merge{{
    type = "checkbox",
    style = (box.type == "checkbox") and "checkbox" or nil,
    state = false,
    enabled = enabled,
    handler = {
      [defines.events.on_gui_checked_state_changed] =
        (box.type and box.type == "radiobutton" and handlers.radio)
        or handlers.check,
        [defines.events.on_gui_elem_changed] =
          box.type and box.type == "choose-elem-button" and handlers.elem
    },
    caption = box.caption or (box.name and {"recipe-combinator-gui." .. box.name})
  },box}
  box2.name = box.name and (prefix .. box.name)
  if load and load[box.name] ~= nil then
    if box2.type == "checkbox" or box2.type == "radiobutton" then
      box2.state = load[box.name]
    -- elseif box2.type == "choose-elem-button" then
    --   box2.elem_value = load[box.name]
    end
  end
  return box2
end

local function checkbox_row(args)
  local boxes = {}
  local enabled = args.zone_enabled
  local load = args.load
  for _,box in ipairs(args.row or {}) do
    if type(box) == string then
      table.insert(boxes,{type="label", caption=box,enabled=enabled})
    elseif next(box) ~= nil then
      box2 = checkbox(box,load,enabled)
      table.insert(boxes,box2)
      if enabled == nil and not args.all_enabled then
        enabled = (box2.enabled == nil or box2.enabled) and box2.state
      end
    end
  end
  return { type="flow", style="recipe-combinator_checkbox_row", children=boxes,
    name=args.name and prefix..args.name }
end

local function tooltip(name)
  return {type="sprite", sprite="info_no_border", style="recipe-combinator_tooltip_sprite",
    tooltip={"recipe-combinator-gui.tooltip_"..name}}
end

local function open(player_index, entity)
  if not player_index then return end
  local player = game.get_player(player_index)
  if not player then return end

  local screen = player.gui.screen
  if not screen then return end

  -- Open/close any existing gui
  if screen[WINDOW_ID] then
    if screen[WINDOW_ID].tags.unit_number == entity.unit_number then
      player.opened = screen[WINDOW_ID]
      return
    else
      close(player_index)
    end
  end

  local load = tagged_entity.get_tags(entity) or circuit.DEFAULT_ROLLUP

  local stretch = {type="empty-widget",style="recipe-combinator_stretch"}
  local named, main_window
  local titlebar = {
    type = "flow",
    drag_target = WINDOW_ID,
    children = {
      {
        type = "label",
        style = "frame_title",
        caption = { "entity-name.recipe-combinator-main" },
        elem_mods = { ignored_by_interaction = true },
      },
      {
        type = "empty-widget",
        style = "flib_titlebar_drag_handle",
        elem_mods = { ignored_by_interaction = true }
      },
      {
        type = "sprite-button",
        style = "close_button",
        mouse_button_filter = { "left" },
        sprite = "utility/close",
        name = WINDOW_ID .. "_close",
        handler = {
          [defines.events.on_gui_click] = handlers.close
        }
      }
    }
  }

  local machines_inner = {type="flow",direction="horizontal",children={},
    style="recipe-combinator_unpadded_horizontal_flow_first"}
  local machines_outer = {type="flow",direction="vertical",children={machines_inner}}
  local rowidx,totalidx=0,0
  local function append_machine(machine)
    rowidx = rowidx+1
    totalidx = totalidx+1
    if rowidx == 11 then
      rowidx=1
      machines_inner = {type="flow",direction="horizontal",children={},
        style="recipe-combinator_unpadded_horizontal_flow"}
      table.insert(machines_outer.children,machines_inner)
    end
    local button = {
        type="choose-elem-button",elem_type="entity",style="recipe-combinator_machine_picker",
        elem_filters={{filter="crafting-machine"}},entity=machine,
        name=prefix.."machine"..tostring(totalidx),
        handler = { [defines.events.on_gui_elem_changed] = handlers.machine_prio }}
    table.insert(machines_inner.children,button)
  end
  for _,machine in ipairs(load.machines or {}) do append_machine(machine) end
  append_machine(nil)

  local function chk(group, ty)
    -- miniature checkbox builder
    return { name=group .. "_" .. ty, 
      caption = { "recipe-combinator-gui." .. ty .. "_checkbox" },
      tooltip = { "recipe-combinator-gui." .. ty .. "_tooltip" },
      style = "recipe-combinator_mini_checkbox"
    }
  end

  local en_one,en_all = load.enable_one or false, load.enable_all or false
  if not en_one and not en_all then en_one = true end

  local main_frame = {
    name=prefix.."combi_config", type="frame", style="inside_shallow_frame_with_padding", direction="vertical",
    children = {
      {type="flow", style="recipe-combinator_label_toolip", children={
        {type="label", caption={"recipe-combinator-gui.label_which_machines"}, style="bold_label"},
        tooltip("which_machines")
      }},
      machines_outer,
      {type="flow", style="recipe-combinator_checkbox_row", children={
        checkbox({name="include_disabled"},load),
        checkbox({name="include_hidden"},load)
      }},
      
      {type="line", style="recipe-combinator_section_divider_line"},
      {type="label", caption={"recipe-combinator-gui.label_input"}, style="bold_label"},
      checkbox_row{row={
        --{ type = "label", caption={"recipe-combinator-gui.index-row-caption"}, style="label"},
        { name="input_recipe",      state=true,caption={"recipe-combinator-gui.index_recipe"}},
        { name="input_ingredients", state=false,caption={"recipe-combinator-gui.index_ingredient"}},
        { name="input_product",     state=false,caption={"recipe-combinator-gui.index_product"}}
      }, all_enabled=true, load=load},

      {type="line", style="recipe-combinator_section_divider_line"},
      {type="label", caption={"recipe-combinator-gui.label_recap"}, style="bold_label"},

      checkbox_row{row={
        { name="show_selected", style=checkbox_header },
        tooltip("show_selected"),
        stretch,
        chk("show_selected","red"),
        chk("show_selected","green")
      }, load=load},
      (HAVE_QUALITY and checkbox_row{name="show_quality_pane", row={
        { name="show_quality", style=checkbox_header },
        tooltip("show_quality"),
        { name="show_quality_signal", type = "choose-elem-button", style="recipe-combinator_signal_button", elem_type="signal" },
        stretch,
        chk("show_quality","red"),
        chk("show_quality","green")
      }, load=load} or {}),

      {type="line", style="recipe-combinator_section_divider_line"},
      {type="flow", style="recipe-combinator_label_toolip", children={
        {type="label",
          caption={"recipe-combinator-gui.label_one"},
          -- style="recipe-combinator_header_radio",
          style="bold_label",
          state=en_one},
        tooltip("section_one")
      }},
      {type="flow",direction="vertical",name=prefix.."subpane_one",
        enabled=en_one, children={
        checkbox_row{row={
          { name="show_recipe", style=checkbox_header },
          stretch,
          chk("show_recipe","neg"),
          chk("show_recipe","ti"),
          chk("show_recipe","red"),
          chk("show_recipe","green")
        }, load=load},
        checkbox_row{row={
          { name="show_ingredients", style=checkbox_header },
          stretch,
          chk("show_ingredients","neg"),
          chk("show_ingredients","ti"),
          chk("show_ingredients","red"),
          chk("show_ingredients","green")
        }, load=load},
        checkbox_row{row={
          { name="show_products", style=checkbox_header },
          stretch,
          chk("show_products","neg"),
          chk("show_products","ti"),
          chk("show_products","red"),
          chk("show_products","green")
        }, load=load},
        checkbox_row{name="show_time_pane", row={
          { name="show_time", style=checkbox_header },
          { name="show_time_signal", type = "choose-elem-button", style="recipe-combinator_signal_button", elem_type="signal" },
          stretch,
          chk("show_time","neg"),
          chk("show_time","ti"),
          chk("show_time","red"),
          chk("show_time","green")
        }, load=load},
        checkbox_row{row={
          { name="show_modules", style=checkbox_header },
          stretch,
          { name="show_modules_opc", type="radiobutton", style="radiobutton" },
          { name="show_modules_all",type="radiobutton", style="radiobutton" },
          chk("show_modules","red"),
          chk("show_modules","green")
        }, load=load},
        checkbox_row{row={
          -- TODO: options for only the first, etc?
          { name="show_machines", style=checkbox_header },
          stretch,
          chk("show_machines","red"),
          chk("show_machines","green")
        }, load=load}
      }},

      {type="line", style="recipe-combinator_section_divider_line"},
      {type="flow", style="recipe-combinator_label_toolip", children={
        {type="label",
          caption={"recipe-combinator-gui.label_all"},
          -- style="recipe-combinator_header_radio"
          style="bold_label"
        },
        tooltip("section_all")
      }},
      {type="flow",direction="vertical",name=prefix.."subpane_all",
        enabled=en_all, children={
        checkbox_row{row={
          { name="show_all_recipes", style=checkbox_header },
          -- tooltip("show_all_recipes"),
          stretch,
          chk("show_all_recipes","red"),
          chk("show_all_recipes","green")
        }, load=load}
      }},

      {type="line", style="recipe-combinator_section_divider_line"},
      {type="flow", style="recipe-combinator_label_toolip", children={
        {type="label",
          caption={"recipe-combinator-gui.label_allvalid"},
          -- style="recipe-combinator_header_radio"
          style="bold_label"
        }
      }},
      {type="flow",direction="vertical",name=prefix.."subpane_allvalid",
        enabled=en_allvalid, children={
        checkbox_row{row={
          { name="show_all_valid_inputs", style=checkbox_header },
          tooltip("show_all_valid_inputs"),
          stretch,
          (HAVE_QUALITY and {name = "show_all_valid_inputs_quality" } or {}),
          chk("show_all_valid_inputs","red"),
          chk("show_all_valid_inputs","green")
        }, load=load}
      }}
    }
  }

  named, main_window = flib_gui.add(screen, {{
    type = "frame",
    direction = "vertical",
    name = WINDOW_ID,
    tags = { unit_number = entity.unit_number },
    children = { titlebar, main_frame }
  }})

  -- the signal states can't be restored by the script
  local show_time_sig = main_window
    [prefix.."combi_config"][prefix.."subpane_one"]
    [prefix.."show_time_pane"][prefix.."show_time_signal"]
  local sts_name = "show_time_signal"
  if show_time_sig and sts_name and load and load[sts_name] then
    show_time_sig.elem_value = load[sts_name]
  end
  if HAVE_QUALITY then
    local show_quality_sig = main_window
      [prefix.."combi_config"]
      [prefix.."show_quality_pane"][prefix.."show_quality_signal"]
    local sqs_name = "show_quality_signal"
    if show_quality_sig and sqs_name and load and load[sqs_name] then
      show_quality_sig.elem_value = load[sqs_name]
    end
  end

  main_window.auto_center = true
  player.opened = main_window
end

M.open = open
M.close = close
M.WINDOW_ID = WINDOW_ID

flib_gui.handle_events()
flib_gui.add_handlers(handlers)

return M
