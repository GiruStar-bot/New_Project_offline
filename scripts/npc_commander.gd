extends RefCounted
## An ordinary GDScript commander. Pure decisions; state executes the orders.

const NAME: String = "General Mira"
const TRAIT: String = "Cautious / logistics first"

func choose_command(battle: RefCounted) -> String:
	if battle.troops < 28 or battle.supply < 4:
		return "retreat"
	if battle.morale < 40 and battle.enemy_intent() != "attack":
		return "regroup"
	if battle.enemy_intent() == "attack" and battle.round_number % 3 == 1:
		return "defend"
	return "attack"
