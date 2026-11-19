extends SceneTree

const Mountain := preload("res://world/mountain.gd")
const Resort := preload("res://demo/resort.gd")
const Feature := preload("res://world/slope_feature.gd")

var failed := false
var hill: Node
var resort: Node

func _initialize() -> void:
	call_deferred("_check")

func expect(ok: bool, note: String) -> void:
	if not ok:
		failed = true
		push_error(note)

func _open(file := "") -> void:
	hill = Mountain.new()
	root.add_child(hill)
	resort = Resort.new()
	resort.save_path = file
	root.add_child(resort)
	resort.setup(hill)

func _close() -> void:
	resort.free()
	hill.free()

func _reach(ledge_id: String, top: Vector2, bias: float, join_z: float, guide_shape: int, base := Vector2(-24,18), around_tower := 0.0) -> void:
	_open()
	for tier in 2:
		if tier > 0:
			expect(resort.place_lift(hill.station_base(tier),hill.station_top(tier),tier),"Lower mountain still opens")
		expect(resort.cut(tier,resort.suggestion(tier)).is_empty(),"Build supporting trail")
		resort._skied(resort.runs[-1].id,tier)
	expect(resort.place_lift(base,top,2),"Tram can reach " + ledge_id)
	var site: Dictionary
	for item in hill.summit_ledges.sites:
		if item.ledge_id == ledge_id:
			site = item
	var lift = resort.lifts[-1]
	var tail: PackedVector2Array = hill.suggested_run(2,guide_shape)
	var user_points := PackedVector2Array([lift.run_start()])
	var side: Vector2 = site.direction.orthogonal() * bias
	for p: Vector2 in [site.approach,site.point,site.landing]:
		user_points.append(p+side)
	for i in tail.size():
		var t := float(i)/(tail.size()-1)
		var p: Vector2 = tail[i] + (lift.run_end()-tail[-1]) * t + Vector2(around_tower*sin(PI*t),0)
		if p.y > maxf(join_z,user_points[-1].y):
			user_points.append(p)
	var issue: String = resort.cut(2,user_points)
	expect(issue.is_empty(), "Custom line past %s: %s" % [ledge_id,issue])
	if issue.is_empty():
		expect(resort.add_feature(Feature.EXTREME,2,ledge_id).is_empty(), "Real route opens " + ledge_id)
	_close()

func _check() -> void:
	# The other three options are covered together on the standard tram cut in
	# slope_features_check.gd. These branches verify the outlying geology.
	_reach("granite_steps",Vector2(-36,-102.75),-2.7,-81,1)
	_reach("east_cornice",Vector2(-36,-102.75),-4.2,-81,1)
	_reach("western_notch",Vector2(-32,-103.75),1.5,-82,0,Vector2(-20,18),-2.0)
	_reach("crown",Vector2(-44,-110.75),-2.3,-77,0)
	var fixture := FileAccess.get_file_as_bytes(get_script().resource_path.get_base_dir().path_join("slope_features_0_3_0.save"))
	var path := OS.get_temp_dir().path_join("resort-cliffs-%d-%d.save" % [OS.get_process_id(),Time.get_ticks_usec()])
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(fixture)
	file.close()
	_open(path)
	expect(resort._restore_complete and resort._opened_ledges.size() == 1, "The unlabelled 0.3.0 cliff opens a permanent ledge")
	expect(resort.runs[0].features.has(Feature.PARK) and resort.village.occupied.get(2,-1) == 2,"Park and lodge built after the old cliff both survive")
	expect(resort.journal.size() == 11 and FileAccess.get_file_as_bytes(path) == fixture,"Reading keeps the complete historical save intact")
	expect(resort.add_building(0,0), "The migrated resort remains playable")
	var key: String = resort._opened_ledges.keys()[0]
	_close()
	_open(path)
	expect(resort._restore_complete and resort._opened_ledges.has(key) and resort.village.occupied.size() == 2,"The next launch restores the same named rock and all later construction")
	_close()
	DirAccess.remove_absolute(path)
	if not failed:
		print("PASS: four outer natural ledges reachable via actual cuts and lifts; 0.3.0 cliff migrates to stable geology and retains later park/lodge")
	quit(1 if failed else 0)
