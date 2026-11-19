extends Node3D

enum { PARK, EXTREME }
const PARK_WIDTH := 1.9
const CLIFF_WIDTH := 1.8

# Each index in the survey is a distance down the player's actual cleared line.
static func survey_curve(points: PackedVector2Array) -> Curve2D:
	var curve := Curve2D.new()
	curve.bake_interval = 0.16
	for p in points:
		curve.add_point(p)
	return curve

static func on_summit_ridge(terrain: Node, point: Vector2) -> bool:
	# The high divide above the bowl ends at the two summit rock fields.
	var map_scale: float = terrain.MAP_SCALE
	var map_point := point / map_scale
	if map_point.x < -39.0 or map_point.x > -7.0 or map_point.y > -59.0 or map_point.y < -80.0:
		return false
	var crest_z := -75.0
	var crest_y := -INF
	for z in range(-81, -68):
		var h: float = terrain.surface_height(point.x, z * map_scale)
		if h > crest_y:
			crest_y = h
			crest_z = z
	return absf(map_point.y - crest_z) <= 18.0 and terrain.surface_height(point.x, point.y) >= crest_y - 12.0 * map_scale

static func _ground(terrain: Node, p: Vector2) -> float:
	return terrain.surface_height(p.x, p.y)

static func too_close(a: Vector2, b: Vector2, c: Vector2, d: Vector2, margin: float) -> bool:
	var nearest := Geometry2D.get_closest_points_between_segments(a, b, c, d)
	return nearest[0].distance_squared_to(nearest[1]) < margin * margin

static func _jump(terrain: Node, curve: Curve2D, d: float, kind: int, second: bool, lifts: Array, existing: Array) -> Dictionary:
	var cliff := kind == EXTREME
	var flight := 6.65 if cliff else (4.1 if second else 3.55)
	var approach_length := 2.75 if cliff else (2.5 if second else 2.35)
	var length := curve.get_baked_length()
	if d < approach_length + 1.6 or d + flight + 2.6 > length:
		return {}
	var point := curve.sample_baked(d)
	var approach := curve.sample_baked(d - approach_length)
	var landing := curve.sample_baked(d + flight)
	var runout := curve.sample_baked(d + flight + 2.0)
	var lead := curve.sample_baked(d - approach_length - 1.0)
	var direction := (landing - point).normalized()
	if (point - approach).normalized().dot(direction) < 0.945 or (runout - landing).normalized().dot(direction) < 0.88:
		return {}
	if cliff and (not on_summit_ridge(terrain, point) or not on_summit_ridge(terrain, approach)):
		return {}
	var h := _ground(terrain, point)
	var approach_y := _ground(terrain, approach)
	var landing_y := _ground(terrain, landing)
	var drop := (h - landing_y) / maxf(0.01, point.distance_to(landing))
	var entry_grade := (approach_y - h) / maxf(0.01, approach.distance_to(point))
	var runout_grade := (landing_y - _ground(terrain, runout)) / maxf(0.01, landing.distance_to(runout))
	if drop < (0.60 if cliff else 0.14) or drop > (1.08 if cliff else 0.47):
		return {}
	if entry_grade < 0.08 or entry_grade > (0.98 if cliff else 0.49) or runout_grade < 0.08 or runout_grade > (1.0 if cliff else 0.53):
		return {}
	var width := CLIFF_WIDTH if cliff else PARK_WIDTH
	var clearance := width * 0.5 + 0.19
	if not terrain.route_clear(lead, point, clearance) or not terrain.route_clear(point, landing, clearance) or not terrain.route_clear(landing, runout, clearance):
		return {}
	for lift in lifts:
		if too_close(lead, runout, lift._base, lift._summit, clearance + lift._wheel_radius + 0.44):
			return {}
	for jump in existing:
		if too_close(lead, runout, jump.approach, jump.landing, clearance + jump.width * 0.5 + 0.6):
			return {}
	var rise := 2.0 if cliff else (1.25 if second else 1.06)
	var arc := 1.85 if cliff else (1.39 if second else 1.18)
	# Reject obstructed flight profiles even if the endpoints meet the grade band.
	for step in range(1, 8):
		var t := float(step) / 8
		var flight_y := lerpf(h + rise, landing_y, t) + 4.0 * arc * t * (1.0 - t)
		if _ground(terrain, point.lerp(landing, t)) >= flight_y - 0.08:
			return {}
	return {"kind": kind, "point": point, "approach": approach, "landing": landing, "direction": direction,
		"approach_height": approach_y, "lip_height": h + rise, "landing_height": landing_y,
		"air_height": arc, "width": width, "distance": d, "grade": drop}

static func survey(kind: int, terrain: Node, curve: Curve2D, tier: int, lifts: Array, existing: Array) -> Array[Dictionary]:
	var best: Array[Dictionary] = []
	if kind != PARK and (kind != EXTREME or tier != 2):
		return best
	var length := curve.get_baked_length()
	var first_sites: Array[Dictionary] = []
	var best_score := INF
	for tick in range(8, floori((length - 5.0) * 2.0)):
		var d := tick * 0.5
		var first := _jump(terrain, curve, d, kind, false, lifts, existing)
		if kind == EXTREME:
			if not first.is_empty():
				# Use the highest qualified rock lip nearest the top of the cut.
				return [first]
			continue
		if not first.is_empty():
			first_sites.append(first)
		var second := _jump(terrain, curve, d, kind, true, lifts, existing)
		if second.is_empty():
			continue
		for early in first_sites:
			# Open snow between the first landing and the next approach lets
			# riders settle, then set their edges for the larger second kicker.
			if d - early.distance < 9.5 or too_close(early.approach, early.landing, second.approach, second.landing, 3.1):
				continue
			var score := absf(early.distance / length - 0.30) + absf(d / length - 0.68)
			if score < best_score:
				best_score = score
				best = [early, second]
	return best

static func ledge_fit(terrain: Node, curve: Curve2D, site: Dictionary, lifts: Array, existing: Array) -> float:
	# Match a cleared run to permanent geology. Each branch needs room to
	# leave the run before the rock and to ski back in below the landing.
	var start := curve.get_closest_offset(site.approach)
	var end := curve.get_closest_offset(site.landing)
	if start < 1.6 or end < start + 5.2 or end + 3.0 >= curve.get_baked_length():
		return INF
	var entry := curve.sample_baked(start)
	var exit := curve.sample_baked(end)
	var gap := entry.distance_to(site.approach)
	var return_gap := exit.distance_to(site.landing)
	if gap > 7.2 or return_gap > 7.2 or (exit-entry).normalized().dot(site.direction) < 0.69:
		return INF
	var lead := curve.sample_baked(maxf(0.0,start - 4.8))
	var rejoin := curve.sample_baked(end + 4.8)
	if _ground(terrain, lead) + 0.38 < site.approach_height or _ground(terrain,rejoin) > site.landing_height + 0.38:
		return INF
	if (site.approach-lead).normalized().dot(site.direction) < 0.22 or (rejoin-site.landing).normalized().dot(site.direction) < 0.22:
		return INF
	if site.grade < 0.52 or site.lip_height-site.landing_height < 6.0:
		return INF
	var line := PackedVector2Array([lead,site.approach,site.point,site.landing,rejoin])
	for i in range(1,line.size()):
		if not terrain.route_clear(line[i-1],line[i],0.55):
			return INF
		for lift in lifts:
			if too_close(line[i-1],line[i],lift._base,lift._summit,lift._wheel_radius + 0.46):
				return INF
		for jump in existing:
			if jump.kind == PARK and too_close(line[i-1],line[i],jump.approach,jump.landing,1.8):
				return INF
	# Reject crossovers into the face of another rock during approach/flight.
	for i in range(2,4):
		if not terrain.summit_ledges.clear_segment(line[i-1],line[i],0.27,site.ledge_id):
			return INF
	for i in range(1,12):
		var t := float(i)/12.0
		var flight_y: float = lerpf(site.lip_height,site.landing_height,t) + 4.0*site.air_height*t*(1.0-t)
		if flight_y < _ground(terrain,site.point.lerp(site.landing,t)) + 0.08:
			return INF
	return gap + return_gap

static func _face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outside: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 0.000001:
		return
	var flip := normal.dot(outside) < 0.0
	normal = normal.normalized() * (-1.0 if flip else 1.0)
	for v: Vector3 in ([a, c, b] if flip else [a, b, c]):
		surface.set_normal(normal)
		surface.set_color(color.srgb_to_linear())
		surface.add_vertex(v)

func build(terrain: Node, jumps: Array[Dictionary]) -> void:
	for jump in jumps:
		_mold(terrain, jump)

func _mold(terrain: Node, jump: Dictionary) -> void:
	var rocky: bool = jump.kind == EXTREME
	var rise: float = jump.lip_height - _ground(terrain, jump.point)
	var left: Vector2 = (jump.point - jump.approach).normalized().orthogonal()
	var snow := Color("#edf2f6")
	var side_color := Color("#858592") if rocky else Color("#c9d7e4")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := PackedVector3Array()
	for row in 10:
		var t := float(row) / 9.0
		var center: Vector2 = jump.approach.lerp(jump.point, t)
		var ring := PackedVector3Array()
		for column in 5:
			var across := float(column - 2) * 0.5
			var shape := 1.0 + (0.24 * sin(t * 5.4 + column) if rocky else 0.07 * (1.0 - t))
			var p: Vector2 = center + left * across * jump.width * 0.5 * shape
			var crest := rise * t * t * (1.0 - 0.08 * across * across)
			ring.append(Vector3(p.x, _ground(terrain, p) + 0.018 + crest, p.y))
		if row > 0:
			for col in 4:
				_face(surface, previous[col], ring[col], previous[col + 1], Vector3.UP, snow)
				_face(surface, ring[col], ring[col + 1], previous[col + 1], Vector3.UP, snow)
			for edge in [0, 4]:
				var side := Vector3(left.x, 0, left.y) * (-1 if edge == 0 else 1)
				_wall(terrain, surface, previous[edge], ring[edge], side, side_color, rocky)
		previous = ring
	var front := Vector3(jump.direction.x, 0, jump.direction.y)
	for col in 4:
		_wall(terrain, surface, previous[col], previous[col+1], front, side_color, rocky)
	if rocky:
		# Broken granite shoulders tie the lip back into the exposed summit rib.
		# Keep the ridden center, flight corridor and runout entirely clear.
		for signum: float in [-1.0, 1.0]:
			var out := left * signum
			var toe: Vector2 = jump.point - jump.direction * (0.50 if signum < 0.0 else 0.92)
			var shoulder: Vector2 = toe + out * (jump.width * 0.55)
			var offset := Vector3(out.x, 0, out.y)
			var peak := Vector3(shoulder.x, _ground(terrain, shoulder) + rise * 0.65, shoulder.y)
			var fragments := PackedVector3Array()
			for corner in 6:
				var angle := TAU * corner / 6.0 + signum * 0.36
				var p: Vector2 = shoulder + out * (0.40 * cos(angle)) + jump.direction * (0.76 * sin(angle))
				fragments.append(Vector3(p.x, _ground(terrain, p) - 0.06, p.y))
			for corner in 6:
				var a := fragments[corner]
				var b := fragments[(corner+1)%6]
				var middle := a.lerp(peak, 0.65) + offset * 0.09
				_face(surface, a, b, middle, (a+b)*0.5 - peak + Vector3.UP * rise, side_color.darkened(0.06 * (corner % 3)))
				_face(surface, middle, b, peak, Vector3.UP + offset, side_color.lightened(0.06 * (corner % 3)))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.96
	surface.set_material(mat)
	var model := MeshInstance3D.new()
	model.mesh = surface.commit()
	add_child(model)
	if not rocky:
		for signum: float in [-1.0, 1.0]:
			var p: Vector2 = jump.point + left * signum * jump.width * 0.61
			var post := MeshInstance3D.new()
			var pole := CylinderMesh.new()
			pole.height = 0.77
			pole.radial_segments = 6
			pole.rings = 0
			pole.top_radius = 0.035
			pole.bottom_radius = 0.045
			var ochre := StandardMaterial3D.new()
			ochre.albedo_color = Color("#bd815a")
			pole.material = ochre
			post.mesh = pole
			post.position = Vector3(p.x, _ground(terrain, p) + 0.385, p.y)
			add_child(post)

func _wall(terrain: Node, surface: SurfaceTool, a: Vector3, b: Vector3, normal: Vector3, color: Color, rocky: bool) -> void:
	var bottom_a := Vector3(a.x, terrain.surface_height(a.x, a.z) - 0.04, a.z)
	var bottom_b := Vector3(b.x, terrain.surface_height(b.x, b.z) - 0.04, b.z)
	if not rocky:
		_face(surface, bottom_a, bottom_b, a, normal, color)
		_face(surface, bottom_b, b, a, normal, color)
		return
	var skirt_a := bottom_a.lerp(a, 0.82 + 0.10 * sin(a.x * 2.2 + a.z))
	var skirt_b := bottom_b.lerp(b, 0.82 + 0.10 * sin(b.x * 2.2 + b.z))
	var bulge := 0.12 if rocky else 0.065
	var ridge := bottom_a.lerp(b, 0.36 + 0.15 * sin(a.x * 1.7 + b.z)) + normal * bulge
	var shade := color.darkened(0.10 if rocky else 0.045)
	_face(surface, bottom_a, bottom_b, ridge, normal, shade)
	_face(surface, bottom_b, skirt_b, ridge, normal, color)
	_face(surface, skirt_b, skirt_a, ridge, normal, color.lightened(0.08))
	_face(surface, skirt_a, bottom_a, ridge, normal, shade)
	_face(surface, skirt_a, skirt_b, a, normal, Color("#dae3ed"))
	_face(surface, skirt_b, b, a, normal, Color("#dae3ed"))
