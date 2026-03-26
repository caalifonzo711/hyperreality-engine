extends Control
class_name GeminiConfigGeneratorPanel

const GeminiSchemas = preload("res://config/gemini_schemas.gd")
const ContentDomains = preload("res://config/content_domains.gd")
const ConfigFactory = preload("res://addons/gemini_integration/src/ConfigFactory.gd")

# UI references ---------------------------------------------------------------

@onready var _domain_option: OptionButton  = $MarginContainer/VBoxContainer/OptionsRow/DomainOption
@onready var _schema_option: OptionButton  = $MarginContainer/VBoxContainer/OptionsRow/SchemaOption
@onready var _prompt_edit: TextEdit        = $MarginContainer/VBoxContainer/PromptEdit
@onready var _json_preview: TextEdit       = $MarginContainer/VBoxContainer/JsonPreview
@onready var _generate_button: Button      = $MarginContainer/VBoxContainer/ButtonsRow/GenerateButton
@onready var _save_button: Button          = $MarginContainer/VBoxContainer/ButtonsRow/SaveButton
@onready var _status_label: Label          = $MarginContainer/VBoxContainer/StatusLabel

# State -----------------------------------------------------------------------

var _domain_ids: Array[String] = []
var _schema_ids: Array[String] = []
var _last_generated: Dictionary = {}   # { schema_id, domain_id, data }


func _ready() -> void:
	# Force this panel to fill the whole viewport
	var vr: Rect2 = get_viewport_rect()
	size = vr.size
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	print("GeminiConfigGeneratorPanel: _ready called, size: ", size)

	_populate_domain_options()
	_populate_schema_options()

	# Signals
	_generate_button.pressed.connect(_on_generate_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_domain_option.item_selected.connect(_on_domain_changed)

	_status_label.text = "Ready. Enter a prompt and click Generate."


# ---------- OPTIONS POPULATION ----------------------------------------------

func _populate_domain_options() -> void:
	_domain_option.clear()
	_domain_ids.clear()

	for domain_id in ContentDomains.DOMAINS.keys():
		var d_id: String = str(domain_id)
		_domain_ids.append(d_id)
		_domain_option.add_item(d_id)

	if _domain_option.item_count > 0:
		_domain_option.select(0)


func _populate_schema_options() -> void:
	_schema_option.clear()
	_schema_ids.clear()

	var domain_id := _get_selected_domain_id()

	var schema_list: Array = []
	if ContentDomains.has_domain(domain_id):
		schema_list = ContentDomains.get_schemas(domain_id)
	else:
		# Fallback: show all schemas if domain is unknown
		for s_id in GeminiSchemas.SCHEMAS.keys():
			schema_list.append(s_id)

	for schema_id in schema_list:
		var s_id: String = str(schema_id)
		_schema_ids.append(s_id)
		_schema_option.add_item(s_id)

	if _schema_option.item_count > 0:
		_schema_option.select(0)


func _get_selected_domain_id() -> String:
	if _domain_ids.is_empty():
		return ""
	var idx: int = _domain_option.selected
	idx = clamp(idx, 0, _domain_ids.size() - 1)
	return _domain_ids[idx]


func _get_selected_schema_id() -> String:
	if _schema_ids.is_empty():
		return ""
	var idx: int = _schema_option.selected
	idx = clamp(idx, 0, _schema_ids.size() - 1)
	return _schema_ids[idx]


func _on_domain_changed(_index: int) -> void:
	# When domain changes, rebuild schema list based on that domain
	_populate_schema_options()


# ---------- BUTTON HANDLERS --------------------------------------------------

func _on_generate_pressed() -> void:
	var domain_id := _get_selected_domain_id()
	var schema_id := _get_selected_schema_id()
	var prompt_text: String = _prompt_edit.text.strip_edges()

	if prompt_text.is_empty():
		_status_label.text = "Prompt is empty. Type something first."
		return

	if schema_id == "" or domain_id == "":
		_status_label.text = "Select both a domain and a schema."
		return

	_status_label.text = "Calling Gemini for %s / %s..." % [domain_id, schema_id]
	_json_preview.text = ""

	var context := {
		"domain_id": domain_id,
		"schema_id": schema_id,
	}

	# NOTE: 'Gemini' must be an autoload pointing to GeminiClient.gd
	var result: Dictionary = await Gemini.generate_json_for_schema(
		schema_id,
		prompt_text,
		context
	)

	if not result.get("ok", false):
		_status_label.text = "Gemini error: %s" % result.get("error", "unknown")
		return

	var raw_data: Dictionary = result.get("data", {})
	var norm: Dictionary = ConfigFactory.normalize_config(schema_id, raw_data)

	if not norm.get("ok", false):
		_status_label.text = "Normalize error: %s" % norm.get("error", "unknown")
		return

	var final_data: Dictionary = norm.get("data", {})

	_last_generated = {
		"schema_id": schema_id,
		"domain_id": domain_id,
		"data": final_data,
	}

	_json_preview.text = JSON.stringify(final_data, "  ")
	_status_label.text = "Generated config. Click Save to write file."


func _on_save_pressed() -> void:
	if _last_generated.is_empty():
		_status_label.text = "Nothing to save. Generate a config first."
		return

	var schema_id: String = _last_generated.get("schema_id", "")
	var domain_id: String = _last_generated.get("domain_id", "")
	var data: Dictionary = _last_generated.get("data", {})

	if schema_id == "" or domain_id == "":
		_status_label.text = "Internal error: missing schema/domain info."
		return

	# 1) Resolve root path for this domain
	var root_path := ContentDomains.get_root(domain_id) # e.g. "res://games/rollback_fighter/"
	if root_path == "":
		_status_label.text = "Unknown content domain: %s" % domain_id
		return

	# Normalize root; avoid accidental double slashes
	root_path = root_path.rstrip("/") + "/"

	# 2) Subfolder & filename for this schema
	var subfolder := ConfigFactory.get_default_subfolder_for_schema(schema_id)   # e.g. "moves"
	var dir_path := root_path + subfolder + "/"                                  # "res://games/rollback_fighter/moves/"
	var file_name := ConfigFactory.get_default_filename(schema_id, data)         # e.g. "move_jab.json"
	var full_res_path := dir_path + file_name                                    # full res:// path

	# 3) Ensure directory exists on disk
	var abs_dir_path := ProjectSettings.globalize_path(dir_path)
	var dir := DirAccess.open(abs_dir_path)
	if dir == null:
		var mk_err := DirAccess.make_dir_recursive_absolute(abs_dir_path)
		if mk_err != OK:
			push_error("Gemini panel: Failed to create dir '%s' (err %s)" % [abs_dir_path, mk_err])
			_status_label.text = "Failed to create folder for configs."
			return

	# 4) Write JSON file (we can write directly to res:// in the editor)
	var file := FileAccess.open(full_res_path, FileAccess.WRITE)
	if file == null:
		var ferr := FileAccess.get_open_error()
		push_error("Gemini panel: Failed to open '%s' for write (err %s)" % [full_res_path, ferr])
		_status_label.text = "Failed to open file for write."
		return

	var json_text := JSON.stringify(data, "  ")
	file.store_string(json_text)
	file.close()

	_status_label.text = "Saved: %s" % full_res_path
	print("Gemini panel saved config to: ", full_res_path)
