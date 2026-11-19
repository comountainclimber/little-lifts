extends SceneTree

const Mountain := preload("res://world/mountain.gd")
const Lift := preload("res://lift/chairlift.gd")
const DT := 1.0 / 60.0

var failures := 0

func _initialize() -> void:
	call_deferred("_test")

func expect(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _test() -> void:
	var terrain := Mountain.new()
	root.add_child(terrain)
	for tier in 3:
		var lift := Lift.new()
		root.add_child(lift)
		lift.configure(terrain.station_base(tier), terrain.station_top(tier), terrain, tier)
		lift.set_process(false)
		var rigs := {}
		var previous := {}
		var phases := {}
		var completed := {}
		var worst := 0.0
		for frame in 60 * 150:
			lift._process(DT)
			var seen := 0
			for guest in lift._queue:
				observe(guest, "queue", rigs, phases)
				seen += 1
			for carrier in lift._chairs:
				for guest in carrier.riders:
					if not guest:
						continue
					var phase: String = ["riding", "boarding", "unloading"][carrier.handoff]
					observe(guest, phase, rigs, phases)
					seen += 1
			for skier in lift._skiers:
				observe(skier._model, "skiing", rigs, phases)
				seen += 1
			expect(seen == 8, "All eight guests must have exactly one visible body")
			for id in rigs:
				var rig: Node3D = rigs[id]
				var chest: Vector3 = rig.chest.to_global(Vector3(0, 0.13, -0.015))
				if previous.has(id):
					worst = maxf(worst, chest.distance_to(previous[id]))
				previous[id] = chest
				if phases[id].size() == 5:
					completed[id] = true
			if completed.size() == 8:
				break
			if frame % 60 == 0:
				await process_frame
		expect(completed.size() == 8, "Every skier and boarder must traverse all five phases")
		expect(worst < 0.34, "A rider teleported at a transfer on tier %d: %.3f m/frame" % [tier, worst])
		print("Lift %d: %d continuously visible identities, max 60 Hz torso step %.3f m" % [tier, completed.size(), worst])
		lift.free()
	terrain.free()
	if failures == 0:
		print("PASS: all 24 guests keep the same body, boots, and equipment through queue, boarding, ride, unload and skiing")
	quit(1 if failures else 0)

func observe(guest: Node, phase: String, rigs: Dictionary, phases: Dictionary) -> void:
	var id: int = guest.variant
	if not rigs.has(id):
		rigs[id] = guest
		phases[id] = {}
	expect(rigs[id] == guest and guest.is_visible_in_tree(), "Guest identity must survive every handoff")
	phases[id][phase] = true
