extends SceneTree

const Mountain := preload("res://world/mountain.gd")
const Resort := preload("res://demo/resort.gd")
const Rider := preload("res://skiing/rider_style.gd")

var hill: Node
var resort: Node
var failed := false
var returns := {}
var path := OS.get_temp_dir().path_join("little-lifts-forest-%d-%d.save" % [OS.get_process_id(),Time.get_ticks_usec()])

func _initialize() -> void:
	call_deferred("_check")

func expect(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)

func open() -> void:
	hill = Mountain.new()
	root.add_child(hill)
	resort = Resort.new()
	resort.save_path = path
	root.add_child(resort)
	resort.setup(hill)

func close() -> void:
	resort.free()
	hill.free()

func _returned(guest: int) -> void:
	returns[Rider.is_boarder(guest)] = true

func _check() -> void:
	open()
	var cabin: Vector2 = Vector2(2.1,15.0)*hill.MAP_SCALE
	expect(not hill.lift_ground_clear(cabin,cabin,0.0),"Existing lodge is a solid fixed obstacle")
	expect(not resort.place_lift(cabin,cabin+Vector2(-3,-19),0),"The lodge cannot be cleared for a lift")
	var upper_base := Vector2(-44,-61)
	var upper_top := Vector2(-41,-81)
	expect(not resort.place_lift(upper_base,upper_top,0),"A small chair cannot open the upper mountain on its own")
	var endpoints := [[Vector2(-36,14),Vector2(-46,-8)],[Vector2(44,23),Vector2(58,-5)]]
	var exits := PackedVector2Array()
	for pair in endpoints:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var before: int = hill.scenery._felled.size()
		var events: int = resort.journal.size()
		expect(not hill.scenery.forest_clear(a,a,0) and not hill.scenery.forest_clear(b,b,0),"Test stations actually sit inside separate standing pines")
		expect(resort.placement_issue(a,b,0).is_empty(),"A lawful lift survey accepts this stand of trees")
		expect(not resort.place_lift(b,a,0),"An uphill return is rejected")
		expect(not resort.place_lift(a,b,2),"A new forest site cannot skip tram progression")
		expect(not resort.place_lift(hill.station_base(0),b,0),"A second station cannot occupy an existing station")
		expect(before==hill.scenery._felled.size() and events==resort.journal.size(),"Preview and unsuccessful builds leave trees and construction journal untouched")
		expect(resort.place_lift(a,b,0),"Build the new chair and skiable clearing")
		if resort.lifts.size() != exits.size()+2:
			break
		var lift: Node = resort.lifts[-1]
		var n: int = hill.scenery._felled.size()-before
		expect(n>8 and n<90,"A lift clears a bounded forest corridor")
		expect(hill.scenery.forest_clear(a,b,1.10),"Both moving chair lanes are clear")
		expect(hill.scenery.forest_clear(lift.run_start(),lift.run_end(),1.48),"The return path is clear after construction")
		exits.append(lift.run_start())
		expect(resort.journal[-1].get("corridor_side",Vector2.ZERO) == lift._right,"The journal keeps the return side")
		for rider: Node in lift._skiers:
			var points: PackedVector3Array = rider._points
			for i in range(1,points.size()):
				expect(hill.route_clear(Vector2(points[i-1].x,points[i-1].z),Vector2(points[i].x,points[i].z),0.09),"A resident skier stays inside a real clearing")
		returns.clear()
		lift.returned.connect(_returned)
		for i in 3600:
			lift._process(1.0/30.0)
			if returns.size()==2:
				break
		expect(returns.size()==2,"A skier and boarder both reached the queue on the new woodland line")
		print("Woodland line ",a," to ",b,", ",n," trees, skier and snowboarder returns ",returns.size())
	var felled: Dictionary = hill.scenery._felled.duplicate()
	var events: int = resort.journal.size()
	close()
	open()
	expect(resort._restore_complete and resort.journal.size()==events and resort.lifts.size()==3,"Both independent lifts reopen")
	expect(hill.scenery._felled==felled,"Reload reopens exactly the same compact tree corridors")
	if resort.lifts.size()==3 and exits.size()==2:
		expect(resort.lifts[1].run_start().is_equal_approx(exits[0]) and resort.lifts[2].run_start().is_equal_approx(exits[1]),"The exact unloading sides survive replay")
	for tier in 3:
		if tier > 0:
			expect(resort.place_lift(hill.station_base(tier),hill.station_top(tier),tier),"Higher lift opens its own zone")
		if tier < 2:
			var lift_index: int = 0 if tier == 0 else resort.lifts.size()-1
			expect(resort.cut(lift_index,resort.suggestion(lift_index)).is_empty(),"Cut the supporting trail")
			resort._skied(resort.runs[-1].id,lift_index)
	expect(resort.place_lift(upper_base,upper_top,0),"A single chair can connect two points on the served summit afterwards")
	close()
	open()
	expect(resort._restore_complete and resort.lifts.size()==6,"Upper connector and earlier woodland lifts reopen together")
	close()
	DirAccess.remove_absolute(path)
	if not failed:
		print("PASS: off-survey woodland lifts, passive previews, fixed obstacles, unlocks, round trips, and saved clearings")
	quit(1 if failed else 0)
