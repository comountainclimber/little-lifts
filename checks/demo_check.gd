extends SceneTree

const Village := preload("res://world/village.gd")
var problems: Array[String] = []
var main: Node
var save_file := OS.get_temp_dir().path_join("little-lifts-test-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()])

func _initialize() -> void:
	call_deferred("_check")

func expect(good: bool, message: String) -> void:
	if not good:
		problems.append(message)
		push_error(message)

func launch() -> void:
	main = load("res://demo/main.tscn").instantiate()
	main.resort.save_path = save_file
	main.settings_path = save_file + ".cfg"
	root.add_child(main)
	await process_frame
	await process_frame

func mouse(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	root.push_input(e, true)

func motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)

func screen(p: Vector2) -> Vector2:
	return main.mountain.camera.unproject_position(main._surface(p))

func button(b: Button) -> void:
	var pos := b.get_global_rect().get_center()
	mouse(pos, true)
	mouse(pos, false)
	await process_frame

func press_m(echo := false) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	key.echo = echo
	root.push_input(key, true)
	key.pressed = false
	key.echo = false
	root.push_input(key, true)

func drag_line(points: PackedVector2Array) -> void:
	mouse(screen(points[0]), true)
	for i in range(1, points.size()):
		motion(screen(points[i]))
	mouse(screen(points[-1]), false)
	await process_frame

func _check() -> void:
	await launch()
	var master := AudioServer.get_bus_index(&"Master")
	expect(not AudioServer.is_bus_mute(master) and main.hud.mute.text == "Mute", "First launch starts with sound on")
	await button(main.hud.mute)
	expect(AudioServer.is_bus_mute(master) and main.hud.mute.text == "Unmute", "Clicking Mute silences the master bus")
	press_m(true)
	expect(AudioServer.is_bus_mute(master), "Holding M must not repeatedly toggle sound")
	press_m()
	expect(not AudioServer.is_bus_mute(master) and main.hud.mute.text == "Mute", "M restores sound")
	press_m()
	var m = main.mountain
	var r = main.resort
	expect(r.lifts.size() == 1 and r.unlocked == 0 and r.building_count() == 0, "Opening resort needs a single working chair and a first trail to cut")
	var first = main.active_lift
	var jacket = first.get_node("Skiers").get_child(1)
	var at: Vector2 = m.camera.unproject_position(jacket.global_position + Vector3.UP * 0.48)
	mouse(at,true)
	mouse(at,false)
	expect(main.subject == jacket, "Click to follow the opening snowboarder")
	main._wide()
	main._toggle_speed()
	expect(Engine.time_scale < 1.0, "Slow motion changes simulation time")
	main._toggle_speed()
	expect(not r.place_lift(m.station_base(2), m.station_top(2), 2), "The summit tram requires lower mountain progression")
	expect(not r.add_building(2,0), "A day lodge needs a larger resort")
	var reach0: float = m.station_base(0).distance_to(m.station_top(0))
	expect(m.station_base(2).distance_to(m.station_top(2)) > 3.6 * reach0, "The high ridge must be significantly farther from the village")
	for tier in 3:
		if tier > 0:
			await button(main.hud.tools[2])
			expect(main.tool == main.Tool.LIFT and main.lift_type == tier, "Build tool selects newly unlocked lift")
			var bad := PackedVector2Array([m.station_base(tier), m.station_base(tier)+Vector2(2.5,-3)])
			await drag_line(bad)
			expect(r.lifts.size() == tier, "A lift shorter than its station spacing preserves the resort")
			var stations := PackedVector2Array([m.station_base(tier),m.station_top(tier)])
			if tier == 2: stations.reverse()
			await drag_line(stations)
			expect(r.lifts.size() == tier + 1, "Drag builds the next lift on surveyed line: %s" % main.hud.hint.text)
			if r.lifts.size() != tier + 1:
				break
		await button(main.hud.tools[1])
		expect(main.tool == main.Tool.CUT, "Cut tool receives normal HUD clicks")
		var route: PackedVector2Array = r.suggestion(tier)
		expect(not m.cut_issue(route).length(), "Surveyed line is viable before construction")
		var before: int = r.runs.size()
		var uphill := route.duplicate()
		uphill.reverse()
		await drag_line(uphill)
		expect(r.runs.size() == before, "An uphill stroke must not clear the forest")
		await drag_line(route)
		expect(r.runs.size() == before + 1, "Pointer stroke should create a run on tier %d: %s" % [tier, main.hud.hint.text])
		if r.runs.size() == before:
			break
		expect(not r.runs[-1].used and r.unlocked == tier, "Lifts unlock when a skier actually completes the route")
		if tier == 0:
			main._toggle_follow()
			expect(main.awaiting_run == r.runs[-1].id, "Follow waits for the first skier on the cut")
			for i in 1200:
				main.active_lift._process(1.0/60)
				main._update_follow(1.0/60)
				if main.subject != null:
					break
			expect(is_instance_valid(main.subject) and main.subject.used_cut_run, "The first-tracks camera follows a guest on the player trail")
			main._wide()
		var boarded := {}
		var returned := {}
		var lift = r.lifts[tier]
		lift.boarded.connect(func(guest): boarded[guest] = true)
		lift.returned.connect(func(guest): returned[guest] = true)
		for second in 130:
			for tick in 30:
				lift._process(1.0/30.0)
				for track in lift.get_node("Tracks").get_children():
					if track.is_processing() and not track.is_queued_for_deletion():
						track._process(1.0/30.0)
			await process_frame
			if r.runs[-1].used and boarded.size() == 8 and returned.size() == 8:
				break
		expect(r.runs[-1].used and r.unlocked == mini(tier+1,2), "A completed player trail opens the next tier")
		expect(boarded.size() == 8 and returned.size() == 8, "All eight guests must board and return on this lift")
		expect(lift.get_node("Tracks").get_child_count() <= 24, "Trail memory must stay bounded")
		await button(main.hud.tools[3])
		expect(main.tool == main.Tool.VILLAGE and main.building_type == tier, "Village offers the unlocked building")
		var plot_pos := screen(Village.PLOTS[tier])
		mouse(plot_pos,true)
		mouse(plot_pos,false)
		expect(r.village.occupied.get(tier,-1) == tier, "Clicking a marked lot adds the selected building")
		expect(not r.add_building(0,tier), "Occupied buildings cannot be overwritten")
	expect(r.lifts[0] == first, "The original chair continues operating")
	if r.lifts.size() == 3:
		main.set_tool(main.Tool.EXPLORE)
		main._toggle_follow()
		for i in 1800:
			if main.subject != null: break
			for line in r.lifts: line._process(1.0/60)
			main._update_follow(1.0/60)
		for i in 75:
			main._update_follow(1.0/60.0)
		expect(is_instance_valid(main.subject) and m.camera.size < main.camera_wide_size * 0.2,"Follow shows a guest on the expanded mountain")
		for i in 3000:
			for line in r.lifts: line._process(1.0/60)
			main._update_follow(1.0/60.0)
		expect(main.view == main.View.MANUAL, "The camera returns after a summit descent")
	var events: Array = r.journal.duplicate(true)
	main.queue_free()
	await process_frame
	AudioServer.set_bus_mute(master, false)
	await launch()
	expect(AudioServer.is_bus_mute(master) and main.hud.mute.text == "Unmute", "Reopening the resort restores mute")
	await button(main.hud.mute)
	var prefs := ConfigFile.new()
	expect(prefs.load(main.settings_path) == OK and prefs.get_value("audio", "muted", true) == false and not AudioServer.is_bus_mute(master), "Unmute restores and saves sound")
	expect(main.resort.journal == events and main.resort.lifts.size() == 3 and main.resort.village.occupied.size() == 3, "Save and reopen restores the forest, finished runs, all lifts and every chosen plot")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(save_file)
	DirAccess.remove_absolute(save_file + ".cfg")
	if problems.is_empty():
		print("PASS: three lifts, three real player trails, skier and snowboarder cycles, village placement, camera controls, sound controls and save/reopen")
	quit(0 if problems.is_empty() else 1)
