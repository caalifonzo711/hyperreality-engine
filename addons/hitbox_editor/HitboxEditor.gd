extends Control

# --- CONFIG ---------------------------------------------------

@export_dir var sprite_folder: String = "res://rollback_fighter/characters/example_fighter/sprites"
@export var output_hitbox_file: String = "res://rollback_fighter/characters/example_fighter/hitboxes/jab.json"

# size of boxes we drop when we click
const BOX_SIZE: Vector2 = Vector2(32, 32)

enum HitType { HITBOX, HURTBOX }

# --- NODE REFS ------------------------------------------------

@onready var sprite_rect: TextureRect        = $SpriteRect
@onready var overlay: Control                = $Overlay
@onready var hit_type_button: OptionButton   = $UI/HitTypeButton
@onready var prev_button: Button             = $UI/PrevFrame
@onready var next_button: Button             = $UI/NextFrame
@onready var save_button: Button             = $UI/SaveButton

# --- RUNTIME STATE --------------------------------------------

var _frames: Array[Texture2D] = []
var _current_frame: int = 0

# per-frame data:
# [ { "hitboxes": Array[Rect2], "hurtboxes": Array[Rect2] }, ... ]
var _frame_data: Array = []

var _current_hit_type: int = HitType.HITBOX


func _ready() -> void:
	# Setup UI options
	hit_type_button.clear()
	hit_type_button.add_item("Hitbox (red)", HitType.HITBOX)
	hit_type_button.add_item("Hurtbox (blue)", HitType.HURTBOX)
	hit_type_button.selected = 0

	# Connect signals
	hit_type_button.item_selected.connect(_on_hit_type_changed)
	prev_button.pressed.connect(_on_prev_frame)
	next_button.pressed.connect(_on_next_frame)
	save_button.pressed.connect(_on_save)

	overlay.gui_input.connect(_on_overlay_input)
	overlay.draw.connect(_on_Overlay_draw)  # draw signal for red/blue boxes

	# Load all pngs in the folder
	_load_frames_from_folder(sprite_folder)

	# Init frame data (one dict per frame)
	_frame_data.clear()
	for i in range(_frames.size()):
		_frame_data.append({
			"hitboxes": [],
			"hurtboxes": []
		})

	_show_current_frame()
	overlay.queue_redraw()


# --------------------------------------------------------------
# LOADING FRAMES
# --------------------------------------------------------------
func _load_frames_from_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("HitboxEditor: could not open folder: " + path)
		return

	dir.list_dir_begin()
	while true:
		var file: String = dir.get_next()
		if file == "":
			break
		if dir.current_is_dir():
			continue
		if file.ends_with(".png"):
			var tex := load(path + "/" + file) as Texture2D
			if tex:
				_frames.append(tex)
	dir.list_dir_end()

	if _frames.is_empty():
		push_warning("HitboxEditor: no PNGs found in " + path)


# --------------------------------------------------------------
# FRAME NAV
# --------------------------------------------------------------
func _show_current_frame() -> void:
	if _frames.is_empty():
		sprite_rect.texture = null
		return

	_current_frame = clamp(_current_frame, 0, _frames.size() - 1)
	sprite_rect.texture = _frames[_current_frame]
	overlay.queue_redraw()

func _on_prev_frame() -> void:
	if _frames.is_empty():
		return
	_current_frame = max(0, _current_frame - 1)
	_show_current_frame()

func _on_next_frame() -> void:
	if _frames.is_empty():
		return
	_current_frame = min(_frames.size() - 1, _current_frame + 1)
	_show_current_frame()

func _on_hit_type_changed(index: int) -> void:
	_current_hit_type = hit_type_button.get_selected_id()


# --------------------------------------------------------------
# INPUT: clicking on overlay places boxes
# --------------------------------------------------------------
func _on_overlay_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if _frames.is_empty():
		return

	# Mouse in overlay local coords
	var local_pos: Vector2 = overlay.get_local_mouse_position()

	# Create a rect centered at click
	var rect := Rect2(local_pos - BOX_SIZE * 0.5, BOX_SIZE)

	var frame_dict: Dictionary = _frame_data[_current_frame]

	match _current_hit_type:
		HitType.HITBOX:
			frame_dict["hitboxes"].append(rect)
		HitType.HURTBOX:
			frame_dict["hurtboxes"].append(rect)

	overlay.queue_redraw()


# --------------------------------------------------------------
# DRAW BOXES
# --------------------------------------------------------------
func _draw_rects_on_overlay() -> void:
	if _frames.is_empty():
		return

	var frame_dict: Dictionary = _frame_data[_current_frame]
	var hitboxes: Array = frame_dict["hitboxes"]
	var hurtboxes: Array = frame_dict["hurtboxes"]

	for r in hitboxes:
		overlay.draw_rect(r, Color(1, 0, 0, 0.5), true, 2.0)
	for r in hurtboxes:
		overlay.draw_rect(r, Color(0, 0, 1, 0.5), true, 2.0)

func _process(delta: float) -> void:
	# nothing needed, but keeps Control "live"
	pass

func _on_Overlay_draw() -> void:
	_draw_rects_on_overlay()


# --------------------------------------------------------------
# SAVE TO JSON
# --------------------------------------------------------------
func _on_save() -> void:
	var json_frames: Array = []

	for i in range(_frame_data.size()):
		var frame_dict: Dictionary = _frame_data[i]
		var frame_entry := {
			"index": i,
			"hitboxes": [],
			"hurtboxes": []
		}

		for r in frame_dict["hitboxes"]:
			frame_entry["hitboxes"].append({
				"x": r.position.x,
				"y": r.position.y,
				"w": r.size.x,
				"h": r.size.y,
			})
		for r in frame_dict["hurtboxes"]:
			frame_entry["hurtboxes"].append({
				"x": r.position.x,
				"y": r.position.y,
				"w": r.size.x,
				"h": r.size.y,
			})

		json_frames.append(frame_entry)

	var root := { "frames": json_frames }

	var file := FileAccess.open(output_hitbox_file, FileAccess.WRITE)
	if file == null:
		push_error("HitboxEditor: could not open for write: " + output_hitbox_file)
		return

	var text := JSON.stringify(root, "\t") # pretty print
	file.store_string(text)
	file.close()

	print("[HitboxEditor] Saved hitboxes to ", output_hitbox_file)


func _on_overlay_draw() -> void:
	pass # Replace with function body.
