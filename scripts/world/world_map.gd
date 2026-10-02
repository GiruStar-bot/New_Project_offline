extends Node2D
## Procedural placeholder art. No grids; geography, politics and people are layers.

var world: RefCounted
var selected_entity: int = -1
var selected_site: int = -1
var hovered_entity: int = -1
var assessment: Dictionary = {}
var view_zoom: float = 0.5
var map_font: SystemFont = SystemFont.new()
var trees: Array[Vector2] = []

func configure(model: RefCounted) -> void:
	world = model
	map_font.font_names = PackedStringArray(["Yu Gothic", "Meiryo", "Noto Sans CJK JP"])
	trees.clear()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 137
	for index in range(280):
		var point: Vector2 = Vector2(random.randf_range(220, 1530), random.randf_range(150, 1080))
		if world.geography.is_walkable(point) and (point.distance_to(Vector2(460, 600)) < 260 or point.distance_to(Vector2(1450, 470)) < 170):
			trees.append(point)
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	var physical: RefCounted = world.geography
	draw_rect(Rect2(-2000, -2000, 6000, 5000), Color("193643"))
	for y in range(100, 1300, 115):
		for x in range(80, 2050, 135):
			var point: Vector2 = Vector2(x + (y % 4) * 12, y)
			if not physical.is_land(point):
				draw_arc(point, 24, 0.15, 0.8, 8, Color("315363"), 2)
	for land in [physical.mainland, physical.island]:
		for shelf in Geometry2D.offset_polygon(land, 30):
			draw_colored_polygon(shelf, Color("2d5960"))
		draw_colored_polygon(land, Color("7e8e63"))
		_closed_line(land, Color("bfbc8d"), 5)
	var regions: Array[PackedVector2Array] = world.treaty.regions(world.treaty.border)
	draw_colored_polygon(regions[0], Color(0.1, 0.5, 0.42, 0.15))
	draw_colored_polygon(regions[1], Color(0.52, 0.26, 0.28, 0.12))
	draw_colored_polygon(physical.neutral_land, Color(0.74, 0.68, 0.43, 0.24))
	# Low hills and forest are visual cues; only the explicit cliffs obstruct paths.
	for tree in trees:
		draw_circle(tree + Vector2(3, 3), 8, Color("617150"))
		draw_colored_polygon(PackedVector2Array([tree + Vector2(-7, 5), tree + Vector2(0, -11), tree + Vector2(7, 5)]), Color("3c614c"))
	for cliff in physical.cliffs:
		for foothill in Geometry2D.offset_polygon(cliff, 22):
			draw_colored_polygon(foothill, Color("8e916c"))
		draw_colored_polygon(cliff, Color("666f65"))
		_closed_line(cliff, Color("a4a28b"), 3)
		var peak: Vector2 = (cliff[0] + cliff[2]) * 0.5 + Vector2(0, -28)
		draw_colored_polygon(PackedVector2Array([cliff[0], peak, cliff[2]]), Color("97998c"))
		_text(peak + Vector2(0, 22), "崖", Color("e5e2c3"), 20)
	var water: PackedVector2Array = PackedVector2Array([Vector2(690, 80), Vector2(746, 80), Vector2(754, 700), Vector2(785, 1140), Vector2(725, 1140), Vector2(710, 700)])
	draw_colored_polygon(water, Color("396d80"))
	_closed_line(water, Color("88a8a2"), 3)
	# Only this gap is walkable across the continuous river.
	draw_rect(Rect2(688, 646, 88, 48), Color("605743"))
	draw_rect(Rect2(690, 651, 84, 38), Color("bea276"))
	for x in range(695, 774, 10):
		draw_line(Vector2(x, 651), Vector2(x, 689), Color("82694e"), 2)
	_text(Vector2(732, 626), "石橋", Color("ecdfb2"), 25)
	_text(Vector2(460, 670), "評議国", Color("d1edcf"), 42)
	_text(Vector2(1300, 650), "東方国", Color("eddac8"), 42)
	_text(Vector2(1060, 255), "無所属地域", Color("e2d9b7"), 28)
	_text(Vector2(1840, 1030), "沖合の無所属島", Color("d4dabc"), 23)
	draw_polyline(world.treaty.border, Color("dfd1a0"), 4, true)
	for landmark in physical.landmarks:
		var location: Vector2 = landmark.position
		draw_circle(location, 5, Color("dee0c5"))
		if not world.treaty.draft.is_empty():
			_text(location + Vector2(0, -17), landmark.name, Color("ece7bd"), 18)
	if not world.treaty.draft.is_empty():
		if assessment.get("valid", false):
			var proposed: Array[PackedVector2Array] = world.treaty.regions(world.treaty.draft)
			for gain in Geometry2D.clip_polygons(proposed[0], regions[0]):
				draw_colored_polygon(gain, Color(0.15, 0.9, 0.7, 0.5))
			for gain in Geometry2D.clip_polygons(proposed[1], regions[1]):
				draw_colored_polygon(gain, Color(0.95, 0.43, 0.38, 0.48))
		var color: Color = Color("ffe19a") if assessment.get("valid", false) else Color("ff9c81")
		draw_polyline(world.treaty.draft, color, 3.0 / view_zoom, true)
		for index in range(world.treaty.draft.size()):
			var location: Vector2 = world.treaty.draft[index]
			var radius: float = 6.0 / view_zoom
			if index == 0 or index == world.treaty.draft.size() - 1:
				draw_rect(Rect2(location - Vector2.ONE * radius, Vector2.ONE * radius * 2), Color("b0b9b7"))
			else:
				draw_circle(location, radius, Color("182d39"))
				draw_arc(location, radius, 0, TAU, 20, color, 2.0 / view_zoom)
	for site in world.sites:
		_draw_site(site)
	# Only already-developed worksites, never undiscovered mineral deposits.
	for site in world.economy.worksites:
		var point: Vector2 = site.position
		if site.kind == "farm":
			draw_rect(Rect2(point - Vector2(28, 16), Vector2(56, 32)), Color("a9a46b"))
			for offset in [-10, 0, 10]:
				draw_line(point + Vector2(-23, offset), point + Vector2(23, offset), Color("726d42"), 2)
		else:
			draw_circle(point, 13, Color("736c5c") if site.kind == "stone" else Color("466447"))
		_text(point + Vector2(0, -24), "農地" if site.kind == "farm" else site.name, Color("e5d4ab"), 18)
	if selected_entity >= 0:
		var entity: Dictionary = world.entities[selected_entity]
		var route: PackedVector2Array = PackedVector2Array([entity.position])
		var path: PackedVector2Array = entity.path
		for index in range(entity.path_index, path.size()):
			route.append(path[index])
		if route.size() > 1:
			draw_polyline(route, Color("ffe5a1"), 2.5 / view_zoom, true)
			draw_arc(route[-1], 12.0 / view_zoom, 0, TAU, 24, Color("ffe5a1"), 2 / view_zoom)
	for entity in world.entities:
		_draw_person(entity)

func _draw_site(site: Dictionary) -> void:
	var point: Vector2 = site.position
	var color: Color = _faction_color(site.owner)
	if site.kind == "城塞":
		draw_rect(Rect2(point - Vector2(25, 19), Vector2(50, 38)), Color("454e4a"))
		draw_rect(Rect2(point - Vector2(17, 12), Vector2(34, 25)), Color("a7ad99"))
		for offset in [Vector2(-26, -20), Vector2(18, -20), Vector2(-26, 12), Vector2(18, 12)]:
			draw_rect(Rect2(point + offset, Vector2(10, 10)), Color("d0cfb4"))
	else:
		for offset in [Vector2(-21, 4), Vector2(1, -8), Vector2(17, 6)]:
			draw_rect(Rect2(point + offset, Vector2(15, 13)), Color("e0c998"))
			draw_colored_polygon(PackedVector2Array([point + offset + Vector2(-3, 0), point + offset + Vector2(7, -9), point + offset + Vector2(18, 0)]), Color("805d4b"))
	draw_line(point + Vector2(-28, 28), point + Vector2(31, 28), color, 5)
	if selected_site == int(site.id):
		draw_arc(point, 39, 0, TAU, 32, Color("ffe5a1"), 3 / view_zoom)
	_text(point + Vector2(0, -37), site.name, Color("f3ecd3"), 25)

func _draw_person(entity: Dictionary) -> void:
	var point: Vector2 = entity.position
	var color: Color = _faction_color(entity.owner)
	draw_circle(point + Vector2(3, 4), 10, Color(0.05, 0.12, 0.14, 0.45))
	if entity.role == "兵士":
		draw_rect(Rect2(point - Vector2(8, 8), Vector2(16, 16)), color)
		draw_line(point + Vector2(1, -11), point + Vector2(1, 11), Color("edf0d3"), 2)
	else:
		draw_circle(point, 8, color)
		draw_circle(point + Vector2(0, -7), 4, Color("e9d6b1"))
	if world.shipments.has(str(entity.id)) and world.shipments[str(entity.id)].phase != "pickup":
		draw_rect(Rect2(point + Vector2(9, -5), Vector2(8, 8)), Color("ffe5a1"))
	if int(entity.id) == selected_entity or int(entity.id) == hovered_entity:
		draw_arc(point, 12 / view_zoom, 0, TAU, 24, Color("ffe5a1"), 2 / view_zoom)
		_text(point + Vector2(0, -21 / view_zoom), entity.name, Color("fff0bc"), roundi(15 / view_zoom))

func _text(point: Vector2, value: String, color: Color, font_size: int) -> void:
	var width: float = map_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(map_font, point - Vector2(width / 2, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _closed_line(points: PackedVector2Array, color: Color, width: float) -> void:
	var line: PackedVector2Array = points.duplicate()
	line.append(points[0])
	draw_polyline(line, color, width, true)

func _faction_color(owner: String) -> Color:
	return Color("70dec0") if owner == "council" else (Color("df9281") if owner == "rival" else Color("e7d8a1"))
