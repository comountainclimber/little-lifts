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
# Transverse joint locations, half widths and signed relief. Positive values
# keep a projecting rib. Negative values pluck a slot out of the cliff.
# Strike (last column) tips those joints across the face toward the toe.
const BEDROCK := [
	[[Vector3(-0.70,0.36,0.38),Vector3(0.63,0.37,-0.45)], -0.30, 0.13],
	[[Vector3(-0.77,0.25,0.84),Vector3(-0.49,0.16,-1.04),Vector3(0.58,0.42,-0.33)], 0.41, 0.13],
	[[Vector3(-0.57,0.35,-0.73),Vector3(0.46,0.28,0.47),Vector3(0.77,0.32,-0.54)], -0.48, 0.10],
	[[Vector3(-0.77,0.32,0.56),Vector3(-0.42,0.18,-0.70),Vector3(0.66,0.39,0.43)], 0.31, 0.14],
	[[Vector3(-0.71,0.27,-0.37),Vector3(-0.42,0.20,0.24),Vector3(0.57,0.40,-0.27),Vector3(0.82,0.18,0.40)], -0.40, 0.10],
	[[Vector3(-0.61,0.41,0.45),Vector3(0.74,0.31,-0.43)], 0.22, 0.41],
	[[Vector3(-0.76,0.20,0.93),Vector3(-0.50,0.18,-0.85),Vector3(0.46,0.16,-0.64),Vector3(0.73,0.23,0.86)], -0.32, 0.18],
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

func _rib_relief(site: Dictionary, across: float, t: float) -> float:
	# Fractures rake uphill and converge, rather than running parallel like
	# flutes. Leave an uninterrupted snow tongue beneath skis and boards.
	var shoulder := smoothstep(0.22,0.39,absf(across))
	var x := across + float(BEDROCK[site.seed][1]) * (1.0-t) * 0.57 * shoulder
	var relief := 0.0
	for joint: Vector3 in BEDROCK[site.seed][0]:
		var distance := absf(x-joint.x)/joint.y
		var triangle := maxf(0.0, 1.0-distance)
		relief += joint.z * smoothstep(0.03,0.84,triangle)
	return relief * shoulder

func _brow(site: Dictionary, across: float) -> float:
	var joint := _rib_relief(site,across,1.0)
	# A broken block recedes into the ridge. Its intact neighbour projects,
	# always within the original surveyed lip and approach footprint.
	return maxf(-site.length+0.52, _edge_offset(site,across) + minf(0,joint)*1.08)

func _position(site: Dictionary, across: float, t: float) -> Vector2:
	var along := lerpf(-site.length,_brow(site,across),t)
	return site.point + site.direction*along + site.direction.orthogonal()*across*_half_width(site,across)

func _crest(site: Dictionary, across: float, t: float) -> float:
	var snow := 1.0-smoothstep(0.39,1.0,absf(across))
	var rock := _rib_relief(site,across,t)*smoothstep(0.12,0.72,t)
	if rock > 0.0:
		rock *= 0.68
	var fade := 1.0-smoothstep(0.87,1.0,absf(across))
	return maxf(0.0, snow+rock)*fade

func cap_height(site: Dictionary, p: Vector2) -> float:
	var delta: Vector2 = p-site.point
	var side: float = delta.dot(site.direction.orthogonal())
	var across := side/_half_width(site,side)
	var t := clampf((delta.dot(site.direction)+site.length)/(site.length+_brow(site,across)),0.0,1.0)
	return _hill.surface_height(p.x,p.y) + site.rise*smoothstep(0.0,1.0,t)*_crest(site,across,t)

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

func _sections(site: Dictionary) -> PackedFloat32Array:
	var xs := PackedFloat32Array([-1.0,-0.88,-0.34,-0.18,0.0,0.22,0.32,0.89,1.0])
	for joint: Vector3 in BEDROCK[site.seed][0]:
		xs.append(clampf(joint.x-joint.y*0.67,-0.96,0.96))
		xs.append(joint.x-joint.y*0.17)
		xs.append(joint.x+joint.y*0.17)
		xs.append(clampf(joint.x+joint.y*0.67,-0.96,0.96))
	xs.sort()
	var sections := PackedFloat32Array([xs[0]])
	for x in xs:
		if x-sections[-1] > 0.032:
			sections.append(x)
	return sections

func _granite(site: Dictionary, across: float, level: float, normal: Vector3) -> Color:
	var strike := Vector3(0.91,-0.12,-0.36)
	var light_plane := clampf(0.48+0.64*normal.dot(strike),0.0,1.0)
	var stone := Color("#606778").lerp(Color("#a3978e"),light_plane)
	var seam := _rib_relief(site,across,1.0)
	var depth := (1.0-smoothstep(0.12,0.70,level))*0.12 + clampf(-seam,0.0,1.0)*0.20
	return stone.darkened(depth).lerp(Color("#acaaa8"),0.075*smoothstep(0.02,0.8,seam))

func _roof(site: Dictionary, surface: SurfaceTool, xs: PackedFloat32Array) -> void:
	var previous := PackedVector3Array()
	var rows := PackedFloat32Array([0.0,0.15,0.29,0.43,0.57,0.72,0.85,0.94,1.0])
	for t in rows:
		var ring := PackedVector3Array()
		for x in xs:
			var p := _position(site,x,t)
			ring.append(Vector3(p.x,cap_height(site,p)+0.009,p.y))
		if not previous.is_empty():
			for i in range(xs.size()-1):
				var x := (xs[i]+xs[i+1])*0.5
				var mid := (previous[i]+ring[i+1])*0.5
				var n := (ring[i]-previous[i]).cross(ring[i+1]-previous[i]).normalized()
				if n.y < 0.0: n = -n
				var rock := _rib_relief(site,x,t)
				# Snow lies in the cracks and across the launch tongue. Steep
				# windward backs and the crest flanks are scoured down to rock.
				var reveal := smoothstep(0.30,0.52,absf(x))*smoothstep(0.22,0.52,t)
				reveal *= smoothstep(0.0,0.38,rock+0.85*(1.0-n.y))
				reveal *= 1.0-smoothstep(0.87,1.0,absf(x))
				var tint := _native_snow(mid).lerp(_granite(site,x,1.0,n),reveal)
				Feature._face(surface,previous[i],ring[i],previous[i+1],Vector3.UP,tint)
				Feature._face(surface,ring[i],ring[i+1],previous[i+1],Vector3.UP,tint)
		previous = ring

func _face_vertex(site: Dictionary, across: float, row: int) -> Vector3:
	var level: float = [1.0,0.0,0.62,0.58,0.26,0.0][row]
	var strike: float = BEDROCK[site.seed][1]
	var x := across
	if row >= 2:
		x += strike*(1.0-level)*0.39*(1.0-absf(across))
	var lip := _position(site,across,1.0)
	var headroom := maxf(0.0,cap_height(site,lip)-_hill.surface_height(lip.x,lip.y))
	var rib := _rib_relief(site,across,1.0)
	var mantle: float = BEDROCK[site.seed][2]
	var cap := minf(headroom*0.20,mantle*(0.75+0.32*cos(2.9*across+site.seed*0.83)))
	var foot := _position(site,x,1.0)
	var overhang := minf(0.27,mantle*0.65)*smoothstep(0.0,0.76,headroom)
	# The snow blister reaches a short distance past the granite below it.
	# A tilted shelf catches snow on just one side of the face; at the other
	# end the two fracture planes meet directly with no continuous stripe.
	var bench := smoothstep(-0.2,0.8,cos(3.6*across+site.seed*1.47))
	var offset := 0.0
	match row:
		0: offset = 0.0
		1: offset = overhang
		2: offset = -0.25 + 0.15*rib
		3: offset = -0.25 + 0.46*bench + 0.15*rib
		4: offset = 0.15 + 0.20*rib
		5: offset = 0.50 + 0.10*clampf(rib,-1,1)
	foot += site.direction*offset
	var ground: float = _hill.surface_height(foot.x,foot.y)-0.045
	var y := cap_height(site,lip)+0.009
	if row == 1:
		y -= cap
	elif row >= 2:
		var dip := (0.17*across*strike+0.055*rib)*sin(PI*level)
		y = lerpf(ground,y-cap,level+dip)
	return Vector3(foot.x,y,foot.y)

func _cliff_face(site: Dictionary, surface: SurfaceTool, xs: PackedFloat32Array) -> void:
	var previous := PackedVector3Array()
	var outward := Vector3(site.direction.x,0.0,site.direction.y)
	for row in 6:
		var ring := PackedVector3Array()
		for x in xs:
			ring.append(_face_vertex(site,x,row))
		if row > 0:
			for i in range(xs.size()-1):
				var across := (xs[i]+xs[i+1])*0.5
				var a := previous[i]
				var b := ring[i]
				var c := previous[i+1]
				var d := ring[i+1]
				var n := (c-a).cross(b-a).normalized()
				if n.dot(outward) < 0.0: n = -n
				var tint := _granite(site,across,1.0-float(row)/5.0,n)
				if row == 1:
					tint = _native_snow(a).darkened(0.08)
				elif row == 3 and n.y > 0.80:
					var catchment := smoothstep(0.28,0.93,cos(5.0*across+site.seed*1.73))
					tint = tint.lerp(_native_snow(b),catchment*smoothstep(0.80,0.98,n.y)*0.68)
				elif row == 2:
					tint = tint.darkened(0.12*maxf(-n.y,0.0))
				Feature._face(surface,a,b,c,outward,tint)
				Feature._face(surface,b,d,c,outward,tint)
		previous = ring

# Broken sheets buttress the front and trail back into the divide. Their
# roots are inside the original clearance envelope. Fractional coordinates
# give each face its own mass and tread pattern independent of the skier.
# Each piece is (across, position front to back, half breadth, height).
const BUTTRESSES := [
	[Vector4(-0.71,0.83,0.28,0.86),Vector4(-0.54,0.48,0.32,0.41),Vector4(0.64,0.91,0.33,0.42)],
	[Vector4(-0.79,0.73,0.19,1.00),Vector4(0.65,0.77,0.34,0.77),Vector4(0.63,0.48,0.29,0.47)],
	[Vector4(-0.68,0.82,0.29,0.47),Vector4(0.70,0.60,0.24,0.76)],
	[Vector4(-0.75,0.62,0.24,0.84),Vector4(0.65,0.84,0.34,1.16),Vector4(0.55,0.53,0.35,0.73)],
	[Vector4(-0.62,0.87,0.36,0.94),Vector4(-0.64,0.54,0.32,0.60),Vector4(0.72,0.76,0.28,0.59)],
	[Vector4(-0.73,0.76,0.24,0.72),Vector4(0.70,0.91,0.31,0.72),Vector4(0.68,0.53,0.30,0.52)],
	[Vector4(-0.75,0.56,0.25,0.84),Vector4(0.72,0.79,0.26,0.95),Vector4(0.73,0.48,0.27,0.65)],
]
const SLAB_PLAN := [Vector2(-0.74,-0.84),Vector2(0.38,-1.0),Vector2(1.0,-0.34),Vector2(0.77,0.70),Vector2(0.18,1.0),Vector2(-0.67,0.82),Vector2(-1.0,0.02)]

func _slab_site(site: Dictionary, across: float, along: float) -> Vector2:
	var x := signf(across)*clampf(absf(across),0.40,0.99)
	var depth := clampf(along,-site.length+0.03,_edge_offset(site,x)+0.64)
	return site.point + site.direction*depth + site.direction.orthogonal()*x*_half_width(site,x)

func _buttress(site: Dictionary, surface: SurfaceTool, piece: Vector4) -> void:
	var direction: Vector2 = site.direction
	var side: Vector2 = direction.orthogonal()
	var toe := lerpf(-site.length,_edge_offset(site,piece.x)+0.46,piece.y)
	var axis := signf(piece.x)
	var rootline := PackedVector3Array()
	var shoulder := PackedVector3Array()
	var table := PackedVector3Array()
	for uv: Vector2 in SLAB_PLAN:
		# The basal socket splays toward the open face. At the narrow end
		# the entire block disappears beneath the approach snow.
		var raked := piece.x + piece.z*uv.x + axis*0.095*uv.y
		var z := toe+uv.y*(0.80+0.23*piece.w)+0.19*axis*uv.x
		var p := _slab_site(site,raked,z)
		var q := _slab_site(site,piece.x+(raked-piece.x)*0.88-axis*0.035,z-0.09)
		var top := _slab_site(site,piece.x+(raked-piece.x)*0.71-axis*0.03,z-0.19)
		var y: float = _hill.surface_height(top.x,top.y)
		var h := piece.w*(0.73 + 0.23*uv.y + 0.14*axis*uv.x)
		# Pieces at a weathered shoulder sit low. A central snow pocket can
		# cover their inner edge naturally without making a detached boulder.
		var bed := maxf(y,cap_height(site,top)-0.27)
		rootline.append(Vector3(p.x,_hill.surface_height(p.x,p.y)-0.065,p.y))
		shoulder.append(Vector3(q.x,bed+0.64*h,q.y))
		table.append(Vector3(top.x,bed+h,top.y))
	var core := Vector3.ZERO
	for p in table:
		core += p
	core /= table.size()
	for i in table.size():
		var j := (i+1)%table.size()
		var outer := ((rootline[i]+rootline[j])*0.5-core)
		outer.y = 0.0
		var radial := outer.normalized()
		var tint := _granite(site,piece.x,0.4,radial)
		Feature._face(surface,rootline[i],rootline[j],shoulder[i],radial,tint)
		Feature._face(surface,rootline[j],shoulder[j],shoulder[i],radial,tint)
		Feature._face(surface,shoulder[i],shoulder[j],table[i],radial,tint.lightened(0.05))
		Feature._face(surface,shoulder[j],table[j],table[i],radial,tint.lightened(0.05))
		var top_normal := (table[i]-core).cross(table[j]-core).normalized()
		if top_normal.y < 0.0: top_normal = -top_normal
		var pocket := smoothstep(0.68,0.99,top_normal.y) * (0.34+0.36*maxf(-side.dot(Vector2(top_normal.x,top_normal.z))*axis,0.0))
		var top_tint := _granite(site,piece.x,1.0,top_normal).lerp(_native_snow(core),pocket)
		Feature._face(surface,table[i],table[j],core,Vector3.UP,top_tint)

# A faulted sill remains attached to the wall at its base. Its front breaks
# the vertical silhouette at snow level. All of it sits below the flight.
func _basal_sill(site: Dictionary, surface: SurfaceTool, near_x: float, far_x: float, rise: float) -> void:
	var row := PackedVector3Array()
	var knobs := PackedFloat32Array([0.0,0.16,0.39,0.75,0.91,1.0])
	var shoulders := PackedFloat32Array([0.06,0.60,1.0,0.83,0.40,0.05])
	var outward := Vector3(site.direction.x,0.0,site.direction.y)
	for i in knobs.size():
		var f := knobs[i]
		var x := lerpf(near_x,far_x,f)
		var edge := _edge_offset(site,x)
		var root_point: Vector2 = site.point + site.direction*(edge+0.63) + site.direction.orthogonal()*x*_half_width(site,x)
		var leading: Vector2 = root_point-site.direction*(0.07+0.055*f)
		var rear: Vector2 = leading-site.direction*(0.44+0.38*shoulders[i])
		var base: float = _hill.surface_height(root_point.x,root_point.y)-0.045
		var h := rise*shoulders[i]
		var next := PackedVector3Array([Vector3(root_point.x,base,root_point.y),Vector3(leading.x,base+h,leading.y),Vector3(rear.x,_hill.surface_height(rear.x,rear.y)+h*1.1,rear.y)])
		if not row.is_empty():
			var rock := _granite(site,x,0.18,outward).lightened(0.08)
			Feature._face(surface,row[0],next[0],row[1],outward,rock)
			Feature._face(surface,next[0],next[1],row[1],outward,rock)
			var n := (row[2]-row[1]).cross(next[1]-row[1]).normalized()
			var snow_catch := 0.84*smoothstep(0.65,0.97,absf(n.y))*smoothstep(0.18,0.45,f)
			var top := rock.lerp(_native_snow(row[1]),snow_catch)
			Feature._face(surface,row[1],row[2],next[1],Vector3.UP,top)
			Feature._face(surface,row[2],next[2],next[1],Vector3.UP,top)
		row = next

func _expose(site: Dictionary) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := _sections(site)
	_roof(site,surface,xs)
	_cliff_face(site,surface,xs)
	for piece: Vector4 in BUTTRESSES[site.seed]:
		_buttress(site,surface,piece)
	var sill: Vector3 = [Vector3(-0.84,0.39,0.70),Vector3(-0.23,0.86,0.75),Vector3(0.03,0.79,0.49),Vector3(-0.21,0.94,0.86),Vector3(-0.88,0.66,0.89),Vector3(-0.72,0.37,0.54),Vector3(-0.26,0.61,0.70)][site.seed]
	_basal_sill(site,surface,sill.x,sill.y,sill.z)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.96
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
