extends SceneTree

var failures: Array[String] = []

func expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func pointer(pos: Vector2, pressed: bool, shift := false, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	root.push_input(e, true)

func motion(pos: Vector2, mask := MOUSE_BUTTON_MASK_LEFT) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = mask
	root.push_input(e, true)

func swipe(pos: Vector2, delta: Vector2) -> void:
	var e := InputEventPanGesture.new()
	e.position = pos
	e.delta = delta
	root.push_input(e, true)

func pinch(pos: Vector2, factor: float) -> void:
	var e := InputEventMagnifyGesture.new()
	e.position = pos
	e.factor = factor
	root.push_input(e, true)

func zoom_key(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	root.push_input(e, true)

func run() -> void:
	var game = load("res://demo/main.tscn").instantiate()
	game.resort.save_path = ""
	game.settings_path = OS.get_temp_dir().path_join("little-lifts-inspection-%d.cfg" % OS.get_process_id())
	root.add_child(game)
	await process_frame
	await process_frame
	var m = game.mountain
	var camera: Camera3D = m.camera
	var original := camera.global_transform
	var center: Vector2 = game._map_center()
	expect(is_equal_approx(game.zoom_ratio, 1.0) and is_equal_approx(camera.size, m.overview_size()), "Opens at full overview")
	swipe(center, Vector2(0.08, -1.5))
	expect(game.zoom_ratio < 0.99, "Two-finger vertical scroll zooms in from the opening overview")
	var after_swipe: float = game.zoom_ratio
	swipe(center, Vector2(1, 0.01))
	expect(is_equal_approx(game.zoom_ratio, after_swipe), "A sideways swipe leaves the zoom steady")
	swipe(center, Vector2(0, 1.5))
	expect(is_equal_approx(game.zoom_ratio, 1.0), "Reversing the scroll returns to overview")
	pinch(center, 1.25)
	expect(is_equal_approx(game.zoom_ratio, 0.8), "Spreading two fingers zooms in")
	pinch(center, 0.8)
	expect(is_equal_approx(game.zoom_ratio, 1.0), "Pinching back out restores the overview")
	pointer(center, true, false, MOUSE_BUTTON_WHEEL_UP)
	expect(game.zoom_ratio < 0.99, "A mouse wheel still zooms in")
	pointer(center, true, false, MOUSE_BUTTON_WHEEL_DOWN)
	expect(is_equal_approx(game.zoom_ratio, 1.0), "A mouse wheel still zooms out")
	zoom_key(KEY_EQUAL)
	expect(game.zoom_ratio < 0.99, "The plus/equal key zooms the map in")
	zoom_key(KEY_MINUS)
	expect(is_equal_approx(game.zoom_ratio, 1.0), "The minus key zooms the map out")
	game._wide()
	var map := Rect2(Vector2(game.hud.map_inset(),0),root.get_visible_rect().size-Vector2(game.hud.map_inset(),0)).grow(-8.0)
	for tier in 3:
		for p: Vector2 in [m.station_base(tier),m.station_top(tier)]:
			expect(map.has_point(camera.unproject_position(game._surface(p))),"Every survey station opens in the map area")
	var bounds: AABB = m.get_node("Alpine basin").get_aabb()
	expect(bounds.size.x > 1700 and bounds.size.z > 1700, "The surrounding range continues on all four sides of the resort")
	pointer(center, true)
	motion(center + Vector2(250,40))
	pointer(center + Vector2(250,40), false)
	var rotated := camera.global_transform
	expect(rotated.basis.z.dot(original.basis.z) < 0.8 and game.view == game.View.MANUAL, "Left drag orbits the mountain")
	expect(camera.unproject_position(m.VIEW_CENTER).distance_to(center) < 1.0, "Resort stays at the center of the unobscured map")
	game._zoom(0.6, center)
	pointer(center, true, true)
	motion(center + Vector2(45,19))
	pointer(center + Vector2(45,19), false)
	expect(camera.global_basis.is_equal_approx(rotated.basis) and camera.global_position.distance_to(rotated.origin) > 1.0, "Shift-left drag pans the rotated view")
	expect(game.resort.lifts.size() == 1 and game.resort.journal.is_empty(), "Navigation cannot build a lift or modify the resort")
	game._zoom(10.0, center)
	expect(is_equal_approx(camera.size, m.overview_size()) and camera.global_basis.is_equal_approx(rotated.basis), "Zooming all the way out keeps the chosen angle")
	game._wide()
	expect(camera.global_transform.is_equal_approx(original), "Whole mountain restores opening position and orientation")
	game.set_tool(game.Tool.CUT)
	var pre_pan := camera.global_transform
	var line: PackedVector2Array = game.resort.suggestion(0)
	var at := camera.unproject_position(game._surface(line[0]))
	pointer(at,true)
	expect(game.dragging and not game.stroke.is_empty(),"A left stroke starts on the survey")
	pointer(at,true,false,MOUSE_BUTTON_RIGHT)
	motion(at+Vector2(38,29),MOUSE_BUTTON_MASK_RIGHT)
	pointer(at+Vector2(38,29),false,false,MOUSE_BUTTON_RIGHT)
	pointer(at+Vector2(38,29),false)
	expect(game.tool == game.Tool.CUT and not game.dragging and game.stroke.is_empty() and game.resort.journal.is_empty(),"Right drag cancels the current stroke and keeps the tool")
	expect(camera.global_position.distance_to(pre_pan.origin)>0.5 and camera.global_basis.is_equal_approx(pre_pan.basis),"Right-drag pans within a building tool")
	pointer(center,true,false,MOUSE_BUTTON_RIGHT)
	game._focus_lost()
	expect(not game.dragging and game.map_button == MOUSE_BUTTON_NONE,"Focus loss releases the camera drag")
	game._wide()
	var stable := camera.global_transform
	pointer(center,true,false,MOUSE_BUTTON_RIGHT)
	motion(center+Vector2(2,1),MOUSE_BUTTON_MASK_RIGHT)
	pointer(center+Vector2(2,1),false,false,MOUSE_BUTTON_RIGHT)
	expect(camera.global_transform.is_equal_approx(stable) and game.view == game.View.MANUAL,"A right click with slight jitter leaves the camera steady")
	var w = m.weather
	w.set_process(false)
	expect(w.phase == w.Phase.CLEAR and w.snowfall == 0, "Startup is clear")
	for i in 2:
		w.advance(w.duration - w.elapsed + 0.01)
		expect(w.phase == w.Phase.CLOUDING and w.cloud_cover < 0.001, "Cloud bank rolls in continuously")
		w.advance(w.duration * 0.93)
		expect(w.cloud_cover > 0.91 and w.snowfall > 0.35, "The sky changes before snow builds")
		w.advance(w.duration - w.elapsed + 0.01)
		expect(w.phase == w.Phase.SNOWING and w._flakes.visible, "Flakes fall in the snow phase")
		w.advance(w.duration - w.elapsed + 0.01)
		expect(w.phase == w.Phase.CLEARING and w.cloud_cover > 0.98, "Clearing starts overcast")
		w.advance(w.duration - w.elapsed + 0.01)
		expect(w.phase == w.Phase.CLEAR and is_zero_approx(w.snowfall) and not w._flakes.visible, "Flurries stop and light returns")
	print("Opening camera span ", camera.size, "; summit tram horizontal span ",m.station_base(2).distance_to(m.station_top(2)),"; forest trees ",m.scenery.trees.size())
	game.free()
	if failures.is_empty():
		print("PASS: map framing and continuous terrain, orbit, pan, zoom, reset, construction isolation, and two complete weather cycles")
	quit(0 if failures.is_empty() else 1)
