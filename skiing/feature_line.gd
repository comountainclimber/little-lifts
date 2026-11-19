extends RefCounted

# Build the contact and flight geometry together so the feet, powder and
# interrupted tracks agree on the exact lip and landing of each feature.
class Pass:
	var kind: int
	var ledge_id := ""
	var ramp_row: int
	var lip_row: int
	var landing_row: int
	var horizontal_speed: float

var points := PackedVector3Array()
var passes: Array[Pass] = []


func build(carves: PackedVector2Array, spine: PackedVector2Array, distances: PackedFloat32Array, terrain: Node, sites: Array) -> void:
	var sections: Array[Dictionary] = []
	for site: Dictionary in sites:
		var start := _nearest_distance(site.approach, spine, distances)
		var end := _nearest_distance(site.landing, spine, distances)
		if end > start + 0.75:
			var reach := 6.6 if site.has("ledge_id") else 2.4
			sections.append({"site": site, "start": start, "end": end,
				"entry_blend": minf(reach, start), "exit_blend": minf(reach, distances[-1] - end)})
	sections.sort_custom(func(a: Dictionary, b: Dictionary): return a.start < b.start)

	var row := 0
	var last_end := -INF
	var previous: Dictionary = {}
	for section in sections:
		if section.start < last_end:
			continue
		while row < distances.size() and distances[row] < section.start:
			_append_snow(carves[row], distances[row], previous, section, terrain)
			row += 1
		_append_feature(section.site, terrain)
		while row < distances.size() and distances[row] <= section.end:
			row += 1
		last_end = section.end
		previous = section
	while row < distances.size():
		_append_snow(carves[row], distances[row], previous, {}, terrain)
		row += 1


static func _nearest_distance(target: Vector2, spine: PackedVector2Array, distances: PackedFloat32Array) -> float:
	var nearest := INF
	var offset := 0.0
	for i in range(1, spine.size()):
		var a := spine[i - 1]
		var foot := Geometry2D.get_closest_point_to_segment(target, a, spine[i])
		var d := foot.distance_squared_to(target)
		if d < nearest:
			nearest = d
			offset = distances[i - 1] + foot.distance_to(a)
	return offset


func _append_snow(carve: Vector2, d: float, previous: Dictionary, upcoming: Dictionary, terrain: Node) -> void:
	var exit_gap := INF if previous.is_empty() else d - float(previous.end)
	var entry_gap := INF if upcoming.is_empty() else float(upcoming.start) - d
	var gap := minf(exit_gap, entry_gap)
	var p := carve
	if exit_gap <= entry_gap and not previous.is_empty() and gap < float(previous.exit_blend):
		var line: Vector2 = previous.site.landing + previous.site.direction * gap
		p = line.lerp(carve, smoothstep(0.0, previous.exit_blend, gap))
	elif not upcoming.is_empty() and gap < float(upcoming.entry_blend):
		var approach_axis: Vector2 = (upcoming.site.point - upcoming.site.approach).normalized()
		var line: Vector2 = upcoming.site.approach - approach_axis * gap
		p = line.lerp(carve, smoothstep(0.0, upcoming.entry_blend, gap))
	points.append(Vector3(p.x, terrain.surface_height(p.x, p.y), p.y))


func _append_feature(site: Dictionary, terrain: Node) -> void:
	var approach: Vector2 = site.approach
	var lip: Vector2 = site.point
	var landing: Vector2 = site.landing
	var run_up := maxi(8, ceili(approach.distance_to(lip) / 0.12))
	var rise: float = site.lip_height - terrain.surface_height(lip.x, lip.y)
	var pass_data := Pass.new()
	pass_data.kind = site.kind
	pass_data.ledge_id = site.get("ledge_id", "")
	pass_data.ramp_row = points.size()
	for i in range(run_up + 1):
		var t := float(i) / run_up
		var p := approach.lerp(lip, t)
		var top: float = terrain.surface_height(p.x, p.y) + rise * t * t
		if not pass_data.ledge_id.is_empty():
			top = terrain.summit_ledges.cap_height(site, p)
		points.append(Vector3(p.x, top, p.y))
	pass_data.lip_row = points.size() - 1
	var span := lip.distance_to(landing)
	var flight_steps := maxi(20, ceili(span / 0.12))
	for i in range(1, flight_steps + 1):
		var t := float(i) / flight_steps
		var p := lip.lerp(landing, t)
		var y: float = lerpf(site.lip_height, site.landing_height, t) + 4.0 * site.air_height * t * (1.0 - t)
		points.append(Vector3(p.x, y, p.y))
	pass_data.landing_row = points.size() - 1
	# y(t) above has the normal acceleration of gravity when t spans this duration.
	pass_data.horizontal_speed = span / sqrt(8.0 * site.air_height / 9.8)
	passes.append(pass_data)


# The outcrops remain solid even before a player opens a drop. Reroute only
# the nearby on-snow spans, keeping both lift transfers and all takeoffs fixed.
static func skirt_rocks(path: PackedVector3Array, flights: Array[Pass], terrain: Node, spine: PackedVector2Array) -> bool:
	var ledges: Node = terrain.get("summit_ledges")
	if ledges == null or ledges.sites.is_empty():
		return false
	var nearby := false
	for site: Dictionary in ledges.sites:
		if path[0].y > float(site.landing_height) - 2.5:
			nearby = true
			break
	if not nearby:
		return false
	var changed := false
	var start := 0
	for flight in flights:
		if _skirt_section(path, start, flight.ramp_row, flight.ledge_id, terrain, PackedVector2Array()):
			changed = true
		start = flight.landing_row
	if _skirt_section(path, start, path.size() - 1, "", terrain, spine if flights.is_empty() else PackedVector2Array()):
		changed = true
	return changed


static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


static func _blocks(terrain: Node, p: Vector2, approach: Vector2, target: String) -> bool:
	var approach_id := target if p.distance_squared_to(approach) < 1.2 * 1.2 else ""
	return terrain.summit_ledges.contains(p, 0.40, approach_id)


static func _skirt_section(path: PackedVector3Array, start: int, end: int, target: String, terrain: Node, spine: PackedVector2Array) -> bool:
	if end <= start:
		return false
	var anchor := _flat(path[end])
	var affected := PackedInt32Array()
	for i in range(start, end + 1):
		if _blocks(terrain, _flat(path[i]), anchor, target):
			affected.append(i)
	if affected.is_empty():
		return false
	var changed := false
	var n := 0
	while n < affected.size():
		var first := affected[n]
		var last := first
		n += 1
		while n < affected.size() and path[last].distance_to(path[affected[n]]) < 12.0:
			last = affected[n]
			n += 1
		var left := first
		var right := last
		while left > start and path[left].distance_to(path[first]) < 6.0:
			left -= 1
		while right < end and path[right].distance_to(path[last]) < 6.0:
			right += 1
		if _round_outcrop(path, left, first, last, right, terrain, anchor, target, spine):
			changed = true
	return changed


static func _round_outcrop(path: PackedVector3Array, left: int, first: int, last: int, right: int, terrain: Node, anchor: Vector2, target: String, spine: PackedVector2Array) -> bool:
	if first == left or last == right:
		return false
	var across := (_flat(path[right]) - _flat(path[left])).normalized().orthogonal()
	var profile := PackedFloat32Array()
	var centers := PackedVector2Array()
	var enter := path[left].distance_to(path[first])
	var exit_length := path[last].distance_to(path[right])
	for i in range(left, right + 1):
		var weight := 1.0
		if i < first:
			weight = smoothstep(0.0, enter, path[i].distance_to(path[left]))
		elif i > last:
			weight = smoothstep(0.0, exit_length, path[i].distance_to(path[right]))
		profile.append(weight)
		var p := _flat(path[i])
		centers.append(p.lerp(spine[i], weight) if spine.size() == path.size() else p)
	for radius: int in [6, 18, 34]:
		if _skiable_channel(path, left, centers, profile, across, radius, terrain, anchor, target):
			return true
	return false


static func _skiable_channel(path: PackedVector3Array, first_row: int, centers: PackedVector2Array, profile: PackedFloat32Array, across: Vector2, radius: int, terrain: Node, anchor: Vector2, target: String) -> bool:
	# Consecutive shelves can pinch opposite sides of a run. Find the least
	# sideways movement that fits between them, starting with the cleared width.
	const STEP := 0.30
	var lanes := radius * 2 + 1
	var parents := PackedInt32Array()
	parents.resize(centers.size() * lanes)
	var costs := PackedFloat32Array()
	costs.resize(lanes)
	costs.fill(0.0)
	for row in range(1, centers.size()):
		var next := PackedFloat32Array()
		next.resize(lanes)
		next.fill(INF)
		for lane in lanes:
			var offset := (lane - radius) * STEP
			var p := centers[row] + across * offset * profile[row]
			if _blocks(terrain, p, anchor, target) or not terrain.route_clear(p, p, 0.23):
				continue
			for parent in range(maxi(0, lane - 1), mini(lanes, lane + 2)):
				var cost := costs[parent] + 0.012 * offset * offset * profile[row] * profile[row] + absf(lane - parent) * 0.15
				if cost >= next[lane]:
					continue
				var previous := centers[row - 1] + across * (parent - radius) * STEP * profile[row - 1]
				if _blocks(terrain, p.lerp(previous, 0.5), anchor, target) or not terrain.route_clear(previous, p, 0.19):
					continue
				next[lane] = cost
				parents[row * lanes + lane] = parent
		costs = next
	var last_lane := 0
	for lane in range(1, lanes):
		if costs[lane] < costs[last_lane]:
			last_lane = lane
	if not is_finite(costs[last_lane]):
		return false
	var offsets := PackedFloat32Array()
	offsets.resize(centers.size())
	for row in range(centers.size() - 1, -1, -1):
		offsets[row] = STEP * (last_lane - radius) * profile[row]
		last_lane = parents[row * lanes + last_lane]
	for smooth in [true, false]:
		var candidate := PackedVector2Array([centers[0]])
		for row in range(1, centers.size()):
			var offset := offsets[row]
			if smooth and row < offsets.size() - 1:
				offset = (offsets[row - 1] + 2.0 * offset + offsets[row + 1]) * 0.25
			var p := centers[row] + across * offset
			if _blocks(terrain, p, anchor, target) or _blocks(terrain, p.lerp(candidate[-1], 0.5), anchor, target) or not terrain.route_clear(candidate[-1], p, 0.19):
				break
			candidate.append(p)
		if candidate.size() == centers.size():
			for row in range(1, candidate.size() - 1):
				var p := candidate[row]
				path[row + first_row] = Vector3(p.x, terrain.surface_height(p.x, p.y), p.y)
			return true
	return false
