local flib_gui = require "__flib__.gui"

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
        handler = handlers.close
      }
    }
  }

  local main_frame = {
    type="frame", style="inside_shallow_frame_with_padding", direction="vertical",
    children = {
      {
        type = "checkbox",
        style = "subheader_caption_checkbox",
        state = true,
        caption = { "recipe-combinator-gui.recipe-info-checkbox" }
      },
      { type = "line", style="inside_shallow_frame_with_padding_line" }, -- TODO: outset
      {
        type = "checkbox",
        style = "subheader_caption_checkbox",
        state = false,
        caption = { "recipe-combinator-gui.item-info-checkbox" }
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

return M
