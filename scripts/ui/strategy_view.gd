extends HBoxContainer

const UI = preload("res://scripts/ui/ui.gd")
signal territory_selected(id: int)
signal action_requested(action: String)
var state: RefCounted

func setup(campaign: RefCounted) -> void:
	state = campaign
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	left.add_child(UI.label_text("01 / THE FRONTIER", 20, UI.GOLD))
	left.add_child(UI.label_text("TEAL  Council     RED  Rival     SLATE  Neutral     ~  Sea     ^  Mountain", 14, UI.MUTED))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(grid)
	for territory in state.territories:
		var tile: Button = Button.new()
		tile.custom_minimum_size = Vector2(158, 107)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var color: Color = Color("1d303d")
		match str(territory.owner):
			"player": color = Color("174e4b")
			"enemy": color = Color("542f3c")
			"none": color = Color("102f46")
		var border: Color = UI.GOLD if int(territory.id) == state.selected else color.lightened(0.15)
		tile.add_theme_stylebox_override("normal", UI.box_style(color, border))
		tile.add_theme_stylebox_override("hover", UI.box_style(color.lightened(0.14), UI.GOLD))
		tile.add_theme_stylebox_override("focus", UI.box_style(color, UI.GOLD))
		var marker: String = "  [ DIVISION ]" if int(territory.id) == int(state.division.location) else ""
		var symbol: String = "^ " if territory.terrain == "Mountain" else ""
		if territory.terrain == "Sea":
			tile.text = "~  OPEN WATER  ~\n\nNo land route"
		else:
			tile.text = "%s%s\n%s%s\n%s" % [symbol, territory.name, territory.terrain, marker, "COUNCIL" if territory.owner == "player" else "Garrison %d" % int(territory.garrison)]
		tile.add_theme_font_size_override("font_size", 14)
		tile.pressed.connect(func() -> void: territory_selected.emit(int(territory.id)))
		grid.add_child(tile)
	left.add_child(UI.label_text("Land adjacency is orthogonal. Capturing the Citadel completes this prototype.\nMountain defenders absorb 7 attack damage. Coasts yield more tax; plains yield more grain.", 14, UI.MUTED))
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size.x = 310
	add_child(right)
	var target: Dictionary = state.territories[state.selected]
	right.add_child(UI.label_text(str(target.name).to_upper(), 25, UI.GOLD))
	right.add_child(UI.label_text("%s / %s\nTax +%d   Grain +%d each turn" % [target.terrain, target.owner, target.income, target.grain], 15, UI.MUTED))
	var error: String = state.attack_error(state.selected)
	if state.won:
		right.add_child(UI.label_text("CITADEL SECURED\nYour council controls the eastern route.", 18, UI.TEAL))
	else:
		right.add_child(UI.button("Lead attack  /  8 treasury", func() -> void: action_requested.emit("attack"), error.is_empty()))
		right.add_child(UI.button("Delegate occupation to Mira", func() -> void: action_requested.emit("occupy"), error.is_empty()))
		right.add_child(UI.button("Move division  /  2 supply", func() -> void: action_requested.emit("move"), target.owner == "player" and state.adjacent(int(state.division.location), state.selected) and int(state.division.supply) >= 2))
	right.add_child(HSeparator.new())
	right.add_child(UI.label_text("MIRA / CAUTIOUS COMMANDER", 15, UI.TEAL))
	right.add_child(UI.label_text("Order: %s" % ("awaiting orders" if state.assignment.is_empty() else "%s %s" % [state.assignment, state.territories[state.assignment_target].name]), 14, UI.MUTED))
	right.add_child(UI.button("Delegate defense here", func() -> void: action_requested.emit("defend"), not state.won and state.selected == int(state.division.location)))
	right.add_child(UI.button("Reinforce  /  12 tax + 15 grain", func() -> void: action_requested.emit("reinforce"), not state.won and state.treasury >= 12 and state.grain >= 15))
	right.add_child(UI.button("End turn  /  execute orders", func() -> void: action_requested.emit("end_turn"), not state.won))
