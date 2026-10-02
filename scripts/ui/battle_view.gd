extends HBoxContainer

const UI = preload("res://scripts/ui/ui.gd")
const Field = preload("res://scripts/ui/battlefield.gd")
signal command_requested(command: String)
signal return_requested

func setup(battle: RefCounted, territory: Dictionary) -> void:
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	left.add_child(UI.label_text("02 / BATTLE OF " + str(territory.name).to_upper(), 25, UI.GOLD))
	left.add_child(UI.label_text("%s terrain  /  Round %d  /  deterministic prototype combat" % [territory.terrain, mini(10, battle.round_number)], 15, UI.MUTED))
	var field: Control = Field.new()
	field.battle = battle
	field.custom_minimum_size = Vector2(500, 220)
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(field)
	left.add_child(UI.label_text("COUNCIL DIVISION                                           RIVAL GARRISON", 15, UI.MUTED))
	left.add_child(UI.label_text("Rival: %d troops / %d morale\n%s" % [battle.enemy, battle.enemy_morale, "Observe the announced enemy intent before choosing an order." if battle.outcome.is_empty() else "The battle has ended. Return to the campaign to apply its result."], 16))
	var recent: String = "\n".join(battle.records.slice(maxi(0, battle.records.size() - 3)))
	left.add_child(UI.label_text(recent if not recent.is_empty() else "The armies take position. Your orders determine the next exchange.", 14, UI.MUTED))
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size.x = 310
	add_child(right)
	var finished: bool = not battle.outcome.is_empty()
	right.add_child(UI.label_text(battle.outcome.to_upper() if finished else "ENEMY INTENT: " + battle.enemy_intent().to_upper(), 22, UI.RED if not finished else UI.GOLD))
	right.add_child(UI.meter("Division strength", battle.troops, UI.TEAL))
	right.add_child(UI.meter("Morale", battle.morale, UI.GOLD))
	right.add_child(UI.meter("Supply", battle.supply, Color("648fba")))
	right.add_child(UI.button("Attack  /  spend 8 supply", func() -> void: command_requested.emit("attack"), not finished))
	right.add_child(UI.button("Defend  /  spend 4 supply", func() -> void: command_requested.emit("defend"), not finished))
	right.add_child(UI.button("Regroup  /  recover morale", func() -> void: command_requested.emit("regroup"), not finished))
	right.add_child(UI.button("Retreat  /  preserve the division", func() -> void: command_requested.emit("retreat"), not finished))
	right.add_child(UI.label_text("Defend: reduce losses, counter attacks.\nRegroup: +16 morale, exposed troops.\nSupply <12: attack strength halved.\nRound 10: nightfall forces withdrawal.", 13, UI.MUTED))
	if finished:
		right.add_child(UI.button("Return to council  /  apply result", func() -> void: return_requested.emit()))
