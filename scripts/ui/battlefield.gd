extends Control
## Procedural placeholder battlefield, kept separate from combat calculation.

var battle: RefCounted

func _draw() -> void:
	if battle == null:
		return
	draw_style_box(preload("res://scripts/ui/ui.gd").box_style(Color("182832")), Rect2(Vector2.ZERO, size))
	for x in range(40, int(size.x), 52):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("223744"))
	for y in range(30, int(size.y), 45):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("223744"))
	# Central ridge / open plain makes the selected terrain visible.
	if battle.terrain == "Mountain":
		for y in range(35, int(size.y) - 30, 75):
			var center: Vector2 = Vector2(size.x * 0.58, y)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-38, 30), center + Vector2(0, -20), center + Vector2(38, 30)]), Color("55636a"))
	else:
		draw_line(Vector2(size.x * 0.5, 20), Vector2(size.x * 0.5, size.y - 20), Color("6b6951"), 3)
	_draw_division(Vector2(size.x * 0.22, size.y * 0.42), battle.troops, Color("4bbaa7"), false)
	_draw_division(Vector2(size.x * 0.77, size.y * 0.42), battle.enemy, Color("d57671"), true)
	var advance: float = 22.0 if battle.enemy_intent() == "attack" else 0.0
	draw_line(Vector2(size.x * 0.7, size.y * 0.77), Vector2(size.x * 0.57 - advance, size.y * 0.77), Color("d57671"), 3)
	draw_line(Vector2(size.x * 0.57 - advance, size.y * 0.77), Vector2(size.x * 0.60 - advance, size.y * 0.77 - 10), Color("d57671"), 3)

func _draw_division(origin: Vector2, strength: int, color: Color, reverse: bool) -> void:
	var count: int = ceili(strength / 10.0)
	for index in range(count):
		var point: Vector2 = origin + Vector2((index % 3) * 24, (index / 3) * 30)
		draw_rect(Rect2(point, Vector2(15, 20)), color)
		draw_line(point + Vector2(7, 10), point + Vector2(-9 if reverse else 25, 10), color, 3)
