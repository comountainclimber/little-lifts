extends SceneTree

const Resort := preload("res://demo/resort.gd")
const Mountain := preload("res://world/mountain.gd")
const RiderStyle := preload("res://skiing/rider_style.gd")
const RunProfile := preload("res://world/run_profile.gd")

class ProfileHill extends Node:
	func surface_height(x: float, _z: float) -> float:
		return x

var problems := PackedStringArray()

func _initialize() -> void:
	call_deferred("_check")

func expect(ok: bool, note: String) -> void:
	if not ok:
		problems.append(note)
		push_error(note)

func pointer(view: Window, p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	e.global_position = p
	view.push_input(e,true)

func trace(main: Node, line: PackedVector2Array) -> void:
	var camera: Camera3D = main.mountain.camera
	pointer(root,camera.unproject_position(main._surface(line[0])),true)
	for i in range(1, line.size()):
		var e := InputEventMouseMotion.new()
		e.position = camera.unproject_position(main._surface(line[i]))
		e.global_position = e.position
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e,true)
	pointer(root,camera.unproject_position(main._surface(line[-1])),false)

func bends(line: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(1, line.size()-1):
		if (line[i].x - line[i-1].x) * (line[i+1].x - line[i].x) < 0:
			result.append(line[i])
	return result

func run_route(lift: Node, terrain: Node, drawn: PackedVector2Array, variant: int) -> void:
	var checkpoints := bends(drawn)
	lift._first_tracks.assign([0])
	lift._start_descent(variant)
	var rider: Node = lift._skiers[-1]
	expect(rider.used_cut_run and rider.cut_run_id == 0, "Skier and boarder take the recorded freehand route")
	var reached := 0
	var last := Vector2(rider.position.x,rider.position.z)
	var distance := 0.0
	for tick in 7200:
		rider.step(1.0/60.0)
		var pos := Vector2(rider.position.x,rider.position.z)
		if reached < checkpoints.size() and pos.distance_to(checkpoints[reached]) < 2.15:
			reached += 1
		expect(terrain.route_clear(last,pos,0.09), "Skied path must stay inside its clearing")
		distance += last.distance_to(pos)
		last = pos
		if rider.is_queued_for_deletion():
			break
	expect(reached == checkpoints.size() and reached >= 3, "Rider visits the actual S-turn extrema in order")
	expect(distance > drawn[0].distance_to(drawn[-1]) * 1.13, "Rider follows the long traverses into the trees")
	expect(rider.is_queued_for_deletion() and last.distance_to(lift.run_end()) < 0.35, "Rider completes the run at the queue")

func _check() -> void:
	var profile := ProfileHill.new()
	var small_roll := PackedVector2Array([Vector2(5,0), Vector2(1,6), Vector2(1.76,9), Vector2(0,14)])
	var climb := PackedVector2Array([Vector2(5,0), Vector2(1,6), Vector2(3.1,14), Vector2(0,22)])
	expect(RunProfile.flows_downhill(small_roll,profile), "A real downhill entry carries riders over a small roll")
	expect(not RunProfile.flows_downhill(climb,profile), "A sustained uphill still rejects the route")
	profile.free()
	for shape in 3:
		var hill := Mountain.new()
		root.add_child(hill)
		var r := Resort.new()
		r.save_path = ""
		root.add_child(r)
		r.setup(hill)
		for tier in 3:
			if tier > 0:
				expect(r.place_lift(hill.station_base(tier),hill.station_top(tier),tier), "Open the next actual lift")
			if r.lifts.size() <= tier:
				break
			var line := r.suggestion(tier,shape)
			var issue := r.cut(tier,line)
			expect(issue.is_empty(), "Shape %d on tier %d should open: %s" % [shape,tier,issue])
			if not issue.is_empty():
				break
			if shape > 0:
				expect(bends(line).size() >= (3 if shape == 1 else 4), "Survey makes several cross-slope directional changes")
			r._skied(r.runs[-1].id, tier)
		r.free()
		hill.free()
	var main = load("res://demo/main.tscn").instantiate()
	main.resort.save_path = ""
	main.settings_path = OS.get_temp_dir().path_join("ll-runshape-preferences-%d" % OS.get_process_id())
	root.add_child(main)
	await process_frame
	main.set_tool(main.Tool.CUT)
	var line: PackedVector2Array = main.resort.suggestion(0,2)
	# Leave the Gentle arc guide selected and draw our own changing S-curves.
	# Offset the middle of each lobe by a different amount from the survey.
	for i in range(1,line.size()-1):
		var t := float(i) / (line.size()-1)
		line[i].x += sin(PI*t) * (1.55 * cos(t*TAU*2.0+0.34) + 0.74 * sin(t*TAU))
	trace(main,line)
	expect(main.resort.runs.size() == 1, "Freehand pointer strokes accept a custom S line independent of selected guide: " + main.hud.hint.text)
	if not main.resort.runs.is_empty():
		var captured: PackedVector2Array = main.active_lift._runs[0]
		expect(captured.size() > 8 and bends(captured).size() >= 3, "Actual pointer stroke records several turns")
		for variant in [0,RiderStyle.REGULAR_BOARDER]:
			run_route(main.active_lift,main.mountain,captured,variant)
		expect(main.resort.runs[0].used, "A completed freehand route credits first tracks")
	main.free()
	if problems.is_empty():
		print("PASS: nine surveyed shape/tier choices and independent freehand S turns, both rider disciplines reached every bend and returned to the lift")
	quit(0 if problems.is_empty() else 1)
