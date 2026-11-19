extends RefCounted

# A descending rider can coast across a contour or carry a small roll after
# building speed. Sample the snow between pointer events as well as at them.
static func flows_downhill(points: PackedVector2Array, terrain: Node) -> bool:
	if points.size() < 2 or not points[0].is_finite():
		return false
	var entry: float = terrain.surface_height(points[0].x, points[0].y)
	var low := entry
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		if not b.is_finite():
			return false
		var steps := maxi(1, ceili(a.distance_to(b) / 0.65))
		for j in range(1, steps + 1):
			var p := a.lerp(b, float(j) / steps)
			var h: float = terrain.surface_height(p.x, p.y)
			low = minf(low, h)
			var carry := minf(1.05, 0.44 + (entry - low) * 0.16)
			if h - low > carry:
				return false
	return true

# Rate the steepest sustained stretch. Measuring along the marked trail keeps a
# traverse easier than the fall line and skips small bumps between survey points.
static func grade(points: PackedVector2Array, terrain: Node) -> String:
	if points.size() < 2:
		return ""
	var length := 0.0
	var distances := PackedFloat32Array([0.0])
	var heights := PackedFloat32Array([terrain.surface_height(points[0].x,points[0].y)])
	var steepest := 0.0
	var first := 0
	const WINDOW := 6.0
	for i in range(1, points.size()):
		var span := points[i-1].distance_to(points[i])
		if span < 0.001:
			continue
		var steps := ceili(span / 1.2)
		for j in range(1, steps+1):
			var t := float(j) / steps
			var at := points[i-1].lerp(points[i],t)
			var h: float = terrain.surface_height(at.x,at.y)
			var d := length + span*t
			distances.append(d)
			heights.append(h)
			if d < WINDOW:
				continue
			var start := d-WINDOW
			while first+1 < distances.size()-1 and distances[first+1] <= start:
				first += 1
			var fade := inverse_lerp(distances[first],distances[first+1],start)
			var top := lerpf(heights[first],heights[first+1],fade)
			steepest = maxf(steepest,(top-h)/WINDOW)
		length += span
	if length < WINDOW:
		return ""
	if steepest < 0.43:
		return "Easy"
	if steepest < 0.68:
		return "Intermediate"
	return "Advanced"
