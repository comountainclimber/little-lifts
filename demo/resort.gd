extends Node

const Lift := preload("res://lift/chairlift.gd")
const Village := preload("res://world/village.gd")
const SlopeFeature := preload("res://world/slope_feature.gd")
const TYPES := ["Single chair", "Saddle double", "High-speed tram"]
const AREAS := ["Village Hill", "The Saddle", "Summit Ridge"]
signal changed
signal milestone(message: String)
var terrain: Node
var village := Village.new()
var lifts: Array[Node] = []
var runs: Array[Dictionary] = []
var _feature_surveys := {}
var _built_jumps: Array[Dictionary] = []
var _opened_ledges := {}
var unlocked := 0
var highest_built := 0
var journal: Array = []
var save_path := "user://little-lifts-resort-v1.save"
var _restoring := false
var _restore_complete := true
var _legacy_starter := false

func setup(mountain: Node) -> void:
	terrain = mountain
	add_child(village)
	village.setup(terrain)
	var data := _read_save()
	_legacy_starter = data.get("version") == 1 or data.get("legacy_starter", false) == true
	_add_lift(terrain.station_base(0), terrain.station_top(0), 0, _legacy_starter)
	_restore(data)

func building_count() -> int:
	if unlocked == 0:
		return 0
	return mini(3, highest_built + 1)

func placement_issue(a: Vector2, b: Vector2, tier: int) -> String:
	if tier < 0 or tier > unlocked:
		return "Open the lower mountain first."
	var length := a.distance_to(b)
	if length < [7.0, 14.0, 24.0][tier]:
		return "Drag farther uphill to place the upper station."
	if length > [30.0, 59.0, 112.0][tier] * terrain.MAP_SCALE:
		return "Bring the upper station closer for this lift."
	var top: Vector2 = terrain.station_top(tier)
	if terrain.height_at(b.x, b.y) > terrain.height_at(top.x, top.y) + 1.4 * terrain.MAP_SCALE:
		return "This elevation needs a higher-capacity lift."
	if not _restoring and (terrain.summit_ledges.contains(a,1.75) or terrain.summit_ledges.contains(b,1.75)):
		return "Leave room beside the natural rock ledge for the station."
	for lift in lifts:
		if a.distance_to(lift._base) < 2.4 or b.distance_to(lift._summit) < 2.4:
			return "Give the other station a little room."
		if Geometry2D.segment_intersects_segment(a, b, lift._base, lift._summit) != null:
			return "Keep the new cable clear of the other lift."
	for jump in _built_jumps:
		# Existing saves can contain a cable built beside the slightly different
		# 0.3.0 cliff location. Restore its original station approvals.
		if _restoring and jump.has("ledge_id"):
			continue
		if SlopeFeature.too_close(a, b, jump.approach, jump.landing, 1.9 + jump.width * 0.5):
			return "Keep the new cable clear of the jumps and landings."
	if not terrain.route_clear(a, b, 0.65):
		return "Find an open strip for the lift line."
	var start_h: float = terrain.surface_height(a.x, a.y)
	if terrain.surface_height(b.x, b.y) - start_h < 1.4:
		return "Place the second station higher up the hill."
	if not Lift.descent_fits(a, b, terrain, tier):
		return "Try the near face, with a clear return to the lower station."
	return ""

func place_lift(a: Vector2, b: Vector2, tier: int, legacy_supports := false) -> bool:
	if not placement_issue(a, b, tier).is_empty():
		return false
	_add_lift(a, b, tier, legacy_supports)
	_record({"event":"lift", "a":a, "b":b, "tier":tier})
	changed.emit()
	return true

func _add_lift(a: Vector2, b: Vector2, tier: int, legacy_supports := false) -> void:
	var lift := Lift.new()
	if legacy_supports:
		lift.support_spacing_scale = terrain.MAP_SCALE
	add_child(lift)
	lift.configure(a, b, terrain, tier)
	lift.run_completed.connect(_skied.bind(lifts.size()))
	lifts.append(lift)
	_feature_surveys.clear()
	highest_built = maxi(highest_built, tier)
	village.grow(highest_built + (1 if unlocked > 0 else 0))

func suggestion(lift_index: int, shape := 0) -> PackedVector2Array:
	var lift: Node = lifts[lift_index]
	var start: Vector2 = lift.run_start()
	var finish: Vector2 = lift.run_end()
	var first := PackedVector2Array()
	for variation in 12:
		var line: PackedVector2Array = terrain.suggested_run(lift.tier, shape, variation)
		var entry := start - line[0]
		var exit := finish - line[-1]
		for i in line.size():
			line[i] += entry.lerp(exit, float(i) / (line.size() - 1))
		if _cut_issue(lift_index, line, false).is_empty():
			return line
		if first.is_empty():
			first = line
	return first

func _cut_issue(lift_index: int, line: PackedVector2Array, legacy: bool) -> String:
	if lift_index < 0 or lift_index >= lifts.size() or line.size() < 2:
		return "Draw a line from the upper station to the lower one."
	var lift: Node = lifts[lift_index]
	if line[0].distance_to(lift.run_start()) > 2.0 or line[-1].distance_to(lift.run_end()) > 2.0:
		return "Connect both marked ends so riders can use the run."
	var problem: String = terrain.cut_issue(line, not legacy)
	if not problem.is_empty():
		return problem
	# Never cut across a lift tower. The two ends lead onto the adjacent snow.
	for other in lifts:
		for k in range(1, other._heights.size() - 1):
			var tower: Vector2 = other._base.lerp(other._summit, float(k) / (other._heights.size() - 1))
			for j in range(1, line.size()):
				if Geometry2D.get_closest_point_to_segment(tower, line[j-1], line[j]).distance_to(tower) < 1.05:
					return "Curve around the lift tower."
	return ""

func cut(lift_index: int, line: PackedVector2Array, legacy := false) -> String:
	var issue := _cut_issue(lift_index, line, legacy)
	if not issue.is_empty():
		return issue
	var lift: Node = lifts[lift_index]
	var felled: int = terrain.cut_run(line, not legacy)
	if felled <= 0 and not legacy:
		return "Bend the trail into the pines to open a new run."
	var id: int = lift.register_run(line)
	if id < 0:
		terrain.undo_last_cut()
		return "Ease that bend so riders can ski it all the way through."
	runs.append({"lift":lift_index, "id":id, "used":false, "survey":SlopeFeature.survey_curve(line), "features":{}})
	_feature_surveys.clear()
	_record({"event":"cut", "lift":lift_index, "line":line.duplicate()})
	changed.emit()
	return ""

func _skied(id: int, lift_index: int) -> void:
	for i in runs.size():
		if runs[i].lift == lift_index and runs[i].id == id and not runs[i].used:
			_credit(i)
			return

func _credit(index: int) -> void:
	runs[index].used = true
	var tier: int = lifts[runs[index].lift].tier
	var previous := unlocked
	unlocked = maxi(unlocked, mini(2, tier + 1))
	village.grow(highest_built + 1)
	_record({"event":"skied", "run":index})
	changed.emit()
	if not _restoring:
		if unlocked > previous:
			milestone.emit("First tracks!   " + TYPES[unlocked] + " is ready in Build a lift.")
		elif tier == 2:
			milestone.emit("First tracks from Summit Ridge to the village.")
		else:
			milestone.emit("The first rider made it home on your new run.")

func add_building(kind: int, plot: int) -> bool:
	if kind < 0 or kind >= building_count() or not village.build_at(kind, plot):
		return false
	_record({"event":"building", "kind":kind, "plot":plot})
	changed.emit()
	return true

func feature_sites(kind: int) -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	if kind != SlopeFeature.PARK and kind != SlopeFeature.EXTREME:
		return sites
	if _feature_surveys.has(kind):
		return _feature_surveys[kind]
	if kind == SlopeFeature.EXTREME:
		for ledge in terrain.summit_ledges.sites:
			if _opened_ledges.has(ledge.ledge_id):
				continue
			var chosen := -1
			var best := INF
			for i in runs.size():
				var run := runs[i]
				if lifts[run.lift].tier != 2:
					continue
				var fit := SlopeFeature.ledge_fit(terrain,run.survey,ledge,lifts,_built_jumps)
				if fit < best:
					chosen = i
					best = fit
			if chosen >= 0:
				var jumps: Array[Dictionary] = [ledge]
				sites.append({"run":chosen, "kind":kind, "point":ledge.point, "name":ledge.name, "ledge_id":ledge.ledge_id, "jumps":jumps})
		_feature_surveys[kind] = sites
		return sites
	for i in runs.size():
		var run := runs[i]
		if run.features.has(kind):
			continue
		var lift: Node = lifts[run.lift]
		var jumps := SlopeFeature.survey(kind, terrain, run.survey, lift.tier, lifts, _built_jumps)
		if not jumps.is_empty():
			sites.append({"run":i, "kind":kind, "point":jumps[0].point, "jumps":jumps})
	_feature_surveys[kind] = sites
	return sites

func feature_hint(kind: int) -> String:
	if kind == SlopeFeature.PARK:
		if runs.is_empty():
			return "Cut a run with a long, gentle pitch for two park jumps."
		if feature_sites(kind).is_empty():
			return "A park needs a clear, moderate pitch with room for both landings."
		return "Choose a marked run to shape two park jumps."
	if highest_built < 2:
		return "Reach the rock ledges on Summit Ridge with the tram."
	if feature_sites(kind).is_empty():
		return "Cut a run past an unopened summit ledge with room to ski out below."
	return "Choose a summit ledge to open its cliff line."

func add_feature(kind: int, run_index: int, ledge_id := "") -> String:
	if run_index < 0 or run_index >= runs.size():
		return "Choose a marked run."
	var run := runs[run_index]
	if kind == SlopeFeature.PARK and run.features.has(kind):
		return "This run already has that feature."
	if not ledge_id.is_empty() and _opened_ledges.has(ledge_id):
		return "That cliff line is already open."
	for site in feature_sites(kind):
		if site.run != run_index or (not ledge_id.is_empty() and site.get("ledge_id","") != ledge_id):
			continue
		var jumps: Array[Dictionary] = site.jumps
		var event := {"event":"feature", "kind":kind, "run":run_index}
		if kind == SlopeFeature.PARK:
			_build_formation(jumps, "Terrain park %d" % (run_index+1))
		else:
			_opened_ledges[site.ledge_id] = run_index
			event.ledge_id = site.ledge_id
		_register_jumps(run,kind,jumps)
		_record(event)
		changed.emit()
		return ""
	return feature_hint(kind)

func _build_formation(jumps: Array[Dictionary], label: String) -> void:
	var feature := SlopeFeature.new()
	feature.name = label
	add_child(feature)
	feature.build(terrain, jumps)

func _register_jumps(run: Dictionary, kind: int, jumps: Array[Dictionary]) -> void:
	if not run.features.has(kind):
		run.features[kind] = []
	for jump in jumps:
		run.features[kind].append(jump)
		_built_jumps.append(jump)
		lifts[run.lift].set_run_feature(run.id, jump)
	_feature_surveys.clear()

func _restore_old_cliff(run_index: int) -> bool:
	if run_index < 0 or run_index >= runs.size():
		return false
	var run := runs[run_index]
	# 0.3.0 allowed an individually constructed cliff on any qualified cut.
	# Retain that construction on a saved custom line with no natural shelf.
	var jumps := SlopeFeature.survey(SlopeFeature.EXTREME,terrain,run.survey,lifts[run.lift].tier,lifts,_built_jumps)
	if jumps.is_empty():
		# A previously migrated cliff may now occupy a nearby parallel line.
		# Its new footprint didn't constrain this historical construction.
		var old_clearances: Array = []
		for jump in _built_jumps:
			if not jump.has("ledge_id"):
				old_clearances.append(jump)
		jumps = SlopeFeature.survey(SlopeFeature.EXTREME,terrain,run.survey,lifts[run.lift].tier,lifts,old_clearances)
	if jumps.is_empty():
		# Keep the original journal entry for a subsequent replay without
		# discarding a later chair, run or building from the player's resort.
		push_warning("Preserving the old summit cliff reservation on run %d; its saved approach cannot be reconstructed." % (run_index+1))
		return true
	_build_formation(jumps, "Original summit cliff %d" % (run_index+1))
	_register_jumps(run,SlopeFeature.EXTREME,jumps)
	return true

func _record(item: Dictionary) -> void:
	if _restoring:
		return
	journal.append(item)
	if save_path.is_empty() or not _restore_complete:
		return
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save the resort.")
		return
	file.store_var({"version":2, "events":journal, "legacy_starter":_legacy_starter})
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	if not ok or DirAccess.rename_absolute(temporary, save_path) != OK:
		push_warning("Could not finish saving the resort.")

func _read_save() -> Dictionary:
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		_restore_complete = false
		return {}
	var data = file.get_var(false)
	file.close()
	if not data is Dictionary or data.get("version") not in [1,2] or not data.get("events") is Array:
		_restore_complete = false
		return {}
	return data

func _restore(data: Dictionary) -> void:
	if data.is_empty():
		return
	_restoring = true
	for saved in data.events:
		if not saved is Dictionary:
			_restore_complete = false
			break
		var e: Dictionary = _migrate_event(saved) if data.version == 1 else saved
		var ok := false
		match e.get("event", ""):
			"lift":
				if e.get("a") is Vector2 and e.get("b") is Vector2 and e.get("tier") is int:
					if e.get("legacy_corridor", false):
						# Furniture keeps its original size on the enlarged map.
						# Clear infill from the cable, exit lane, and queue.
						terrain.scenery.clear_legacy_corridor(PackedVector2Array([e.a,e.b]), 3.9)
					ok = place_lift(e.a, e.b, e.tier, e.get("legacy_corridor", false))
			"cut":
				if e.get("line") is PackedVector2Array and e.get("lift") is int:
					var legacy: bool = e.get("legacy_corridor", false)
					if legacy:
						terrain.scenery.clear_legacy_corridor(e.line, terrain.CUT_HALF_WIDTH * terrain.MAP_SCALE)
					ok = cut(e.lift, e.line, legacy).is_empty()
			"skied":
				if e.get("run") is int and e.run >= 0 and e.run < runs.size() and not runs[e.run].used:
					_credit(e.run)
					ok = true
			"building":
				if e.get("kind") is int and e.get("plot") is int:
					ok = add_building(e.kind, e.plot)
			"feature":
				if e.get("kind") is int and e.get("run") is int:
					ok = add_feature(e.kind, e.run, e.get("ledge_id","")).is_empty()
					if e.kind == SlopeFeature.EXTREME and not e.has("ledge_id"):
						if ok:
							e = e.duplicate(true)
							e.ledge_id = runs[e.run].features[e.kind][-1].ledge_id
						else:
							ok = _restore_old_cliff(e.run)
		if not ok:
			_restore_complete = false
			push_warning("Could not restore %s at construction event %d." % [e.get("event", "unknown"), journal.size()])
			break
		journal.append(e)
	_restoring = false

func _migrate_event(saved: Dictionary) -> Dictionary:
	var e := saved.duplicate(true)
	var scale_factor: float = terrain.MAP_SCALE
	if e.get("event") == "lift" and e.get("a") is Vector2 and e.get("b") is Vector2:
		e.a *= scale_factor
		e.b *= scale_factor
		e.legacy_corridor = true
	elif e.get("event") == "cut" and e.get("line") is PackedVector2Array and e.get("lift") is int and e.lift >= 0 and e.lift < lifts.size():
		var points: PackedVector2Array = e.line
		if points.size() >= 2:
			var lift: Node = lifts[e.lift]
			var entry: Vector2 = lift.run_start() - points[0] * scale_factor
			var exit: Vector2 = lift.run_end() - points[-1] * scale_factor
			var from_start := PackedFloat32Array([0.0])
			for i in range(1, points.size()):
				from_start.append(from_start[-1] + points[i].distance_to(points[i-1]) * scale_factor)
			for i in points.size():
				# Only the metres beside each terminal need moving. Preserve the
				# rest of the player's original turns in mountain coordinates.
				var head := 1.0 - smoothstep(0.0, 4.0, from_start[i])
				var tail := 1.0 - smoothstep(0.0, 4.0, from_start[-1] - from_start[i])
				points[i] = points[i] * scale_factor + entry * head + exit * tail
			points[0] = lift.run_start()
			points[-1] = lift.run_end()
			e.line = points
			e.legacy_corridor = true
	return e
