extends SceneTree

var problems: Array[String] = []
var demo: Node

func expect(good: bool, message: String) -> void:
	if not good:
		problems.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("check")

func point(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.global_position = at
	e.pressed = pressed
	root.push_input(e, true)

func click(b: Button) -> void:
	var at := b.get_global_rect().get_center()
	point(at, true)
	point(at, false)
	await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

func select_option(b: OptionButton, index: int) -> void:
	await click(b)
	var popup := b.get_popup()
	expect(popup.visible, "%s opens on click" % b.accessibility_name)
	if not popup.visible:
		return
	# Normal top-level input is forwarded to the focused popup window.
	for step in popup.item_count:
		if popup.get_focused_item() == index:
			break
		key(KEY_DOWN)
	key(KEY_ENTER)
	await process_frame
	expect(not popup.visible and b.selected == index, "%s commits the requested item" % b.accessibility_name)

func map_click(p: Vector2) -> void:
	var screen: Vector2 = demo.mountain.camera.unproject_position(demo._surface(p))
	point(screen,true)
	point(screen,false)

func plan_trail() -> void:
	var r = demo.resort
	var hill = demo.mountain
	var line: PackedVector2Array = r.suggestion(0,0)
	var count: int = hill.scenery._felled.size()
	var pin := line[line.size()/2]+Vector2(0.25,0.0)
	map_click(pin)
	expect(demo.drafting and demo.bends.size() == 1 and demo.bends[0].distance_to(pin) < 0.15,"Clicking away from a terminal starts a custom trail through that exact point")
	map_click(line[line.size()*3/4])
	key(KEY_BACKSPACE)
	expect(demo.bends.size() == 1 and r.runs.is_empty() and hill.scenery._felled.size() == count,"Undo edits the survey before any trees are cut")
	key(KEY_ESCAPE)
	expect(not demo.drafting and r.runs.is_empty(),"Escape cancels the entire survey")
	# Sketch only the middle of the run. Its station links appear in the
	# draft, and the forest stays standing until explicitly committed.
	var part := line.slice(4,line.size()-4)
	point(hill.camera.unproject_position(demo._surface(part[0])),true)
	for p in part:
		var event := InputEventMouseMotion.new()
		event.position = hill.camera.unproject_position(demo._surface(p))
		event.global_position = event.position
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event,true)
	point(hill.camera.unproject_position(demo._surface(part[-1])),false)
	var draft: PackedVector2Array = demo._draft_line()
	expect(demo.drafting and demo.bends.size() >= 1 and draft[0] == demo.active_lift.run_start() and draft[-1] == demo.active_lift.run_end(),"An off-terminal stroke becomes a connected editable draft")
	expect(r.runs.is_empty() and hill.scenery._felled.size() == count,"A partial stroke remains a preview")
	key(KEY_ESCAPE)
	for i in [0.24,0.48,0.72]:
		map_click(line[roundi((line.size()-1)*i)])
	var middle: Vector2 = demo.bends[1]
	var changed := middle+Vector2(0.8,0.1)
	var from: Vector2 = hill.camera.unproject_position(demo._surface(middle))
	var to: Vector2 = hill.camera.unproject_position(demo._surface(changed))
	point(from,true)
	var drag := InputEventMouseMotion.new()
	drag.position = to
	drag.global_position = to
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag,true)
	point(to,false)
	expect(demo.bends.size() == 3 and demo.bends[1].distance_to(changed) < 0.15,"Grabbing a bend moves that point without adding a new one")
	var planned: PackedVector2Array = demo._draft_line()
	await click(demo.hud.finish_trail)
	expect(r.runs.size() == 1 and r.journal[-1].line == planned,"Cut trail opens exactly the previewed route")

func draw_survey() -> void:
	var path: PackedVector2Array = demo.resort.suggestion(0, demo.run_shape)
	var points := PackedVector2Array()
	for p in path:
		points.append(demo.mountain.camera.unproject_position(demo._surface(p)))
	point(points[0], true)
	for pos in points:
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
	point(points[-1], false)

func check() -> void:
	demo = load("res://demo/main.tscn").instantiate()
	demo.resort.save_path = ""
	demo.settings_path = OS.get_temp_dir().path_join("terrain-ui-%d.cfg" % OS.get_process_id())
	root.add_child(demo)
	await process_frame
	await process_frame
	expect(demo.hud._grade_key.is_visible_in_tree() and demo.hud._grade_labels.size() == 3,"The opening rail shows a labeled trail key")
	await click(demo.hud.tools[1])
	await select_option(demo.hud.shape, 1)
	var displayed_grade := preload("res://world/run_profile.gd").grade(demo.resort.suggestion(0,1),demo.mountain)
	expect(displayed_grade == "Easy" and demo.hud._grade_flags[0].is_visible_in_tree(),"Village Hill S turns show a green-circle grade in the sidebar")
	expect(demo.tool == demo.Tool.CUT and demo.run_shape == 1, "The S turns selector updates the active survey")
	var r = demo.resort
	var m = demo.mountain
	draw_survey()
	expect(r.runs.size() == 1, "S turns can be cut by drawing the displayed survey")
	await click(demo.hud.tools[4])
	await select_option(demo.hud.choice, 1)
	expect(demo.feature_kind == 1 and r.feature_sites(1).is_empty() and "tram" in demo.hud.hint.text, "Summit terrain needs the tram")
	expect(demo.zoom_ratio < 0.7 and not demo.guide.visible,"The actual summit geology is visible before the tram without offering a build")
	await select_option(demo.hud.choice, 0)
	var sites: Array = r.feature_sites(0)
	# Some S-shaped runs have no straight double-jump site. Cut a separate
	# eligible gentle run to exercise the same Terrain entry point.
	if sites.is_empty():
		await click(demo.hud.tools[1])
		await select_option(demo.hud.shape, 0)
		draw_survey()
		expect(r.runs.size() == 2, "A gentle cut can be drawn for a park site")
		await click(demo.hud.tools[4])
		sites = r.feature_sites(0)
	expect(not sites.is_empty(), "Surveyed sites become available in the Terrain tool")
	if not sites.is_empty():
		var at: Vector2 = m.camera.unproject_position(demo._surface(sites[0].point))
		point(at, true)
		point(at, false)
		expect(r.runs[sites[0].run].features.get(0, []).size() == 2, "Clicking a marked park creates both kickers")
	for tier in range(1,3):
		r._skied(r.runs[-1].id,r.runs[-1].lift)
		expect(r.place_lift(m.station_base(tier),m.station_top(tier),tier),"Build the lift serving the next survey")
		expect(r.cut(tier,r.suggestion(tier)).is_empty(),"Open the next marked run")
	await click(demo.hud.tools[4])
	await select_option(demo.hud.choice,1)
	expect(demo.hud.choice.get_item_icon(0) != demo.hud.choice.get_item_icon(1),"Each terrain option has its own ski-area sign")
	var extremes: Array = r.feature_sites(1)
	expect(extremes.size() >= 2,"The summit offers multiple marked rocks")
	if extremes.size() >= 2:
		var selected: Dictionary = extremes[-1]
		var target := Vector3(selected.point.x,selected.jumps[0].lip_height+0.65,selected.point.y)
		var screen: Vector2 = m.camera.unproject_position(target)
		point(screen,true)
		point(screen,false)
		expect(r.journal[-1].get("ledge_id","") == selected.ledge_id,"Clicking the elevated marker opens that exact ledge")
		expect(selected.name in demo.hud.hint.text,"The sidebar names the opened cliff")
	demo.free()
	demo = load("res://demo/main.tscn").instantiate()
	demo.resort.save_path = ""
	demo.settings_path = OS.get_temp_dir().path_join("terrain-ui-%d.cfg" % OS.get_process_id())
	root.add_child(demo)
	await process_frame
	await click(demo.hud.tools[1])
	await plan_trail()
	demo.free()
	if problems.is_empty():
		print("PASS: clickable bends, dragging, undo, cancel, preview/commit, freehand S turns, summit preview, two-jump park and named cliff selection")
	quit(0 if problems.is_empty() else 1)
