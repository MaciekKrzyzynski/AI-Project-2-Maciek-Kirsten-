extends Node3D

const HumanoidScript := preload("res://scripts/Humanoid.gd")
const TruckScript    := preload("res://scripts/Truck.gd")
const CameraControllerScript := preload("res://scripts/CameraController.gd")

# --- Economy ---
var funds: int = 80000
var supplies: int = 150
const MAX_SUPPLIES: int = 400

# ============================================================
# HOSPITAL GEOMETRY CONSTANTS
# ============================================================
const BX_MIN := -20.0
const BX_MAX :=  20.0
const BZ_MIN := -10.0
const BZ_MAX :=  10.0
const WALL_T := 0.4
const WALL_H := 6.0

const FRONT_CORRIDOR_Z := -3.0
const BACK_CORRIDOR_Z  :=  7.0
const CORRIDOR_HALF_W  := 1.5

const WARD_DEFS := [
	{ "name": "A", "x_min": -20.0, "x_max": -12.0 },
	{ "name": "B", "x_min": -12.0, "x_max":  -4.0 },
	{ "name": "C", "x_min":  -4.0, "x_max":   4.0 },
	{ "name": "D", "x_min":   4.0, "x_max":  12.0 },
	{ "name": "E", "x_min":  12.0, "x_max":  20.0 },
]

const BACK_DEFS := [
	{ "name": "Pharmacy", "x_min": -20.0, "x_max": -10.0 },
	{ "name": "Depot",    "x_min": -10.0, "x_max":   0.0 },
	{ "name": "Staff",    "x_min":   0.0, "x_max":  10.0 },
	{ "name": "Storage",  "x_min":  10.0, "x_max":  20.0 },
]

const DOOR_W := 2.0

# --- Beds ---
var bed_positions: Array[Vector3] = []
var bed_wards: Array[String] = []
var bed_occupied: Array[bool] = []
var occupied_beds: int = 0

# --- Nav graph ---
var nav: RefCounted = null

# --- Wall collision ---
var wall_rects: Array[Rect2] = []
const AGENT_RADIUS := 0.42

# --- Doors ---
var doors: Array = []
var entrance_left: MeshInstance3D
var entrance_right: MeshInstance3D
var entrance_open_amount: float = 0.0
const ENTRANCE_CLOSED_X := 0.85

# --- Actors ---
var patients: Array = []
var staff: Array = []
var truck: Node3D = null

# --- Spawning ---
var population_clock: float = 0.0
const POPULATION_INTERVAL := 3.5
const MAX_PATIENTS := 10

# --- Node refs ---
var actors_root: Node3D
var buildings_root: Node3D
var props_root: Node3D
var doors_root: Node3D
var camera: Camera3D
var hospital_roof: MeshInstance3D
var funds_label: Label
var supplies_bar: ProgressBar
var beds_bar: ProgressBar
var order_button: Button
var recruit_button: Button
var status_label: Label

func _ready() -> void:
	for w in WARD_DEFS:
		var cx: float = (float(w["x_min"]) + float(w["x_max"])) * 0.5
		bed_positions.append(Vector3(cx, 1.2, -7.5))
		bed_wards.append(str(w["name"]))
		bed_positions.append(Vector3(cx, 1.2, -5.0))
		bed_wards.append(str(w["name"]))
	bed_occupied.resize(bed_positions.size())
	for i in range(bed_occupied.size()):
		bed_occupied[i] = false

	_build_scene()
	_build_nav_graph()
	_build_skyline()
	_build_street_props()
	_spawn_initial_staff()

	supplies_bar.max_value = MAX_SUPPLIES
	supplies_bar.value = supplies
	beds_bar.max_value = bed_positions.size()
	beds_bar.value = occupied_beds

	order_button.pressed.connect(_on_order_supplies)
	recruit_button.pressed.connect(_on_recruit_staff)

	_update_hud()

# ============================================================
# MASTER SCENE BUILDER
# ============================================================
func _build_scene() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_camera()

	props_root    = Node3D.new(); props_root.name    = "Props";    add_child(props_root)
	doors_root    = Node3D.new(); doors_root.name    = "Doors";    add_child(doors_root)
	actors_root   = Node3D.new(); actors_root.name   = "Actors";   add_child(actors_root)
	buildings_root = Node3D.new(); buildings_root.name = "Buildings"; add_child(buildings_root)

	_build_ground()
	_build_roads()
	_build_hospital_shell()
	_build_front_row_walls()
	_build_back_row_walls()
	_build_reception()
	_build_waiting_area()
	_build_beds()
	_build_pharmacy()
	_build_supply_depot()
	_build_staff_room()
	_build_helipad()
	_build_entrance_canopy()
	_build_hud()

# ------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------
func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.53, 0.65, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.75)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 140, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.shadow_enabled = false
	add_child(fill)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 32, -50)
	camera.rotation_degrees = Vector3(-32, 0, 0)
	camera.fov = 55
	camera.current = true
	camera.set_script(CameraControllerScript)
	add_child(camera)
# ============================================================
# NAVIGATION GRAPH
# ============================================================
func _build_nav_graph() -> void:
	nav = NavGraph.new()

	# Corridor geometry recap:
	#   Front corridor: z = -3 is the centerline, walls at z = -1.5 (north) and
	#                   z = -4.5 (nothing — the front corridor is bounded by the
	#                   ward-north wall at z = -1.5 and by the corridor's south
	#                   side which is open toward the waiting area at x < -16).
	#   In practice: front corridor walkable band is z ∈ [-4.0, -2.0].
	#   Back corridor:  z = +7 centerline, walkable band z ∈ [+6.0, +8.0].
	#
	# Door centers on walls (door opening spans DOOR_W = 2.0, centered at the
	# wall's z position):
	#   Ward doors: wall at z = -1.5, opening z ∈ [-2.5, -0.5].
	#   Back doors: wall at z = +5.5, opening z ∈ [+4.5, +6.5].
	# Door nodes therefore need to sit at the corridor-side edge of the opening
	# so agents transition smoothly from corridor → room without stepping into
	# the wall itself.

	# ---- Entrance chain ----
	nav.add_node("entrance_out",     Vector3(  0.0, 0.5, -13.0))
	nav.add_node("entrance_in",      Vector3(  0.0, 0.5, -10.0))    # mid-doorway
	nav.add_node("entrance_inner",   Vector3(  0.0, 0.5,  -5.5))    # inside, past the wall

	# ---- Front corridor: mid-corridor nodes, safely away from both walls ----
	nav.add_node("corridor_front_w", Vector3(-15.0, 0.5, -3.0))
	nav.add_node("corridor_front_mw",Vector3( -8.0, 0.5, -3.0))
	nav.add_node("corridor_front_c", Vector3(  0.0, 0.5, -3.0))
	nav.add_node("corridor_front_me",Vector3(  8.0, 0.5, -3.0))
	nav.add_node("corridor_front_e", Vector3( 15.0, 0.5, -3.0))
	nav.add_node("reception",        Vector3(-10.0, 0.5, -3.0))    # moved into corridor center

	# ---- Mid connectors (front corridor to back corridor) ----
	# These run north-south at x = -8, 0, +8.
	# Mid corridor z = +1 is between the front-corridor north wall (z = -1.5)
	# and the back-corridor south wall (z = +5.5). It's open space.
	nav.add_node("corridor_mid_w",   Vector3( -8.0, 0.5,  1.0))
	nav.add_node("corridor_mid_c",   Vector3(  0.0, 0.5,  1.0))
	nav.add_node("corridor_mid_e",   Vector3(  8.0, 0.5,  1.0))

	# ---- Back corridor ----
	nav.add_node("corridor_back_w",  Vector3(-15.0, 0.5,  7.0))
	nav.add_node("corridor_back_mw", Vector3( -8.0, 0.5,  7.0))
	nav.add_node("corridor_back_c",  Vector3(  0.0, 0.5,  7.0))
	nav.add_node("corridor_back_me", Vector3(  8.0, 0.5,  7.0))
	nav.add_node("corridor_back_e",  Vector3( 15.0, 0.5,  7.0))

	# ---- Ward doors + ward centers ----
	# Door nodes sit 0.8 units south of the wall (into the corridor side),
	# which is safely inside the doorway band z ∈ [-4.0, -2.0].
	for w in WARD_DEFS:
		var xc: float = (float(w["x_min"]) + float(w["x_max"])) * 0.5
		var wdoor_id: String = "door_" + str(w["name"])
		var wroom_id: String = "room_" + str(w["name"])
		# Door node: at the door's x, but at the corridor centerline z = -3,
		# so the agent walks up to the door along the corridor and then steps
		# straight north through it.
		nav.add_node(wdoor_id, Vector3(xc, 0.5, -2.5))
		# Room node: inside the ward, clear of beds and walls.
		nav.add_node(wroom_id, Vector3(xc, 0.5, -6.5))

	# ---- Back doors + back room centers ----
	for b in BACK_DEFS:
		var xc: float = (float(b["x_min"]) + float(b["x_max"])) * 0.5
		var bdoor_id: String = "back_door_" + str(b["name"])
		var broom_id: String = "back_room_" + str(b["name"])
		# Door node sits just south of the back wall (into the corridor).
		nav.add_node(bdoor_id, Vector3(xc, 0.5, 6.5))
		# Room node inside the room.
		nav.add_node(broom_id, Vector3(xc, 0.5, 8.5))

	# ---- Bed nodes ----
	for i in range(bed_positions.size()):
		var bp: Vector3 = bed_positions[i]
		nav.add_node("bed_%d" % i, Vector3(bp.x, 0.5, bp.z - 1.6))

	# ============================================================
	# EDGES
	# ============================================================
	# Entrance → corridor (the entrance_inner node is inside the building,
	# between the south wall and the corridor's south edge).
	nav.link("entrance_out",   "entrance_in")
	nav.link("entrance_in",    "entrance_inner")
	nav.link("entrance_inner", "corridor_front_c")

	# Front corridor chain (east-west)
	nav.link("corridor_front_w",  "corridor_front_mw")
	nav.link("corridor_front_mw", "corridor_front_c")
	nav.link("corridor_front_c",  "corridor_front_me")
	nav.link("corridor_front_me", "corridor_front_e")
	nav.link("corridor_front_w",  "reception")

	# Front corridor ↔ mid connectors
	nav.link("corridor_front_w",  "corridor_mid_w")
	nav.link("corridor_front_c",  "corridor_mid_c")
	nav.link("corridor_front_e",  "corridor_mid_e")

	# Mid connectors chain (east-west)
	nav.link("corridor_mid_w", "corridor_mid_c")
	nav.link("corridor_mid_c", "corridor_mid_e")

	# Mid connectors ↔ back corridor
	nav.link("corridor_mid_w", "corridor_back_w")
	nav.link("corridor_mid_c", "corridor_back_c")
	nav.link("corridor_mid_e", "corridor_back_e")

	# Back corridor chain
	nav.link("corridor_back_w",  "corridor_back_mw")
	nav.link("corridor_back_mw", "corridor_back_c")
	nav.link("corridor_back_c",  "corridor_back_me")
	nav.link("corridor_back_me", "corridor_back_e")

	# Ward doors: connect to the nearest front-corridor node AND to the ward room
	for w in WARD_DEFS:
		var wdoor_id2: String = "door_" + str(w["name"])
		var wroom_id2: String = "room_" + str(w["name"])
		var wc: float = (float(w["x_min"]) + float(w["x_max"])) * 0.5

		# Find the nearest front-corridor node by x
		var nearest_corr := "corridor_front_c"
		var best_dx := 999.0
		for cid in ["corridor_front_w", "corridor_front_mw", "corridor_front_c",
					"corridor_front_me", "corridor_front_e"]:
			var cpos: Vector3 = nav.get_pos(cid)
			var dx: float = absf(cpos.x - wc)
			if dx < best_dx:
				best_dx = dx
				nearest_corr = cid

		nav.link(nearest_corr, wdoor_id2)
		nav.link(wdoor_id2, wroom_id2)

		# Ward room connects to its own beds
		for i in range(bed_positions.size()):
			if bed_wards[i] == str(w["name"]):
				nav.link(wroom_id2, "bed_%d" % i)

	# Back doors: connect to the nearest back-corridor node AND to the room
	for b in BACK_DEFS:
		var bdoor_id2: String = "back_door_" + str(b["name"])
		var broom_id2: String = "back_room_" + str(b["name"])
		var bc: float = (float(b["x_min"]) + float(b["x_max"])) * 0.5

		var nearest_back := "corridor_back_c"
		var best_dx2 := 999.0
		for cid in ["corridor_back_w", "corridor_back_mw", "corridor_back_c",
					"corridor_back_me", "corridor_back_e"]:
			var cpos2: Vector3 = nav.get_pos(cid)
			var dx2: float = absf(cpos2.x - bc)
			if dx2 < best_dx2:
				best_dx2 = dx2
				nearest_back = cid

		nav.link(nearest_back, bdoor_id2)
		nav.link(bdoor_id2, broom_id2)

func get_nav_path(from_pos: Vector3, to_pos: Vector3) -> Array:
	if nav == null:
		return []
	var start_id: String = nav.nearest_node_id(from_pos)
	var goal_id: String = nav.nearest_node_id(to_pos)
	return nav.find_path(start_id, goal_id)

func nav_pos(id: String) -> Vector3:
	if nav == null:
		return Vector3.ZERO
	return nav.get_pos(id)

# ============================================================
# COLLISION
# ============================================================
func _register_wall(rect: Rect2) -> void:
	wall_rects.append(rect)

func _wall_rect_from_center(size: Vector3, pos: Vector3) -> Rect2:
	return Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z)

func _register_door(rect: Rect2, mesh: MeshInstance3D) -> void:
	doors.append({ "rect": rect, "mesh": mesh, "open": true })

func _is_position_blocked(p: Vector3) -> bool:
	for r in wall_rects:
		if _point_in_expanded_rect(p.x, p.z, r, AGENT_RADIUS):
			return true
	for d in doors:
		if not d["open"]:
			var r: Rect2 = d["rect"]
			if _point_in_expanded_rect(p.x, p.z, r, AGENT_RADIUS):
				return true
	return false

func _point_in_expanded_rect(x: float, z: float, r: Rect2, pad: float) -> bool:
	var min_x := r.position.x - pad
	var max_x := r.position.x + r.size.x + pad
	var min_z := r.position.y - pad
	var max_z := r.position.y + r.size.y + pad
	return x >= min_x and x <= max_x and z >= min_z and z <= max_z

func is_walkable(p: Vector3) -> bool:
	return not _is_position_blocked(p)

# ============================================================
# GROUND & ROADS
# ============================================================
func _build_ground() -> void:
	_make_box(Vector3(300, 0.1, 300), Vector3(0, -0.05, 0),
		Color(0.28, 0.42, 0.25), "Ground")
	_make_box(Vector3(70, 0.12, 44), Vector3(0, 0.02, 0),
		Color(0.42, 0.43, 0.46), "Forecourt")

func _build_roads() -> void:
	_make_box(Vector3(10, 0.02, 60), Vector3(0, 0.14, -35),
		Color(0.16, 0.16, 0.18), "Driveway")
	_make_box(Vector3(80, 0.02, 8), Vector3(0, 0.14, -50),
		Color(0.16, 0.16, 0.18), "CrossStreet")
	for z in range(-65, -5, 6):
		_make_box(Vector3(0.3, 0.01, 2), Vector3(0, 0.16, z),
			Color(0.9, 0.85, 0.2), "RoadDash_%d" % z)

# ============================================================
# HOSPITAL SHELL
# ============================================================
func _build_hospital_shell() -> void:
	var W := BX_MAX - BX_MIN
	var D := BZ_MAX - BZ_MIN
	var cx := (BX_MIN + BX_MAX) * 0.5
	var cz := (BZ_MIN + BZ_MAX) * 0.5

	_make_box(Vector3(W + 0.4, 0.2, D + 0.4),
		Vector3(cx, 0.1, cz), Color(0.88, 0.9, 0.92), "HospitalFloor")

	hospital_roof = _make_box_transparent(
		Vector3(W + 0.8, 0.3, D + 0.8),
		Vector3(cx, WALL_H + 0.15, cz),
		Color(0.55, 0.57, 0.6), 0.25, "HospitalRoof")

	var s_z := BZ_MIN - WALL_T * 0.5
	_make_box(Vector3((-2.0) - BX_MIN, WALL_H, WALL_T),
		Vector3((BX_MIN + (-2.0)) * 0.5, WALL_H * 0.5, s_z),
		Color(0.92, 0.9, 0.86), "Wall_South_L")
	_register_wall(Rect2(BX_MIN, s_z - WALL_T * 0.5, (-2.0) - BX_MIN, WALL_T))

	_make_box(Vector3(BX_MAX - 2.0, WALL_H, WALL_T),
		Vector3((2.0 + BX_MAX) * 0.5, WALL_H * 0.5, s_z),
		Color(0.92, 0.9, 0.86), "Wall_South_R")
	_register_wall(Rect2(2.0, s_z - WALL_T * 0.5, BX_MAX - 2.0, WALL_T))

	_make_box(Vector3(4.0, WALL_H - 3.0, WALL_T),
		Vector3(0, 3.0 + (WALL_H - 3.0) * 0.5, s_z),
		Color(0.92, 0.9, 0.86), "Wall_South_Lintel")

	var n_z := BZ_MAX + WALL_T * 0.5
	_make_box(Vector3(W + WALL_T * 2, WALL_H, WALL_T),
		Vector3(cx, WALL_H * 0.5, n_z),
		Color(0.92, 0.9, 0.86), "Wall_North")
	_register_wall(Rect2(BX_MIN, BZ_MAX, W, WALL_T))

	var w_x := BX_MIN - WALL_T * 0.5
	_make_box(Vector3(WALL_T, WALL_H, D + WALL_T * 2),
		Vector3(w_x, WALL_H * 0.5, cz),
		Color(0.92, 0.9, 0.86), "Wall_West")
	_register_wall(Rect2(BX_MIN - WALL_T, BZ_MIN, WALL_T, D))

	var e_x := BX_MAX + WALL_T * 0.5
	_make_box(Vector3(WALL_T, WALL_H, D + WALL_T * 2),
		Vector3(e_x, WALL_H * 0.5, cz),
		Color(0.92, 0.9, 0.86), "Wall_East")
	_register_wall(Rect2(BX_MAX, BZ_MIN, WALL_T, D))

	for x in [-16.0, -10.0, 10.0, 16.0]:
		_build_window(Vector3(x, 3.5, s_z - WALL_T * 0.5 - 0.01), true)
	for x in [-14.0, -5.0, 5.0, 14.0]:
		_build_window(Vector3(x, 3.5, n_z + WALL_T * 0.5 + 0.01), true)
	for z in [-6.0, 0.0, 6.0]:
		_build_window(Vector3(w_x - WALL_T * 0.5 - 0.01, 3.5, z), false)
		_build_window(Vector3(e_x + WALL_T * 0.5 + 0.01, 3.5, z), false)

	entrance_left = _make_box(
		Vector3(1.9, 2.8, 0.1),
		Vector3(-ENTRANCE_CLOSED_X, 1.4, s_z + WALL_T * 0.5 - 0.02),
		Color(0.55, 0.78, 0.88), "EntranceDoor_L")
	entrance_right = _make_box(
		Vector3(1.9, 2.8, 0.1),
		Vector3( ENTRANCE_CLOSED_X, 1.4, s_z + WALL_T * 0.5 - 0.02),
		Color(0.55, 0.78, 0.88), "EntranceDoor_R")

func _build_window(pos: Vector3, horizontal: bool) -> void:
	var frame_col := Color(0.4, 0.4, 0.44)
	var glass_col := Color(0.55, 0.75, 0.88)
	var w := 2.4 if horizontal else 0.6
	var d := 0.6 if horizontal else 2.4
	_make_box(Vector3(w - 0.3, 1.8, d - 0.3), pos, glass_col, "WindowGlass")
	_make_box(Vector3(w, 0.1, d), pos + Vector3(0,  0.95, 0), frame_col, "WinTop")
	_make_box(Vector3(w, 0.1, d), pos + Vector3(0, -0.95, 0), frame_col, "WinBot")
	if horizontal:
		_make_box(Vector3(0.1, 2.0, d), pos + Vector3(-w * 0.5, 0, 0), frame_col, "WinL")
		_make_box(Vector3(0.1, 2.0, d), pos + Vector3( w * 0.5, 0, 0), frame_col, "WinR")
		_make_box(Vector3(0.06, 1.8, d - 0.3), pos, frame_col, "WinMullion")
	else:
		_make_box(Vector3(w, 2.0, 0.1), pos + Vector3(0, 0, -d * 0.5), frame_col, "WinL")
		_make_box(Vector3(w, 2.0, 0.1), pos + Vector3(0, 0,  d * 0.5), frame_col, "WinR")
		_make_box(Vector3(w - 0.3, 1.8, 0.06), pos, frame_col, "WinMullion")
	_make_box(Vector3(w + 0.3, 0.1, d + 0.3), pos + Vector3(0, -1.05, 0), frame_col, "WinSill")

# ============================================================
# FRONT ROW WALLS
# ============================================================
func _build_front_row_walls() -> void:
	var wall_col := Color(0.88, 0.88, 0.9)
	var zn := FRONT_CORRIDOR_Z + CORRIDOR_HALF_W

	for w in WARD_DEFS:
		var x_min: float = float(w["x_min"])
		var x_max: float = float(w["x_max"])
		var wc: float   = (x_min + x_max) * 0.5
		var door_min := wc - DOOR_W * 0.5
		var door_max := wc + DOOR_W * 0.5
		if door_min > x_min + 0.05:
			var len_l := door_min - x_min
			_make_box(Vector3(len_l, WALL_H, WALL_T),
				Vector3(x_min + len_l * 0.5, WALL_H * 0.5, zn),
				wall_col, "WardNorth_%s_L" % str(w["name"]))
			_register_wall(Rect2(x_min, zn - WALL_T * 0.5, len_l, WALL_T))
		if door_max < x_max - 0.05:
			var len_r := x_max - door_max
			_make_box(Vector3(len_r, WALL_H, WALL_T),
				Vector3(door_max + len_r * 0.5, WALL_H * 0.5, zn),
				wall_col, "WardNorth_%s_R" % str(w["name"]))
			_register_wall(Rect2(door_max, zn - WALL_T * 0.5, len_r, WALL_T))
		_build_swing_door(Vector3(wc - DOOR_W * 0.5, 1.15, zn), -45.0,
			"WardDoor_%s" % str(w["name"]))

	for i in range(WARD_DEFS.size() - 1):
		var x: float = float(WARD_DEFS[i]["x_max"])
		var zc: float = (BZ_MIN + zn) * 0.5
		var zd: float = zn - BZ_MIN
		_make_box(Vector3(WALL_T, WALL_H, zd),
			Vector3(x, WALL_H * 0.5, zc),
			wall_col, "WardDivider_%d" % i)
		_register_wall(Rect2(x - WALL_T * 0.5, BZ_MIN, WALL_T, zd))

# ============================================================
# BACK ROW WALLS
# ============================================================
func _build_back_row_walls() -> void:
	var wall_col := Color(0.88, 0.88, 0.9)
	var zs: float = BACK_CORRIDOR_Z - CORRIDOR_HALF_W

	for w in BACK_DEFS:
		var x_min: float = float(w["x_min"])
		var x_max: float = float(w["x_max"])
		var wc: float = (x_min + x_max) * 0.5
		var door_min := wc - DOOR_W * 0.5
		var door_max := wc + DOOR_W * 0.5
		if door_min > x_min + 0.05:
			var len_l := door_min - x_min
			_make_box(Vector3(len_l, WALL_H, WALL_T),
				Vector3(x_min + len_l * 0.5, WALL_H * 0.5, zs),
				wall_col, "BackSouth_%s_L" % str(w["name"]))
			_register_wall(Rect2(x_min, zs - WALL_T * 0.5, len_l, WALL_T))
		if door_max < x_max - 0.05:
			var len_r := x_max - door_max
			_make_box(Vector3(len_r, WALL_H, WALL_T),
				Vector3(door_max + len_r * 0.5, WALL_H * 0.5, zs),
				wall_col, "BackSouth_%s_R" % str(w["name"]))
			_register_wall(Rect2(door_max, zs - WALL_T * 0.5, len_r, WALL_T))
		_build_swing_door(Vector3(wc - DOOR_W * 0.5, 1.15, zs), 45.0,
			"BackDoor_%s" % str(w["name"]))

	for i in range(BACK_DEFS.size() - 1):
		var x: float = float(BACK_DEFS[i]["x_max"])
		var z_n: float = BZ_MAX
		var zc: float = (zs + z_n) * 0.5
		var zd: float = z_n - zs
		_make_box(Vector3(WALL_T, WALL_H, zd),
			Vector3(x, WALL_H * 0.5, zc),
			wall_col, "BackDivider_%d" % i)
		_register_wall(Rect2(x - WALL_T * 0.5, zs, WALL_T, zd))

func _build_swing_door(pos: Vector3, angle_deg: float, node_name: String) -> void:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = pos
	doors_root.add_child(pivot)

	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(DOOR_W - 0.1, 2.3, 0.08)
	panel.mesh = box
	panel.position = Vector3((DOOR_W - 0.1) * 0.5, 0, 0)
	panel.rotation.y = deg_to_rad(angle_deg)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.45, 0.3)
	m.roughness = 0.85
	panel.material_override = m
	pivot.add_child(panel)

	_register_door(Rect2(pos.x - DOOR_W, pos.z - 0.2, DOOR_W * 2, 0.4), panel)

# ============================================================
# RECEPTION
# ============================================================
func _build_reception() -> void:
	var cz := FRONT_CORRIDOR_Z + CORRIDOR_HALF_W - 0.6
	var wood := Color(0.42, 0.28, 0.15)
	var dark_wood := Color(0.25, 0.16, 0.08)

	_make_box(Vector3(5, 1.1, 1.0), Vector3(-8.5, 0.55, cz), wood, "ReceptionDesk")
	_make_box(Vector3(5.2, 0.1, 1.2), Vector3(-8.5, 1.15, cz), dark_wood, "ReceptionCounter")
	_make_box(Vector3(0.7, 0.55, 0.1), Vector3(-9.5, 1.55, cz - 0.2),
		Color(0.05, 0.05, 0.08), "Monitor")
	_make_box(Vector3(0.55, 0.4, 0.02), Vector3(-9.5, 1.55, cz - 0.26),
		Color(0.3, 0.5, 0.7), "MonitorScreen")
	_make_box(Vector3(0.25, 0.08, 0.2), Vector3(-7.5, 1.2, cz),
		Color(0.1, 0.1, 0.12), "DeskPhone")

func _build_waiting_area() -> void:
	var chair_col := Color(0.15, 0.4, 0.7)
	for row in range(2):
		for col in range(3):
			var px := -18.0 + col * 1.3
			var pz := -4.2 + row * 1.1
			_make_box(Vector3(0.9, 0.1, 0.9), Vector3(px, 0.5, pz), chair_col, "ChairSeat")
			_make_box(Vector3(0.9, 0.9, 0.1), Vector3(px, 0.85, pz - 0.4), chair_col, "ChairBack")
	_make_box(Vector3(0.5, 1.1, 0.5), Vector3(-3.5, 0.55, -4.4),
		Color(0.9, 0.9, 0.9), "WaterCooler")

# ============================================================
# BEDS
# ============================================================
func _build_beds() -> void:
	for i in range(bed_positions.size()):
		var bp: Vector3 = bed_positions[i]
		_make_box(Vector3(1.8, 0.4, 3.0), Vector3(bp.x, 0.8, bp.z),
			Color(0.35, 0.37, 0.4), "Bed%d_Frame" % i)
		_make_box(Vector3(1.7, 0.2, 2.8), Vector3(bp.x, 1.1, bp.z),
			Color(0.95, 0.96, 0.98), "Bed%d_Mattress" % i)
		_make_box(Vector3(1.0, 0.15, 0.5), Vector3(bp.x, 1.28, bp.z - 1.0),
			Color(1.0, 1.0, 1.0), "Bed%d_Pillow" % i)
		_make_box(Vector3(1.6, 0.08, 1.3), Vector3(bp.x, 1.2, bp.z + 0.6),
			Color(0.4, 0.55, 0.75), "Bed%d_Blanket" % i)
		_make_cylinder(0.04, 1.9, Vector3(bp.x - 1.1, 0.95, bp.z),
			Color(0.7, 0.7, 0.72), "Bed%d_IV" % i)
		_make_box(Vector3(0.28, 0.35, 0.08), Vector3(bp.x - 1.1, 2.05, bp.z),
			Color(0.9, 0.95, 0.9), "Bed%d_IVBag" % i)
		_make_box(Vector3(0.35, 0.1, 0.35), Vector3(bp.x + 1.1, 0.95, bp.z),
			Color(0.2, 0.2, 0.22), "Bed%d_MonStand" % i)
		_make_box(Vector3(0.5, 0.42, 0.25), Vector3(bp.x + 1.1, 1.25, bp.z),
			Color(0.1, 0.1, 0.12), "Bed%d_Monitor" % i)
		_make_box(Vector3(0.4, 0.3, 0.02), Vector3(bp.x + 1.1, 1.25, bp.z - 0.13),
			Color(0.2, 0.9, 0.3), "Bed%d_Screen" % i)

# ============================================================
# PHARMACY
# ============================================================
func _build_pharmacy() -> void:
	var bottle_colors: Array[Color] = [
		Color(0.9, 0.3, 0.3),
		Color(0.3, 0.5, 0.9),
		Color(0.3, 0.8, 0.4),
	]
	for i in range(3):
		var y := 1.0 + i * 1.1
		_make_box(Vector3(8.0, 0.1, 0.5), Vector3(-15.0, y, 9.2),
			Color(0.5, 0.4, 0.3), "PharmShelf_%d" % i)
		for b in range(5):
			var col: Color = bottle_colors.pick_random()
			_make_box(Vector3(0.22, 0.3, 0.22),
				Vector3(-18.0 + b * 1.5, y + 0.2, 9.2),
				col, "PharmBottle")
	_make_box(Vector3(1.0, 1.0, 4.0), Vector3(-19.0, 0.5, 7.5),
		Color(0.42, 0.3, 0.2), "PharmCounter")

# ============================================================
# SUPPLY DEPOT
# ============================================================
func _build_supply_depot() -> void:
	var crate_colors: Array[Color] = [
		Color(0.65, 0.45, 0.25),
		Color(0.55, 0.4, 0.2),
		Color(0.75, 0.55, 0.3),
	]
	for i in range(3):
		for j in range(2):
			_make_box(Vector3(1.3, 1.1, 1.3),
				Vector3(-9.0 + i * 1.5, 0.55 + j * 1.1, 7.0),
				crate_colors[i % 3], "Crate")
	_make_box(Vector3(8.0, 0.1, 0.7), Vector3(-5.0, 2.4, 9.2),
		Color(0.4, 0.42, 0.45), "DepotShelf")
	_make_box(Vector3(8.0, 0.1, 0.7), Vector3(-5.0, 1.2, 9.2),
		Color(0.4, 0.42, 0.45), "DepotShelf2")

# ============================================================
# STAFF ROOM
# ============================================================
func _build_staff_room() -> void:
	for i in range(6):
		_make_box(Vector3(0.55, 2.0, 0.4),
			Vector3(1.0 + i * 0.62, 1.0, 9.2),
			Color(0.35, 0.4, 0.5), "Locker")
	_make_box(Vector3(1.8, 0.1, 0.9), Vector3(5.5, 0.9, 7.5),
		Color(0.65, 0.55, 0.45), "BreakTable")
	for dx in [-0.8, 0.8]:
		_make_box(Vector3(0.45, 0.85, 0.45), Vector3(5.5 + dx, 0.42, 7.5),
			Color(0.25, 0.28, 0.35), "BreakChair")
	_make_box(Vector3(0.35, 0.4, 0.35), Vector3(5.0, 1.15, 7.5),
		Color(0.15, 0.15, 0.18), "CoffeeMachine")

# ============================================================
# HELIPAD
# ============================================================
func _build_helipad() -> void:
	var ry := WALL_H + 0.3
	_make_cylinder(4.0, 0.15, Vector3(0, ry, 0), Color(0.2, 0.2, 0.22), "Helipad")
	_make_cylinder(3.7, 0.16, Vector3(0, ry + 0.02, 0), Color(0.9, 0.8, 0.15), "Ring")
	_make_cylinder(3.4, 0.17, Vector3(0, ry + 0.03, 0), Color(0.2, 0.2, 0.22), "RingInner")
	_make_box(Vector3(0.4, 0.1, 2.4), Vector3(-0.8, ry + 0.08, 0), Color.WHITE, "H_L")
	_make_box(Vector3(0.4, 0.1, 2.4), Vector3( 0.8, ry + 0.08, 0), Color.WHITE, "H_R")
	_make_box(Vector3(1.6, 0.1, 0.4), Vector3( 0.0, ry + 0.08, 0), Color.WHITE, "H_C")

# ============================================================
# ENTRANCE CANOPY
# ============================================================
func _build_entrance_canopy() -> void:
	var s_z := BZ_MIN - WALL_T * 0.5
	_make_box(Vector3(0.3, 3.5, 0.3), Vector3(-3.5, 1.75, s_z - 1.5),
		Color(0.7, 0.7, 0.72), "Pillar_L")
	_make_box(Vector3(0.3, 3.5, 0.3), Vector3( 3.5, 1.75, s_z - 1.5),
		Color(0.7, 0.7, 0.72), "Pillar_R")
	_make_box(Vector3(9, 0.25, 3), Vector3(0, 3.6, s_z - 1.5),
		Color(0.6, 0.62, 0.65), "Canopy")
	_make_box(Vector3(6.0, 1.2, 0.15), Vector3(0, 5.0, s_z - 0.5),
		Color(0.1, 0.35, 0.6), "MainSign")
	_make_box(Vector3(5.4, 0.75, 0.02), Vector3(0, 5.0, s_z - 0.4),
		Color.WHITE, "MainSignFace")
	_make_box(Vector3(0.45, 0.7, 0.02), Vector3(-2.0, 5.0, s_z - 0.35),
		Color(0.9, 0.15, 0.15), "SignCrossV")
	_make_box(Vector3(1.1, 0.3, 0.02), Vector3(-2.0, 5.0, s_z - 0.35),
		Color(0.9, 0.15, 0.15), "SignCrossH")

# ============================================================
# SKYLINE
# ============================================================
func _build_skyline() -> void:
	for i in range(16):
		var side := -1.0 if i % 2 == 0 else 1.0
		var depth_z := float(i / 2) * 22.0 - 40.0
		var h := randi_range(18, 32)
		var w := randf_range(10, 16)
		var col := Color(0.3, 0.33, 0.38).lerp(Color(0.5, 0.55, 0.62), randf())
		_make_box(Vector3(w, h, w), Vector3(side * 55.0, h * 0.5, depth_z),
			col, "Skyline_%d" % i)

# ============================================================
# STREET PROPS
# ============================================================
func _build_street_props() -> void:
	for z in [-14, -26, -38, -50]:
		_make_cylinder(0.1, 5.0, Vector3(-7, 2.5, z),
			Color(0.25, 0.25, 0.28), "LampPole")
		_make_box(Vector3(1.2, 0.1, 0.1), Vector3(-6.4, 5.0, z),
			Color(0.25, 0.25, 0.28), "LampArm")
		_make_box(Vector3(0.5, 0.2, 0.3), Vector3(-5.9, 4.9, z),
			Color(1.0, 0.95, 0.7), "LampHead")
	

func _build_ambulance(pos: Vector3) -> void:
	var root := Node3D.new(); root.name = "ParkedAmbulance"; root.position = pos
	add_child(root)
	_make_box(Vector3(2.4, 2.4, 5.0), Vector3(0, 1.4, 0), Color(0.95, 0.95, 0.97), "Body")
	_make_box(Vector3(2.3, 1.8, 2.0), Vector3(0, 1.1, 3.3), Color(0.95, 0.95, 0.97), "Cab")
	_make_box(Vector3(2.0, 0.7, 0.1), Vector3(0, 1.5, 4.3), Color(0.4, 0.6, 0.75), "Shield")
	_make_box(Vector3(2.45, 0.35, 5.05), Vector3(0, 1.2, 0), Color(0.8, 0.15, 0.15), "Stripe")
	_make_box(Vector3(0.02, 0.9, 0.3), Vector3(1.22, 2.0, 0), Color(0.85, 0.1, 0.1), "CrossV")
	_make_box(Vector3(0.02, 0.3, 0.9), Vector3(1.22, 2.0, 0), Color(0.85, 0.1, 0.1), "CrossH")
	_make_box(Vector3(1.6, 0.25, 0.4), Vector3(0, 2.75, 3.0), Color(0.15, 0.15, 0.18), "Bar")
	_make_box(Vector3(0.5, 0.2, 0.35), Vector3(-0.5, 2.85, 3.0), Color(0.9, 0.1, 0.1), "Red")
	_make_box(Vector3(0.5, 0.2, 0.35), Vector3( 0.5, 2.85, 3.0), Color(0.1, 0.5, 0.9), "Blue")
	for wp in [Vector3(-1.25, 0.45, 2.4), Vector3(1.25, 0.45, 2.4),
			   Vector3(-1.25, 0.45, -1.8), Vector3(1.25, 0.45, -1.8)]:
		_make_cylinder(0.45, 0.3, wp, Color(0.05, 0.05, 0.05), "Wheel")

# ============================================================
# MESH HELPERS
# ============================================================
func _make_box(size: Vector3, pos: Vector3, col: Color, node_name: String = "Box") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new(); box.size = size
	mi.mesh = box; mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col; m.roughness = 0.85
	mi.material_override = m
	add_child(mi)
	return mi

func _make_box_transparent(size: Vector3, pos: Vector3, col: Color, alpha: float, node_name: String = "Box") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new(); box.size = size
	mi.mesh = box; mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	return mi

func _make_cylinder(radius: float, height: float, pos: Vector3, col: Color, node_name: String = "Cyl") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius; cyl.bottom_radius = radius; cyl.height = height
	mi.mesh = cyl; mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col; m.roughness = 0.85
	mi.material_override = m
	add_child(mi)
	return mi

# ============================================================
# HUD
# ============================================================
func _build_hud() -> void:
	var hud := CanvasLayer.new(); hud.name = "HUD"; add_child(hud)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.offset_left = 20; panel.offset_top = 20
	panel.offset_right = 540; panel.offset_bottom = 265
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.047, 0.055, 0.078, 0.88)
	ps.corner_radius_top_left = 10
	ps.corner_radius_top_right = 10
	ps.corner_radius_bottom_left = 10
	ps.corner_radius_bottom_right = 10
	ps.content_margin_left = 18; ps.content_margin_right = 18
	ps.content_margin_top = 14; ps.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", ps)
	hud.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var help := Label.new()
	help.text = "Right-drag: orbit  |  Wheel: zoom  |  WASD: pan  |  R: reset  |  Space: top-down  |  Tab: toggle roof"
	help.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	help.add_theme_font_size_override("font_size", 12)
	vbox.add_child(help)

	funds_label = Label.new()
	funds_label.text = "CAPITAL STATUS: $80000"
	funds_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	funds_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(funds_label)

	var supp_l := Label.new()
	supp_l.text = "SUPPLIES"
	supp_l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(supp_l)

	supplies_bar = ProgressBar.new()
	supplies_bar.custom_minimum_size = Vector2(480, 24)
	supplies_bar.show_percentage = false
	var sf := StyleBoxFlat.new()
	sf.bg_color = Color(1.0, 0.55, 0.1)
	sf.corner_radius_top_left = 4; sf.corner_radius_top_right = 4
	sf.corner_radius_bottom_left = 4; sf.corner_radius_bottom_right = 4
	supplies_bar.add_theme_stylebox_override("fill", sf)
	vbox.add_child(supplies_bar)

	var bed_l := Label.new()
	bed_l.text = "BED OCCUPANCY"
	bed_l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(bed_l)

	beds_bar = ProgressBar.new()
	beds_bar.custom_minimum_size = Vector2(480, 24)
	beds_bar.show_percentage = false
	var bf := StyleBoxFlat.new()
	bf.bg_color = Color(0.0, 0.9, 1.0)
	bf.corner_radius_top_left = 4; bf.corner_radius_top_right = 4
	bf.corner_radius_bottom_left = 4; bf.corner_radius_bottom_right = 4
	beds_bar.add_theme_stylebox_override("fill", bf)
	vbox.add_child(beds_bar)

	status_label = Label.new()
	status_label.text = "Shift: DAY  |  Staff: 0  |  Patients: 0"
	status_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	status_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status_label)

	var hbox := HBoxContainer.new()
	hbox.anchor_left = 0.5; hbox.anchor_top = 1.0
	hbox.anchor_right = 0.5; hbox.anchor_bottom = 1.0
	hbox.offset_left = -230; hbox.offset_top = -90
	hbox.offset_right = 230; hbox.offset_bottom = -25
	hbox.add_theme_constant_override("separation", 20)
	hud.add_child(hbox)

	order_button = Button.new()
	order_button.text = "ORDER SUPPLIES  ($3500)"
	order_button.custom_minimum_size = Vector2(220, 55)
	order_button.add_theme_font_size_override("font_size", 16)
	hbox.add_child(order_button)

	recruit_button = Button.new()
	recruit_button.text = "RECRUIT STAFF  ($5000)"
	recruit_button.custom_minimum_size = Vector2(220, 55)
	recruit_button.add_theme_font_size_override("font_size", 16)
	hbox.add_child(recruit_button)

# ============================================================
# SLIDING DOOR + ROOF TOGGLE
# ============================================================
func _update_entrance_door(delta: float) -> void:
	var someone_near := false
	for p in patients:
		if p is Node3D:
			var pn: Node3D = p
			if pn.position.distance_to(Vector3(0, 0, BZ_MIN)) < 4.0:
				someone_near = true
				break
	var target := 1.0 if someone_near else 0.0
	entrance_open_amount = lerpf(entrance_open_amount, target, delta * 5.0)
	if entrance_left != null:
		entrance_left.position.x = -ENTRANCE_CLOSED_X - entrance_open_amount * 1.4
	if entrance_right != null:
		entrance_right.position.x = ENTRANCE_CLOSED_X + entrance_open_amount * 1.4

func toggle_roof() -> void:
	if hospital_roof == null:
		return
	hospital_roof.visible = not hospital_roof.visible

# ============================================================
# ACTORS
# ============================================================
func _spawn_initial_staff() -> void:
	var roles: Array[int] = [HumanoidScript.Role.DOCTOR, HumanoidScript.Role.NURSE]
	for i in range(6):
		var role: int = roles.pick_random()
		_spawn_humanoid(role)

func _spawn_humanoid(role: int) -> Node3D:
	var node := Node3D.new()
	node.set_script(HumanoidScript)
	node.configure(role, self, [])
	actors_root.add_child(node)
	if role == HumanoidScript.Role.PATIENT:
		patients.append(node)
	else:
		staff.append(node)
	return node

# ============================================================
# PUBLIC API
# ============================================================
func request_bed() -> int:
	for i in range(bed_positions.size()):
		if not bed_occupied[i]:
			bed_occupied[i] = true
			occupied_beds += 1
			_update_hud()
			return i
	return -1

func get_bed_position(idx: int) -> Vector3:
	if idx < 0 or idx >= bed_positions.size():
		return Vector3.ZERO
	return bed_positions[idx]

func finish_patient_treatment(idx: int) -> void:
	if idx < 0 or idx >= bed_positions.size():
		return
	if supplies >= 8:
		supplies -= 8
		funds += 4500
	else:
		funds += 1500
	bed_occupied[idx] = false
	occupied_beds = max(0, occupied_beds - 1)
	_update_hud()

func unregister_patient(p: Node) -> void:
	patients.erase(p)

func deliver_supplies(amount: int) -> void:
	supplies = min(supplies + amount, MAX_SUPPLIES)
	truck = null
	_update_hud()

# ============================================================
# BUTTON CALLBACKS
# ============================================================
func _on_order_supplies() -> void:
	if funds < 3500 or truck != null:
		return
	funds -= 3500
	var t := Node3D.new()
	t.set_script(TruckScript)
	t.configure(self)
	add_child(t)
	truck = t
	_update_hud()

func _on_recruit_staff() -> void:
	if funds < 5000:
		return
	funds -= 5000
	var roles: Array[int] = [HumanoidScript.Role.DOCTOR, HumanoidScript.Role.NURSE]
	var role: int = roles.pick_random()
	_spawn_humanoid(role)
	_update_hud()

# ============================================================
# HUD UPDATE
# ============================================================
func _update_hud() -> void:
	funds_label.text = "CAPITAL STATUS: $%d" % funds
	supplies_bar.value = supplies
	beds_bar.value = occupied_beds
	status_label.text = "Staff: %d  |  Patients: %d  |  Beds: %d/%d" % [
		staff.size(), patients.size(), occupied_beds, bed_positions.size()
	]

# ============================================================
# PER FRAME
# ============================================================
func _process(delta: float) -> void:
	population_clock += delta
	if population_clock >= POPULATION_INTERVAL:
		population_clock = 0.0
		if patients.size() < MAX_PATIENTS:
			_spawn_humanoid(HumanoidScript.Role.PATIENT)
	_update_entrance_door(delta)
