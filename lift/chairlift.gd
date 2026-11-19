extends Node3D

const Skier = preload("res://skiing/skier.gd")
const RiderStyle = preload("res://skiing/rider_style.gd")
const Guest = preload("res://lift/transfer_guest.gd")
const Fixtures = preload("res://lift/lift_fixtures.gd")
const UNLOAD_SECONDS := 1.25
enum Handoff { RIDING, BOARDING, UNLOADING }

class Descent:
	var forward: Vector2
	var side: Vector2
	var exit: Vector2
	var queue := PackedVector2Array()
const WHEEL_RADIUS := 0.58
const LANE_RADIUS := [WHEEL_RADIUS, 0.98, 1.24]
const TERMINAL_HEIGHT := [1.88, 2.08, 2.40]
const CAPACITY := [1, 2, 4]
const TRAM_DWELL := 4.65
const RUBBER := Color("#344550")

class Carrier extends Node3D:
	var distance := 0.0
	var riders: Array[Guest] = []
	var passenger: Guest:
		get:
			for rider in riders:
				if rider != null:
					return rider
			return null
	var guest: int:
		get: return passenger.variant if passenger != null else -1
	var handoff := Handoff.RIDING
	var handoff_time := 0.0
	var handoff_from: Array[Transform3D] = []
	var lane := 1.0
	var doors: Array[Node3D] = []
	var swing := 0.0
	var swing_speed := 0.0

var tier := 0
var support_spacing_scale := 1.0
var _wheel_radius: float
var _tram_dwell := TRAM_DWELL
var _tram_in_transit := 0.0
var _tram_outbound := true
var _runs: Array[PackedVector2Array] = []
var _run_spines: Array[PackedVector2Array] = []
var _spine_revisions := PackedInt64Array()
var _features_by_run := {}
var _next_ledge := {}
var _next_feature_departure := {}
var _elapsed := 0.0
var _first_tracks: Array[int] = []
var _last_player_run: Dictionary[int, int] = {}
var _took_cut_last_time: Dictionary[int, bool] = {}

var _terrain: Node
var _base: Vector2
var _summit: Vector2
var _forward: Vector2
var _right: Vector2
var _span: float
var _bend: float
var _loop_length: float
var _speed: float
var _heights := PackedFloat32Array()
var _chairs: Array[Carrier] = []
var _queue: Array[Guest] = []
var _ski_exit: Vector2
var _queue_points := PackedVector2Array()
var _laps: Dictionary[int, int] = {}
var _skiers: Array[Node3D] = []
var _tracks: Node3D
var _skiers_parent: Node3D
var _materials := {}
var _unit_box := BoxMesh.new()
var _unit_cylinder := CylinderMesh.new()

# These lifecycle signals also make a full round trip observable in headless playtests.
signal boarded(guest: int)
signal unloaded(guest: int)
signal returned(guest: int)
signal run_completed(run_id: int)


static func descent_fits(base: Vector2, summit: Vector2, terrain: Node, lift_tier: int = 0) -> bool:
	return _choose_descent(base, summit, terrain, lift_tier) != null


static func _choose_descent(base: Vector2, summit: Vector2, terrain: Node, lift_tier: int = 0, allow_tree_cut := false, preferred_side := Vector2.ZERO) -> Descent:
	if base.distance_squared_to(summit) < 1.0:
		return null
	var forward := (summit - base).normalized()
	var side := Vector2(forward.y, -forward.x)
	var midpoint := base.lerp(summit, 0.5)
	# Start with the side facing the center of the valley. A lower or more open
	# outside slope is still available when the inside crosses a knoll or grove.
	if absf(midpoint.x - side.x * 3.0) < absf(midpoint.x + side.x * 3.0):
		side = -side
	if preferred_side != Vector2.ZERO:
		side = side if side.dot(preferred_side) >= 0.0 else -side
	var open := Callable(terrain,"lift_ground_clear" if allow_tree_cut else "route_clear")
	for signum: float in [1.0, -1.0]:
		var plan := Descent.new()
		plan.forward = forward
		plan.side = side * signum
		plan.exit = summit + plan.side * 1.85 - forward * 0.23
		if lift_tier == 2:
			plan.exit = summit + plan.side * 2.69 - forward * 1.57
		for i in RiderStyle.GUEST_COUNT:
			var offset := plan.side * (WHEEL_RADIUS + 0.2 + 0.32 * i) - forward * (0.26 + 0.22 * i)
			plan.queue.append(base + offset)
		if not open.call(plan.exit, plan.queue[4], 0.25):
			continue
		if not open.call(base, plan.queue[0], 0.24) or not open.call(plan.queue[0], plan.queue[-1], 0.24):
			continue
		var radius: float = LANE_RADIUS[clampi(lift_tier, 0, 2)]
		var unload_tip := summit + plan.side * radius + forward * 0.95
		if not open.call(summit, unload_tip, 0.30) or not open.call(unload_tip, plan.exit, 0.30):
			continue
		# Use the tessellated surface and the real start/stop positions. A small
		# uphill bump can be carried on momentum, a sustained climb cannot.
		var end := plan.queue[4]
		if allow_tree_cut:
			var line := PackedVector2Array([plan.exit,end])
			if preload("res://world/run_profile.gd").flows_downhill(line,terrain):
				return plan
			continue
		var previous: float = terrain.surface_height(plan.exit.x, plan.exit.y)
		var climb := 0.0
		var samples := maxi(1, ceili(plan.exit.distance_to(end) * 6.0))
		for i in range(1, samples + 1):
			var point := plan.exit.lerp(end, float(i) / samples)
			var height: float = terrain.surface_height(point.x, point.y)
			climb += maxf(0.0, height - previous)
			previous = height
			if climb > 0.08:
				break
		if climb <= 0.08:
			return plan
	return null


func configure(base: Vector2, summit: Vector2, terrain: Node, lift_tier: int = 0, accepted: Descent = null, seed_hill := true) -> void:
	if _terrain != null:
		return
	tier = clampi(lift_tier, 0, 2)
	_wheel_radius = LANE_RADIUS[tier]
	var plan := accepted if accepted != null else _choose_descent(base, summit, terrain, tier)
	if plan == null:
		return
	_terrain = terrain
	_base = base
	_summit = summit
	_span = base.distance_to(summit)
	_forward = plan.forward
	_right = plan.side
	_ski_exit = plan.exit
	_queue_points = plan.queue
	_bend = PI * _wheel_radius
	_loop_length = 2.0 * (_span + _bend)
	_speed = clampf(_span / 10.0, 1.1, 3.25)
	if tier == 1:
		_speed = clampf(_span / 10.0, 2.45, 4.5)
	elif tier == 2:
		_speed = clampf(_span / 10.4, 7.8, 11.8)

	_unit_cylinder.radial_segments = 10
	_unit_cylinder.rings = 1
	_unit_cylinder.top_radius = 0.5
	_unit_cylinder.bottom_radius = 0.5
	_unit_cylinder.height = 1.0

	_tracks = Node3D.new()
	_skiers_parent = Node3D.new()
	_tracks.name = "Tracks"
	_skiers_parent.name = "Skiers"
	add_child(_tracks)
	add_child(_skiers_parent)
	_build_line()
	# Seed a hill already in use. Subsequent laps use exactly the same transitions.
	if seed_hill:
		_start_descent(0)
	if tier == 2:
		for i in 2:
			var cabin := _make_chair()
			cabin.lane = 1.0 if i == 0 else -1.0
			cabin.distance = _span * i
			_chairs.append(cabin)
			_pose_chair(cabin)
		for guest_id in [1, 2, 3, 4, 5, RiderStyle.GOOFY_BOARDER]:
			_join_queue(guest_id)
		_board(_chairs[0])
	else:
		var chair_count := clampi(roundi(_loop_length / (5.5 if tier == 0 else 8.8)), 6, 16)
		for i in chair_count:
			var chair := _make_chair()
			chair.distance = (float(i) + 0.25) * _loop_length / chair_count
			_chairs.append(chair)
			_pose_chair(chair)
			if i < 2 and chair.distance < _span:
				var seeded := _new_guest(i + 1)
				chair.riders.append(seeded)
				seeded.transform = _seat_transform(chair, 0)
				seeded.sit(1.0)
		for guest_id in [3, 4, 5, RiderStyle.GOOFY_BOARDER]:
			_join_queue(guest_id)
	if seed_hill:
		# The initial diorama is already running. Newly opened lifts greet
		# these same two guests at the base for their first ride instead.
		for tick in 48:
			_advance(1.0 / 30.0)
		_start_descent(RiderStyle.REGULAR_BOARDER)
	else:
		_join_queue(0)
		_join_queue(RiderStyle.REGULAR_BOARDER)


func _process(delta: float) -> void:
	if _terrain == null:
		return
	# One stalled frame should not skip anyone past both transfer points.
	var remaining := delta
	while remaining > 0.00001:
		var step_time := minf(remaining, 0.1)
		_advance(step_time)
		remaining -= step_time


func _advance(dt: float) -> void:
	_elapsed += dt
	# Work backwards because a skier can finish and leave this array during step().
	for i in range(_skiers.size() - 1, -1, -1):
		_skiers[i].call(&"step", dt)
	for i in _queue.size():
		var guest := _queue[i]
		var target := _queue_spot(i)
		var old := Vector2(guest.position.x, guest.position.z)
		if guest.approaching_island:
			var apron := _base - _forward * 2.84
			if old.distance_to(apron) < 0.05:
				guest.approaching_island = false
			else:
				target = _world(apron, _ground(apron))
		var p := old.move_toward(Vector2(target.x, target.z), dt * 1.65)
		guest.position = _world(p, _queue_height(p))
		var step_dir := (p - old).normalized()
		var facing := _forward if step_dir.is_zero_approx() else step_dir
		guest.basis = guest.basis.slerp(_snow_basis(guest.position, facing), 1.0 - exp(-5.0 * dt))
		guest.shuffle(p.distance_to(old), dt)
	if tier == 2:
		_advance_tram(dt)
	else:
		for chair in _chairs:
			var previous := chair.distance
			chair.distance = fposmod(previous + _speed * dt, _loop_length)
			chair.swing_speed -= (15.0 * chair.swing + 3.4 * chair.swing_speed) * dt
			chair.swing += chair.swing_speed * dt
			_pose_chair(chair)
			if chair.distance < previous:
				_board(chair)
			elif previous < _span and chair.distance >= _span:
				_unload(chair)
	for chair in _chairs:
		if not chair.riders.is_empty():
			_move_passengers(chair, dt)


func _advance_tram(dt: float) -> void:
	# Two counterbalanced cabins stop at opposite stations, exchange guests,
	# then reverse on the same two track ropes.
	if _tram_dwell > 0.0:
		_tram_dwell = maxf(0.0, _tram_dwell - dt)
		var open := smoothstep(0, 0.30, _tram_dwell) * smoothstep(0, 0.32, TRAM_DWELL - _tram_dwell)
		for cabin in _chairs:
			for i in cabin.doors.size():
				cabin.doors[i].position.z = (1 if i % 2 else -1) * (0.21 + open * 0.37)
		return
	var travel_time := _span / _speed + 1.4
	_tram_in_transit = minf(_tram_in_transit + dt, travel_time)
	var t := _tram_in_transit / travel_time
	# Accelerate out and brake into each station, keeping a long constant-speed middle.
	var progress := t
	const RAMP := 0.13
	if t < RAMP:
		progress = t * t / (2 * RAMP)
	elif t > 1.0 - RAMP:
		progress = 1.0 - RAMP - (1.0 - t) * (1.0 - t) / (2 * RAMP)
	else:
		progress = t - 0.5 * RAMP
	progress /= 1.0 - RAMP
	for i in 2:
		var cabin := _chairs[i]
		var outgoing := _tram_outbound == (i == 0)
		cabin.distance = (progress if outgoing else 1.0 - progress) * _span
		_pose_chair(cabin)
		if t >= 1.0:
			if outgoing:
				_unload(cabin)
			else:
				_board(cabin)
	if t >= 1.0:
		_tram_outbound = not _tram_outbound
		_tram_in_transit = 0.0
		_tram_dwell = TRAM_DWELL


func _board(c: Carrier) -> void:
	if _queue.is_empty() or not c.riders.is_empty():
		return
	var ready_count := 0
	for i in mini(CAPACITY[tier], _queue.size()):
		if _queue[i].approaching_island or _queue[i].position.distance_to(_queue_spot(i)) > 0.64:
			break
		ready_count += 1
	if ready_count == 0:
		return
	c.handoff = Handoff.BOARDING
	c.handoff_time = 0.0
	c.handoff_from.clear()
	for i in ready_count:
		var rider: Guest = _queue.pop_front()
		c.riders.append(rider)
		c.handoff_from.append(rider.transform)
		boarded.emit(rider.variant)
	c.swing_speed = 0.28


func _unload(c: Carrier) -> void:
	if c.riders.is_empty():
		return
	c.handoff = Handoff.UNLOADING
	c.handoff_time = 0.0
	c.handoff_from.clear()
	for i in c.riders.size():
		c.handoff_from.append(_seat_transform(c, i))
	c.swing_speed = -0.18


func _seat_transform(c: Carrier, index: int) -> Transform3D:
	var offset := Vector3(0.0, -1.49, 0.20)
	if tier == 1:
		offset.x = -0.33 if index == 0 else 0.33
	elif tier == 2:
		offset = Vector3(-0.32 if index % 2 == 0 else 0.32, -1.98, 0.32 if index < 2 else -0.32)
	return c.transform * Transform3D(Basis(Vector3.UP, PI), offset)


func _snow_basis(point: Vector3, facing: Vector2) -> Basis:
	var p := Vector2(point.x, point.z)
	var dx := _ground(p + Vector2(0.12, 0)) - _ground(p - Vector2(0.12, 0))
	var dz := _ground(p + Vector2(0, 0.12)) - _ground(p - Vector2(0, 0.12))
	var up := Vector3(-dx, 0.24, -dz).normalized()
	var direction := _world(facing, 0.0).slide(up).normalized()
	return Basis.looking_at(direction, up)


func _move_passengers(c: Carrier, dt: float) -> void:
	c.handoff_time += dt
	for i in c.riders.size():
		var rider := c.riders[i]
		if rider == null:
			continue
		var stagger := i * (0.37 if tier == 2 else 0.14)
		var elapsed := maxf(0.0, c.handoff_time - stagger - (0.24 if tier == 2 else 0.0))
		if c.handoff == Handoff.BOARDING:
			var duration := 1.56 if tier == 2 else 0.78
			var t := clampf(elapsed / duration, 0.0, 1.0)
			if tier == 2:
				_tram_transfer(rider, c, c.handoff_from[i], i, t, true, dt)
			else:
				_load_chair(rider, c.handoff_from[i], _seat_transform(c, i), t)
			if i == c.riders.size() - 1 and t >= 1.0:
				c.handoff = Handoff.RIDING
		elif c.handoff == Handoff.UNLOADING:
			var duration := 2.90 if tier == 2 else UNLOAD_SECONDS
			var t := clampf(elapsed / duration, 0.0, 1.0)
			if tier == 2:
				_tram_transfer(rider, c, c.handoff_from[i], i, t, false, dt)
			else:
				_glide_off(rider, c.handoff_from[i], t)
			if t >= 1.0:
				var variant := rider.variant
				c.riders[i] = null
				_start_descent(variant, rider)
				unloaded.emit(variant)
		else:
			rider.transform = _seat_transform(c, i)
	if c.handoff == Handoff.UNLOADING and c.passenger == null:
		c.riders.clear()
		c.handoff_from.clear()
		c.handoff = Handoff.RIDING


func _load_chair(rider: Guest, start: Transform3D, seat: Transform3D, t: float) -> void:
	# Slide the equipment on the snow until the bench catches the knees.
	var path := start.origin.lerp(seat.origin, smoothstep(0.0, 0.94, t))
	var p := Vector2(path.x, path.z)
	var sitting := smoothstep(0.32, 0.82, t)
	path.y = lerpf(_ground(p), seat.origin.y, smoothstep(0.38, 1.0, t))
	rider.transform = Transform3D(start.basis.slerp(seat.basis, smoothstep(0.0, 0.76, t)), path)
	rider.sit(sitting)


func _tram_transfer(rider: Guest, cabin: Carrier, start: Transform3D, seat: int, t: float, loading: bool, dt: float) -> void:
	# Both cars share the island between the two tracks. Step across the actual
	# center of the open sliding doors before moving to or from a standing spot.
	var floor_y := cabin.position.y - 1.955
	var inward := -_right * cabin.lane
	var door := cabin.position + _world(inward * 0.81, 0)
	door.y = floor_y
	var seat_pose := _seat_transform(cabin, seat)
	var station := _base if loading else _summit
	var apron := _world(station - _forward * 2.65, 0)
	apron.y = _ground(Vector2(apron.x, apron.z))
	var exit := _world(_ski_exit, _ground(_ski_exit))
	var aisle := door + _world(inward * 0.34 - _forward * 0.68, 0)
	var inside := seat_pose.origin
	var inside_door := door - _world(inward * 0.32, 0)
	var outside_door := door + _world(inward * 0.37, 0)
	var u := smoothstep(0.0, 1.0, t)
	var pos: Vector3
	if loading:
		if u < 0.61:
			pos = start.origin.bezier_interpolate(start.origin.lerp(aisle, 0.70), outside_door, door, u / 0.61)
		else:
			pos = door.bezier_interpolate(inside_door, inside.lerp(inside_door, 0.36), inside, (u - 0.61) / 0.39)
	else:
		if u < 0.24:
			pos = inside.bezier_interpolate(inside.lerp(inside_door, 0.36), inside_door, door, u / 0.24)
		elif u < 0.59:
			var approach := apron + _world(_forward * 0.77, 0)
			pos = door.bezier_interpolate(outside_door, approach, apron, (u - 0.24) / 0.35)
			pos.y = _station_height(Vector2(pos.x, pos.z), station, floor_y)
		else:
			var first := apron + _world(_right * 0.85 - _forward * 0.33, 0)
			var last := exit + _world(_forward * 0.38, 0)
			pos = apron.bezier_interpolate(first, last, exit, (u - 0.59) / 0.41)
			pos.y = _ground(Vector2(pos.x, pos.z))
	var moved := pos.distance_to(rider.position)
	var across := -inward if loading else inward
	var through_door := Basis.looking_at(_world(across, 0.0), Vector3.UP)
	var facing := seat_pose.basis if loading else _snow_basis(pos, -_forward)
	var threshold := 0.61 if loading else 0.24
	var orientation := start.basis.slerp(through_door, smoothstep(0.0, threshold, u))
	if not loading and u > threshold:
		var motion := Vector2(pos.x - rider.position.x, pos.z - rider.position.z)
		if motion.length_squared() > 0.00002:
			facing = _snow_basis(pos, motion.normalized())
		orientation = rider.basis.slerp(facing, 1.0 - exp(-8.0 * dt))
	else:
		orientation = orientation.slerp(facing, smoothstep(threshold, 1.0, u))
	rider.transform = Transform3D(orientation, pos)
	rider.shuffle(moved, dt)


func _glide_off(rider: Guest, start_pose: Transform3D, t: float) -> void:
	# Carry the chair's forward motion out over the snow, then arc around the
	# terminal toward the piste before the skier begins their first downhill turn.
	var start := Vector2(start_pose.origin.x, start_pose.origin.z)
	var handle := clampf(_speed * 0.34, 0.38, 0.87)
	var first := start + _forward * handle
	var last := _ski_exit + _forward * 0.58
	var p := start.bezier_interpolate(first, last, _ski_exit, t)
	var tangent := start.bezier_derivative(first, last, _ski_exit, t).normalized()
	var contact := smoothstep(0.04, 0.59 if rider.board != null else 0.52, t)
	var start_gap := start_pose.origin.y - _ground(start)
	var pos := _world(p, _ground(p) + start_gap * (1.0 - contact))
	var orientation := start_pose.basis.slerp(_snow_basis(pos, tangent), smoothstep(0, 0.36, t))
	rider.transform = Transform3D(orientation, pos)
	if tier < 2:
		rider.sit(1.0 - contact)


func run_start() -> Vector2:
	return _ski_exit


func run_end() -> Vector2:
	return _queue_xz(4)


func register_run(points: PackedVector2Array) -> int:
	if _terrain == null or points.size() < 2:
		return -1
	var spine := Skier.cut_run_spine(run_start(), run_end(), points, _terrain)
	if spine.is_empty():
		return -1
	_runs.append(points.duplicate())
	_run_spines.append(spine)
	_spine_revisions.append(_terrain.route_revision)
	_first_tracks.append(_runs.size() - 1)
	return _runs.size() - 1


func set_run_feature(run_id: int, site: Dictionary) -> void:
	if run_id < 0 or run_id >= _runs.size() or (site.kind == 1 and tier != 2):
		return
	var sites: Array = _features_by_run.get_or_add(run_id, [])
	for existing: Dictionary in sites:
		if existing.point.is_equal_approx(site.point):
			return
	sites.append(site.duplicate())
	if site.kind == 1:
		# First tracks go to the newly opened line for each discipline.
		_next_ledge[run_id] = [site.point, site.point]
	_first_tracks.erase(run_id)
	_first_tracks.push_front(run_id)


func _sites_for_lap(run_id: int, variant: int) -> Array:
	var installed: Array = _features_by_run.get(run_id, [])
	if not _next_ledge.has(run_id):
		return installed
	var route: Array = []
	var ledges: Array = []
	for site: Dictionary in installed:
		if site.kind == 1:
			ledges.append(site)
		else:
			route.append(site)
	var discipline := int(RiderStyle.is_boarder(variant))
	var next: Vector2 = _next_ledge[run_id][discipline]
	for i in ledges.size():
		if next.is_equal_approx(ledges[i].point):
			route.append(ledges[i])
			_next_ledge[run_id][discipline] = ledges[(i + 1) % ledges.size()].point
			break
	return route


func _start_descent(variant: int, guest: Guest = null) -> void:
	var skier = Skier.new()
	skier.name = "Skier%d" % variant
	_skiers_parent.add_child(skier)
	_skiers.append(skier)
	var run_id := -1
	var authored := PackedVector2Array()
	var spine := PackedVector2Array()
	var first_tracks := not _first_tracks.is_empty()
	if first_tracks:
		run_id = _first_tracks.pop_front()
	elif not _runs.is_empty() and not _took_cut_last_time.get(variant, variant % 2 == 1):
		run_id = (_last_player_run.get(variant, -1) + 1) % _runs.size()
	# A tram can unload a group almost together. Leave a clear landing
	# between feature riders while their companions take the regular piste.
	if _features_by_run.has(run_id):
		if _elapsed < float(_next_feature_departure.get(run_id, 0.0)):
			if first_tracks:
				_first_tracks.push_front(run_id)
			run_id = -1
		else:
			_next_feature_departure[run_id] = _elapsed + 1.6
	if run_id >= 0:
		authored = _runs[run_id]
		if _spine_revisions[run_id] != _terrain.route_revision:
			_run_spines[run_id] = Skier.cut_run_spine(run_start(),run_end(),authored,_terrain)
			_spine_revisions[run_id] = _terrain.route_revision
		spine = _run_spines[run_id]
		if spine.is_empty():
			authored = PackedVector2Array()
	if guest == null:
		guest = _new_guest(variant)
		guest.transform = Transform3D(_snow_basis(_world(_ski_exit, _ground(_ski_exit)), -_forward), _world(_ski_exit, _ground(_ski_exit)))
	skier.start_run(run_start(), run_end(), variant, _terrain, _tracks, _laps.get(variant, 0), _right, authored, _sites_for_lap(run_id, variant), guest, spine, true)
	if run_id >= 0 and skier.used_cut_run:
		_last_player_run[variant] = run_id
		skier.cut_run_id = run_id
	else:
		run_id = -1
	_took_cut_last_time[variant] = run_id >= 0
	skier.finished.connect(_finish_descent.bind(skier, variant, run_id), CONNECT_ONE_SHOT)


func _finish_descent(skier: Node3D, variant: int, run_id: int) -> void:
	_laps[variant] = _laps.get(variant, 0) + 1
	_skiers.erase(skier)
	var guest: Guest = skier._model
	guest.reparent(self, true)
	guest._sitting = -1.0
	guest.approaching_island = tier == 2
	if guest._powder != null:
		guest._powder.leave_snow()
	_queue.append(guest)
	skier.hide()
	skier.queue_free()
	returned.emit(variant)
	if run_id >= 0:
		run_completed.emit(run_id)


func _new_guest(variant: int) -> Guest:
	var guest := Guest.new()
	guest.name = "Guest%d" % variant
	add_child(guest)
	guest.prepare(variant, Skier.jacket_color(variant))
	return guest


func _join_queue(variant: int) -> Guest:
	var guest := _new_guest(variant)
	guest.position = _queue_spot(_queue.size())
	guest.basis = _snow_basis(guest.position, _forward)
	_queue.append(guest)
	return guest


func _queue_xz(i: int) -> Vector2:
	return _queue_points[i]


func _queue_spot(i: int) -> Vector3:
	var point := _queue_xz(i)
	if tier == 2:
		point = _base + _right * minf(0.18, 0.035 * i) - _forward * (0.55 + 0.58 * i)
	return _world(point, _queue_height(point))


func _queue_height(p: Vector2) -> float:
	if tier != 2:
		return _ground(p)
	return _station_height(p, _base, _heights[0] - 1.955)


func _station_height(p: Vector2, station: Vector2, floor_y: float) -> float:
	var offset := p - station
	var ramp := clampf((2.7 - absf(offset.dot(_forward))) / (2.7 - 1.12), 0.0, 1.0)
	var width := 1.0 - smoothstep(0.44, 0.57, absf(offset.dot(_right)))
	return lerpf(_ground(p), floor_y, width * ramp)



func _world(xz: Vector2, height: float) -> Vector3:
	return Vector3(xz.x, height, xz.y)


func _ground(xz: Vector2) -> float:
	return _terrain.call(&"surface_height", xz.x, xz.y)


func _upright(facing: Vector2) -> Basis:
	return Basis(Vector3(facing.y, 0, -facing.x), Vector3.UP, Vector3(facing.x, 0, facing.y))


func _build_line() -> void:
	var spans := clampi(ceili(_span / ((24.0 if tier == 2 else 12.5) * support_spacing_scale)), 2, 8)
	for i in range(spans + 1):
		var point := _base.lerp(_summit, float(i) / spans)
		var mast_height: float = TERMINAL_HEIGHT[tier] if i == 0 or i == spans else [3.05, 3.65, 5.10][tier]
		var cable_y := _ground(point) + mast_height
		if tier == 2:
			cable_y = maxf(cable_y, _tram_clearance_height(point))
		_heights.append(cable_y)
	# A convex shoulder can rise into a straight cable. Sample both travel lanes and
	# lift the neighboring support wherever their sagging chord needs more clearance.
	for i in spans:
		var raise_start := 0.0
		var raise_end := 0.0
		for j in range(1, 16):
			var f := float(j) / 16
			var center := _base.lerp(_summit, (i + f) / spans)
			var required := _tram_clearance_height(center) if tier == 2 else 1.80 + maxf(
				_ground(center + _right * _wheel_radius), _ground(center - _right * _wheel_radius))
			var clearance := required - _section_height(i, f)
			if clearance > 0:
				if i == 0:
					raise_end = maxf(raise_end, clearance / f)
				elif i == spans - 1:
					raise_start = maxf(raise_start, clearance / (1.0 - f))
				else:
					raise_start = maxf(raise_start, clearance)
					raise_end = maxf(raise_end, clearance)
		_heights[i] += raise_start
		_heights[i + 1] += raise_end
	for i in range(spans + 1):
		var center := _base.lerp(_summit, float(i) / spans)
		_support(center, _heights[i], i == 0 or i == spans)
	# Straight spans and terminal curves are sampled separately so the cable meets
	# the sheaves precisely; chairs use this same continuous centerline.
	if tier == 2:
		for side in [-1.0, 1.0]:
			var previous := _tram_cable(0.0, side)
			for j in range(1, spans * 7 + 1):
				var next := _tram_cable(float(j) / (spans * 7), side)
				_rod(self, previous, next, 0.063, RUBBER)
				previous = next
		return
	var edges: Array[float] = [0.0, _span, _span + _bend, 2.0 * _span + _bend, _loop_length]
	for section in 4:
		var steps := spans * 6 if section % 2 == 0 else 9
		var prev := _cable_position(edges[section])
		for j in range(1, steps + 1):
			var at := lerpf(edges[section], edges[section + 1], float(j) / steps)
			var point := _cable_position(at)
			_rod(self, prev, point, 0.042, RUBBER)
			prev = point


func _tram_clearance_height(center: Vector2) -> float:
	# A tram's uphill floor corner passes above different terrain from the
	# rope centerline, especially when the line approaches a summit diagonally.
	var highest := -INF
	for lane: float in [-1.0, 1.0]:
		var cable := center + _right * _wheel_radius * lane
		for side: float in [-0.77, 0.77]:
			for end: float in [-0.90, 0.90]:
				highest = maxf(highest, _ground(cable + _right * side + _forward * end))
	return highest + 2.24


func _tram_cable(t: float, lane: float) -> Vector3:
	return _world(_base.lerp(_summit, t) + _right * _wheel_radius * lane, _span_height(t))


func _section_height(i: int, f: float) -> float:
	var segment_length := _span / (_heights.size() - 1)
	return lerpf(_heights[i], _heights[i + 1], f) - 4.0 * f * (1.0 - f) * minf(0.2, segment_length * 0.017)


func _span_height(t: float) -> float:
	var scaled := clampf(t, 0, 1) * (_heights.size() - 1)
	var i := mini(floori(scaled), _heights.size() - 2)
	return _section_height(i, scaled - i)


func _cable_position(distance: float) -> Vector3:
	if distance <= _span:
		var t := distance / _span
		return _world(_base.lerp(_summit, t) + _right * _wheel_radius, _span_height(t))
	var d := distance - _span
	if d <= _bend:
		var a := d / _wheel_radius
		return _world(_summit + _wheel_radius * (_right * cos(a) + _forward * sin(a)), _heights[-1])
	d -= _bend
	if d <= _span:
		var t := 1.0 - d / _span
		return _world(_base.lerp(_summit, t) - _right * _wheel_radius, _span_height(t))
	var a := (d - _span) / _wheel_radius
	return _world(_base - _wheel_radius * (_right * cos(a) + _forward * sin(a)), _heights[0])


func _support(xz: Vector2, cable_y: float, terminal: bool) -> void:
	var frame := Node3D.new()
	add_child(frame)
	frame.position = _world(xz, _ground(xz))
	frame.basis = _upright(_forward)
	var h := cable_y - frame.position.y
	Fixtures.support(self, frame, h, terminal, tier, _wheel_radius)


func _make_chair() -> Carrier:
	var c := Carrier.new()
	add_child(c)
	if tier == 2:
		Fixtures.tram(self, c)
	else:
		Fixtures.chair(self, c, tier)
	return c


func _pose_chair(c: Carrier) -> void:
	if tier == 2:
		c.transform = Transform3D(_upright(_forward), _tram_cable(c.distance / _span, c.lane))
		return
	var pos := _cable_position(c.distance)
	var ahead := _cable_position(fposmod(c.distance + 0.035, _loop_length))
	var direction := Vector2(ahead.x - pos.x, ahead.z - pos.z).normalized()
	c.transform = Transform3D(_upright(direction) * Basis(Vector3.RIGHT, c.swing), pos)


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.90
		_materials[color] = mat
	return _materials[color]


func _mesh(parent: Node3D, shape: Mesh, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = shape
	part.material_override = _material(color)
	parent.add_child(part)
	part.position = pos
	part.scale = size
	return part


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	_mesh(parent, _unit_box, pos, size, color)


func _rod(parent: Node3D, a: Vector3, b: Vector3, diameter: float, color: Color) -> void:
	var axis := b - a
	var length := axis.length()
	var part := _mesh(parent, _unit_cylinder, (a + b) * 0.5, Vector3.ONE, color)
	part.basis = Basis(Quaternion(Vector3.UP, axis / length)).scaled_local(Vector3(diameter, length, diameter))
