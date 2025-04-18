local styles = data.raw["gui-style"].default

styles["recipe-combinator_section_divider_line"] = {
    type = "line_style",
    parent = "inside_shallow_frame_with_padding_line",
    top_margin=11,
    bottom_margin=11
}

styles["recipe-combinator_indented_checkbox_row"] = {
    type = "horizontal_flow_style",
    left_padding = 24,
    right_padding = 8,
    vertical_align = "center"
}
  
styles["recipe-combinator_checkbox_row"] = {
    type = "horizontal_flow_style",
    left_padding = 12,
    right_padding = 12,
    vertical_align = "center"
}

styles["recipe-combinator_label_toolip"] = {
    type = "horizontal_flow_style",
    parent = "recipe-combinator_checkbox_row",
    left_padding = 0,
    right_padding = 0
}

  
styles["recipe-combinator_unpadded_horizontal_flow"] = {
    type = "horizontal_flow_style",
    top_margin = -12,
    bottom_margin = 8
}
styles["recipe-combinator_unpadded_horizontal_flow_first"] = {
    type = "horizontal_flow_style",
    bottom_margin = 8,
    top_margin = 4
}
  
styles["recipe-combinator_tooltip_sprite"] = {
    type = "image_style",
    size = 8,
    stretch_image_to_widget_size = true,
    left_margin = 2
}
  
styles["recipe-combinator_machine_picker"] = {
    type = "button_style",
    parent = "slot_button",
    right_margin = -4
}

styles["recipe-combinator_checkbox_header"] = {
    type = "checkbox_style",
    parent = "checkbox"
}

styles["recipe-combinator_mini_checkbox"] = {
    type = "checkbox_style",
    parent = "checkbox",
    margin_left = 16,
    text_padding = 0
}

styles["recipe-combinator_stretch"] = {
    type = "empty_widget_style",
    horizontally_stretchable = "on"
}
  
styles["recipe-combinator_signal_button"] = {
    type = "button_style",
    parent = "flib_slot_button_default",
    width=32,
    height=32
}

styles["recipe-combinator_subheader_caption_radio"] = {
  type = "radiobutton_style",
  parent = "caption_radiobutton",
  left_margin = 8,
  bottom_margin = 4
}

styles["recipe-combinator_header_radio"] = {
  type = "radiobutton_style",
  parent = "caption_radiobutton",
  font = "default-bold",
  left_margin = 4
}