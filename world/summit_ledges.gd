extends Node3D

const Feature := preload("res://world/slope_feature.gd")
# Survey stations on the permanent high divide. Coordinates are in mountain
# map units, independent of where the player eventually puts a lift or cut.
const SHELVES := [
	["ptarmigan", "Ptarmigan Ledge", Vector2(-17.75,-64.15), Vector2(0.14,0.99), 3.45, 2.35, 7.1],
	["split_rock", "Split Rock", Vector2(-20.8,-61.75), Vector2(0.41,0.91), 3.35, 2.08, 6.8],
	["snow_fin", "Snow Fin", Vector2(-14.2,-60.65), Vector2(0.63,0.78), 3.9, 2.60, 7.4],
	["western_notch", "Western Notch", Vector2(-26.8,-65.2), Vector2(-0.19,0.98), 4.45, 2.65, 7.45],
	["granite_steps", "Granite Steps", Vector2(-11.3,-63.25), Vector2(0.55,0.84), 3.8, 2.28, 7.15],
	["east_cornice", "East Cornice", Vector2(-9.2,-66.6), Vector2(0.44,0.90), 4.65, 2.46, 7.4],
	["crown", "Crown Rock", Vector2(-18.2,-69.5), Vector2(0.50,0.86), 4.05, 2.7, 8.1],
]
var sites: Array[Dictionary] = []
var _hill: Node
var _bounds: Rect2

func build(terrain: Node) -> void:
	_hill = terrain
	name = "Summit geology"
	for i in SHELVES.size():
		var data: Array = SHELVES[i]
		var point: Vector2 = data[2] * terrain.MAP_SCALE
		var direction: Vector2 = data[3].normalized()
		var length := 3.15 + 0.25 * (i % 3)
		var approach := point - length * direction
		var landing := point + float(data[6]) * direction
		var ground: float = _hill.surface_height(point.x,point.y)
		var landing_y: float = _hill.surface_height(landing.x,landing.y)
		var site := {"kind":Feature.EXTREME, "ledge_id":data[0], "name":data[1], "point":point,
			"approach":approach, "landing":landing, "direction":direction, "length":length,
			"approach_height":_hill.surface_height(approach.x,approach.y), "landing_height":landing_y,
			"lip_height":ground + float(data[5]), "rise":data[5], "width":data[4],
			"air_height":1.75 + 0.08 * (i % 4), "grade":(ground-landing_y) / point.distance_to(landing), "seed":i}
		var half_span := direction.orthogonal() * float(data[4]) * 0.58
		var bounds := Rect2(point+half_span,Vector2.ZERO).expand(point-half_span).expand(approach-half_span).expand(approach+half_span).grow(0.7)
		site.bounds = bounds
		_bounds = bounds if sites.is_empty() else _bounds.merge(bounds)
		sites.append(site)
		_expose(site)

func _half_width(site: Dictionary, side: float) -> float:
	var asymmetry := 0.16 * sin(site.seed * 1.87 + 0.63)
	return 0.5 * site.width * (1.0 + signf(side) * asymmetry)

func _edge_offset(site: Dictionary, across: float) -> float:
	# A stepped, asymmetric rock brow, tapered out into the snow on each wing.
	var joint := absf(sin(4.4 * across + 0.83 * site.seed) - sin(0.83 * site.seed))
	return -absf(across) * (0.28 + 0.51 * joint) + 0.50 * across * sin(1.36 * site.seed) - 0.16 * across * across

func _position(site: Dictionary, across: float, t: float) -> Vector2:
	var along := lerpf(-site.length, _edge_offset(site,across), t)
	return site.point + site.direction * along + site.direction.orthogonal() * across * _half_width(site,across)

func cap_height(site: Dictionary, p: Vector2) -> float:
	var delta: Vector2 = p - site.point
	var side: float = delta.dot(site.direction.orthogonal())
	var across := side / _half_width(site,side)
	var edge := _edge_offset(site,across)
	var t := clampf((delta.dot(site.direction) + site.length) / (site.length + edge), 0.0, 1.0)
	var blend := 1.0 - smoothstep(0.47,1.0,absf(across))
	return _hill.surface_height(p.x,p.y) + site.rise * smoothstep(0.0,1.0,t) * blend

func contains(p: Vector2, clearance := 0.0, except_id := "") -> bool:
	if not _bounds.grow(clearance).has_point(p):
		return false
	for site in sites:
		var bounds: Rect2 = site.bounds
		if site.ledge_id == except_id or not bounds.grow(clearance).has_point(p):
			continue
		var delta: Vector2 = p - site.point
		var along: float = delta.dot(site.direction)
		if along < -site.length - clearance or along > 0.7 + clearance:
			continue
		var side: float = delta.dot(site.direction.orthogonal())
		var half := _half_width(site,side)
		if absf(side) <= half + clearance and along <= _edge_offset(site,clampf(side/half,-1.0,1.0)) + 0.7 + clearance:
			return true
	return false

func clear_segment(a: Vector2, b: Vector2, clearance: float, except_id := "") -> bool:
	var count := maxi(1, ceili(a.distance_to(b) / 0.5))
	for i in range(count + 1):
		if contains(a.lerp(b,float(i) / count),clearance,except_id):
			return false
	return true

func _expose(site: Dictionary) -> void:
	var stone := Color("#858c9b").lerp(Color("#a39a98"), 0.5 + 0.4 * sin(site.seed * 2.71))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := PackedVector3Array()
	var columns := 15
	for row in 13:
		var ring := PackedVector3Array()
		for col in columns:
			var across := 2.0 * col / (columns-1) - 1.0
			var p := _position(site,across, float(row)/12.0)
			ring.append(Vector3(p.x,cap_height(site,p) + 0.006,p.y))
		if row > 0:
			for col in range(columns-1):
				var across := 2.0 * (col+0.5)/(columns-1) - 1.0
				var center := (previous[col]+ring[col+1]) * 0.5
				var tint := _native_snow(center)
				var exposure := smoothstep(0.35,0.8,absf(across)) * (1.0 - smoothstep(0.78,1.0,absf(across)))
				tint = tint.lerp(stone, 0.32 * exposure * smoothstep(6.0,12.0,row))
				Feature._face(surface,previous[col],ring[col],previous[col+1],Vector3.UP,tint)
				Feature._face(surface,ring[col],ring[col+1],previous[col+1],Vector3.UP,tint)
		previous = ring
	# Exposed horizontal bedding follows the irregular lip across the rib.
	# The toe sinks into the hillside. Snow seams round off the highest face.
	var outward := Vector3(site.direction.x,0,site.direction.y)
	var upper := previous
	for band in 4:
		var lower := PackedVector3Array()
		for col in columns:
			var across := 2.0 * col / (columns-1) - 1.0
			var lip := previous[col]
			var offset := (0.36 + 0.17 * sin(8.3*across + site.seed)) * (band+1) / 4.0
			var p := Vector2(lip.x,lip.z) + Vector2(outward.x,outward.z) * offset
			var toe: float = _hill.surface_height(p.x,p.y) - 0.055
			var level: float = [0.88,0.56,0.31,0.0][band]
			if band == 1 or band == 2:
				level += 0.13 * across * sin(0.9+site.seed) + 0.07 * sin(4.1*across+site.seed) + 0.045 * cos(9.4*across)
			lower.append(Vector3(p.x,lerpf(toe,lip.y,level),p.y))
		for col in range(columns-1):
			var tone: Color = [_native_snow(previous[col]).darkened(0.055),stone.lightened(0.075),stone.darkened(0.06),stone][band]
			var facet := tone.darkened(0.045 * (0.5 + 0.5 * sin(col*1.31 + band*0.73 + site.seed)))
			Feature._face(surface,upper[col],lower[col],upper[col+1],outward,facet)
			Feature._face(surface,lower[col],lower[col+1],upper[col+1],outward,facet)
		upper = lower
	for flank: float in [-1.0, 1.0]:
		var t := 0.50 + 0.31 * sin(1.4 + flank * 1.8 + site.seed * 2.1)
		var c := _position(site,flank*0.81,t)
		var ridge := Vector3(c.x, cap_height(site,c) + 0.38 + 0.27 * t, c.y)
		var ring := PackedVector3Array()
		for j in 6:
			var angle: float = TAU * j/6.0 + site.seed*0.61
			var p: Vector2 = c + site.direction * cos(angle) * (0.52+0.49*t) + site.direction.orthogonal()*sin(angle)*0.31
			ring.append(Vector3(p.x,cap_height(site,p) - 0.07,p.y))
		for j in 6:
			var a := ring[j]
			var b := ring[(j+1)%6]
			var peak := a.lerp(ridge,0.73)
			Feature._face(surface,a,b,peak,Vector3.UP,stone.lightened(0.065*(j%3)))
			Feature._face(surface,peak,b,ridge,Vector3.UP,_native_snow(ridge).darkened(0.03*(j%3)))
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	surface.set_material(material)
	var outcrop := MeshInstance3D.new()
	outcrop.name = site.name
	outcrop.mesh = surface.commit()
	add_child(outcrop)

func _native_snow(p: Vector3) -> Color:
	var scale_factor: float = _hill.MAP_SCALE
	var dx: float = _hill.height_at(p.x-0.3,p.z) - _hill.height_at(p.x+0.3,p.z)
	var dz: float = _hill.height_at(p.x,p.z-0.3) - _hill.height_at(p.x,p.z+0.3)
	var normal := Vector3(dx,0.6,dz).normalized()
	var color: Color = _hill.snow_pigment(p.x/scale_factor,p.z/scale_factor,_hill.surface_height(p.x,p.z)/scale_factor,normal)
	return color.linear_to_srgb()
