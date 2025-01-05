local flib_gui = require "__flib__.gui"
local util = require "__core__.lualib.util"

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

local function checkbox_row(args)
  local boxes = {}
  local enabled = nil
  for _,box in ipairs(args) do
    if type(box) == string then
      table.insert(boxes,{type="label", caption=box,enabled=enabled})
    else
      box = util.merge{{
        type = "checkbox",
        style = "checkbox",
        state = false,
        enabled = enabled
      },box}
      table.insert(boxes,box)
      if enabled == nil then
        enabled = (box.enabled == nil or box.enabled) and box.state
      end
    end
  end
  return { type="flow", style="recipe-combinator_indented_checkbox_row", children=boxes }
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
    type="frame", style="inside_shallow_frame_with_padding", direction="vertical",
    children = {
      {
        type = "radiobutton",
        style = "recipe-combinator_subheader_caption_radio",
        state = true,
        caption = { "recipe-combinator-gui.recipe-info-mode" }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-recipe-ingredients-checkbox" }, state = true },
        stretch,
        { caption = { "recipe-combinator-gui.negate-checkbox" }, state = true },
        { caption = { "recipe-combinator-gui.times-input-checkbox" }, state = true }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-recipe-products-checkbox" }, state = true },
        stretch,
        { caption = { "recipe-combinator-gui.negate-checkbox" }, state = false },
        { caption = { "recipe-combinator-gui.times-input-checkbox" }, state = true }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-crafting-time-checkbox" }, state = false },
        { type = "choose-elem-button", style="recipe-combinator_signal_button", elem_type="signal" },
        stretch,
        { caption = { "recipe-combinator-gui.negate-checkbox" }, state = false },
        { caption = { "recipe-combinator-gui.times-input-checkbox" }, state = false }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-allowed-modules-checkbox" }, state = true },
        { type="radiobutton", style="radiobutton", caption = { "recipe-combinator-gui.one-module-per-category-radio" }, state = true },
        { type="radiobutton", style="radiobutton", caption = { "recipe-combinator-gui.all-modules-radio" }, state = false }
      },
      checkbox_row{
        -- TODO: options for only the first, etc?
        { caption = { "recipe-combinator-gui.show-machines" }, state = false }
      },


      { type = "line", style="recipe-combinator_section_divider_line" },
      {
        type = "radiobutton",
        style = "recipe-combinator_subheader_caption_radio",
        state = false,
        caption = { "recipe-combinator-gui.item-info-mode" }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-recipes-for-this-checkbox" }, state=true, enabled=false }
      },

      { type = "line", style="recipe-combinator_section_divider_line" },
      {
        type = "radiobutton",
        style = "recipe-combinator_subheader_caption_radio",
        state = false,
        caption = { "recipe-combinator-gui.spoilage-info-mode" }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-spoilage-time-checkbox" }, state=false, enabled=false },
        { type = "choose-elem-button", style="recipe-combinator_signal_button", elem_type="signal" },
        { type="radiobutton", style="radiobutton", caption = { "recipe-combinator-gui.show-spoilage-seconds-radio" }, state = true },
        { type="radiobutton", style="radiobutton", caption = { "recipe-combinator-gui.show-spoilage-ticks-radio" }, state = false }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-spoilage-products-checkbox" }, state=false, enabled=false },
        { caption = { "recipe-combinator-gui.times-input-checkbox" }, state = false }
      },

      { type = "line", style="recipe-combinator_section_divider_line" },
      {
        type = "radiobutton",
        style = "recipe-combinator_subheader_caption_radio",
        state = false,
        caption = { "recipe-combinator-gui.recycling-info-mode" }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-recycling-time-checkbox" }, state = false, enabled=false },
        { type = "choose-elem-button", style="recipe-combinator_signal_button", elem_type="signal" },
        stretch,
        { caption = { "recipe-combinator-gui.negate-checkbox" }, state = false },
        { caption = { "recipe-combinator-gui.times-input-checkbox" }, state = false }
      },
      checkbox_row{
        { caption = { "recipe-combinator-gui.show-recycling-products-checkbox" }, state = false, enabled=false },
        stretch,
        { caption = { "recipe-combinator-gui.negate-checkbox" }, state = false },
        { caption = { "recipe-combinator-gui.times-input-checkbox" }, state = false }
      }
    }
  }

  named, main_window = flib_gui.add(screen, {{
    type = "frame",
    direction = "vertical",
    name = WINDOW_ID,
    tags = { unit_number = entity.unit_number },
    children = { titlebar, main_frame }
  }})
  main_window.auto_center = true
  player.opened = main_window
end

M.open = open
M.close = close
M.WINDOW_ID = WINDOW_ID

flib_gui.handle_events()
flib_gui.add_handlers(handlers)

return M
