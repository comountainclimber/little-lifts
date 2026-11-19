extends SceneTree

const Mountain := preload("res://world/mountain.gd")
const Resort := preload("res://demo/resort.gd")
const Feature := preload("res://world/slope_feature.gd")

var failures := PackedStringArray()
var save_path := OS.get_temp_dir().path_join("little-lifts-features-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()])
var hill: Node
var resort: Node

func _initialize() -> void:
	call_deferred("_check")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func open_resort() -> void:
	hill = Mountain.new()
	root.add_child(hill)
	resort = Resort.new()
	resort.save_path = save_path
	root.add_child(resort)
	resort.setup(hill)

func _check() -> void:
	open_resort()
	var rock_count: int = hill.summit_ledges.get_child_count()
	expect(rock_count == 7 and hill.summit_ledges.sites.size() == rock_count, "All seven permanent rock ledges are visible on the opening mountain")
	for ledge in hill.summit_ledges.sites:
		var model: MeshInstance3D = hill.summit_ledges.get_node(ledge.name)
		expect(model.mesh.get_surface_count() > 0 and model.is_visible_in_tree(), "Each ledge has real scenery before the player builds anything")
	expect(resort.feature_sites(Feature.PARK).is_empty(), "Uncut snow has no park survey")
	expect(not resort.add_feature(Feature.EXTREME, 0).is_empty(), "A cliff needs a real cut run")
	for tier in 3:
		if tier > 0:
			expect(resort.place_lift(hill.station_base(tier), hill.station_top(tier), tier), "Later lift still fits after park construction")
		var cut_issue: String = resort.cut(tier, resort.suggestion(tier))
		expect(cut_issue.is_empty(), "Surveyed trail opens: " + cut_issue)
		if not cut_issue.is_empty():
			break
		if tier < 2:
			expect(resort.feature_sites(Feature.EXTREME).is_empty(), "Cliffs cannot be opened from lower lifts")
		if tier == 0 or tier == 2:
			expect(resort.add_feature(Feature.PARK, tier).is_empty(), "Surveyed slope fits a two-jump park")
			var jumps: Array = resort.runs[tier].features.get(Feature.PARK, [])
			expect(jumps.size() == 2, "Both park kickers are placed in one operation")
			if jumps.size() == 2:
				expect(jumps[1].distance - jumps[0].distance >= 9.5 and jumps[0].landing.distance_to(jumps[1].approach) > 3.0, "First landing has runout before the second approach")
				for jump in jumps:
					expect(jump.grade >= 0.14 and jump.grade <= 0.47, "Park surveying requires moderate pitch")
					expect(hill.route_clear(jump.approach, jump.point, jump.width * 0.5), "Jump has lateral room")
			expect(not resort.add_feature(Feature.PARK, tier).is_empty(), "A park cannot be installed twice")
		resort._skied(resort.runs[tier].id, tier)
	if resort.runs.size() == 3:
		var extremes: Array = resort.feature_sites(Feature.EXTREME)
		expect(extremes.size() >= 3, "At least three different existing ledges can be skied from this summit cut")
		if not extremes.is_empty():
			var drop: Dictionary = extremes[0].jumps[0]
			expect(Feature.on_summit_ridge(hill, drop.point) and Feature.on_summit_ridge(hill, drop.approach), "Entire cliff formation sits on the summit ridge")
			expect(drop.grade >= 0.60 and drop.lip_height - drop.landing_height >= 6.0 and drop.landing.distance_to(drop.point) > 6.0, "The cliff has a major vertical drop and a long flight to open snow")
		expect(not Feature.on_summit_ridge(hill, Vector2(-14,-51) * hill.MAP_SCALE), "The steep lower bowl lies outside the summit ridgeline")
		var low_run: Curve2D = resort.runs[0].survey
		expect(Feature.survey(Feature.EXTREME, hill, low_run, 2, resort.lifts, []).is_empty(), "A summit lift alone cannot turn a lower run into an extreme")
		expect(resort.add_feature(Feature.EXTREME, 2).is_empty(), "A ridge cliff and a lower two-jump park coexist on the summit trail")
		if extremes.size() >= 3:
			var second: Dictionary = extremes[1]
			expect(resort.add_feature(Feature.EXTREME, 2, second.ledge_id).is_empty(), "Open a second named line off the same cut")
			expect(not resort.add_feature(Feature.EXTREME, 2, second.ledge_id).is_empty(), "Each rock can only be opened once")
			expect(resort.feature_sites(Feature.EXTREME).size() == extremes.size() - 2, "Other natural ledges stay selectable")
		expect(hill.summit_ledges.get_child_count() == rock_count, "Opening lines never adds to the mountain's geology")
		var journal: Array = resort.journal.duplicate(true)
		var summit: Dictionary = resort.runs[2].features.duplicate(true)
		resort.free()
		hill.free()
		open_resort()
		expect(resort.journal == journal and resort.runs.size() == 3, "Reopen replays every construction event")
		if resort.runs.size() == 3:
			expect(resort.runs[2].features == summit and resort.runs[0].features.get(0,[]).size() == 2, "Reopen restores the same two kickers and summit cliff")
			expect(resort.get_node_or_null("Terrain park 1") != null and hill.summit_ledges.get_child_count() == rock_count and resort._opened_ledges.size() == 2, "Reopen restores selected ledge IDs on the original meshes")
	resort.free()
	hill.free()
	DirAccess.remove_absolute(save_path)
	if failures.is_empty():
		print("PASS: paired park kickers, qualified summit ridge cliffs, safe landing clearance, progression and save/reopen")
	quit(0 if failures.is_empty() else 1)
