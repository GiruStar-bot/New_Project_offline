extends SubViewportContainer
## Mouse/camera adapter. Emits intent; never writes campaign state.

const MapArt = preload("res://scripts/world/world_map.gd")
signal person_selected(id: int)
signal site_selected(id: int)
signal destination_requested(point: Vector2)
signal border_point_moved(index: int, point: Vector2)
signal border_point_inserted(segment: int, point: Vector2)
signal border_point_removed(index: int)
var world: RefCounted
var viewport: SubViewport
var camera: Camera2D
var artwork: Node2D
var dragging_point: int = -1
var panning: bool = false

func _ready() -> void:
	stretch = true
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.size = Vector2i(900, 560)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	artwork = MapArt.new()
	viewport.add_child(artwork)
	camera = Camera2D.new()
	viewport.add_child(camera)
	camera.position = Vector2(1050, 640)
	if world != null:
		artwork.configure(world)
	call_deferred("fit_map")

func configure(model: RefCounted) -> void:
	world = model
	if artwork != null:
		artwork.configure(world)
		update_assessment()

func update_assessment() -> void:
	if artwork != null:
		artwork.assessment = world.treaty.evaluate()
		artwork.queue_redraw()

func fit_map() -> void:
	if camera == null:
		return
	camera.position = Vector2(1050, 640)
	var scale_value: float = minf(float(viewport.size.x) / 2050, float(viewport.size.y) / 1260)
	camera.zoom = Vector2.ONE * maxf(0.25, scale_value)
	camera.force_update_scroll()

func world_from_screen(point: Vector2) -> Vector2:
	return viewport.get_canvas_transform().affine_inverse() * point

func screen_from_world(point: Vector2) -> Vector2:
	return viewport.get_canvas_transform() * point

func zoom_at(point: Vector2, factor: float) -> void:
	var previous: Vector2 = world_from_screen(point)
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, 0.25, 2.0)
	camera.force_update_scroll()
	camera.position += previous - world_from_screen(point)
	camera.force_update_scroll()

func pick_person(point: Vector2) -> int:
	var best: int = -1
	var distance: float = 13 / camera.zoom.x
	for entity in world.entities:
		var candidate_distance: float = point.distance_to(entity.position)
		if candidate_distance < distance:
			best = entity.id
			distance = candidate_distance
	return best

func pick_site(point: Vector2) -> int:
	for site in world.sites:
		if point.distance_to(site.position) < 23 / camera.zoom.x:
			return int(site.id)
	return -1

func nearest_handle(point: Vector2) -> int:
	for index in range(world.treaty.draft.size()):
		if point.distance_to(world.treaty.draft[index]) < 13 / camera.zoom.x:
			return index
	return -1

func _gui_input(event: InputEvent) -> void:
	if world == null or camera == null:
		return
	if event is InputEventMouseButton:
		var point: Vector2 = world_from_screen(event.position)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.2)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				dragging_point = -1
			elif not world.treaty.draft.is_empty():
				dragging_point = nearest_handle(point)
				if event.double_click and dragging_point < 0:
					var nearest: int = -1
					var distance: float = 18 / camera.zoom.x
					for index in range(world.treaty.draft.size() - 1):
						var projected: Vector2 = Geometry2D.get_closest_point_to_segment(point, world.treaty.draft[index], world.treaty.draft[index + 1])
						if point.distance_to(projected) < distance:
							nearest = index
							distance = point.distance_to(projected)
					if nearest >= 0:
						border_point_inserted.emit(nearest, point)
			else:
				var id: int = pick_person(point)
				if id >= 0:
					person_selected.emit(id)
				else:
					site_selected.emit(pick_site(point))
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if not world.treaty.draft.is_empty():
				var index: int = nearest_handle(point)
				if index >= 0:
					border_point_removed.emit(index)
			else:
				destination_requested.emit(point)
			accept_event()
	elif event is InputEventMouseMotion:
		if panning:
			camera.position -= event.relative / camera.zoom
			camera.force_update_scroll()
		elif dragging_point > 0 and dragging_point < world.treaty.draft.size() - 1:
			border_point_moved.emit(dragging_point, world_from_screen(event.position))
		else:
			artwork.hovered_entity = pick_person(world_from_screen(event.position))

func _process(_delta: float) -> void:
	if artwork != null:
		artwork.view_zoom = camera.zoom.x
		artwork.queue_redraw()
