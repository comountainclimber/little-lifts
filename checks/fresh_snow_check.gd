extends SceneTree

const Hill := preload("res://world/mountain.gd")
const Resort := preload("res://demo/resort.gd")
const Track := preload("res://skiing/carve_track.gd")
const FeatureLine := preload("res://skiing/feature_line.gd")
var errors := 0

func _initialize() -> void:
	call_deferred("_check")

func expect(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		errors += 1

func _check() -> void:
	var terrain := Hill.new()
	root.add_child(terrain)
	var resort := Resort.new()
	resort.save_path = OS.get_temp_dir().path_join("little-lifts-snow-%d-%d.save" % [OS.get_process_id(),Time.get_ticks_usec()])
	root.add_child(resort)
	resort.setup(terrain)
	var lift: Node = resort.lifts[0]
	var center := PackedVector2Array()
	var branch := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		var p: Vector2 = lift.run_start().lerp(lift.run_end(),t)
		center.append(p)
		branch.append(p + lift._right * 2.9 * sin(t*PI))
	expect(terrain.scenery.trees_along(center,terrain.CUT_HALF_WIDTH).is_empty(),"Fixture must begin on open snow")
	expect(resort.cut(0,center).is_empty(),"Open a treeless route between real terminals")
	var original_size := resort.journal.size()
	var repeat := PackedVector2Array()
	for i in range(1,center.size()):
		repeat.append(center[i-1])
		repeat.append(center[i-1].lerp(center[i],0.5))
	repeat.append(center[-1])
	expect(not resort.cut(0,repeat).is_empty() and resort.journal.size()==original_size,"Resampling an open corridor must not create a duplicate")
	expect(resort.cut(0,branch).is_empty() and resort.runs.size()==2,"A real branch beside the same lift is a new route")
	var saved := resort.save_path
	resort.free()
	terrain.free()
	terrain = Hill.new()
	root.add_child(terrain)
	resort = Resort.new()
	resort.save_path = saved
	root.add_child(resort)
	resort.setup(terrain)
	expect(resort._restore_complete and resort.runs.size()==2,"Both open-snow routes replay from a real saved journal")
	DirAccess.remove_absolute(saved)

	# Compare the rendered geometry at chunk boundaries and at a landing.
	var path := PackedVector3Array()
	var distances := PackedFloat32Array()
	var jump := FeatureLine.Pass.new()
	jump.ramp_row = 12
	jump.lip_row = 21
	jump.landing_row = 44
	var jumps: Array[FeatureLine.Pass] = [jump]
	for i in 90:
		var flat: Vector2 = center[0].lerp(center[-1],i/89.0)
		var air := 0.0
		if i > jump.lip_row and i < jump.landing_row:
			air = 1.8*sin(PI*(i-jump.lip_row)/float(jump.landing_row-jump.lip_row))
		path.append(Vector3(flat.x,terrain.surface_height(flat.x,flat.y)+air,flat.y))
		distances.append(0.0 if i==0 else distances[-1]+path[i].distance_to(path[i-1]))
	for board: bool in [false,true]:
		var full := Track.new()
		var streamed := Track.new()
		root.add_child(full)
		root.add_child(streamed)
		full.build(path,distances,terrain,board,1.0,jumps)
		streamed.build(path,distances,terrain,board,1.0,jumps,true)
		expect(streamed.last_row < jump.landing_row,"Departure should bake only the snow immediately ahead")
		streamed.reveal(distances[jump.landing_row])
		expect(streamed.last_row >= jump.landing_row,"Landing snow must be ready before the feet touch")
		streamed.finish()
		var original := full.mesh.surface_get_arrays(0)
		var finished := streamed.mesh.surface_get_arrays(0)
		for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR,Mesh.ARRAY_INDEX]:
			expect(original[slot] == finished[slot],"Completed streamed mesh differs at attribute %s" % slot)
		full.free()
		streamed.free()
	resort.free()
	terrain.free()
	if errors==0:
		print("PASS: all-snow branches save and restore, duplicate strokes rejected, streamed ski/board powder meshes match one-shot vertices, normals and airborne gaps")
	quit(1 if errors else 0)
