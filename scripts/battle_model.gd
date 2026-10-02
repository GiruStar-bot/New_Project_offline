extends RefCounted
## Deterministic, deliberately provisional combat. No scene or UI dependencies.

var target_id: int
var terrain: String
var troops: int
var morale: int
var supply: int
var enemy: int
var enemy_morale: int = 80
var round_number: int = 1
var outcome: String = ""
var records: Array[String] = []

func _init(target: Dictionary, division: Dictionary) -> void:
	target_id = int(target.id)
	terrain = str(target.terrain)
	troops = int(division.troops)
	morale = int(division.morale)
	supply = int(division.supply)
	enemy = int(target.garrison)

func enemy_intent() -> String:
	if enemy_morale < 35:
		return "regroup"
	return ["attack", "defend", "attack"][((round_number - 1) % 3)]

func step(command: String) -> String:
	if not outcome.is_empty():
		return "Battle already concluded."
	if command not in ["attack", "defend", "regroup", "retreat"]:
		return "Unknown command."
	if command == "retreat":
		troops = maxi(0, troops - 4)
		morale = maxi(0, morale - 8)
		outcome = "retreat"
		return _record("Ordered retreat: 4 troops lost while disengaging.")
	var intent: String = enemy_intent()
	var terrain_cover: int = 7 if terrain == "Mountain" else 0
	var outgoing: int = maxi(5, roundi(troops * 0.21 + morale * 0.08))
	var incoming: int = maxi(4, roundi(enemy * 0.18 + enemy_morale * 0.05))
	if supply < 12:
		outgoing = maxi(3, outgoing / 2)
		incoming += 4
	if intent == "defend":
		outgoing = maxi(2, outgoing - 12)
		incoming = maxi(2, incoming / 2)
	elif intent == "regroup":
		incoming = 3
		enemy_morale = mini(100, enemy_morale + 12)
	outgoing = maxi(2, outgoing - terrain_cover)
	if command == "defend":
		incoming = maxi(1, incoming / 3)
		outgoing = 9 if intent == "attack" else 2
		morale = mini(100, morale + 3)
	elif command == "regroup":
		outgoing = 0
		morale = mini(100, morale + 16)
		incoming += 2
	enemy = maxi(0, enemy - outgoing)
	troops = maxi(0, troops - incoming)
	supply = maxi(0, supply - (8 if command == "attack" else 4))
	morale = maxi(0, morale - roundi(incoming * 0.5))
	enemy_morale = maxi(0, enemy_morale - roundi(outgoing * 0.7))
	var message: String = "Round %d | %s vs %s: enemy -%d, division -%d." % [round_number, command, intent, outgoing, incoming]
	if troops == 0 or morale == 0:
		outcome = "defeat"
	elif enemy == 0 or enemy_morale == 0:
		outcome = "victory"
	elif round_number >= 10:
		outcome = "retreat"
		message += " Nightfall: forced withdrawal."
	round_number += 1
	return _record(message)

func _record(message: String) -> String:
	records.append(message)
	return message
