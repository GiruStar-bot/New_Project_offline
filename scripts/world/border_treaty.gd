extends RefCounted
## Territory geometry and provisional bilateral exchange. No entity or UI mutation.

const ACCEPTANCE_RATIO: float = 0.95 # [PLACEHOLDER] NPC's area-only negotiating rule.
const SITE_CLEARANCE: float = 40.0 # [PLACEHOLDER] protected settlement footprint.
const MIN_EXCHANGE_AREA: float = 1.0
var geography: RefCounted
var sites: Array[Dictionary]
var border: PackedVector2Array = PackedVector2Array([
	Vector2(900, 300), Vector2(900, 500), Vector2(900, 700), Vector2(900, 900), Vector2(900, 1100)])
var draft: PackedVector2Array = PackedVector2Array()
var revision: int = 0

func _init(physical_world: RefCounted, settlements: Array[Dictionary]) -> void:
	geography = physical_world
	sites = settlements

func regions(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var west: PackedVector2Array = geography.west_coast.duplicate()
	var reverse: PackedVector2Array = points.duplicate()
	reverse.reverse()
	west.append_array(reverse)
	var east: PackedVector2Array = points.duplicate()
	reverse = geography.east_coast.duplicate()
	reverse.reverse()
	east.append_array(reverse)
	return [west, east]

func owner_at(point: Vector2) -> String:
	var shapes: Array[PackedVector2Array] = regions(border)
	if Geometry2D.is_point_in_polygon(point, shapes[0]):
		return "council"
	if Geometry2D.is_point_in_polygon(point, shapes[1]):
		return "rival"
	return "neutral" if geography.is_land(point) else "sea"

func begin() -> void:
	draft = border.duplicate()

func cancel() -> void:
	draft = PackedVector2Array()

func move_point(index: int, position: Vector2) -> bool:
	if index <= 0 or index >= draft.size() - 1:
		return false
	draft[index] = geography.snap(position)
	return true

func insert_point(segment: int, position: Vector2) -> bool:
	if segment < 0 or segment >= draft.size() - 1 or draft.size() >= 32:
		return false
	draft.insert(segment + 1, geography.snap(position))
	return true

func remove_point(index: int) -> bool:
	if index <= 0 or index >= draft.size() - 1 or draft.size() <= 3:
		return false
	draft.remove_at(index)
	return true

func example() -> void:
	# A reversible equal-area exchange from the current boundary, for onboarding.
	draft = PackedVector2Array([border[0], Vector2(_x_at(500) - 80, 500), Vector2(_x_at(700) + 80, 700), Vector2(_x_at(900), 900), border[-1]])

func evaluate() -> Dictionary:
	var result: Dictionary = {"valid": false, "reason": "国境の提案を開始してください。", "council_gain": 0.0, "rival_gain": 0.0, "accepted": false}
	if draft.size() < 3:
		return result
	if not draft[0].is_equal_approx(border[0]) or not draft[-1].is_equal_approx(border[-1]):
		result.reason = "国境の両端は固定です。"
		return result
	for index in range(draft.size()):
		var point: Vector2 = draft[index]
		if not point.is_finite() or not Geometry2D.is_point_in_polygon(point, geography.mainland) or point.y < 300 or point.y > 1100:
			result.reason = "国境は両国の本土内に配置してください。無所属地域と海は変更できません。"
			return result
		if index > 0 and draft[index].y - draft[index - 1].y < 4.0:
			result.reason = "点は北から南へ並べてください。折り返しや飛び地はこの試作では扱いません。"
			return result
		if index > 0 and not geography.segment_in_mainland(draft[index - 1], point):
			result.reason = "国境の線が海岸を越えています。本土内に収めてください。"
			return result
		if index > 0 and index < draft.size() - 1:
			for edge in range(geography.mainland.size()):
				if Geometry2D.get_closest_point_to_segment(point, geography.mainland[edge], geography.mainland[(edge + 1) % geography.mainland.size()]).distance_to(point) < 4:
					result.reason = "途中の点を海岸に接触させると領土が分断されます。"
					return result
		for second in range(index + 2, draft.size() - 1):
			if index < draft.size() - 1 and Geometry2D.segment_intersects_segment(draft[index], draft[index + 1], draft[second], draft[second + 1]) != null:
				result.reason = "国境の線が自己交差しています。"
				return result
	var proposed: Array[PackedVector2Array] = regions(draft)
	for polygon in proposed:
		if polygon_area(polygon) < 1 or Geometry2D.triangulate_polygon(polygon).is_empty():
			result.reason = "領土の形状が不正です。"
			return result
	var overlap: float = area_sum(Geometry2D.intersect_polygons(proposed[0], proposed[1]))
	var original: Array[PackedVector2Array] = regions(border)
	var old_area: float = polygon_area(original[0]) + polygon_area(original[1])
	if overlap > 0.1 or absf(polygon_area(proposed[0]) + polygon_area(proposed[1]) - old_area) > 0.1:
		result.reason = "領土の重複または空白が発生する提案です。"
		return result
	for site in sites:
		if site.owner == "neutral":
			continue
		var side: int = 0 if site.owner == "council" else 1
		if not Geometry2D.is_point_in_polygon(site.position, proposed[side]):
			result.reason = "村・城塞の譲渡は次の段階で扱います。"
			return result
		for index in range(draft.size() - 1):
			if Geometry2D.get_closest_point_to_segment(site.position, draft[index], draft[index + 1]).distance_to(site.position) < SITE_CLEARANCE:
				result.reason = "国境が村または城塞の敷地に接近しすぎています。"
				return result
	result.valid = true
	result.council_gain = area_sum(Geometry2D.clip_polygons(proposed[0], original[0]))
	result.rival_gain = area_sum(Geometry2D.clip_polygons(proposed[1], original[1]))
	if result.council_gain <= MIN_EXCHANGE_AREA or result.rival_gain <= MIN_EXCHANGE_AREA:
		result.reason = "土地交換には、双方が差し出す土地が必要です。"
	elif result.rival_gain + 0.001 < result.council_gain * ACCEPTANCE_RATIO:
		result.reason = "相手国が拒否：取得する面積が、譲渡する面積の95%に届きません。"
	else:
		result.accepted = true
		result.reason = "相手国はこの土地交換に合意します。提出すると国境が確定します。"
	return result

func submit() -> Dictionary:
	var result: Dictionary = evaluate()
	if result.accepted:
		border = draft.duplicate()
		draft = PackedVector2Array()
		revision += 1
	return result

static func polygon_area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	for index in range(polygon.size()):
		total += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return absf(total) / 2.0

static func area_sum(polygons: Array[PackedVector2Array]) -> float:
	# Signed winding preserves holes returned by Geometry2D's boolean operations.
	var total: float = 0.0
	for polygon in polygons:
		var signed_area: float = 0.0
		for index in range(polygon.size()):
			signed_area += polygon[index].cross(polygon[(index + 1) % polygon.size()]) / 2.0
		total += signed_area
	return absf(total)

func _x_at(y: float) -> float:
	for index in range(border.size() - 1):
		if y >= border[index].y and y <= border[index + 1].y:
			return lerpf(border[index].x, border[index + 1].x, inverse_lerp(border[index].y, border[index + 1].y, y))
	return border[0].x
