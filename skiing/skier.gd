extends Node3D

signal finished

const RiderStyle := preload("res://skiing/rider_style.gd")
const FeatureLine := preload("res://skiing/feature_line.gd")
const Model := preload("res://skiing/skier_model.gd")
const SnowSound := preload("res://skiing/snow_sound.gd")
const CarveTrack := preload("res://skiing/carve_track.gd")
const JACKETS := [
	Color("#e24f35"), Color("#e7a32d"), Color("#297e82"),
	Color("#bd495e"), Color("#3f71a7"), Color("#d16b32"),
	Color("#9952aa"), Color("#5bbe9c"),
]

var used_cut_run := false
var cut_run_id := -1
var is_snowboarder := false
var _passes: Array[FeatureLine.Pass] = []
var _pass_index := 0
var _landing_age := 1.0
var airborne: bool:
	get:
		return _pass_index < _passes.size() and _travelled >= _distances[_passes[_pass_index].lip_row]
var air_kind: int:
	get:
		return _passes[_pass_index].kind if airborne else -1
var _toe_side := 0.0
var _points := PackedVector3Array()
var _distances := PackedFloat32Array()
var _track: CarveTrack
var _sound := SnowSound.new()
var _entry_basis := Basis.IDENTITY
var _transferred := false
var _model: Model
var _terrain: Node
var _length := 0.0
var _travelled := 0.0
var _speed := 1.1
var _bank := 0.0
var _drag := 0.07
var _active := false


static func jacket_color(variant: int) -> Color:
	return JACKETS[posmod(variant, JACKETS.size())]


func start_run(summit: Vector2, base: Vector2, variant: int, terrain: Node, tracks_parent: Node3D, lap: int = 0, piste_side: Vector2 = Vector2.ZERO, run_line := PackedVector2Array(), sites: Array = [], arriving_model: Model = null, prepared_spine := PackedVector2Array(), stream_tracks := false) -> void:
	_terrain = terrain
	is_snowboarder = RiderStyle.is_boarder(variant)
	_toe_side = RiderStyle.toe_side(variant) if is_snowboarder else 0.0
	# A skier has a preferred turn radius, starting edge and pace. Restarting
	# a lap with their variant preserves their style across rides.
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(variant) * 196613 + 87437
	var spine := PackedVector2Array()
	if not run_line.is_empty():
		spine = prepared_spine if not prepared_spine.is_empty() else cut_run_spine(summit, base, run_line, terrain)
		if not spine.is_empty():
			_plot_cut_run(spine, rng, lap, sites)
			used_cut_run = true
	if not used_cut_run:
		_plot_line(summit, base, rng, lap, piste_side)
	if FeatureLine.skirt_rocks(_points, _passes, terrain, spine):
		_length = 0.0
		for i in range(1, _points.size()):
			_length += _points[i - 1].distance_to(_points[i])
			_distances[i] = _length
	if arriving_model == null:
		_model = Model.new()
		add_child(_model)
		_model.build(jacket_color(variant), variant)
	else:
		_model = arriving_model
		_entry_basis = _model.global_basis.orthonormalized()
		_transferred = true
		_model.reparent(self, false)
		_model.transform = Transform3D.IDENTITY
	add_child(_sound)
	_sound.start(variant)
	_drag = rng.randf_range(0.075, 0.115)
	_track = CarveTrack.new()
	tracks_parent.add_child(_track)
	_track.build(_points, _distances, terrain, is_snowboarder, _toe_side, _passes, stream_tracks)
	_active = true
	_update_pose(1.0)


func set_followed(focused: bool) -> void:
	_sound.followed = focused


func _height(p: Vector2) -> float:
	return _terrain.surface_height(p.x, p.y)


func _gradient(p: Vector2) -> Vector2:
	const H := 0.15
	return Vector2(
		_height(p + Vector2(H, 0.0)) - _height(p - Vector2(H, 0.0)),
		_height(p + Vector2(0.0, H)) - _height(p - Vector2(0.0, H))
	) / (2.0 * H)


static func _station_index(line: PackedVector2Array, station: Vector2, from_top: bool) -> int:
	# Only trim the short station approach. A branch may swing near a station
	# partway through its descent; snapping there would silently skip that run.
	var increment := 1 if from_top else -1
	var index := 0 if from_top else line.size() - 1
	var nearest := index
	var walked := 0.0
	while index + increment >= 0 and index + increment < line.size():
		var following := index + increment
		walked += line[index].distance_to(line[following])
		if walked > 4.3:
			break
		if line[following].distance_squared_to(station) < line[nearest].distance_squared_to(station):
			nearest = following
		index = following
	return nearest


static func _run_open(line: PackedVector2Array, terrain: Node, clearance: float) -> bool:
	for i in range(1, line.size()):
		var p := line[i]
		if not terrain.route_clear(line[i-1], p, clearance):
			return false
	return preload("res://world/run_profile.gd").flows_downhill(line, terrain)


static func cut_run_spine(exit: Vector2, arrival: Vector2, line: PackedVector2Array, terrain: Node) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if line.size() < 2 or line[0].distance_to(exit) > 6.0 or line[-1].distance_to(arrival) > 6.0:
		return empty
	if terrain.surface_height(exit.x, exit.y) < terrain.surface_height(arrival.x, arrival.y) + 0.65:
		return empty
	for point in line:
		if not point.is_finite():
			return empty
	var knots := PackedVector2Array([exit])
	var begin := _station_index(line, exit, true)
	var end := _station_index(line, arrival, false)
	if end <= begin:
		return empty
	for i in range(begin, end + 1):
		var p := line[i]
		if p.distance_to(knots[-1]) > 0.32 and p.distance_to(arrival) > 0.32:
			knots.append(p)
	knots.append(arrival)

	# Round stylus/mouse corners inside the lane, never replacing the drawn
	# route with a chord through other parts of the forest.
	var curve := Curve2D.new()
	curve.bake_interval = 0.18
	for i in knots.size():
		var p := knots[i]
		var previous := knots[maxi(0, i - 1)]
		var following := knots[mini(i + 1, knots.size() - 1)]
		var tangent := (following - previous).normalized()
		curve.add_point(p, -tangent * minf(0.60, p.distance_to(previous) * 0.25), tangent * minf(0.60, p.distance_to(following) * 0.25))
	var length := curve.get_baked_length()
	if length < 3.0:
		return empty
	var spine := PackedVector2Array()
	var steps := maxi(12, ceili(length / 0.24))
	for i in range(steps + 1):
		spine.append(curve.sample_baked(length * float(i) / steps))
	spine[0] = exit
	spine[-1] = arrival
	if _run_open(spine, terrain, 0.20):
		return spine
	# On an especially tight corner, rounding can cut inside the grove.
	# Follow the actual cleared stroke there and keep its original switchback.
	spine = PackedVector2Array([knots[0]])
	for i in range(1, knots.size()):
		var count := maxi(1, ceili(knots[i-1].distance_to(knots[i]) / 0.24))
		for j in range(1, count + 1):
			spine.append(knots[i-1].lerp(knots[i], float(j) / count))
	return spine if _run_open(spine, terrain, 0.20) else empty


const CONTOUR_STRIDE := 3

static func _offset_at(samples: PackedVector2Array, row: int, last: int) -> Vector2:
	if row >= last:
		return samples[-1]
	var anchor := row / CONTOUR_STRIDE
	if row % CONTOUR_STRIDE == 0:
		return samples[anchor]
	var t := float(row % CONTOUR_STRIDE) / mini(CONTOUR_STRIDE,last-anchor*CONTOUR_STRIDE)
	return samples[anchor].cubic_interpolate(samples[anchor+1],samples[maxi(0,anchor-1)],samples[mini(samples.size()-1,anchor+2)],t)


func _plot_cut_run(spine: PackedVector2Array, rng: RandomNumberGenerator, lap: int, sites: Array) -> void:
	var reference := PackedFloat32Array([0.0])
	for i in range(1, spine.size()):
		reference.append(reference[-1] + spine[i].distance_to(spine[i-1]))
	var width := rng.randf_range(1.12, 1.52) * (1.17 if is_snowboarder else 1.0)
	var cadence := rng.randf_range(8.1, 10.0) * (1.18 if is_snowboarder else 1.0)
	var phase := rng.randf_range(-PI, PI) + 0.47 * sin(lap * 1.71)
	# The turns change over several metres. Sample contour direction every
	# three snow rows, interpolate the offsets, and still validate every row.
	var anchors := PackedVector2Array()
	for j in ceili(float(spine.size()-1)/CONTOUR_STRIDE)+1:
		var i := mini(j*CONTOUR_STRIDE,spine.size()-1)
		var d := reference[i]
		var center := spine[i]
		var travel := (spine[mini(i+2, spine.size()-1)] - spine[maxi(i-2,0)]).normalized()
		var across := Vector2(-travel.y, travel.x)
		var fall_line := -_gradient(center).normalized()
		var room := smoothstep(0.06, 0.68, travel.dot(fall_line))
		# Let the cut supply the big turn. Keep the guest's own short powder
		# turns on straighter sections without swinging across a hairpin.
		var incoming := (center - spine[maxi(0,i-5)]).normalized()
		var outgoing := (spine[mini(i+5,spine.size()-1)] - center).normalized()
		room *= lerpf(0.20, 1.0, smoothstep(0.25, 0.92, incoming.dot(outgoing)))
		var settle := smoothstep(0.0, 2.4, minf(d, reference[-1] - d))
		var angle := TAU * d / cadence + phase + 0.27 * sin(d * 0.36 + phase)
		if is_snowboarder:
			angle += 0.23 * cos(angle) * _toe_side
		var swing := width * room * settle * sin(angle)
		var offset := _follow_contour(center, absf(swing), across * signf(swing)) - center
		anchors.append(offset)
	var weave := PackedVector2Array()
	for i in spine.size():
		weave.append(_offset_at(anchors,i,spine.size()-1))
	# Every point stays within the cleared width. Tighter corridors reduce
	# the rider's arcs; even the narrowest option still follows all branches
	# of the validated line instead of returning to the lift's straight piste.
	var candidate := PackedVector2Array()
	candidate.resize(spine.size())
	for scale_factor: float in [1.0, 0.70, 0.40, 0.18, 0.0]:
		for i in spine.size():
			candidate[i] = spine[i] + scale_factor * weave[i]
		if scale_factor == 0.0 or _run_open(candidate, _terrain, 0.18):
			break
	if sites.is_empty():
		for p in candidate:
			_points.append(Vector3(p.x, _terrain.surface_height(p.x, p.y), p.y))
	else:
		var line := FeatureLine.new()
		line.build(candidate, spine, reference, _terrain, sites)
		_points = line.points
		_passes = line.passes
	for i in _points.size():
		if i > 0:
			_length += _points[i - 1].distance_to(_points[i])
		_distances.append(_length)


func _plot_line(summit: Vector2, base: Vector2, rng: RandomNumberGenerator, lap: int, piste_side: Vector2) -> void:
	var direct := base - summit
	var distance := direct.length()
	var along := direct.normalized()
	var cross_line := Vector2(-along.y, along.x)
	if cross_line.dot(piste_side) < 0.0:
		cross_line = -cross_line
	var turns := clampf(distance / rng.randf_range(8.4, 10.6), 1.05, 3.55)
	var width := clampf(distance * rng.randf_range(0.090, 0.122), 0.48, 3.65)
	# A board links longer traverses with a deeper arc across the hill.
	if is_snowboarder:
		turns *= 0.85
		width *= 1.20
	var margin := clampf(distance * 0.19, 1.2, 4.8)
	var phase := rng.randf_range(-PI, PI) + 0.57 * sin(lap * 2.4)
	width *= 1.0 + 0.12 * sin(lap * 1.7)
	var rhythm := rng.randf_range(0.28, 0.46)
	var subdivisions := maxi(40, ceili(distance * 6.0))
	var offsets := PackedFloat32Array()
	var stance_across_piste := _toe_side * cross_line.dot(Vector2(-along.y, along.x))
	for i in range(subdivisions + 1):
		var t := float(i) / subdivisions
		# One long traverse and shorter linked turns, with stable preferences
		# per rider. Slowly changing cadence avoids a metronomic slalom.
		var cycle := phase + TAU * turns * t + rhythm * (sin(TAU * t + phase) - sin(phase))
		if is_snowboarder:
			# Give the heel-side check a longer beat. Mirroring the stance or
			# the piste mirrors which half of each S receives the extra time.
			cycle += 0.23 * cos(cycle) * stance_across_piste
		# Link broad edge-to-edge arcs, with room to straighten at both terminals.
		var envelope := smoothstep(0.0, 0.20, t) * (1.0 - smoothstep(0.76, 1.0, t))
		var arc := sin(cycle) * (0.90 + 0.16 * sin(PI * 1.6 * t + phase * 0.5))
		# The two endpoints sit on the unloading side of the lift. Fan out onto
		# open snow and keep even the innermost arc outside the tower corridor.
		offsets.append(margin * sin(PI * t) + (1.0 + arc) * width * envelope)

	# A skier needs a continuous corridor for the entire arc. If a tree clips
	# an outer edge, tighten the whole line so it still has smooth edge changes.
	for scale_factor: float in [1.0, 0.72, 0.45, 0.22, 0.0]:
		_points.clear()
		_distances.clear()
		_length = 0.0
		var last_flat := summit
		var last_center_y: float = _terrain.surface_height(summit.x, summit.y)
		var anchors := PackedVector2Array()
		for j in ceili(float(subdivisions)/CONTOUR_STRIDE)+1:
			var i := mini(j*CONTOUR_STRIDE,subdivisions)
			var p := summit.lerp(base,float(i)/subdivisions)
			anchors.append(_follow_contour(p,offsets[i]*scale_factor,cross_line)-p)
		for i in offsets.size():
			var center := summit.lerp(base, float(i) / subdivisions)
			var flat := center + _offset_at(anchors,i,subdivisions)
			var point := Vector3(flat.x, _terrain.surface_height(flat.x, flat.y), flat.y)
			var center_y: float = _terrain.surface_height(center.x, center.y)
			if i > 0:
				var climb_limit := maxf(0.025, center_y - last_center_y + 0.012)
				if scale_factor > 0 and (point.y - _points[i-1].y > climb_limit or not _terrain.route_clear(last_flat, flat, 0.18)):
					break
				_length += point.distance_to(_points[i-1])
			_points.append(point)
			_distances.append(_length)
			last_flat = flat
			last_center_y = center_y
		if _points.size() == offsets.size():
			return


func _contour_direction(point: Vector2, previous: Vector2) -> Vector2:
	var gradient := _gradient(point)
	if gradient.length_squared() < 0.006:
		return previous
	var tangent := gradient.normalized().orthogonal()
	return tangent if tangent.dot(previous) >= 0 else -tangent


func _follow_contour(center: Vector2, swing: float, side: Vector2) -> Vector2:
	# Walk across the mountain following its actual elevation contour. A single
	# tangent line would cut uphill when a wide turn wraps round a shoulder.
	if swing < 0.0001:
		return center
	var steps := maxi(1, ceili(swing / 1.05))
	var stride := swing / steps
	var point := center
	var direction := side
	for i in steps:
		direction = _contour_direction(point, direction)
		direction = _contour_direction(point + direction * stride * 0.5, direction)
		var next := point + direction * stride
		if not _terrain.playable_at(next):
			break
		point = next
	return point


func _point_at(distance: float) -> Vector3:
	var index := clampi(_distances.bsearch(distance), 1, _points.size() - 1)
	var start := _distances[index - 1]
	var end := _distances[index]
	var blend := clampf((distance - start) / maxf(0.00001, end - start), 0.0, 1.0)
	return _points[index - 1].lerp(_points[index], blend)


func _heading(distance: float) -> Vector3:
	return (_point_at(distance + 0.24) - _point_at(distance - 0.24)).normalized()


func step(delta: float) -> void:
	if not _active or delta <= 0.0:
		return
	var remaining := delta
	var touched_down := false
	while remaining > 0.00001 and _travelled < _length:
		var dt := minf(remaining, 1.0 / 30.0)
		var heading := _heading(_travelled)
		# Gravity acts along the skis: the fall line accelerates the skier,
		# crossing the slope damps that acceleration, and air drag limits speed.
		var gravity := -heading.y * 8.5
		var acceleration := gravity - 0.24 - _drag * _speed * _speed
		if is_snowboarder:
			# A board can feather its tail on a loaded edge. The heel-side
			# check scrubs a little more speed before releasing into the fall line.
			var right := heading.cross(Vector3.UP).normalized()
			var edge_load := _bend_at(_travelled, right) * _speed * _speed / 9.0
			var heel := clampf(-edge_load * _toe_side, 0.0, 1.0)
			acceleration -= _speed * smoothstep(0.08, 0.9, absf(edge_load)) * (0.09 + 0.09 * heel)
		_speed = clampf(_speed + acceleration * dt, 1.25, 6.4)
		# Round off the last turn and glide gently into the loading area.
		var glide_limit := lerpf(1.25, 6.4, smoothstep(0.0, 3.5, _length - _travelled))
		_speed = minf(_speed, glide_limit)
		if _pass_index < _passes.size():
			var feature := _passes[_pass_index]
			var to_lip := _distances[feature.lip_row] - _travelled
			# Carry speed through the approach and take off in the fall line.
			if to_lip < 4.0:
				var horizontal := maxf(0.28, Vector2(heading.x, heading.z).length())
				var target := feature.horizontal_speed / horizontal
				_speed = lerpf(_speed, target, 1.0 - smoothstep(0.0, 4.0, to_lip))
		_travelled = minf(_length, _travelled + dt * _speed)
		_landing_age += dt
		if _pass_index < _passes.size() and _travelled >= _distances[_passes[_pass_index].landing_row]:
			_pass_index += 1
			_landing_age = 0.0
			touched_down = true
		remaining -= dt
	_update_pose(delta)
	if touched_down:
		_model.touch_down(_speed)
	_track.reveal(maxf(0.0, _travelled - (0.45 if is_snowboarder else 0.32)))
	if _travelled >= _length:
		_active = false
		_sound.release()
		_track.finish()
		finished.emit()


func _bend_at(distance: float, right: Vector3) -> float:
	var ahead := minf(_length, distance + 0.52)
	var behind := maxf(0.0, distance - 0.24)
	return (_heading(ahead) - _heading(behind)).dot(right) / maxf(ahead - behind, 0.01)


func _update_pose(delta: float) -> void:
	var point := _point_at(_travelled)
	var gradient := _gradient(Vector2(point.x, point.z))
	var snow_normal := Vector3(-gradient.x, 1.0, -gradient.y).normalized()
	var heading := _heading(_travelled)
	var takeoff := 0.0
	var flight := 0.0
	if _pass_index < _passes.size():
		var feature := _passes[_pass_index]
		var lip := _distances[feature.lip_row]
		takeoff = smoothstep(_distances[feature.ramp_row], lip, _travelled)
		if airborne:
			flight = clampf((_travelled - lip) / (_distances[feature.landing_row] - lip), 0.0, 1.0)
		if takeoff > 0.0:
			# Ease from edge contact into a flat, fall-line deck. By touchdown it
			# already matches the landing slope rather than pointing into the snow.
			var grade := clampf(heading.y / maxf(0.01, Vector2(heading.x, heading.z).length()), -0.58, 0.40)
			var along := Vector3(heading.x, 0.0, heading.z).normalized()
			var deck_direction := (along + Vector3.UP * grade).normalized()
			var deck_up := deck_direction.cross(Vector3.UP).cross(deck_direction).normalized()
			snow_normal = snow_normal.slerp(deck_up, takeoff * (1.0 - smoothstep(0.68, 1.0, flight)))
	var right := heading.cross(snow_normal).normalized()
	var forward := snow_normal.cross(right).normalized()
	var orientation := Basis(right, snow_normal, -forward)
	if _transferred and _travelled < 1.15:
		orientation = _entry_basis.slerp(orientation, smoothstep(0.0, 1.15, _travelled))
	global_transform = Transform3D(orientation, point)
	var bend := _bend_at(_travelled, right)
	# Banking follows centripetal acceleration. Filtering avoids abrupt edge
	# swaps even on short turns and keeps the body moving between carved arcs.
	var bank_target := 0.68 * tanh(bend * _speed * _speed / 8.8) * (1.0 - takeoff)
	if is_snowboarder:
		var heel := smoothstep(0.0, 0.5, -bank_target * _toe_side)
		bank_target *= lerpf(1.08, 0.90, heel)
		_bank = lerpf(_bank, bank_target, 1.0 - exp(-6.4 * delta))
		# Let the tail smear slightly across the path on heel-side checks.
		global_rotate(snow_normal, -_bank * lerpf(0.05, 0.20, heel))
	else:
		_bank = lerpf(_bank, bank_target, 1.0 - exp(-7.5 * delta))
	# The upper body keeps looking into the fall line while the skis turn
	# under it. Advance the weight transfer slightly ahead of the edge swap.
	var downhill := Vector3(-gradient.x, 0.0, -gradient.y).slide(snow_normal).normalized()
	var counter_yaw := clampf(-atan2(downhill.dot(right), downhill.dot(forward)), -0.50, 0.50)
	var pressure := clampf(absf(_bank) / 0.67, 0, 1)
	var impact := (1.0 - smoothstep(0.06, 0.37, _landing_age)) * lerpf(0.55, 1.0, smoothstep(0.0, 0.06, _landing_age))
	var tuck := takeoff * (0.32 + 0.48 * sin(PI * flight))
	pressure = maxf(pressure, maxf(tuck, impact))
	_model.pose(_bank, _speed, bend, counter_yaw * (1.0 - takeoff), pressure, airborne)
	_sound.shape(_speed, _bank, _length - _travelled, delta, airborne, impact)
