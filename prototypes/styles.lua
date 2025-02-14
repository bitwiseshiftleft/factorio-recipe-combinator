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
    left_padding = 8,
    right_padding = 8,
    vertical_align = "center"
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