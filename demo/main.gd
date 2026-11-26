extends Node3D

enum View { MANUAL, WAITING, FOLLOWING, RETURNING }
enum Tool { EXPLORE, CUT, LIFT, VILLAGE, TERRAIN }
const Resort := preload("res://demo/resort.gd")
const TrailPlanner := preload("res://demo/trail_planner.gd")
const Village := preload("res://world/village.gd")
@onready var mountain = $Mountain
@onready var hud = $HUD
@onready var guide = $Guide
var resort := Resort.new()
var settings_path := "user://settings.cfg"
var settings := ConfigFile.new()
var active_lift: Node
var selected_lift := 0
var lift_type := 0
var building_type := 0
var tool := Tool.EXPLORE
var dragging := false
var drag_origin := Vector2.ZERO
var drag_base := Vector2.ZERO
var feature_kind := 0
var run_shape := 0
var moved_map := false
var shift_pan := false
var map_button := MOUSE_BUTTON_NONE
var drag_basis := Basis.IDENTITY
var drag_pivot := Vector3.ZERO
var drag_depth := 0.0
var pan_start := Vector3.ZERO
const DRAG_THRESHOLD := 6.0
const ZOOM_STEP := 0.88
var tapped_skier: Node3D
var stroke := PackedVector2Array()
var bends := PackedVector2Array()
var drafting := false
var editing_bend := -1
var preview_dirty := false
var lift_anchor := Vector2.INF
var lift_pointer := Vector2.INF
var precise_terminal := false
var hint_time := 0.0
var slow := false
var closing := false
var camera_wide_size := 1.0
var camera_wide_position := Vector3.ZERO
var camera_wide_basis := Basis.IDENTITY
var camera_focus_depth := 60.0
var zoom_ratio := 1.0
var follow_basis := Basis.IDENTITY
var follow_ratio := 0.27
var view := View.MANUAL
var subject: Node3D
var awaiting_run := -1

func _ready() -> void:
	var load_error := settings.load(settings_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load sound preferences (%s)" % error_string(load_error))
	_apply_mute(settings.get_value("audio", "muted", false) == true)
	add_child(resort)
	resort.setup(mountain)
	selected_lift = resort.lifts.size() - 1
	active_lift = resort.lifts[selected_lift]
	lift_type = resort.unlocked
	building_type = maxi(0, resort.building_count() - 1)
	resort.changed.connect(_refresh)
	resort.milestone.connect(_milestone)
	hud.tool_requested.connect(set_tool)
	hud.choice_requested.connect(_select_choice)
	hud.shape_requested.connect(_select_shape)
	hud.undo_bend_requested.connect(_undo_bend)
	hud.finish_trail_requested.connect(_open_draft)
	hud.follow_requested.connect(_toggle_follow)
	hud.slow_requested.connect(_toggle_speed)
	hud.mute_requested.connect(_toggle_mute)
	hud.wide_requested.connect(_wide)
	get_window().focus_exited.connect(_focus_lost)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_finish_session)
	mountain.map_inset = hud.map_inset()
	camera_wide_size = mountain.overview_size()
	camera_wide_position = mountain.camera_rig.global_position
	camera_wide_basis = mountain.camera_rig.global_basis
	camera_focus_depth = camera_wide_position.distance_to(mountain.VIEW_CENTER)
	get_viewport().size_changed.connect(_resize_camera)
	_wide()
	if OS.has_feature("web") and JavaScriptBridge.eval("typeof window.littleLiftsSceneReady === 'function'"):
		_prime_web_renderer.call_deferred()

func _prime_web_renderer() -> void:
	# WebGL links these programs on their first visible draw. Render the
	# real guide and groomed snow under the browser loading screen. The
	# survey and draft controls also warm the corresponding canvas items.
	set_tool(Tool.CUT)
	hud.show_draft(true,1)
	var path := resort.suggestion(selected_lift,run_shape)
	var piste := preload("res://world/groomed_trail.gd").new()
	mountain.add_child(piste)
	piste.build(mountain,path.slice(0,mini(5,path.size())),mountain.CUT_HALF_WIDTH)
	await get_tree().process_frame
	await get_tree().process_frame
	piste.queue_free()
	set_tool(Tool.EXPLORE)
	await get_tree().process_frame
	JavaScriptBridge.eval("window.littleLiftsSceneReady()")

func _apply_mute(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), muted)
	hud.show_muted(muted)

func _toggle_mute() -> void:
	var muted := not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master"))
	_apply_mute(muted)
	settings.set_value("audio", "muted", muted)
	var save_error := settings.save(settings_path)
	if save_error != OK:
		push_warning("Could not save sound preferences (%s)" % error_string(save_error))

func _surface(p: Vector2) -> Vector3:
	return Vector3(p.x, mountain.surface_height(p.x,p.y), p.y)

func _process(delta: float) -> void:
	if preview_dirty:
		preview_dirty = false
		if tool == Tool.CUT:
			_draw_edit()
		elif tool == Tool.LIFT and lift_pointer.is_finite():
			_preview_lift()
	_update_follow(delta / Engine.time_scale)
	if hint_time > 0.0:
		hint_time -= delta / Engine.time_scale
		if hint_time <= 0.0 and view == View.MANUAL:
			hud.set_hint(_instructions())

func _finish_session() -> void:
	if closing:
		return
	closing = true
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	for lift in resort.lifts:
		lift.set_process(false)
		for sound in lift.find_children("*", "AudioStreamPlayer3D", true, false):
			sound.stop()
			sound.stream = null
	await get_tree().create_timer(0.15, true, false, true).timeout
	get_tree().quit()

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	get_tree().auto_accept_quit = true

func _instructions() -> String:
	match tool:
		Tool.TERRAIN:
			return resort.feature_hint(feature_kind)
		Tool.CUT:
			if drafting:
				return "Click to add a bend. Drag a ring to move it. Cut trail when the line feels right."
			return "Click to place bends or draw on the snow. Short strokes connect to the lift stations."
		Tool.LIFT:
			if lift_anchor.is_finite():
				return "Click the other terminal to build. Hold Alt for precise placement. Esc cancels."
			return "Click two terminals or drag between them. Trees along the lift line will be cleared."
		Tool.VILLAGE:
			if resort.building_count() == 0:
				return "The waffle hut opens when a rider finishes your first cut run."
			if resort.village.occupied.size() == Village.PLOTS.size():
				return "Every village plot is in use."
			return "Choose a building, then click an open plot in the village."
	if resort.runs.is_empty():
		return "Left-drag to rotate · Right-drag to pan · Scroll or pinch to zoom · Cut a run to begin."
	if not resort.runs[-1].used:
		return "Your trail is open. Follow a rider down the new cut."
	if resort.highest_built < resort.unlocked:
		return Resort.TYPES[resort.unlocked] + " is available in Build a lift."
	return "Left-drag to rotate · Right-drag to pan · Scroll or pinch to zoom · Click a rider to follow."

func _refresh() -> void:
	var names := PackedStringArray()
	var index := 0
	match tool:
		Tool.TERRAIN:
			names = PackedStringArray(["Terrain park", "Summit extremes"])
			index = feature_kind
		Tool.CUT:
			for i in resort.lifts.size():
				var lift: Node = resort.lifts[i]
				var label: String = Resort.AREAS[lift.tier]
				if names.has(label):
					label += " · " + str(i + 1)
				names.append(label)
			index = selected_lift
		Tool.LIFT:
			for i in resort.unlocked + 1:
				names.append(Resort.TYPES[i])
			index = lift_type
		Tool.VILLAGE:
			for i in resort.building_count():
				names.append(Village.KINDS[i])
			index = building_type
	hud.set_tools(tool, names, index)
	hud.show_run_shapes(tool == Tool.CUT, run_shape)
	hud.place.text = Resort.AREAS[resort.highest_built] + "   ·   " + str(resort.lifts.size()) + (" lifts" if resort.lifts.size() != 1 else " lift")
	if view == View.MANUAL and hint_time <= 0.0:
		hud.set_hint(_instructions())

func _milestone(message: String) -> void:
	lift_type = resort.unlocked
	building_type = maxi(0, resort.building_count()-1)
	_refresh()
	if not dragging:
		_message(message, 7.0)

func _message(message: String, seconds := 4.5) -> void:
	hud.set_hint(message)
	hint_time = seconds

func set_tool(value: int) -> void:
	_stop_drag()
	_reset_camera()
	tool = clampi(value, Tool.EXPLORE, Tool.TERRAIN) as Tool
	if tool == Tool.LIFT:
		lift_type = resort.unlocked
	if tool == Tool.VILLAGE:
		building_type = maxi(0, resort.building_count()-1)
	hint_time = 0.0
	_refresh()
	_show_work_area()

func _select_choice(index: int) -> void:
	if tool == Tool.TERRAIN:
		feature_kind = index
	elif tool == Tool.CUT:
		selected_lift = index
		active_lift = resort.lifts[index]
	elif tool == Tool.LIFT:
		lift_type = index
	elif tool == Tool.VILLAGE:
		building_type = index
	_stop_drag()
	_reset_camera()
	hint_time = 0.0
	_refresh()
	_show_work_area()

func _select_shape(index: int) -> void:
	run_shape = clampi(index, 0, 2)
	if tool == Tool.CUT:
		_stop_drag()
		_reset_camera()
		_refresh()
		_show_work_area()

func _show_work_area() -> void:
	if tool == Tool.CUT:
		var path := resort.suggestion(selected_lift, run_shape)
		_work_camera(path, 24.0)
	elif tool == Tool.LIFT:
		_work_camera(PackedVector2Array([mountain.station_base(lift_type), mountain.station_top(lift_type)]), 34.0)
	elif tool == Tool.TERRAIN:
		var points := PackedVector2Array()
		var sites := resort.feature_sites(feature_kind)
		for site in sites:
			for jump in site.jumps:
				points.append(jump.approach)
				points.append(jump.landing)
				points.append(jump.point)
		if feature_kind == 1:
			# The ridge is permanent. It remains visible both before the tram
			# opens and after all the available cliff lines have been signed.
			if points.is_empty():
				for ledge in mountain.summit_ledges.sites:
					points.append(ledge.point)
					points.append(ledge.landing)
			# Looking across the slope shows the exposed wall and the landing.
			_work_camera(points,18.5,Vector3(0.82,0.53,1.0))
		elif not points.is_empty():
			_work_camera(points,27.0)
	elif tool == Tool.VILLAGE:
		_work_camera(PackedVector2Array(Village.PLOTS), 25.0)
	_show_guide()

func _work_camera(points: PackedVector2Array, minimum: float, direction := Vector3(0.27,0.95,1.0)) -> void:
	var work_basis := Basis.looking_at(-direction.normalized(),Vector3.UP)
	var bounds := AABB()
	for i in points.size():
		var p := work_basis.inverse() * _surface(points[i])
		bounds = AABB(p,Vector3.ZERO) if i == 0 else bounds.expand(p)
	var target := work_basis * bounds.get_center()
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := maxf(0.25,(viewport_size.x-mountain.map_inset)/maxf(1.0,viewport_size.y))
	var size := maxf(minimum,maxf(bounds.size.y,bounds.size.x/aspect)*1.48+4.0)
	size += bounds.size.z*tan(deg_to_rad(mountain.camera.fov)*0.5)
	zoom_ratio = minf(size/camera_wide_size,1.0)
	mountain.camera_rig.global_basis = work_basis
	mountain.camera_rig.global_position = target + work_basis.z*camera_focus_depth
	_set_camera_size(camera_wide_size * zoom_ratio)
	hud.wide.visible = true

func _feature_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for site in resort.feature_sites(feature_kind):
		points.append(site.point)
	return points

func _show_guide() -> void:
	guide.clear()
	if view != View.MANUAL:
		return
	if tool == Tool.TERRAIN:
		if feature_kind == 1:
			guide.summit_sites(mountain,resort.feature_sites(feature_kind))
		else:
			guide.sites(mountain, _feature_points())
	elif tool == Tool.CUT:
		var line := resort.suggestion(selected_lift,run_shape)
		guide.trail(mountain,line,false)
		hud.set_run_grade(preload("res://world/run_profile.gd").grade(line,mountain))
	elif tool == Tool.LIFT:
		guide.preview(mountain, mountain.station_base(lift_type), mountain.station_top(lift_type), true)
	elif tool == Tool.VILLAGE and resort.building_count() > 0:
		var points := PackedVector2Array()
		for i in Village.PLOTS.size():
			if not resort.village.occupied.has(i):
				points.append(Village.PLOTS[i])
		guide.sites(mountain, points)

func _toggle_speed() -> void:
	slow = not slow
	Engine.time_scale = 0.4 if slow else 1.0
	hud.show_slow(slow)

func _set_camera_size(span: float) -> void:
	mountain.set_camera_span(span)

func _map_center() -> Vector2:
	return get_viewport().get_visible_rect().get_center() + Vector2(mountain.map_inset * 0.5,0)

func _resize_camera() -> void:
	mountain.map_inset = hud.map_inset()
	camera_wide_size = mountain.overview_size()
	_set_camera_size(camera_wide_size * zoom_ratio)

func _toggle_follow() -> void:
	if view == View.FOLLOWING or view == View.WAITING:
		_return_to_valley()
		return
	set_tool(Tool.EXPLORE)
	for i in range(resort.runs.size()-1,-1,-1):
		var run := resort.runs[i]
		if run.lift == selected_lift and not run.used:
			awaiting_run = run.id
			break
	view = View.WAITING
	hud.follow.text = "End follow"
	if awaiting_run >= 0:
		_work_camera(PackedVector2Array([active_lift.run_start()]), 13.0)
		hud.set_hint("Watching the upper station for the first rider on your cut…")
	else:
		hud.set_hint("Waiting for a rider at the upper station…")

func _lock_on(skier: Node3D) -> void:
	guide.clear()
	hint_time = 0.0
	subject = skier
	subject.set_followed(true)
	view = View.FOLLOWING
	follow_ratio = 8.8 / camera_wide_size
	var side := 1.0 if skier.global_position.x <= mountain.base_point.x else -1.0
	var toward_camera := Vector3(0.20,0.51,1.0).normalized().rotated(Vector3.UP, deg_to_rad(19.0) * side)
	toward_camera.y += 0.14
	follow_basis = Basis.looking_at(-toward_camera.normalized(), Vector3.UP)
	hud.follow.text = "End follow"
	hud.wide.visible = true
	var discipline := "snowboarder" if skier.is_snowboarder else "skier"
	hud.set_hint("Following a " + discipline + (" on your cut run" if skier.used_cut_run else "") + "   ·   Space for slow motion")

func _release_subject() -> void:
	awaiting_run = -1
	if is_instance_valid(subject):
		subject.set_followed(false)
	subject = null

func _return_to_valley() -> void:
	_release_subject()
	view = View.RETURNING
	hud.follow.text = "Follow a rider"
	hud.set_hint(_instructions())

func _follow_candidate(lift: Node) -> Node3D:
	for i in range(lift._skiers.size()-1,-1,-1):
		var rider: Node3D = lift._skiers[i]
		if not rider.is_queued_for_deletion() and (awaiting_run < 0 or rider.cut_run_id == awaiting_run):
			return rider
	return null

func _update_follow(real_delta: float) -> void:
	if view == View.MANUAL:
		return
	if view == View.WAITING:
		var rider := _follow_candidate(active_lift)
		if rider == null and awaiting_run < 0:
			for lift in resort.lifts:
				if lift != active_lift:
					rider = _follow_candidate(lift)
					if rider != null: break
		if rider != null:
			_lock_on(rider)
		if view == View.WAITING:
			return
	var rig: Node3D = mountain.camera_rig
	var pivot := rig.global_position - rig.global_basis.z * camera_focus_depth
	var goal := camera_wide_position - camera_wide_basis.z * camera_focus_depth
	var goal_basis := camera_wide_basis
	var target_ratio := 1.0
	if view == View.FOLLOWING:
		if not is_instance_valid(subject) or subject.is_queued_for_deletion():
			_return_to_valley()
		else:
			goal = subject.global_position - subject.global_basis.z * 0.9 + Vector3.UP * 0.35
			goal_basis = follow_basis
			target_ratio = follow_ratio
	var k := 1.0 - exp(-real_delta * 3.5)
	rig.global_basis = rig.global_basis.slerp(goal_basis, k).orthonormalized()
	rig.global_position = pivot.lerp(goal, k) + rig.global_basis.z * camera_focus_depth
	zoom_ratio = lerpf(zoom_ratio, target_ratio, k)
	_set_camera_size(camera_wide_size * zoom_ratio)
	if view == View.RETURNING and zoom_ratio > 0.997:
		_reset_camera()

func _wide() -> void:
	set_tool(Tool.EXPLORE)

func _reset_camera() -> void:
	_release_subject()
	view = View.MANUAL
	hud.follow.text = "Follow a rider"
	mountain.camera_rig.global_position = camera_wide_position
	mountain.camera_rig.global_basis = camera_wide_basis
	camera_wide_size = mountain.overview_size()
	_set_camera_size(camera_wide_size)
	zoom_ratio = 1.0
	hud.wide.visible = false

func _zoom(factor: float, screen_pos: Vector2) -> void:
	if dragging:
		return
	if view == View.FOLLOWING:
		follow_ratio = clampf(follow_ratio * factor, 5.3 / camera_wide_size, 16.0 / camera_wide_size)
		return
	if view != View.MANUAL:
		return
	var new_ratio := clampf(zoom_ratio * factor, 12.0 / camera_wide_size, 1.0)
	if is_equal_approx(new_ratio, 1.0):
		zoom_ratio = 1.0
		_set_camera_size(camera_wide_size)
		mountain.camera_rig.global_position = mountain.VIEW_CENTER + mountain.camera_rig.global_basis.z * camera_focus_depth
		hud.wide.visible = not mountain.camera_rig.global_basis.is_equal_approx(camera_wide_basis)
		return
	var anchor = mountain.pick_ground(screen_pos)
	var pivot: Vector3 = mountain.camera_rig.global_position - mountain.camera_rig.global_basis.z * camera_focus_depth
	var target := pivot
	if anchor != null:
		target = _surface(anchor)
	else:
		var plane := Plane(mountain.camera_rig.global_basis.z,pivot)
		var intersection = plane.intersects_ray(mountain.camera.project_ray_origin(screen_pos),mountain.camera.project_ray_normal(screen_pos))
		if intersection != null:
			target = intersection
	mountain.camera_rig.global_position += (target-pivot)*(1.0-new_ratio/zoom_ratio)
	zoom_ratio = new_ratio
	_set_camera_size(camera_wide_size * zoom_ratio)
	hud.wide.visible = true

func _input(event: InputEvent) -> void:
	if map_button != MOUSE_BUTTON_NONE:
		if event is InputEventMouseMotion:
			_move_map(event.position)
		elif event is InputEventMouseButton and not event.pressed and event.button_index == map_button:
			_finish_map(event.position)
		elif not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			return
		get_viewport().set_input_as_handled()
	elif dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag(event.position)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _toggle_speed()
			KEY_M:
				if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
					return
				_toggle_mute()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT:
				if event.meta_pressed or event.ctrl_pressed or event.alt_pressed:
					return
				var zoom_out: bool = event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT
				_zoom(1.0 / ZOOM_STEP if zoom_out else ZOOM_STEP, _map_center())
			KEY_R: _wide()
			KEY_F: _toggle_follow()
			KEY_ESCAPE:
				if dragging or drafting or lift_anchor.is_finite():
					_stop_drag()
					_show_guide()
				else:
					_wide()
			KEY_BACKSPACE:
				if not drafting: return
				_undo_bend()
			KEY_ENTER, KEY_KP_ENTER:
				if not drafting: return
				_open_draft()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5: set_tool(event.keycode - KEY_1)
			_: return
	elif event is InputEventPanGesture:
		# macOS sends a two-finger scroll as a pan gesture with fractional deltas.
		if absf(event.delta.y) <= absf(event.delta.x):
			return
		_zoom(pow(ZOOM_STEP, -event.delta.y), event.position)
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf(event.factor, 0.01), event.position)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var dir := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
					_zoom(pow(ZOOM_STEP, dir * maxf(event.factor, 0.15)), event.position)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					precise_terminal = event.alt_pressed
					_begin_drag(event.position, event.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if dragging:
						_stop_drag()
						_show_guide()
					_begin_map(event.position,MOUSE_BUTTON_RIGHT,true)
			_: return
	elif event is InputEventMouseMotion and ((dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT) or lift_anchor.is_finite()):
		precise_terminal = event.alt_pressed
		_update_drag(event.position)
	else:
		return
	get_viewport().set_input_as_handled()

func _skier_at(screen_pos: Vector2) -> Node3D:
	var nearest: Node3D
	var radius := 15.0
	for lift in resort.lifts:
		for skier in lift.get_node("Skiers").get_children():
			if skier.is_queued_for_deletion():
				continue
			var chest: Vector3 = skier.global_position + Vector3.UP * 0.48
			var dist: float = mountain.camera.unproject_position(chest).distance_to(screen_pos)
			if dist < radius:
				radius = dist
				nearest = skier
	return nearest

func _station_snap(point: Vector2, target: Vector2) -> Vector2:
	if precise_terminal:
		return point
	var pixels: float = mountain.camera.unproject_position(_surface(point)).distance_to(mountain.camera.unproject_position(_surface(target)))
	return target if pixels <= 10.0 else point

func _snap(point: Vector2, target: Vector2) -> Vector2:
	var radius := clampf(mountain.camera.size * 0.074, 1.55, 5.0)
	return target if point.distance_to(target) < radius else point

func _begin_drag(screen_pos: Vector2, pan := false) -> void:
	if view != View.MANUAL:
		_return_to_valley()
		return
	drag_origin = screen_pos
	if tool == Tool.EXPLORE:
		_begin_map(screen_pos,MOUSE_BUTTON_LEFT,pan)
		return
	if tool == Tool.TERRAIN:
		_select_feature_at(screen_pos)
		return
	var hit = mountain.pick_ground(screen_pos)
	if hit == null:
		return
	drag_base = hit
	if tool == Tool.VILLAGE:
		if resort.building_count() > 0:
			var plot := resort.village.nearest_plot(hit)
			if resort.add_building(building_type, plot):
				_message(Village.KINDS[building_type] + " is open.")
				_show_guide()
			else:
				_message("Choose an open plot marked with a ring.")
		return
	if tool == Tool.CUT:
		var start: Vector2 = active_lift.run_start()
		editing_bend = -1
		if drafting:
			for i in bends.size():
				var projected: Vector2 = mountain.camera.unproject_position(_surface(bends[i]))
				if projected.distance_to(screen_pos) < 12.0:
					editing_bend = i
					break
		var at_start := _station_snap(hit,start) == start if drafting else _snap(hit,start) == start
		if at_start:
			editing_bend = -1
			stroke = PackedVector2Array([start])
		hud.set_run_grade("")
	elif tool == Tool.LIFT:
		drag_base = lift_anchor if lift_anchor.is_finite() else _station_snap(hit,mountain.station_base(lift_type))
	dragging = true

func _select_feature_at(screen_pos: Vector2) -> void:
	var candidate := {}
	var radius := clampf(1.65 * get_viewport().get_visible_rect().size.y / mountain.camera.size,12.0,38.0)
	for site in resort.feature_sites(feature_kind):
		var mark := _surface(site.point)
		if feature_kind == 1:
			mark.y = float(site.jumps[0].lip_height) + 0.65
		var distance: float = mountain.camera.unproject_position(mark).distance_to(screen_pos)
		if distance < radius:
			candidate = site
			radius = distance
	if candidate.is_empty():
		_message(resort.feature_hint(feature_kind))
		return
	var issue := resort.add_feature(feature_kind,candidate.run,candidate.get("ledge_id",""))
	if issue.is_empty():
		selected_lift = resort.runs[candidate.run].lift
		active_lift = resort.lifts[selected_lift]
	_show_guide()
	var opened := "Terrain park open." if feature_kind == 0 else "%s is open." % candidate.get("name","Summit line")
	_message(opened if issue.is_empty() else issue)

func _begin_map(screen_pos: Vector2, button: MouseButton, pan: bool) -> void:
	map_button = button
	shift_pan = pan
	tapped_skier = _skier_at(screen_pos) if not pan else null
	drag_origin = screen_pos
	dragging = true
	moved_map = false
	_capture_map_pose()

func _capture_map_pose() -> void:
	drag_basis = mountain.camera_rig.global_basis
	pan_start = mountain.camera_rig.global_position
	drag_depth = camera_focus_depth
	if zoom_ratio < 0.97:
		var hit = mountain.pick_ground(_map_center())
		if hit != null:
			drag_depth = (pan_start - _surface(hit)).dot(drag_basis.z)
	drag_pivot = pan_start - drag_basis.z * drag_depth

func _finish_map(screen_pos: Vector2) -> void:
	_move_map(screen_pos)
	var select_rider := map_button == MOUSE_BUTTON_LEFT and not shift_pan and not moved_map
	map_button = MOUSE_BUTTON_NONE
	dragging = false
	if select_rider and is_instance_valid(tapped_skier) and not tapped_skier.is_queued_for_deletion():
		_lock_on(tapped_skier)
	tapped_skier = null
	moved_map = false

func _move_map(screen_pos: Vector2) -> void:
	var movement := screen_pos - drag_origin
	if not moved_map and movement.length() < DRAG_THRESHOLD:
		return
	if not moved_map and view != View.MANUAL:
		_capture_map_pose()
		_release_subject()
		view = View.MANUAL
		hud.follow.text = "Follow a rider"
		hud.set_hint(_instructions())
	moved_map = true
	tapped_skier = null
	var rig: Node3D = mountain.camera_rig
	var camera: Camera3D = mountain.camera
	if shift_pan:
		var units := camera.size / maxf(1.0, get_viewport().get_visible_rect().size.y)
		var offset: Vector3 = drag_pivot - mountain.VIEW_CENTER
		var x := clampf(offset.dot(drag_basis.x) - movement.x * units, -125.0, 125.0)
		var y := clampf(offset.dot(drag_basis.y) + movement.y * units, -88.0, 88.0)
		rig.global_position = pan_start + drag_basis.x * (x - offset.dot(drag_basis.x)) + drag_basis.y * (y - offset.dot(drag_basis.y))
	else:
		var yaw := atan2(drag_basis.z.x, drag_basis.z.z) - movement.x * 0.006
		var pitch := clampf(asin(drag_basis.z.y) + movement.y * 0.0045, deg_to_rad(12), deg_to_rad(69))
		pitch = _clear_orbit_pitch(yaw,pitch)
		var back := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		rig.global_basis = Basis.looking_at(-back, Vector3.UP)
		rig.global_position = drag_pivot + back * drag_depth
		var old_size := camera.size
		camera_wide_size = mountain.overview_size()
		if zoom_ratio < 0.999:
			zoom_ratio = minf(old_size / camera_wide_size, 1.0)
		_set_camera_size(camera_wide_size * zoom_ratio)
	hud.wide.visible = true

# Raise a low overview orbit over the intervening ridge. The camera can still
# look up-valley from the base; passing behind the divide keeps the ski area in view.
func _clear_orbit_pitch(yaw: float, requested: float) -> float:
	if zoom_ratio < 0.5:
		return requested
	var direction := Vector2(sin(yaw),cos(yaw))
	var side := direction.orthogonal()
	var center := Vector2(drag_pivot.x,drag_pivot.z)
	var reach: float = mountain.camera_distance(mountain.camera.size)*cos(requested)
	var pitch := requested
	for step in range(1,29):
		var distance := reach*step/28.0
		for offset: float in [-0.11,0.0,0.11]:
			var at := center+direction*distance+side*distance*offset
			var ground: float = mountain.height_at(at.x,at.y)
			var clearance := smoothstep(12.0,90.0,distance)*8.0
			pitch = maxf(pitch,atan2(ground+clearance-drag_pivot.y,distance))
	return minf(pitch,deg_to_rad(69.0))

func _update_drag(screen_pos: Vector2) -> void:
	if tool == Tool.LIFT:
		if lift_anchor.is_finite() or screen_pos.distance_to(drag_origin) > 5.0:
			lift_pointer = screen_pos
			preview_dirty = true
		return
	var hit = mountain.pick_ground(screen_pos)
	if hit == null:
		return
	if tool == Tool.CUT:
		if editing_bend >= 0:
			bends[editing_bend] = hit
		elif not stroke.is_empty():
			if stroke[-1].distance_to(hit) < 0.55:
				return
			if drafting:
				drafting = false
				bends.clear()
				hud.show_draft(false,0)
			stroke.append(hit)
		elif not drafting and screen_pos.distance_to(drag_origin) >= DRAG_THRESHOLD:
			stroke = PackedVector2Array([drag_base,hit])
		else:
			return
		preview_dirty = true

func _terminals(point: Vector2) -> PackedVector2Array:
	# Accept either drawing direction. The uphill terminal is always the top.
	var base := drag_base
	var top := _station_snap(point,mountain.station_top(lift_type))
	if mountain.surface_height(top.x,top.y) < mountain.surface_height(base.x,base.y):
		top = _station_snap(drag_base,mountain.station_top(lift_type))
		base = _station_snap(point,mountain.station_base(lift_type))
	return PackedVector2Array([base,top])

func _preview_lift() -> void:
	var point = mountain.pick_ground(lift_pointer)
	if point == null: return
	var ends := _terminals(point)
	var issue := resort.placement_issue(ends[0],ends[1],lift_type)
	guide.preview(mountain,ends[0],ends[1],issue.is_empty())
	hud.set_hint(("Click to build " if lift_anchor.is_finite() else "Release to build ") + Resort.TYPES[lift_type] if issue.is_empty() else issue)

func _draft_line() -> PackedVector2Array:
	return TrailPlanner.through_bends(active_lift.run_start(),bends,active_lift.run_end())

func _draw_edit(valid := true) -> void:
	var line := _draft_line() if drafting else stroke
	if line.is_empty(): return
	guide.trail(mountain,line,true,active_lift.run_end(),bends,valid)
	hud.set_run_grade(preload("res://world/run_profile.gd").grade(line,mountain))

func _undo_bend() -> void:
	if not drafting or bends.is_empty(): return
	bends.remove_at(bends.size()-1)
	_show_draft()

func _show_draft() -> void:
	drafting = true
	var issue := resort._cut_issue(selected_lift,_draft_line(),false)
	hud.show_draft(true,bends.size(),issue.is_empty())
	hint_time = 0.0
	hud.set_hint(_instructions() if issue.is_empty() else issue+" Move a bend to adjust.")
	_draw_edit(issue.is_empty())

func _open_draft() -> void:
	if drafting:
		_open_trail(_draft_line())

func _open_trail(line: PackedVector2Array) -> void:
	var issue := resort.cut(selected_lift,line)
	if not issue.is_empty():
		if not drafting:
			bends = TrailPlanner.stroke_bends(line,active_lift.run_start(),active_lift.run_end())
			_show_draft()
		_message(issue+" Move a bend to adjust.")
		return
	var grade := preload("res://world/run_profile.gd").grade(line,mountain)
	_stop_drag()
	tool = Tool.EXPLORE
	_refresh()
	_message("%s trail open. Watch for the first tracks." % grade,6.0)

func _finish_drag(screen_pos: Vector2) -> void:
	dragging = false
	preview_dirty = false
	var hit = mountain.pick_ground(screen_pos)
	if hit == null:
		if drafting: _show_draft()
		else: _show_guide()
		_message("Finish the line on the mountain.")
		return
	if tool == Tool.CUT:
		var end: Vector2 = active_lift.run_end()
		if editing_bend >= 0:
			bends[editing_bend] = hit
			editing_bend = -1
			_show_draft()
		elif stroke.size() > 1 and screen_pos.distance_to(drag_origin) >= DRAG_THRESHOLD:
			if _snap(hit,end) != end or stroke[0] != active_lift.run_start():
				if stroke[-1].distance_to(hit) > 0.35: stroke.append(hit)
				# Sketching uphill describes the same piste in the other direction.
				if _surface(stroke[0]).y < _surface(stroke[-1]).y:
					stroke.reverse()
				bends = TrailPlanner.stroke_bends(stroke,active_lift.run_start(),end)
				stroke.clear()
				_show_draft()
				return
			if stroke[-1].distance_to(end) < 0.55: stroke[-1] = end
			else: stroke.append(end)
			_open_trail(stroke)
			stroke.clear()
		else:
			stroke.clear()
			if _station_snap(hit,end) != end and _station_snap(hit,active_lift.run_start()) != active_lift.run_start():
				if bends.is_empty() or bends[-1].distance_to(hit) > 0.55: bends.append(hit)
			_show_draft()
	elif tool == Tool.LIFT:
		if not lift_anchor.is_finite() and screen_pos.distance_to(drag_origin) < DRAG_THRESHOLD:
			lift_anchor = drag_base
			guide.preview(mountain,drag_base,drag_base,true)
			hud.set_hint(_instructions())
			return
		var ends := _terminals(hit)
		var issue := resort.placement_issue(ends[0],ends[1],lift_type)
		if not issue.is_empty():
			guide.preview(mountain,ends[0],ends[1],false)
			_message(issue)
			return
		if resort.place_lift(ends[0],ends[1],lift_type):
			selected_lift = resort.lifts.size()-1
			active_lift = resort.lifts[selected_lift]
			var built: String = Resort.TYPES[lift_type]
			set_tool(Tool.EXPLORE)
			guide.placed(mountain,ends[0],ends[1])
			_message(built+" is running. Cut a trail from its upper station.")

func _stop_drag() -> void:
	drafting = false
	bends.clear()
	editing_bend = -1
	preview_dirty = false
	lift_anchor = Vector2.INF
	lift_pointer = Vector2.INF
	hud.show_draft(false,0)
	map_button = MOUSE_BUTTON_NONE
	moved_map = false
	dragging = false
	tapped_skier = null
	stroke.clear()
	guide.clear()

func _focus_lost() -> void:
	if dragging:
		_stop_drag()
		_show_guide()
