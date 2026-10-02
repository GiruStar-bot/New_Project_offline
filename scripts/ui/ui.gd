extends RefCounted
## Shared presentation helpers. No campaign rules belong here.

const INK = Color("dce6ee")
const MUTED = Color("8fa7b7")
const GOLD = Color("e9c27a")
const TEAL = Color("4bbaa7")
const RED = Color("d57671")

static func label_text(value: String, font_size: int = 16, color: Color = INK) -> Label:
	var item: Label = Label.new()
	item.text = value
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item

static func button(value: String, action: Callable, enabled: bool = true) -> Button:
	var item: Button = Button.new()
	item.text = value
	item.custom_minimum_size.y = 32
	item.add_theme_font_size_override("font_size", 15)
	item.disabled = not enabled
	item.pressed.connect(action)
	return item

static func box_style(background: Color, border: Color = Color("304657")) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func theme() -> Theme:
	var result: Theme = Theme.new()
	result.default_font_size = 16
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var background: Color = Color("172b38")
		if state == "hover" or state == "focus":
			background = Color("294658")
		elif state == "pressed":
			background = Color("355b68")
		elif state == "disabled":
			background = Color("101e28")
		result.set_stylebox(state, "Button", box_style(background))
	result.set_color("font_color", "Button", INK)
	result.set_color("font_disabled_color", "Button", Color("667886"))
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 16)
	return result

static func meter(title: String, value: int, color: Color) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_child(label_text("%s   %d / 100" % [title, value], 15))
	var bar: ProgressBar = ProgressBar.new()
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size.y = 9
	bar.add_theme_stylebox_override("background", box_style(Color("101e28")))
	bar.add_theme_stylebox_override("fill", box_style(color, color))
	column.add_child(bar)
	return column
