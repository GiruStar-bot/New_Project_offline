extends Control
## Scene coordinator. Rules live in game_state/battle_model; views emit intent.

const State = preload("res://scripts/game_state.gd")
const UI = preload("res://scripts/ui/ui.gd")
const StrategyView = preload("res://scripts/ui/strategy_view.gd")
const BattleView = preload("res://scripts/ui/battle_view.gd")

var campaign: RefCounted = State.new()
var content: VBoxContainer
var notice: String = "Select Crossroads, then lead an attack or delegate occupation to Mira."

func _ready() -> void:
	theme = UI.theme()
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 24)
	add_child(margins)
	content = VBoxContainer.new()
	margins.add_child(content)
	refresh()

func refresh() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var banner: HBoxContainer = HBoxContainer.new()
	content.add_child(banner)
	var title: Label = UI.label_text("FRONTIER COUNCIL", 30, UI.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.add_child(title)
	var subtitle: Label = UI.label_text("NATION & COMMAND  /  v0.1", 14, UI.MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	banner.add_child(subtitle)
	banner.add_child(UI.button("New campaign", _reset))
	var totals: Vector2i = campaign.income()
	content.add_child(UI.label_text("TURN %02d     TREASURY %d  (%+d/turn)     GRAIN %d  (%+d/turn)     TERRITORY %d/13     DIVISION %d / MORALE %d / SUPPLY %d" % [campaign.turn, campaign.treasury, totals.x - 6, campaign.grain, totals.y - 12, campaign.owned_count(), campaign.division.troops, campaign.division.morale, campaign.division.supply], 15, UI.TEAL))
	content.add_child(HSeparator.new())
	var view: Control
	if campaign.active_battle == null:
		view = StrategyView.new()
		view.territory_selected.connect(_select)
		view.action_requested.connect(_action)
		view.setup(campaign)
	else:
		view = BattleView.new()
		view.command_requested.connect(_battle_command)
		view.return_requested.connect(_return_to_map)
		view.setup(campaign.active_battle, campaign.territories[campaign.active_battle.target_id])
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(view)
	content.add_child(HSeparator.new())
	content.add_child(UI.label_text(notice, 15, UI.GOLD))
	var log_label: RichTextLabel = RichTextLabel.new()
	log_label.custom_minimum_size.y = 60
	log_label.add_theme_font_size_override("normal_font_size", 14)
	log_label.add_theme_color_override("default_color", UI.MUTED)
	log_label.text = "COUNCIL RECORD\n" + "\n".join(campaign.journal.slice(maxi(0, campaign.journal.size() - 8)))
	log_label.scroll_following = true
	content.add_child(log_label)

func _select(id: int) -> void:
	campaign.selected = id
	var reason: String = campaign.attack_error(id)
	notice = reason if not reason.is_empty() else "Ready to attack %s. Lead the battle or delegate to Mira." % campaign.territories[id].name
	refresh()

func _action(action: String) -> void:
	match action:
		"attack":
			var battle: RefCounted = campaign.start_battle(campaign.selected)
			notice = "Operation launched. Read enemy intent; issue one command per round." if battle != null else campaign.attack_error(campaign.selected)
		"occupy", "defend": notice = campaign.delegate(action, campaign.selected)
		"move": notice = campaign.move_division(campaign.selected)
		"reinforce": notice = campaign.reinforce()
		"end_turn": notice = campaign.end_turn()
	refresh()

func _battle_command(command: String) -> void:
	notice = campaign.active_battle.step(command)
	refresh()

func _return_to_map() -> void:
	notice = campaign.finish_battle()
	refresh()

func _reset() -> void:
	campaign.reset()
	notice = "New campaign. Capture Crossroads to open the eastern land route."
	refresh()
