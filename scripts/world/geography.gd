extends RefCounted
## Physical world in continuous coordinates. Political borders never affect paths.

const SNAP_DISTANCE: float = 18.0 # [PLACEHOLDER] map-space editing assistance.
var mainland: PackedVector2Array = PackedVector2Array([
	Vector2(200, 300), Vector2(270, 140), Vector2(700, 100), Vector2(1150, 180),
	Vector2(1550, 300), Vector2(1640, 500), Vector2(1590, 700), Vector2(1650, 900),
	Vector2(1550, 1100), Vector2(200, 1100), Vector2(130, 820), Vector2(180, 650), Vector2(150, 450)])
var island: PackedVector2Array = PackedVector2Array([
	Vector2(1750, 750), Vector2(1810, 690), Vector2(1900, 740), Vector2(1950, 860),
	Vector2(1890, 970), Vector2(1770, 930), Vector2(1730, 830)])
var neutral_land: PackedVector2Array = PackedVector2Array([
	Vector2(200, 300), Vector2(270, 140), Vector2(700, 100), Vector2(1150, 180), Vector2(1550, 300)])
var west_coast: PackedVector2Array = PackedVector2Array([
	Vector2(200, 300), Vector2(150, 450), Vector2(180, 650), Vector2(130, 820), Vector2(200, 1100)])
var east_coast: PackedVector2Array = PackedVector2Array([
	Vector2(1550, 300), Vector2(1640, 500), Vector2(1590, 700), Vector2(1650, 900), Vector2(1550, 1100)])
var cliffs: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(400, 430), Vector2(470, 390), Vector2(545, 440), Vector2(525, 550), Vector2(420, 555)]),
	PackedVector2Array([Vector2(1180, 460), Vector2(1260, 410), Vector2(1340, 475), Vector2(1310, 580), Vector2(1200, 560)])]
var river_parts: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(690, 80), Vector2(746, 80), Vector2(754, 640), Vector2(710, 640)]),
	PackedVector2Array([Vector2(710, 700), Vector2(754, 700), Vector2(785, 1140), Vector2(725, 1140)])]
var landmarks: Array[Dictionary] = [
	{"name": "北の標石", "position": Vector2(900, 400)},
	{"name": "尾根の標石", "position": Vector2(820, 500)},
	{"name": "草原の標石", "position": Vector2(980, 700)},
	{"name": "南の標石", "position": Vector2(900, 900)},
	{"name": "橋の西岸", "position": Vector2(690, 670)},
	{"name": "橋の東岸", "position": Vector2(777, 670)}]
var graph: AStar2D = AStar2D.new()
var obstacles: Array[PackedVector2Array] = []

func _init() -> void:
	obstacles.append_array(river_parts)
	obstacles.append_array(cliffs)
	_build_navigation()

func is_land(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, mainland) or Geometry2D.is_point_in_polygon(point, island)

func is_walkable(point: Vector2) -> bool:
	if not is_land(point):
		return false
	for obstacle in obstacles:
		if Geometry2D.is_point_in_polygon(point, obstacle):
			return false
	return true

func segment_in_mainland(start: Vector2, finish: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(start, mainland) or not Geometry2D.is_point_in_polygon(finish, mainland):
		return false
	for index in range(mainland.size()):
		var hit: Variant = Geometry2D.segment_intersects_segment(start, finish, mainland[index], mainland[(index + 1) % mainland.size()])
		if hit != null and start.distance_to(hit) > 0.01 and finish.distance_to(hit) > 0.01:
			return false
	return Geometry2D.is_point_in_polygon(start.lerp(finish, 0.5), mainland)

func segment_walkable(start: Vector2, finish: Vector2) -> bool:
	if not is_walkable(start) or not is_walkable(finish):
		return false
	# Exact obstruction intersections, including shallow/narrow crossings.
	for polygon in obstacles:
		for index in range(polygon.size()):
			if Geometry2D.segment_intersects_segment(start, finish, polygon[index], polygon[(index + 1) % polygon.size()]) != null:
				return false
	# Crossing any coastline interior would leave traversable land.
	for coast in [mainland, island]:
		for index in range(coast.size()):
			var hit: Variant = Geometry2D.segment_intersects_segment(start, finish, coast[index], coast[(index + 1) % coast.size()])
			if hit != null and start.distance_to(hit) > 0.01 and finish.distance_to(hit) > 0.01:
				return false
	var samples: int = maxi(1, ceili(start.distance_to(finish) / 12.0))
	for index in range(1, samples):
		if not is_walkable(start.lerp(finish, float(index) / samples)):
			return false
	return true

func find_path(start: Vector2, finish: Vector2) -> PackedVector2Array:
	if not is_walkable(start) or not is_walkable(finish):
		return PackedVector2Array()
	if segment_walkable(start, finish):
		return PackedVector2Array([start, finish])
	# Visibility graph vertices are routing aids, not tiles or territories.
	var ids: PackedInt64Array = graph.get_point_ids()
	graph.add_point(10000, start)
	graph.add_point(10001, finish)
	for id in ids:
		var position: Vector2 = graph.get_point_position(id)
		if segment_walkable(start, position):
			graph.connect_points(10000, id)
		if segment_walkable(finish, position):
			graph.connect_points(10001, id)
	var result: PackedVector2Array = graph.get_point_path(10000, 10001)
	graph.remove_point(10000)
	graph.remove_point(10001)
	return result

func snap(point: Vector2) -> Vector2:
	var best: Vector2 = point
	var distance: float = SNAP_DISTANCE
	for landmark in landmarks:
		var candidate: Vector2 = landmark.position
		if candidate.distance_to(point) < distance:
			best = candidate
			distance = candidate.distance_to(point)
	return best

func _build_navigation() -> void:
	var candidates: Array[Vector2] = [Vector2(690, 670), Vector2(777, 670), Vector2(710, 652), Vector2(755, 685)]
	for obstacle in obstacles:
		var center: Vector2 = Vector2.ZERO
		for point in obstacle:
			center += point
		center /= obstacle.size()
		for point in obstacle:
			candidates.append(point + (point - center).normalized() * 10.0)
	for coast in [mainland, island]:
		var center: Vector2 = Vector2.ZERO
		for point in coast:
			center += point
		center /= coast.size()
		for point in coast:
			candidates.append(point.move_toward(center, 14.0))
	for candidate in candidates:
		if is_walkable(candidate):
			graph.add_point(graph.get_available_point_id(), candidate)
	var ids: PackedInt64Array = graph.get_point_ids()
	for first in range(ids.size()):
		for second in range(first + 1, ids.size()):
			if segment_walkable(graph.get_point_position(ids[first]), graph.get_point_position(ids[second])):
				graph.connect_points(ids[first], ids[second])
