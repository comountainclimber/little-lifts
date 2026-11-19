extends Node3D

const RiderStyle := preload("res://skiing/rider_style.gd")
const Snowboard := preload("res://skiing/snowboard.gd")
const Outfit := preload("res://skiing/rider_outfit.gd")
const TurnSpray := preload("res://skiing/turn_spray.gd")

var board: Snowboard
var _stance: float
var _neck: Node3D

# Local forward is -Z. The contact points stay on the snow while the knees,
# pelvis and upper body move inside a turn.
var hips := Node3D.new()
var chest := Node3D.new()
var _powder: TurnSpray
var _variant: int
var ski_decks: Array[Node3D] = []
var arms: Array[Node3D] = []
var shins: Array[MeshInstance3D] = []
var thighs: Array[MeshInstance3D] = []
static var _materials: Dictionary = {}
static var _box := BoxMesh.new()
static var _orb: SphereMesh


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var paint := StandardMaterial3D.new()
		paint.albedo_color = color
		paint.roughness = 0.92
		_materials[color] = paint
	return _materials[color]


func _piece(parent: Node3D, shape: Mesh, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = _material(color)
	instance.position = at
	instance.scale = size
	parent.add_child(instance)
	return instance


func build(jacket: Color, variant: int) -> void:
	if _orb == null:
		_orb = SphereMesh.new()
		_orb.radial_segments = 10
		_orb.rings = 5
	_variant = variant
	var trim := Color("#edc77c") if posmod(variant,2)==0 else Color("#95c2bb")
	add_child(hips)
	hips.position.y = 0.36
	hips.add_child(chest)
	chest.position.y = 0.01
	_dressed_part(chest,Outfit.jacket(jacket),"Ski jacket")
	_neck = Node3D.new()
	_neck.name = "Neck"
	chest.add_child(_neck)
	_neck.position = Vector3(0,0.278,-0.032)
	_dressed_part(_neck,Outfit.head(trim,variant),"Helmet and goggles")
	if RiderStyle.is_boarder(variant):
		_stance = RiderStyle.toe_side(variant)
		board = Snowboard.new()
		board.name = "Snowboard"
		add_child(board)
		board.build(self,_stance)
	for side:float in [-1.0,1.0]:
		if board == null:
			var deck := Node3D.new()
			add_child(deck)
			deck.position.x = side*0.12
			ski_decks.append(deck)
			_dressed_part(deck,Outfit.ski(trim),"Ski and boot")
		shins.append(_dressed_part(self,Outfit.trousers(false),"Lower leg"))
		thighs.append(_dressed_part(self,Outfit.trousers(true),"Upper leg"))
		var arm := Node3D.new()
		chest.add_child(arm)
		arm.position = Vector3(side*0.132,0.204,-0.010)
		arms.append(arm)
		_dressed_part(arm,Outfit.sleeve(side,jacket,board!=null),"Sleeve and mitten")

func _dressed_part(parent:Node3D, geometry:Mesh, label:String) -> MeshInstance3D:
	var part:=MeshInstance3D.new()
	part.name=label
	part.mesh=geometry
	parent.add_child(part)
	return part


func _link(mesh_part: MeshInstance3D, low: Vector3, high: Vector3, thickness: float) -> void:
	var span := high - low
	var basis_y := span.normalized()
	var basis_x := basis_y.cross(Vector3.BACK).normalized()
	var basis_z := basis_x.cross(basis_y)
	mesh_part.transform = Transform3D(
		Basis(basis_x * thickness, basis_y * span.length(), basis_z * thickness),
		(low + high) * 0.5
	)


func touch_down(speed: float) -> void:
	if _powder != null:
		_powder.touch_down(speed, board != null)


func pose(bank: float, speed: float, curvature: float, counter_yaw := 0.0, pressure := 0.0, airborne := false) -> void:
	if speed >= 2.25 or _powder != null:
		if _powder == null:
			_powder = TurnSpray.new()
			_powder.name = "TurnSpray"
			add_child(_powder)
			_powder.setup(self, _variant)
		if airborne:
			_powder.leave_snow()
		else:
			_powder.load_edge(bank, speed, curvature, board != null)
	if board != null:
		_board_pose(bank, speed, counter_yaw, pressure, 0.0)
		return
	var loaded := absf(bank)
	var tuck := smoothstep(1.6, 7.0, speed)
	# Stand taller as the skis move under the body, then shorten the inside
	# leg and drop the pelvis as pressure builds on the opposite edge.
	var rise := 0.072 * (1.0 - pressure) * smoothstep(0.8, 3.0, speed)
	hips.position = Vector3(sin(bank) * 0.20, 0.37 + rise - tuck * 0.029 - pressure * 0.087, 0.048 + 0.027 * pressure - 0.034*tuck)
	hips.rotation.z = -bank
	chest.rotation.z = bank * 0.38
	chest.rotation.x = -0.20 - tuck*0.23 - 0.055*pressure*tuck
	chest.rotation.y = counter_yaw * 0.78 + clampf(curvature * 0.07, -0.06, 0.06)
	_neck.rotation.x = -chest.rotation.x*0.58
	_neck.rotation.z = bank*0.16
	for i in 2:
		var side := float(i * 2 - 1)
		var x := side * 0.12
		var inside := clampf(side * bank / 0.67, -1.0, 1.0)
		var lead := -0.075 * inside
		ski_decks[i].position.z = lead
		var foot := Vector3(x, 0.14, -0.015 + lead)
		var knee := Vector3(x + sin(bank) * 0.108, 0.23 + rise * 0.47 - pressure * 0.024 - inside * 0.023, lead - 0.12 - tuck * 0.034 - inside * 0.038)
		var hip_joint := hips.position + Vector3(side * 0.073, 0.02, 0.0)
		_link(shins[i], foot, knee, 0.085)
		_link(thighs[i], knee, hip_joint, 0.113)
		ski_decks[i].rotation.z = -bank * 0.69
		arms[i].rotation.x = 0.07 + 0.23*tuck + side*bank*0.59
		arms[i].rotation.z = side * (0.09 + loaded * 0.30)


func _board_pose(bank: float, speed: float, counter_yaw: float, pressure: float, sitting: float, push := 0.0) -> void:
	board.tilt(bank, sitting)
	if push > 0.0:
		# The lead boot steers while the loose rear boot takes a short skate step.
		var boot := board.boots[1]
		boot.position += Vector3(_stance * 0.12, 0.045 * sin(push * PI), 0.21) * push
	var toe := clampf(bank * _stance / 0.66, -1.0, 1.0)
	var heel_load := maxf(-toe, 0.0)
	var toe_load := maxf(toe, 0.0)
	var rise := (1.0 - pressure) * smoothstep(1.2, 3.6, speed) * 0.052
	var standing := Vector3(sin(bank) * 0.22, 0.39 + rise - pressure * 0.065 - heel_load * 0.038, -0.025)
	hips.position = standing.lerp(Vector3(0, 0.279, 0.222), sitting)
	var yaw := lerpf(-_stance * 1.32, -_stance * 0.085, sitting)
	hips.basis = Basis(Vector3.BACK, -bank * 0.74) * Basis(Vector3.UP, yaw)
	chest.rotation = Vector3(lerpf(-0.16 - toe_load * 0.22, -0.035, sitting), (counter_yaw * 0.42 + _stance * 0.20) * (1.0 - sitting), 0.0)
	_neck.rotation.y = (_stance * 0.80 - counter_yaw * 0.31) * (1.0 - sitting)
	_neck.rotation.x = -chest.rotation.x*0.56
	# Toe edge bends the ankles toward the snow. On the heel edge the seat
	# drops while the knees stay in front of the boots to counterbalance it.
	for i in 2:
		var lead_sign := -1.0 if i == 0 else 1.0
		var side := lead_sign * _stance
		var ankle: Vector3 = board.ankle(i)
		var hip := hips.transform * Vector3(side * 0.081, 0.015, 0.0)
		var knee := ankle.lerp(hip, 0.49)
		var across := _stance * (0.064 + toe_load * 0.082 + heel_load * 0.043)
		knee += Vector3(across, 0.010, lead_sign * 0.055 - 0.022).lerp(Vector3(0, 0.066, -0.136), sitting)
		_link(shins[i], ankle, knee, 0.093)
		_link(thighs[i], knee, hip, 0.121)
		var reach := 0.31 + pressure * 0.37 + (0.12 if i == 0 else 0.0)
		# Arms are indexed by anatomical side, independent of the lead foot.
		var arm := arms[0 if side < 0 else 1]
		arm.rotation.z = side * lerpf(reach, 0.10, sitting)
		arm.rotation.x = lerpf(0.10 + toe * 0.27 + lead_sign * 0.19, -0.25, sitting)
