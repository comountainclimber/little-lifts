extends "res://skiing/skier_model.gd"

var variant: int
var approaching_island := false
var _sitting := -1.0
var _stride := 0.0
var _effort := 0.0


func prepare(id: int, color: Color) -> void:
	variant = id
	build(color, id)
	sit(0.0)


# This is the downhill rig, with the same skis and boot contacts. Moving the
# pelvis behind the feet lets the knees fold into the chair without shortening
# the skier or changing their silhouette at either handoff.
func shuffle(distance: float, dt: float) -> void:
	_effort = lerpf(_effort, smoothstep(0.12, 1.2, distance / maxf(0.0001, dt)), 1.0 - exp(-10.0 * dt))
	if distance > 0.001:
		_stride += distance * 5.8
	if _effort < 0.015:
		sit(0.0)
		return
	_sitting = -1.0
	var stride := sin(_stride)
	if board != null:
		_board_pose(0.0, 1.25, 0.0, 0.26 * _effort, 0.0, (0.5 + 0.5 * stride) * _effort)
	else:
		pose(0.0, 1.25, 0.0, 0.0, 0.20 * _effort)
		for i in 2:
			var phase := stride if i == 0 else -stride
			var reach := phase * _effort
			ski_decks[i].position.z = reach * 0.07
			var side := -1.0 if i == 0 else 1.0
			var foot := Vector3(side * 0.12, 0.14, -0.015 + reach * 0.07)
			var knee := Vector3(side * 0.12, 0.24, -0.13 + reach * 0.055)
			_link(shins[i], foot, knee, 0.085)
			_link(thighs[i], knee, hips.position + Vector3(side * 0.073, 0.02, 0), 0.113)
			arms[i].rotation.x = -0.09 + 0.26 * reach


func sit(weight: float) -> void:
	if is_equal_approx(_sitting, weight):
		return
	_sitting = weight
	if board != null:
		_board_pose(0.0, 1.25, 0.0, 0.0, weight)
		return
	pose(0.0, 1.25, 0.0)
	if weight <= 0.0:
		return
	hips.position += Vector3(0.0, -0.087, 0.16) * weight
	chest.rotation.x = lerpf(chest.rotation.x, -0.02, weight)
	for i in 2:
		var side := float(i * 2 - 1)
		var knee := Vector3(side * 0.12, lerpf(0.235, 0.254, weight), lerpf(-0.12, -0.09, weight))
		var boot := Vector3(side * 0.12, 0.14, -0.015)
		var hip := hips.position + Vector3(side * 0.073, 0.02, 0.0)
		_link(shins[i], boot, knee, 0.085)
		_link(thighs[i], knee, hip, 0.113)
		arms[i].rotation.x -= weight * 0.3
