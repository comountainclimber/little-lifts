extends RefCounted

# The front side drains south between two spurs. A high pass to the west
# separates the playable summit from a higher, more distant crest.
const DIVIDE := [Vector2(-440,57),Vector2(-285,69),Vector2(-201,64),Vector2(-168,83),
	Vector2(-133,69),Vector2(-110,67),Vector2(-83,54),Vector2(-57,39),
	Vector2(-30,45),Vector2(-15,44),Vector2(21,49),Vector2(45,70),
	Vector2(63,75),Vector2(82,93),Vector2(107,64),Vector2(153,73),Vector2(241,57),Vector2(440,64)]
var relief_noise := FastNoiseLite.new()
var grove_noise := FastNoiseLite.new()

func _init() -> void:
	relief_noise.seed = 9157
	relief_noise.frequency = 0.026
	grove_noise.seed = 1837
	grove_noise.frequency = 0.057

func blend_at(x: float, z: float) -> float:
	# All of the editable ski area and its historical forest use the original surface.
	var outside := maxf(absf(x)-74.0,maxf(z-39.0,-81.0-z))
	return maxf(smoothstep(0.0,25.0,outside),smoothstep(81.0,94.0,-z) if z < -81.0 else 0.0)

func creek_axis(z: float) -> float:
	return 13.0 + 0.18*z + 8.0*sin(z*0.039) + 3.0*cos(z*0.075)

func creek_distance(x: float, z: float) -> float:
	return absf(x-creek_axis(z))

func _crest(x: float) -> float:
	for i in range(1,DIVIDE.size()):
		var next: Vector2 = DIVIDE[i]
		if x <= next.x:
			var previous: Vector2 = DIVIDE[i-1]
			return lerpf(previous.y,next.y,clampf(inverse_lerp(previous.x,next.x,x),0,1))
	return DIVIDE[-1].y

func elevation(x: float, z: float) -> float:
	var noise := relief_noise.get_noise_2d(x*0.60,z*0.60)
	# Longitudinal valley floor keeps falling past the base, opening southward.
	var floor_y := clampf((23.0-z)*0.085,-14.0,19.0)
	var bend := creek_axis(z)
	var wall_center := 111.0 + maxf(z,0.0)*0.32
	var lateral := absf(x-bend)
	var west := x < bend
	var along := z + (68.0 if west else 39.0)
	var side_height := (45.0 if west else 35.0) * exp(-pow(along/(112.0 if west else 92.0),2.0))
	var rib := sin(z*0.081 + x*0.048) * 4.0 + 4.0*sin(z*0.037)
	var shoulder := maxf(0.0,1.0-absf(lateral-wall_center-rib)/(70.0 if west else 61.0))
	var spurs := side_height * pow(shoulder,1.25)
	var crest_z := -90.0 - 0.34*absf(x+24.0) + 6.0*sin(x*0.036) - 0.31*maxf(x,0.0)
	var face := z-crest_z
	var crest := _crest(x) - floor_y
	var cross_slope := x + face*(0.19+0.13*sin(x*0.033)) + 2.1*sin(z*0.082+x*0.027)
	var fluting := 0.5+0.5*cos(cross_slope*0.138+1.4*sin(cross_slope*0.061))
	var runout := smoothstep(0.0,16.0,absf(face))*(1.0-smoothstep(45.0,89.0,absf(face)))
	var falloff := 0.87 if face>0.0 else 0.75
	var wall := maxf(0.0,crest-absf(face)*falloff)
	wall -= pow(fluting,2.2)*6.7*runout
	wall += noise*2.4*smoothstep(9.0,28.0,wall)
	var local := floor_y + maxf(spurs,wall) + 0.28*minf(spurs,maxf(0.0,wall))
	var far_z := -350.0+32.0*sin(x*0.013)+0.16*x
	var far_peak := 28.0+0.74*_crest(x*0.82+124.0)+3.0*sin(x*0.072)
	var farther := far_peak-absf(z-far_z)*0.65
	# Across the valley mouth, low overlapping ranges continue the horizon.
	# Their passes sit beyond the creek instead of closing off its drainage.
	var cross_range := z + 0.41*x - 356.0 - 23.0*sin(x*0.013)
	var far_south := 14.0 + 0.51*_crest(0.86*x-75.0) + 5.0*sin(x*0.061)
	var foothills := far_south - absf(cross_range)*0.32
	var wing := absf(x+0.13*z)-405.0-22.0*sin(z*0.017)
	var side_range := 14.0+0.58*_crest(0.84*z+36.0)-absf(wing)*0.42
	var relief := maxf(maxf(local,farther),maxf(side_range,foothills))
	relief += noise*(1.3+0.035*maxf(0.0,relief-floor_y))
	var hollow := smoothstep(32.0,72.0,z)*(1.0-smoothstep(1.3,13.0,creek_distance(x,z)))
	return lerpf(relief,floor_y-0.65,hollow)

func snow_color(p: Vector2, height: float, normal: Vector3, original: Color) -> Color:
	var blend := blend_at(p.x,p.y)
	if blend <= 0.0:
		return original
	var aspect := smoothstep(-0.55,0.60,-normal.x+0.38*normal.z)
	var snow := Color("#f1e9e6").lerp(Color("#aebfd6"),aspect*0.55)
	var rock_noise := relief_noise.get_noise_2d(p.x*1.9+p.y*0.36,p.y*0.65)
	var crag := smoothstep(0.14,0.37,1.0-normal.y+rock_noise*0.18) * smoothstep(29.0,55.0,height)
	var bedding := sin(height*0.36+p.x*0.063+p.y*0.047)
	snow = snow.lerp(Color("#8c8897"),crag*(0.70+0.14*bedding))
	var ice := smoothstep(39.0,56.0,p.y)*(1.0-smoothstep(0.7,1.9,creek_distance(p.x,p.y)))
	return original.lerp(snow.lerp(Color("#a7c6d0"),ice*0.85).srgb_to_linear(),blend)

func plant_forests(world: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 83513
	var foliage: Array[Transform3D] = []
	var caps: Array[Transform3D] = []
	var needles: Array[Transform3D] = []
	# A jittered grid carries the same stands across the old survey boundary.
	# Forest outside the ski area is scenery; it never enters the cuttable tree index.
	for iz in range(-201, 177):
		for ix in range(-175, 176):
			var x := (ix + rng.randf()) * 1.55
			var z := (iz + rng.randf()) * 1.55
			if absf(x) < 74.0 and z > -75.0 and z < 39.0:
				continue
			var patch := grove_noise.get_noise_2d(x,z)
			if patch < -0.17 + 0.14 * sin(z * 0.21 + sin(x * 0.15)):
				continue
			var distance := Vector2(x,z+28.0).length()
			var boundary := maxf(absf(x)/267.0, absf(z+28.0)/270.0)
			if rng.randf() < smoothstep(0.80,1.0,boundary) or (z > 47.0 and creek_distance(x,z) < 3.4):
				continue
			var pos: Vector2 = Vector2(x,z) * world.MAP_SCALE
			var y: float = world.height_at(pos.x,pos.y)
			var treeline := 29.5 + 2.5 * sin(x*0.12) + 1.8 * sin(z*0.08)
			var thinning := smoothstep(treeline-5.0,treeline,y/world.MAP_SCALE)
			if rng.randf() < thinning:
				continue
			var h := rng.randf_range(1.8, 3.9) * (1.0 - 0.32 * thinning)
			var base := Vector3(pos.x,y-0.16,pos.y)
			var yaw := Basis(Vector3.UP,rng.randf() * TAU)
			foliage.append(Transform3D(yaw.scaled_local(Vector3(0.62,0.62,0.62)*h),base+Vector3.UP*h*0.42))
			needles.append(Transform3D(yaw.scaled_local(Vector3(0.47,0.65,0.47)*h),base+Vector3.UP*h*0.68))
			if rng.randf() < 0.77 - 0.14 * smoothstep(140.0,230.0,distance):
				caps.append(Transform3D(yaw.scaled_local(Vector3(0.235,0.36,0.235)*h),base+Vector3.UP*h*0.83))
	_batch(world, world.scenery.pieces["spruce blue"], foliage)
	_batch(world, world.scenery.pieces["needles"], needles)
	_batch(world, world.scenery.pieces["snow on needles"], caps)

func _batch(world: Node3D, mesh: Mesh, positions: Array[Transform3D]) -> void:
	var forest := MultiMesh.new()
	forest.transform_format = MultiMesh.TRANSFORM_3D
	forest.mesh = mesh
	forest.instance_count = positions.size()
	for i in positions.size():
		forest.set_instance_transform(i, positions[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = forest
	if mesh != world.scenery.pieces["spruce blue"]:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(node)
