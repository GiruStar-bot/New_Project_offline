extends SceneTree
## Run: godot --headless --path . --script tests/smoke.gd

const State = preload("res://scripts/game_state.gd")
const Battle = preload("res://scripts/battle_model.gd")
const Commander = preload("res://scripts/npc_commander.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + title)

func press_button(scene: Node, prefix: String) -> bool:
	for node in scene.find_children("*", "Button", true, false):
		if str(node.text).begins_with(prefix) and not node.disabled:
			node.pressed.emit()
			return true
	return false

func _run() -> void:
	var state: RefCounted = State.new()
	check(state.owned_count() == 4 and state.territories.size() == 15, "Initial territories")
	check(not state.adjacent(4, 5), "Adjacency does not wrap rows")
	check(state.adjacent(6, 7) and state.adjacent(6, 1), "Orthogonal adjacency")
	check(state.start_battle(3) == null, "Sea cannot be attacked")
	check(state.start_battle(9) == null, "Nonadjacent attack rejected")
	check(state.start_battle(6) == null, "Friendly attack rejected")
	check(state.start_battle(-1) == null, "Invalid target rejected")
	check(state.treasury == 60, "Rejected actions charge nothing")
	var battle: RefCounted = state.start_battle(7)
	check(battle != null and state.treasury == 52, "Operation cost once")
	check(state.start_battle(7) == null, "No overlapping battles")
	var prior: int = battle.round_number
	battle.step("invalid")
	check(battle.round_number == prior, "Invalid combat command consumes no round")
	check(state.finish_battle() == "No concluded battle.", "No premature settlement")
	while battle.outcome.is_empty():
		battle.step("attack")
	check(battle.outcome == "victory", "Opening battle can be won")
	var survivors: int = battle.troops
	state.finish_battle()
	check(state.territories[7].owner == "player" and state.division.location == 7, "Victory transfers territory and moves division")
	check(state.division.troops == survivors and survivors < 100, "Casualties persist")
	check(state.turn == 2 and state.active_battle == null, "Settlement advances exactly one turn")
	var funds: int = state.treasury
	state.finish_battle()
	check(state.treasury == funds and state.turn == 2, "Repeated settlement does nothing")
	state.reinforce()
	check(state.division.troops <= 100 and state.division.supply <= 100, "Reinforcement caps")
	state.reset()
	battle = state.start_battle(7)
	battle.step("retreat")
	state.finish_battle()
	check(state.territories[7].owner == "neutral" and state.division.location == 6, "Retreat preserves territory ownership and origin")
	check(state.division.troops == 96 and state.turn == 2, "Retreat applies casualties and campaign time")
	state.reset()
	state.division.troops = 20
	state.division.morale = 15
	battle = state.start_battle(1)
	while battle.outcome.is_empty():
		battle.step("attack")
	check(battle.outcome == "defeat", "Weak division defeated")
	state.finish_battle()
	check(state.territories[1].owner == "neutral", "Defeat does not capture land")
	state.reinforce()
	check(state.division.troops >= 30, "Defeated division can recover")
	var troops: Dictionary = {"troops": 100, "morale": 85, "supply": 65}
	var plain: RefCounted = Battle.new({"id": 7, "terrain": "Plain", "garrison": 65}, troops)
	var mountain: RefCounted = Battle.new({"id": 9, "terrain": "Mountain", "garrison": 65}, troops)
	plain.step("attack")
	mountain.step("attack")
	check(mountain.enemy > plain.enemy, "Mountain cover reduces attack damage")
	var defended: RefCounted = Battle.new({"id": 7, "terrain": "Plain", "garrison": 65}, troops)
	defended.step("defend")
	check(defended.troops > plain.troops, "Defense reduces casualties")
	var regrouped: RefCounted = Battle.new({"id": 7, "terrain": "Plain", "garrison": 65}, {"troops": 100, "morale": 30, "supply": 65})
	regrouped.step("regroup")
	check(regrouped.morale > 30 and regrouped.enemy == 65, "Regroup restores morale without damage")
	var dry: RefCounted = Battle.new({"id": 7, "terrain": "Plain", "garrison": 65}, {"troops": 100, "morale": 85, "supply": 0})
	dry.step("attack")
	check(dry.enemy > plain.enemy, "Low supply weakens attack")
	var night: RefCounted = Battle.new({"id": 7, "terrain": "Plain", "garrison": 65}, troops)
	while night.outcome.is_empty():
		night.step("regroup")
	check(night.round_number <= 11, "Every automated battle terminates")
	state.reset()
	state.end_turn()
	check(state.treasury == 73 and state.grain == 74, "Territory revenue and upkeep")
	state.reset()
	state.delegate("occupy", 7)
	state.end_turn()
	check(state.territories[7].owner == "player" and state.turn == 2, "NPC executes occupation and advances once")
	check(state.assignment.is_empty() and state.active_battle == null, "NPC order clears after execution")
	check("Mira:" in "\n".join(state.journal), "NPC decisions recorded")
	var npc: RefCounted = Commander.new()
	dry.troops = 25
	check(npc.choose_command(dry) == "retreat", "Cautious NPC preserves weak division")
	state.reset()
	state.move_division(5)
	check(state.division.location == 5 and state.division.supply == 63, "Friendly relocation costs supply")
	state.move_division(9)
	check(state.division.location == 5, "Nonadjacent move rejected")
	# Compare identical frontier raids with / without a defense assignment.
	state.reset()
	state.territories[7].owner = "player"
	state.division.location = 7
	state.turn = 2
	state.delegate("defend", 7)
	state.end_turn()
	var protected_funds: int = state.treasury
	state.reset()
	state.territories[7].owner = "player"
	state.division.location = 7
	state.turn = 2
	state.end_turn()
	check(protected_funds == state.treasury + 6, "Defense reduces border raid losses")
	# Complete the intended land corridor using the same ordinary NPC.
	state.reset()
	for target in [7, 8, 9]:
		state.reinforce()
		state.delegate("occupy", target)
		state.end_turn()
	if not state.won:
		print("CAMPAIGN DIAGNOSTIC: ", state.division, "\n", "\n".join(state.journal))
	check(state.won and state.territories[9].owner == "player", "Full campaign can reach prototype victory")
	# Instantiate real presentation and exercise its scene coordinator.
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.content.get_child_count() > 0, "Main scene builds UI")
	check(press_button(main, "Red Plain"), "Map territory signal is connected")
	await process_frame
	check(main.campaign.selected == 8, "Each tile selects its own territory")
	press_button(main, "Crossroads")
	await process_frame
	check(press_button(main, "Lead attack"), "Attack button signal is connected")
	await process_frame
	check(main.campaign.active_battle != null, "UI transitions from map to battle")
	check(press_button(main, "Retreat"), "Combat button signal is connected")
	await process_frame
	check(press_button(main, "Return to council"), "Return button signal is connected")
	await process_frame
	check(main.campaign.active_battle == null and main.campaign.turn == 2, "UI returns and applies battle outcome")
	main._reset()
	await process_frame
	check(main.campaign.turn == 1 and main.campaign.division.troops == 100, "UI new campaign resets state")
	main.queue_free()
	await process_frame
	print("CHECKS: %d / FAILURES: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
