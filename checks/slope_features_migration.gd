extends SceneTree

const Mountain := preload("res://world/mountain.gd")
const Resort := preload("res://demo/resort.gd")
const Fixture := "slope_features_0_2_1.save"
var failed := false

func _initialize() -> void:
	call_deferred("_check")

func expect(ok: bool, note: String) -> void:
	if not ok:
		failed = true
		push_error(note)

func _check() -> void:
	var fixture := FileAccess.get_file_as_bytes(get_script().resource_path.get_base_dir().path_join(Fixture))
	var path := OS.get_temp_dir().path_join("little-lifts-v1-%d-%d.save" % [OS.get_process_id(),Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(fixture)
	file.close()
	# Captured from the 0.2.1 game: three non-survey strokes, an off-survey
	# double chair, every constructed village building and all three lift tiers.
	var migrated_events := []
	for pass_index in 2:
		var hill := Mountain.new()
		root.add_child(hill)
		var resort := Resort.new()
		resort.save_path = path
		root.add_child(resort)
		resort.setup(hill)
		expect(resort._restore_complete and resort.lifts.size() == 3 and resort.runs.size() == 3, "All original lifts and hand-drawn trails migrate")
		if resort.lifts.size() == 3 and resort.runs.size() == 3:
			expect(resort.lifts[1]._summit.is_equal_approx(Vector2(18.3,-33) * hill.MAP_SCALE), "The player's custom double chair stays at its mountain location")
			expect(resort.unlocked == 2 and resort.village.occupied.size() == 3, "Village plots and ridden trails survive migration")
			for i in 3:
				var run: Dictionary = resort.runs[i]
				var authored: PackedVector2Array = resort.lifts[i]._runs[run.id]
				expect(authored[0].is_equal_approx(resort.lifts[i].run_start()) and authored[-1].is_equal_approx(resort.lifts[i].run_end()) and run.used, "Migrated runs connect the new physical terminals")
			if pass_index == 0:
				expect(FileAccess.get_file_as_bytes(path) == fixture, "Opening a legacy resort leaves its original save intact")
				expect(resort.journal.size() == 11, "All eleven existing construction events restored")
				expect(resort.add_feature(0,0).is_empty(), "A migrated old trail supports a two-jump park")
				file = FileAccess.open(path, FileAccess.READ)
				var data = file.get_var(false)
				file.close()
				expect(data.version == 2 and data.events.size() == 12, "The next construction writes the migrated journal once")
				migrated_events = resort.journal.duplicate(true)
			else:
				expect(resort.journal == migrated_events and resort.runs[0].features.has(0), "A second reopen keeps the same trail coordinates, park and buildings")
		resort.free()
		hill.free()
	DirAccess.remove_absolute(path)
	if not failed:
		print("PASS: 0.2.1 resort with three authored runs, custom lift, and three buildings migrates to 1.5x map, builds and reopens")
	quit(1 if failed else 0)
