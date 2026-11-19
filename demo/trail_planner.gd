extends RefCounted

static func through_bends(start: Vector2, bends: PackedVector2Array, finish: Vector2) -> PackedVector2Array:
	var knots := PackedVector2Array([start])
	knots.append_array(bends)
	knots.append(finish)
	var line := PackedVector2Array([knots[0]])
	for i in range(knots.size()-1):
		var a := knots[i]
		var b := knots[i+1]
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		# The tangent points along the neighbouring legs. Limit its reach
		# on short segments so a tight switchback stays close to its pins.
		var incoming := a-knots[maxi(0,i-1)]
		var outgoing := knots[mini(i+2,knots.size()-1)]-b
		var ab := (b-a).normalized()
		var m := (incoming.normalized()+ab).normalized()*minf(length,incoming.length())
		var n := (outgoing.normalized()+ab).normalized()*minf(length,outgoing.length())
		var count := maxi(1,ceili(length/1.2))
		for j in range(1,count+1):
			var t := float(j)/count
			var u := 1.0-t
			line.append((u*u*(1.0+2.0*t))*a + (t*u*u)*m + (t*t*(3.0-2.0*t))*b - (t*t*u)*n)
	return line

# Keep the shape of an unfinished stroke while giving the player only the
# handles it takes to describe each bend. Station links stay editable.
static func stroke_bends(stroke: PackedVector2Array, start: Vector2, finish: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([start])
	for p in stroke:
		if p.distance_to(points[-1]) > 0.35 and p.distance_to(finish) > 0.35:
			points.append(p)
	points.append(finish)
	var keep := PackedByteArray()
	keep.resize(points.size())
	var ranges: Array[Vector2i] = [Vector2i(0,points.size()-1)]
	while not ranges.is_empty():
		var edge: Vector2i = ranges.pop_back()
		var largest := 0.42*0.42
		var split := -1
		for i in range(edge.x+1,edge.y):
			var nearest := Geometry2D.get_closest_point_to_segment(points[i],points[edge.x],points[edge.y])
			var deviation := nearest.distance_squared_to(points[i])
			if deviation > largest:
				largest = deviation
				split = i
		if split >= 0:
			keep[split] = 1
			ranges.append(Vector2i(edge.x,split))
			ranges.append(Vector2i(split,edge.y))
	var bends := PackedVector2Array()
	for i in range(1,points.size()-1):
		if keep[i] == 1: bends.append(points[i])
	return bends
