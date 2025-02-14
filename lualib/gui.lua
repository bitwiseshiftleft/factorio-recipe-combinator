local flib_gui = require "__flib__.gui"
local util = require "__core__.lualib.util"
local circuit = require "lualib.circuit"

local M = {}
local WINDOW_ID = "recipe-combinator-window"

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
  if rollup then
    -- save info in the entity description
    entity.combinator_description = serpent.line(rollup)
  end

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

local function checkbox_row(args)
  local boxes = {}
  local enabled = nil
  local load = args.load
  for _,box in ipairs(args.row or {}) do
    if type(box) == string then
      table.insert(boxes,{type="label", caption=box,enabled=enabled})
    else
      local box2 = util.merge{{
        type = "checkbox",
        style = "checkbox",
        state = false,
        enabled = enabled,
        handler = {
          [defines.events.on_gui_checked_state_changed] =
            (box.type and box.type == "radiobutton" and handlers.radio)
            or handlers.check,
            [defines.events.on_gui_elem_changed] =
              box.type and box.type == "choose-elem-button" and handlers.elem
        }
      },box}
      box2.name = box.name and (prefix .. box.name)
      if load and load[box.name] ~= nil then
        if box2.type == "checkbox" or box2.type == "radiobutton" then
          box2.state = load[box.name]
        -- elseif box2.type == "choose-elem-button" then
        --   box2.elem_value = load[box.name]
        end
      end
      table.insert(boxes,box2)
      if enabled == nil and not args.all_enabled then
        enabled = (box2.enabled == nil or box2.enabled) and box2.state
      end
    end
  end
  return { type="flow", style="recipe-combinator_checkbox_row", children=boxes,
    name=args.name and prefix..args.name }
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

  local ok,load = serpent.load(entity.combinator_description)
  load = ok and load or circuit.DEFAULT_ROLLUP

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

  local main_frame = {
    name=prefix.."combi_config", type="frame", style="inside_shallow_frame_with_padding", direction="vertical",
    children = {
      checkbox_row{row={
        { type = "label", caption={"recipe-combinator-gui.index-row-caption"}, style="label"},
        { name="input_recipe",      state=true,caption={"recipe-combinator-gui.index-recipe"}},
        { name="input_ingredients", state=false,caption={"recipe-combinator-gui.index-ingredient"}},
        { name="input_product",     state=false,caption={"recipe-combinator-gui.index-product"}}
      }, all_enabled=true, load=load},

      {type="line", style="recipe-combinator_section_divider_line"},
      {type="label", caption={"recipe-combinator-gui.label-one"}, style="bold_label"},
      checkbox_row{row={
        { name="show_recipe", style=checkbox_header, caption = { "recipe-combinator-gui.show-recipe-checkbox" }, state = true },
        stretch,
        { name="show_recipe_neg", caption = { "recipe-combinator-gui.negate-checkbox" }, state = true },
        { name="show_recipe_ti",  caption = { "recipe-combinator-gui.times-input-checkbox" }, state = true }
      }, load=load},
      checkbox_row{row={
        { name="show_ingredients", style=checkbox_header, caption = { "recipe-combinator-gui.show-recipe-ingredients-checkbox" }, state = false },
        stretch,
        { name="show_ingredients_neg", caption = { "recipe-combinator-gui.negate-checkbox" }, state = true },
        { name="show_ingredients_ti",  caption = { "recipe-combinator-gui.times-input-checkbox" }, state = true }
      }, load=load},
      checkbox_row{row={
        { name="show_products", style=checkbox_header, caption = { "recipe-combinator-gui.show-recipe-products-checkbox" }, state = true },
        stretch,
        { name="show_products_neg", caption = { "recipe-combinator-gui.negate-checkbox" }, state = false },
        { name="show_products_ti",  caption = { "recipe-combinator-gui.times-input-checkbox" }, state = true }
      }, load=load},
      checkbox_row{name="show_time_pane", row={
        { name="show_time", style=checkbox_header, caption = { "recipe-combinator-gui.show-crafting-time-checkbox" }, state = false },
        { name="show_time_signal", type = "choose-elem-button", style="recipe-combinator_signal_button", elem_type="signal" },
        stretch,
        { name="show_time_neg", caption = { "recipe-combinator-gui.negate-checkbox" }, state = false },
        { name="show_time_ti",  caption = { "recipe-combinator-gui.times-input-checkbox" }, state = false }
      }, load=load},
      checkbox_row{row={
        { name="show_modules", style=checkbox_header, caption = { "recipe-combinator-gui.show-allowed-modules-checkbox" }, state = true },
        { name="show_modules_opc", type="radiobutton", style="radiobutton", caption = { "recipe-combinator-gui.one-module-per-category-radio" }, state = true },
        { name="show_modules_all",type="radiobutton", style="radiobutton", caption = { "recipe-combinator-gui.all-modules-radio" }, state = false }
      }, load=load},
      checkbox_row{row={
        -- TODO: options for only the first, etc?
        { name="show_machines", style=checkbox_header, caption = { "recipe-combinator-gui.show-machines" }, state = false }
      }, load=load},

      {type="line", style="recipe-combinator_section_divider_line"},
      {type="label", caption={"recipe-combinator-gui.label-all"}, style="bold_label"},
      checkbox_row{row={
        { name="show_all_recipes", style=checkbox_header, caption = { "recipe-combinator-gui.show-all-recipes" }, state = false }
      }, load=load}
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
  local show_time_sig = main_window[prefix.."combi_config"][prefix.."show_time_pane"][prefix.."show_time_signal"]
  local sts_name = show_time_sig and string.gsub(show_time_sig.name,regex_prefix,"")
  if sts_name and load and load[sts_name] then
    show_time_sig.elem_value = load[sts_name]
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
