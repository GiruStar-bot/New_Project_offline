extends RefCounted
## Owns campaign state; UI and NPC never mutate territory or economy directly.

const Battle = preload("res://scripts/battle_model.gd")
const Commander = preload("res://scripts/npc_commander.gd")

var territories: Array[Dictionary] = []
var division: Dictionary = {}
var treasury: int = 60
var grain: int = 60
var turn: int = 1
var selected: int = 6
var assignment: String = ""
var assignment_target: int = -1
var active_battle: RefCounted
var won: bool = false
var journal: Array[String] = []
var commander: RefCounted = Commander.new()

func _init() -> void:
	reset()

func reset() -> void:
	territories.clear()
	var names: Array[String] = ["Westwood", "High Pass", "North Reach", "Sea", "Iron Hills", "Haven", "Breadbasket", "Crossroads", "Red Plain", "Citadel", "South Port", "Lowland", "Sea", "Stone Ridge", "East Port"]
	var terrains: Array[String] = ["Forest", "Mountain", "Plain", "Sea", "Mountain", "Plain", "Plain", "Plain", "Plain", "Mountain", "Coast", "Plain", "Sea", "Mountain", "Coast"]
	for index in range(15):
		var owner: String = "enemy" if index % 5 >= 3 else "neutral"
		if index in [0, 5, 6, 10]:
			owner = "player"
		var is_sea: bool = terrains[index] == "Sea"
		territories.append({"id": index, "name": names[index], "terrain": terrains[index], "owner": "none" if is_sea else owner, "garrison": 65 if owner == "enemy" else 35, "income": 7 if terrains[index] == "Coast" else 4, "grain": 10 if terrains[index] == "Plain" else 3})
	division = {"troops": 100, "morale": 85, "supply": 65, "location": 6}
	treasury = 60
	grain = 60
	turn = 1
	selected = 7
	assignment = ""
	assignment_target = -1
	active_battle = null
	won = false
	journal = ["Council convened. Secure a land route to the eastern Citadel."]

func adjacent(a: int, b: int) -> bool:
	return absi(a % 5 - b % 5) + absi(a / 5 - b / 5) == 1

func attack_error(target_id: int) -> String:
	if won:
		return "Campaign complete. Start a new campaign to continue."
	if active_battle != null:
		return "A battle is already in progress."
	if target_id < 0 or target_id >= territories.size():
		return "Invalid territory."
	var target: Dictionary = territories[target_id]
	if target.terrain == "Sea":
		return "Sea tiles are impassable. Naval transport is not implemented."
	if target.owner == "player":
		return "This territory is already ours."
	if not adjacent(int(division.location), target_id):
		return "Move the division to an adjacent friendly territory first."
	if int(division.troops) < 20 or int(division.morale) < 15:
		return "Division unfit: reinforce and rest first."
	if treasury < 8 or int(division.supply) < 12:
		return "An operation requires 8 treasury and at least 12 supply."
	return ""

func start_battle(target_id: int) -> RefCounted:
	var reason: String = attack_error(target_id)
	if not reason.is_empty():
		return null
	treasury -= 8
	assignment = ""
	assignment_target = -1
	active_battle = Battle.new(territories[target_id], division)
	return active_battle

func finish_battle(advance_turn: bool = true) -> String:
	if active_battle == null or active_battle.outcome.is_empty():
		return "No concluded battle."
	var battle: RefCounted = active_battle
	var territory: Dictionary = territories[battle.target_id]
	division.troops = battle.troops
	division.morale = battle.morale
	division.supply = battle.supply
	territory.garrison = maxi(15, battle.enemy)
	if battle.outcome == "victory":
		territory.owner = "player"
		division.location = battle.target_id
		territory.garrison = 15
		if battle.target_id == 9:
			won = true
	var result: String = "%s at %s. Division: %d troops, %d morale, %d supply." % [battle.outcome.to_upper(), territory.name, division.troops, division.morale, division.supply]
	active_battle = null
	_add_log(result)
	if advance_turn:
		_economy_tick()
	return result

func move_division(target_id: int) -> String:
	if active_battle != null or won:
		return "Movement unavailable."
	if target_id < 0 or target_id >= territories.size():
		return "Invalid territory."
	if territories[target_id].owner != "player" or not adjacent(int(division.location), target_id):
		return "Move only to adjacent friendly land."
	if int(division.supply) < 2:
		return "Need 2 supply to move. Reinforce first."
	division.location = target_id
	division.supply = int(division.supply) - 2
	assignment = ""
	assignment_target = -1
	var result: String = "Division moved to %s (-2 supply)." % territories[target_id].name
	_add_log(result)
	return result

func delegate(order: String, target_id: int) -> String:
	if active_battle != null or won:
		return "Orders unavailable."
	if order not in ["occupy", "defend"] or target_id < 0 or target_id >= territories.size():
		return "Invalid order."
	if order == "occupy":
		var reason: String = attack_error(target_id)
		if not reason.is_empty():
			return reason
	elif target_id != int(division.location):
		return "Defense can be assigned at the division's current location."
	assignment = order
	assignment_target = target_id
	var result: String = "Mira assigned to %s %s. Executes on End turn." % [order, territories[target_id].name]
	_add_log(result)
	return result

func reinforce() -> String:
	if active_battle != null or won:
		return "Reinforcement unavailable."
	if treasury < 12 or grain < 15:
		return "Reinforcement requires 12 treasury and 15 grain."
	treasury -= 12
	grain -= 15
	division.troops = mini(100, int(division.troops) + 30)
	division.morale = mini(100, int(division.morale) + 20)
	division.supply = mini(100, int(division.supply) + 35)
	_add_log("Reinforced: +30 troops, +20 morale, +35 supply (caps 100).")
	return journal[-1]

func end_turn() -> String:
	if active_battle != null or won:
		return "Finish the battle or start a new campaign."
	var result: String = "Council ended the turn."
	if assignment == "occupy":
		var target: int = assignment_target
		var reason: String = attack_error(target)
		assignment = ""
		assignment_target = -1
		if reason.is_empty():
			var battle: RefCounted = start_battle(target)
			while battle.outcome.is_empty():
				var command: String = commander.choose_command(battle)
				_add_log("Mira: " + battle.step(command))
			result = "Mira / " + finish_battle(false)
		else:
			result = "Mira cancelled operation: " + reason
			_add_log(result)
	elif assignment == "defend":
		division.morale = mini(100, int(division.morale) + 8)
		_add_log("Mira fortified the division's position (+8 morale).")
	_economy_tick()
	return result

func income() -> Vector2i:
	var total: Vector2i = Vector2i.ZERO
	for territory in territories:
		if territory.owner == "player":
			total += Vector2i(int(territory.income), int(territory.grain))
	return total

func owned_count() -> int:
	var total: int = 0
	for territory in territories:
		if territory.owner == "player":
			total += 1
	return total

func _economy_tick() -> void:
	var revenue: Vector2i = income()
	treasury += revenue.x - 6
	grain = maxi(0, grain + revenue.y - 12)
	turn += 1
	if grain == 0:
		division.morale = maxi(0, int(division.morale) - 12)
		_add_log("Grain depleted: division morale -12.")
	# A visible, predictable frontier raid, not a full strategic enemy AI.
	if turn % 3 == 0 and not won:
		for territory in territories:
			if territory.owner != "player":
				continue
			var exposed: bool = false
			for hostile in territories:
				if hostile.owner == "enemy" and adjacent(int(territory.id), int(hostile.id)):
					exposed = true
					break
			if exposed:
				var protected: bool = assignment == "defend" and assignment_target == int(territory.id)
				var loss: int = 2 if protected else 8
				treasury = maxi(0, treasury - loss)
				_add_log("Border raid at %s: treasury -%d%s." % [territory.name, loss, " (Mira defended)" if protected else ""])
				break
	_add_log("Turn %d: revenue +%d treasury / +%d grain; upkeep -6 / -12." % [turn, revenue.x, revenue.y])

func _add_log(message: String) -> void:
	journal.append(message)
	if journal.size() > 50:
		journal.pop_front()
