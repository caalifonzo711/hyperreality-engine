extends Node3D
class_name ZoneTile

# — user‐tweakable grid parameters —
@export var grid_size_x : int = 5
@export var grid_size_z : int = 5
@export var tile_spacing : float = 2.0

# 1) preload the tile scene
@export var ZoneTileScene : PackedScene = preload("res://games/meme_wars/scenes/ZoneTile.tscn")

# 2) grab Camera & physics once
@onready var camera      : Camera3D                  = $Camera3D
@onready var space_state : PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

func _ready() -> void:
	print("Finance War demo ready. Press SPACE to spawn grid.")
	# ── CAMERA SETUP (Ticket 7) ──
	# Compute the exact center of our X×Z grid:
	var center_x = (grid_size_x - 1) * tile_spacing * 0.5
	var center_z = (grid_size_z - 1) * tile_spacing * 0.5
	# Position the camera above & back:
	camera.transform.origin = Vector3(center_x, 8, center_z - 10)
	# Aim it straight at the grid’s center:
	camera.look_at(Vector3(center_x, 0, center_z), Vector3.UP)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		print("Space pressed, spawning grid…")
		spawn_tile_grid()

func spawn_tile_grid() -> void:
	print("Spawning tile grid…")
	# 3) clear old tiles
	for child in get_children():
		if child is Area3D:
			child.queue_free()

	# 4) build the grid
	for x in range(grid_size_x):
		for z in range(grid_size_z):
			var tile = ZoneTileScene.instantiate() as Area3D
			tile.transform.origin = Vector3(
				x * tile_spacing,
				0.05,
				z * tile_spacing
			)
			add_child(tile)

			# — **NEW** give *each* tile its own unshaded material —
			var mi  = tile.get_node("TileMesh") as MeshInstance3D
			var mat = StandardMaterial3D.new()
			mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
			mi.set_surface_override_material(0, mat)

			# 5) wire up its `clicked` signal
			tile.connect("clicked", Callable(self, "_on_tile_clicked"))

func _on_tile_clicked(tile: Area3D) -> void:
	# 1) If it's unclaimed, let Player 1 grab it
	if tile.claimed_by == -1:
		tile.claimed_by = 0
		print("Player 1 claimed tile at ", tile.transform.origin)
		# tint it red
		var mi  = tile.get_node("TileMesh") as MeshInstance3D
		var mat = mi.get_surface_override_material(0) as StandardMaterial3D
		mat.albedo_color = Color.RED
	else:
		# 2) Otherwise report who owns it
		print("Tile already claimed by Player ", tile.claimed_by)
