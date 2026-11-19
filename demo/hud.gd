extends CanvasLayer

signal follow_requested
signal slow_requested
signal mute_requested
signal wide_requested
signal tool_requested(mode: int)
signal choice_requested(index: int)
signal shape_requested(index: int)

const STATION_THEME := preload("res://demo/trail_map_theme.tres")
const PICTOGRAMS := preload("res://demo/wayfinding_icons.svg")
const LIFT_MARK := preload("res://demo/lift_mark.svg")
const TRAIL_MARKS := preload("res://demo/trail_symbols.svg")
const GRADES := ["Easy", "Intermediate", "Advanced"]
const RAIL_WIDTH := 224.0
const ICON_TILE := 96
const TOOL_LABELS := ["Explore", "Cut a run", "Build a lift", "Village", "Terrain"]
const TOOL_TIPS := [
	"Left-drag to rotate. Right-drag to pan. Click a rider to follow (1)",
	"Draw a run through the trees (2)",
	"Place a lift uphill (3)",
	"Choose a building and a village plot (4)",
	"Choose a terrain feature (5)",
]

var hint := Label.new()
var follow := Button.new()
var slow := Button.new()
var mute := Button.new()
var wide := Button.new()
var choice := OptionButton.new()
var shape := OptionButton.new()
var tools: Array[Button] = []
var place := Label.new()
var toolbar := PanelContainer.new()
var message_bar := PanelContainer.new()
var _context := VBoxContainer.new()
var _choice_group := VBoxContainer.new()
var _shape_group := VBoxContainer.new()
var _choice_label := Label.new()
var _key_labels: Array[Label] = []
var _icons: Array[AtlasTexture] = []
var _choices := PackedStringArray()
var _signs: Array[AtlasTexture] = []
var _grade_key := VBoxContainer.new()
var _grade_flags: Array[Label] = []
var _grade_labels: Array[Label] = []

func map_inset() -> float:
	return RAIL_WIDTH

func _ready() -> void:
	toolbar.name = "StationRail"
	toolbar.theme = STATION_THEME
	if OS.has_feature("web"):
		toolbar.theme = STATION_THEME.duplicate()
		toolbar.theme.merge_with(load("res://demo/browser_fonts/web_type.tres"))
	add_child(toolbar)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	toolbar.offset_right = RAIL_WIDTH
	toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	for i in 10:
		var texture := AtlasTexture.new()
		texture.atlas = PICTOGRAMS
		texture.region = Rect2(i * ICON_TILE, 0, ICON_TILE, ICON_TILE)
		_icons.append(texture)
	for i in 5:
		var sign := AtlasTexture.new()
		sign.atlas = TRAIL_MARKS
		sign.region = Rect2(i * 24, 0, 24, 24)
		_signs.append(sign)

	var column := VBoxContainer.new()
	toolbar.add_child(column)
	column.add_theme_constant_override("separation", 0)
	_build_identity(column)
	_gap(column, 9)
	column.add_child(HSeparator.new())
	_gap(column, 10)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var workspace := VBoxContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 0)
	scroll.add_child(workspace)
	_build_tools(workspace)
	_build_context(workspace)
	_gap(workspace, 10)
	message_bar.theme_type_variation = &"TrailMessage"
	workspace.add_child(message_bar)
	hint.theme_type_variation = &"Guidance"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_bar.add_child(hint)
	_build_grade_key(workspace)
	_gap(column, 6)
	column.add_child(HSeparator.new())
	_gap(column, 6)
	_build_utilities(column)

func _build_identity(column: Control) -> void:
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	brand.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_child(brand)
	var stamp := TextureRect.new()
	stamp.texture = LIFT_MARK
	stamp.custom_minimum_size = Vector2(42, 42)
	stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(stamp)
	var title := Label.new()
	title.text = "LITTLE LIFTS"
	title.theme_type_variation = &"Masthead"
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_child(title)
	_gap(column, 8)
	place.theme_type_variation = &"Location"
	column.add_child(place)

func _build_tools(column: Control) -> void:
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 3)
	column.add_child(nav)
	for i in TOOL_LABELS.size():
		var button := Button.new()
		button.theme_type_variation = &"RailTool"
		button.toggle_mode = true
		_button(nav, button, TOOL_LABELS[i], TOOL_TIPS[i], i, 42)
		_key_labels.append(_key(button, str(i + 1)))
		tools.append(button)
		button.pressed.connect(func(): tool_requested.emit(i))

func _build_context(column: Control) -> void:
	column.add_child(_context)
	_context.add_theme_constant_override("separation", 4)
	_gap(_context, 7)
	_select_field(_choice_group, _choice_label, choice, "Tool options")
	shape.accessibility_name = "Suggested line"
	var shape_label := Label.new()
	shape_label.text = "SUGGESTED LINE"
	_select_field(_shape_group, shape_label, shape, "Draw your own line or follow a survey.")
	for label in ["Gentle arc", "S turns", "Tree weave"]:
		shape.add_item(label)
	choice.item_selected.connect(func(index): choice_requested.emit(index))
	shape.item_selected.connect(func(index): shape_requested.emit(index))
	_choice_group.hide()
	_shape_group.hide()
	_context.hide()

func _select_field(group: VBoxContainer, label: Label, button: OptionButton, tip: String) -> void:
	_context.add_child(group)
	group.add_theme_constant_override("separation", 1)
	label.theme_type_variation = &"ContextLabel"
	group.add_child(label)
	button.fit_to_longest_item = false
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	_button(group, button, "", tip, -1, 32)

func _build_grade_key(column: Control) -> void:
	column.add_child(_grade_key)
	_grade_key.add_theme_constant_override("separation", 2)
	_gap(_grade_key, 7)
	var heading := Label.new()
	heading.text = "TRAIL KEY"
	heading.theme_type_variation = &"ContextLabel"
	_grade_key.add_child(heading)
	for i in GRADES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		_grade_key.add_child(row)
		var mark := TextureRect.new()
		mark.texture = _signs[i]
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(19, 19)
		row.add_child(mark)
		var label := Label.new()
		label.text = GRADES[i]
		label.theme_type_variation = &"Location"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_grade_labels.append(label)
		var flag := Label.new()
		flag.text = "THIS LINE"
		flag.theme_type_variation = &"SurveyGrade"
		flag.hide()
		row.add_child(flag)
		_grade_flags.append(flag)

func set_run_grade(grade: String) -> void:
	for i in _grade_flags.size():
		var matches: bool = grade == GRADES[i]
		_grade_flags[i].visible = matches
		_grade_labels[i].accessibility_description = "Grade of this line" if matches else ""

func _build_utilities(column: Control) -> void:
	_button(column, wide, "Whole mountain", "Return to the mountain overview (R)", 5, 33)
	_button(column, follow, "Follow a rider", "Follow a descent (F)", 6, 33)
	_button(column, slow, "Slow motion", "Toggle slow motion (Space)", 7, 33)
	_button(column, mute, "Mute", "Mute game sound (M)", 8, 33)
	_key(wide, "R")
	_key(follow, "F")
	_key(slow, "Space")
	_key(mute, "M")
	wide.hide()
	wide.pressed.connect(func(): wide_requested.emit())
	follow.pressed.connect(func(): follow_requested.emit())
	slow.pressed.connect(func(): slow_requested.emit())
	mute.pressed.connect(func(): mute_requested.emit())

func _gap(parent: Control, height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)
	return gap

func _button(parent: Control, button: Button, caption: String, tip: String, icon_index: int, height: int) -> void:
	button.text = caption
	button.tooltip_text = tip
	button.accessibility_description = tip
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if icon_index >= 0:
		button.icon = _icons[icon_index]
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = height
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	# Pointer use returns keyboard shortcuts to the map. Tab retains normal focus.
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			button.release_focus.call_deferred()
	)

func _key(button: Button, shortcut: String) -> Label:
	var key := Label.new()
	key.text = shortcut
	key.theme_type_variation = &"Key"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.accessibility_name = "Shortcut " + shortcut
	button.add_child(key)
	key.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	key.offset_right = -9
	key.offset_left = -52
	return key

func set_tools(mode: int, names: PackedStringArray, selected: int) -> void:
	for i in tools.size():
		var active := i == mode
		tools[i].set_pressed_no_signal(active)
		_key_labels[i].theme_type_variation = &"ActiveKey" if active else &"Key"
	if names != _choices:
		_choices = names.duplicate()
		choice.clear()
		for item in names:
			choice.add_item(item)
			if mode == 4:
				choice.set_item_icon(choice.item_count - 1, _signs[4 if choice.item_count == 1 else 3])
	_choice_label.text = ["", "LIFT AREA", "LIFT TYPE", "BUILDING", "TERRAIN FEATURE"][mode]
	choice.accessibility_name = _choice_label.text.capitalize()
	_choice_group.visible = not names.is_empty()
	choice.visible = _choice_group.visible
	if choice.visible:
		choice.select(clampi(selected, 0, names.size() - 1))
	_context.visible = _shape_group.visible or _choice_group.visible
	_grade_key.visible = mode == 0 or mode == 1
	if mode != 1:
		set_run_grade("")

func show_run_shapes(in_cut_mode: bool, index: int) -> void:
	shape.visible = in_cut_mode
	_shape_group.visible = in_cut_mode
	_context.visible = in_cut_mode or _choice_group.visible
	if in_cut_mode:
		shape.select(clampi(index, 0, shape.item_count - 1))

func set_hint(message: String) -> void:
	hint.text = message
	message_bar.visible = not message.is_empty()

func show_slow(enabled: bool) -> void:
	slow.text = "Normal speed" if enabled else "Slow motion"

func show_muted(muted: bool) -> void:
	mute.text = "Unmute" if muted else "Mute"
	mute.icon = _icons[9 if muted else 8]
	mute.tooltip_text = "Unmute game sound (M)" if muted else "Mute game sound (M)"
	mute.accessibility_description = mute.tooltip_text
