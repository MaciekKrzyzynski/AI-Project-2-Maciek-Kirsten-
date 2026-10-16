extends Node3D

const HumanoidScript := preload("res://scripts/Humanoid.gd")
const TruckScript    := preload("res://scripts/Truck.gd")
const CameraControllerScript := preload("res://scripts/CameraController.gd")

var funds: int = 80000
var supplies: int = 150
const MAX_SUPPLIES: int = 400

const BX_MIN := -44.0
const BX_MAX :=  44.0
const BZ_MIN := -28.0
const BZ_MAX :=  28.0
const WALL_T := 0.4
const WALL_H := 6.0
const DOOR_W := 3.0

const ROOMS := [
	# --- SOUTH WING ---
	{ "name": "Reception",  "x_min": -22.0, "x_max":  -6.0, "z_min": -24.0, "z_max": -14.0, "kind": "reception" },
	{ "name": "Waiting",    "x_min":   6.0, "x_max":  22.0, "z_min": -24.0, "z_max": -14.0, "kind": "waiting" },
	{ "name": "Triage",     "x_min": -40.0, "x_max": -22.0, "z_min": -24.0, "z_max": -14.0, "kind": "triage" },
	{ "name": "Pharmacy",   "x_min":  22.0, "x_max":  40.0, "z_min": -24.0, "z_max": -14.0, "kind": "pharm" },
	{ "name": "ER",         "x_min": -22.0, "x_max":  -6.0, "z_min": -14.0, "z_max":  -8.0, "kind": "er" },
	{ "name": "Radiology",  "x_min":   6.0, "x_max":  22.0, "z_min": -14.0, "z_max":  -8.0, "kind": "imaging" },

	# --- WEST WING ---
	{ "name": "Ward_A",     "x_min": -40.0, "x_max": -24.0, "z_min":  -8.0, "z_max":   4.0, "kind": "ward" },
	{ "name": "Ward_B",     "x_min": -40.0, "x_max": -24.0, "z_min":   4.0, "z_max":  16.0, "kind": "ward" },
	{ "name": "Storage",    "x_min": -24.0, "x_max": -14.0, "z_min":   2.0, "z_max":  10.0, "kind": "storage" },
	{ "name": "Staff",      "x_min": -24.0, "x_max": -14.0, "z_min":  10.0, "z_max":  18.0, "kind": "staff" },

	# --- EAST WING ---
	{ "name": "Ward_C",     "x_min":  24.0, "x_max":  40.0, "z_min":  -8.0, "z_max":   4.0, "kind": "ward" },
	{ "name": "Ward_D",     "x_min":  24.0, "x_max":  40.0, "z_min":   4.0, "z_max":  16.0, "kind": "ward" },
	{ "name": "Depot",      "x_min":  14.0, "x_max":  24.0, "z_min":   2.0, "z_max":  10.0, "kind": "depot" },
	{ "name": "Cafeteria",  "x_min":  14.0, "x_max":  24.0, "z_min":  10.0, "z_max":  18.0, "kind": "cafe" },

	# --- NORTH WING ---
	{ "name": "ICU",        "x_min": -14.0, "x_max":   0.0, "z_min":  18.0, "z_max":  28.0, "kind": "icu" },
	{ "name": "Surgery",    "x_min":   0.0, "x_max":  14.0, "z_min":  18.0, "z_max":  28.0, "kind": "surgery" },
	{ "name": "Recovery",   "x_min": -30.0, "x_max": -14.0, "z_min":  18.0, "z_max":  28.0, "kind": "ward" },
	{ "name": "Oncology",   "x_min":  14.0, "x_max":  30.0, "z_min":  18.0, "z_max":  28.0, "kind": "ward" },
]

const CORRIDORS := [
	{ "x_min": -3.0, "x_max": 3.0, "z_min": -28.0, "z_max": -14.0, "name": "entry" },
	{ "x_min": -40.0, "x_max": 40.0, "z_min": -13.0, "z_max": -9.0, "name": "main_w" },
	{ "x_min": -3.0, "x_max": 3.0, "z_min":  -9.0, "z_max": 14.0, "name": "spine" },
	{ "x_min": -30.0, "x_max": 30.0, "z_min": 12.0, "z_max": 16.0, "name": "loop" },
	{ "x_min": -24.0, "x_max": -14.0, "z_min":  0.0, "z_max":  2.0, "name": "west_stub" },
	{ "x_min":  14.0, "x_max":  24.0, "z_min":  0.0, "z_max":  2.0, "name": "east_stub" },
]

var bed_positions: Array[Vector3] = []
var bed_wards: Array[String] = []
var bed_occupied: Array[bool] = []
var occupied_beds: int = 0

var nav: RefCounted = null
var wall_rects: Array[Rect2] = []

var entrance_left: MeshInstance3D
var entrance_right: MeshInstance3D
var entrance_open_amount: float = 0.0
const ENTRANCE_CLOSED_X := 1.2

var patients: Array = []
var staff: Array = []
var truck: Node3D = null

var population_clock: float = 0.0
const POPULATION_INTERVAL := 3.5
const MAX_PATIENTS := 10

var actors_root: Node3D
var buildings_root: Node3D
var props_root: Node3D
var camera: Camera3D
var hospital_roof: MeshInstance3D
var funds_label: Label
var supplies_bar: ProgressBar
var beds_bar: ProgressBar
var order_button: Button
var recruit_button: Button
var status_label: Label

func _ready() -> void:
	for room in ROOMS:
		var kind := str(room["kind"])
		if kind == "ward" or kind == "icu":
			var x_min: float = float(room["x_min"])
			var x_max: float = float(room["x_max"])
			var z_min: float = float(room["z_min"])
			var z_max: float = float(room["z_max"])
			var cx: float = (x_min + x_max) * 0.5
			var cz: float = (z_min + z_max) * 0.5
			bed_positions.append(Vector3(cx - 2.5, 1.2, cz))
			bed_wards.append(str(room["name"]))
			bed_positions.append(Vector3(cx + 2.5, 1.2, cz))
			bed_wards.append(str(room["name"]))
	bed_occupied.resize(bed_positions.size())
	for i in range(bed_occupied.size()):
		bed_occupied[i] = false

	_build_nav_graph()
	_build_scene()
	_build_skyline()
	_spawn_initial_staff()

	supplies_bar.max_value = MAX_SUPPLIES
	supplies_bar.value = supplies
	beds_bar.max_value = bed_positions.size()
	beds_bar.value = occupied_beds

	order_button.pressed.connect(_on_order_supplies)
	recruit_button.pressed.connect(_on_recruit_staff)

	_update_hud()

func _build_scene() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_camera()

	props_root    = Node3D.new(); props_root.name    = "Props";    add_child(props_root)
	actors_root   = Node3D.new(); actors_root.name   = "Actors";   add_child(actors_root)
	buildings_root = Node3D.new(); buildings_root.name = "Buildings"; add_child(buildings_root)

	_build_ground()
	_build_roads()
	_build_hospital_shell()
	_build_room_walls()
	_build_reception()
	_build_beds()
	_build_room_props()
	_build_entrance_canopy()
	_build_hud()

func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.53, 0.65, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.76)
	e.ambient_light_energy = 0.95
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 140, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.shadow_enabled = false
	add_child(fill)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 70, -110)
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

	nav.add_node("entrance_out",  Vector3(  0.0, 0.5, -34.0))
	nav.add_node("entrance_in",   Vector3(  0.0, 0.5, -28.5))
	nav.add_node("entry_hall",    Vector3(  0.0, 0.5, -20.0))

	nav.add_node("corr_mw_w",  Vector3(-32.0, 0.5, -11.0))
	nav.add_node("corr_mw_cw", Vector3(-16.0, 0.5, -11.0))
	nav.add_node("corr_mw_c",  Vector3(  0.0, 0.5, -11.0))
	nav.add_node("corr_mw_ce", Vector3( 16.0, 0.5, -11.0))
	nav.add_node("corr_mw_e",  Vector3( 32.0, 0.5, -11.0))

	nav.add_node("corr_sp_1", Vector3(0.0, 0.5,  -4.0))
	nav.add_node("corr_sp_2", Vector3(0.0, 0.5,   3.0))
	nav.add_node("corr_sp_3", Vector3(0.0, 0.5,  10.0))

	nav.add_node("corr_loop_w",  Vector3(-24.0, 0.5, 14.0))
	nav.add_node("corr_loop_cw", Vector3(-10.0, 0.5, 14.0))
	nav.add_node("corr_loop_c",  Vector3(  0.0, 0.5, 14.0))
	nav.add_node("corr_loop_ce", Vector3( 10.0, 0.5, 14.0))
	nav.add_node("corr_loop_e",  Vector3( 24.0, 0.5, 14.0))

	nav.add_node("corr_ws", Vector3(-19.0, 0.5, 1.0))
	nav.add_node("corr_es", Vector3( 19.0, 0.5, 1.0))

	for room in ROOMS:
		var x_min: float = float(room["x_min"])
		var x_max: float = float(room["x_max"])
		var z_min: float = float(room["z_min"])
		var z_max: float = float(room["z_max"])
		var name: String = str(room["name"])
		var cx: float = (x_min + x_max) * 0.5
		var cz: float = (z_min + z_max) * 0.5
		var door_pos := _nearest_corridor_edge(Vector3(cx, 0.5, cz), room)
		nav.add_node("door_" + name, door_pos)
		nav.add_node("room_" + name, Vector3(cx, 0.5, cz))

	for i in range(bed_positions.size()):
		var bp: Vector3 = bed_positions[i]
		nav.add_node("bed_%d" % i, Vector3(bp.x, 0.5, bp.z + 1.6))

	nav.link("entrance_out", "entrance_in")
	nav.link("entrance_in",  "entry_hall")
	nav.link("entry_hall",   "corr_mw_c")

	nav.link("corr_mw_w",  "corr_mw_cw")
	nav.link("corr_mw_cw", "corr_mw_c")
	nav.link("corr_mw_c",  "corr_mw_ce")
	nav.link("corr_mw_ce", "corr_mw_e")

	nav.link("corr_mw_c", "corr_sp_1")
	nav.link("corr_sp_1", "corr_sp_2")
	nav.link("corr_sp_2", "corr_sp_3")
	nav.link("corr_sp_3", "corr_loop_c")

	nav.link("corr_loop_w",  "corr_loop_cw")
	nav.link("corr_loop_cw", "corr_loop_c")
	nav.link("corr_loop_c",  "corr_loop_ce")
	nav.link("corr_loop_ce", "corr_loop_e")

	nav.link("corr_mw_cw", "corr_ws")
	nav.link("corr_ws",    "corr_sp_2")
	nav.link("corr_mw_ce", "corr_es")
	nav.link("corr_es",    "corr_sp_2")

	for room in ROOMS:
		var name: String = str(room["name"])
		var door_id := "door_" + name
		var door_pos: Vector3 = nav.get_pos(door_id)

		var nearest := "corr_mw_c"
		var best := 99999.0
		for cid in ["corr_mw_w","corr_mw_cw","corr_mw_c","corr_mw_ce","corr_mw_e",
					"corr_sp_1","corr_sp_2","corr_sp_3",
					"corr_loop_w","corr_loop_cw","corr_loop_c","corr_loop_ce","corr_loop_e",
					"corr_ws","corr_es","entry_hall"]:
			var cpos: Vector3 = nav.get_pos(cid)
			var d: float = cpos.distance_to(door_pos)
			if d < best:
				best = d
				nearest = cid
		nav.link(nearest, door_id)
		nav.link(door_id, "room_" + name)

	for i in range(bed_positions.size()):
		nav.link("room_" + bed_wards[i], "bed_%d" % i)

func _nearest_corridor_edge(_ref: Vector3, room: Dictionary) -> Vector3:
	var x_min: float = float(room["x_min"])
	var x_max: float = float(room["x_max"])
	var z_min: float = float(room["z_min"])
	var z_max: float = float(room["z_max"])
	var cx: float = (x_min + x_max) * 0.5
	var cz: float = (z_min + z_max) * 0.5

	var candidates: Array = [
		{ "pos": Vector3(cx, 0.5, z_min - 0.2) },
		{ "pos": Vector3(cx, 0.5, z_max + 0.2) },
		{ "pos": Vector3(x_min - 0.2, 0.5, cz) },
		{ "pos": Vector3(x_max + 0.2, 0.5, cz) },
	]

	var best_pos: Vector3 = candidates[0]["pos"]
	var best_dist := 99999.0
	for c in candidates:
		var cpos: Vector3 = c["pos"]
		var d := _distance_to_any_corridor(cpos)
		if d < best_dist:
			best_dist = d
			best_pos = cpos
	return best_pos

func _distance_to_any_corridor(p: Vector3) -> float:
	var pts := [
		Vector3(  0.0, 0.5, -20.0),
		Vector3(-32.0, 0.5, -11.0), Vector3(0.0, 0.5, -11.0), Vector3(32.0, 0.5, -11.0),
		Vector3(  0.0, 0.5,  -4.0), Vector3(0.0, 0.5,   3.0), Vector3(0.0, 0.5, 10.0),
		Vector3(-24.0, 0.5, 14.0), Vector3(0.0, 0.5, 14.0), Vector3(24.0, 0.5, 14.0),
		Vector3(-19.0, 0.5, 1.0), Vector3(19.0, 0.5, 1.0),
	]
	var best := 99999.0
	for v in pts:
		var d := p.distance_to(v)
		if d < best:
			best = d
	return best

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

func _point_in_rect(x: float, z: float, r: Rect2) -> bool:
	return x >= r.position.x and x <= r.position.x + r.size.x \
	   and z >= r.position.y and z <= r.position.y + r.size.y

func is_walkable(p: Vector3) -> bool:
	for r in wall_rects:
		if _point_in_rect(p.x, p.z, r):
			return false
	return true

# ============================================================
# GROUND & ROADS
# ============================================================
func _build_ground() -> void:
	_make_box(Vector3(600, 0.1, 600), Vector3(0, -0.05, 0),
		Color(0.28, 0.42, 0.25), "Ground")
	_make_box(Vector3(150, 0.12, 100), Vector3(0, 0.02, 0),
		Color(0.42, 0.43, 0.46), "Forecourt")

func _build_roads() -> void:
	_make_box(Vector3(12, 0.02, 80), Vector3(0, 0.14, -70),
		Color(0.16, 0.16, 0.18), "Driveway")
	_make_box(Vector3(150, 0.02, 8), Vector3(0, 0.14, -90),
		Color(0.16, 0.16, 0.18), "CrossStreet")

# ============================================================
# HOSPITAL SHELL
# ============================================================
func _build_hospital_shell() -> void:
	var W := BX_MAX - BX_MIN
	var D := BZ_MAX - BZ_MIN

	_make_box(Vector3(W + 0.4, 0.2, D + 0.4),
		Vector3(0, 0.1, 0), Color(0.9, 0.92, 0.94), "HospitalFloor")

	hospital_roof = _make_box_transparent(
		Vector3(W + 0.8, 0.3, D + 0.8),
		Vector3(0, WALL_H + 0.15, 0),
		Color(0.55, 0.57, 0.6), 0.22, "HospitalRoof")

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
		Vector3(0, WALL_H * 0.5, n_z), Color(0.92, 0.9, 0.86), "Wall_North")
	_register_wall(Rect2(BX_MIN, BZ_MAX, W, WALL_T))

	var w_x := BX_MIN - WALL_T * 0.5
	_make_box(Vector3(WALL_T, WALL_H, D + WALL_T * 2),
		Vector3(w_x, WALL_H * 0.5, 0), Color(0.92, 0.9, 0.86), "Wall_West")
	_register_wall(Rect2(BX_MIN - WALL_T, BZ_MIN, WALL_T, D))

	var e_x := BX_MAX + WALL_T * 0.5
	_make_box(Vector3(WALL_T, WALL_H, D + WALL_T * 2),
		Vector3(e_x, WALL_H * 0.5, 0), Color(0.92, 0.9, 0.86), "Wall_East")
	_register_wall(Rect2(BX_MAX, BZ_MIN, WALL_T, D))

	for x in [-36.0, -20.0, 20.0, 36.0]:
		_build_window(Vector3(x, 3.5, s_z - WALL_T * 0.5 - 0.01), true)
	for x in [-36.0, -20.0, 0.0, 20.0, 36.0]:
		_build_window(Vector3(x, 3.5, n_z + WALL_T * 0.5 + 0.01), true)
	for z in [-20.0, -8.0, 4.0, 16.0]:
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
	var w := 2.6 if horizontal else 0.6
	var d := 0.6 if horizontal else 2.6
	_make_box(Vector3(w - 0.3, 1.8, d - 0.3), pos, glass_col, "WindowGlass")
	_make_box(Vector3(w, 0.1, d), pos + Vector3(0,  0.95, 0), frame_col, "WinTop")
	_make_box(Vector3(w, 0.1, d), pos + Vector3(0, -0.95, 0), frame_col, "WinBot")
	if horizontal:
		_make_box(Vector3(0.1, 2.0, d), pos + Vector3(-w * 0.5, 0, 0), frame_col, "WinL")
		_make_box(Vector3(0.1, 2.0, d), pos + Vector3( w * 0.5, 0, 0), frame_col, "WinR")
	else:
		_make_box(Vector3(w, 2.0, 0.1), pos + Vector3(0, 0, -d * 0.5), frame_col, "WinL")
		_make_box(Vector3(w, 2.0, 0.1), pos + Vector3(0, 0,  d * 0.5), frame_col, "WinR")

# ============================================================
# ROOM WALLS
# ============================================================
func _build_room_walls() -> void:
	var wall_col := Color(0.88, 0.88, 0.9)

	for room in ROOMS:
		var x_min: float = float(room["x_min"])
		var x_max: float = float(room["x_max"])
		var z_min: float = float(room["z_min"])
		var z_max: float = float(room["z_max"])
		var name: String = str(room["name"])
		var door_pos: Vector3 = nav.get_pos("door_" + name)

		var door_on_s := absf(door_pos.z - (z_min - 0.2)) < 0.5
		var door_on_n := absf(door_pos.z - (z_max + 0.2)) < 0.5
		var door_on_w := absf(door_pos.x - (x_min - 0.2)) < 0.5
		var door_on_e := absf(door_pos.x - (x_max + 0.2)) < 0.5

		_build_hwall_with_optional_door(x_min, x_max, z_min, door_on_s, door_pos.x, wall_col, name + "_S")
		_build_hwall_with_optional_door(x_min, x_max, z_max, door_on_n, door_pos.x, wall_col, name + "_N")
		_build_vwall_with_optional_door(z_min, z_max, x_min, door_on_w, door_pos.z, wall_col, name + "_W")
		_build_vwall_with_optional_door(z_min, z_max, x_max, door_on_e, door_pos.z, wall_col, name + "_E")

func _build_hwall_with_optional_door(x_min: float, x_max: float, z: float,
		has_door: bool, door_x: float, col: Color, tag: String) -> void:
	var length := x_max - x_min
	if length <= 0.05:
		return
	if not has_door:
		_make_box(Vector3(length, WALL_H, WALL_T),
			Vector3((x_min + x_max) * 0.5, WALL_H * 0.5, z), col, tag)
		_register_wall(Rect2(x_min, z - WALL_T * 0.5, length, WALL_T))
		return

	var door_l := door_x - DOOR_W * 0.5
	var door_r := door_x + DOOR_W * 0.5
	if door_l > x_min + 0.05:
		var len1 := door_l - x_min
		_make_box(Vector3(len1, WALL_H, WALL_T),
			Vector3(x_min + len1 * 0.5, WALL_H * 0.5, z), col, tag + "_L")
		_register_wall(Rect2(x_min, z - WALL_T * 0.5, len1, WALL_T))
	if door_r < x_max - 0.05:
		var len2 := x_max - door_r
		_make_box(Vector3(len2, WALL_H, WALL_T),
			Vector3(door_r + len2 * 0.5, WALL_H * 0.5, z), col, tag + "_R")
		_register_wall(Rect2(door_r, z - WALL_T * 0.5, len2, WALL_T))
	_make_box(Vector3(DOOR_W, WALL_H - 2.4, WALL_T),
		Vector3(door_x, 2.4 + (WALL_H - 2.4) * 0.5, z), col, tag + "_Lintel")

func _build_vwall_with_optional_door(z_min: float, z_max: float, x: float,
		has_door: bool, door_z: float, col: Color, tag: String) -> void:
	var length := z_max - z_min
	if length <= 0.05:
		return
	if not has_door:
		_make_box(Vector3(WALL_T, WALL_H, length),
			Vector3(x, WALL_H * 0.5, (z_min + z_max) * 0.5), col, tag)
		_register_wall(Rect2(x - WALL_T * 0.5, z_min, WALL_T, length))
		return

	var door_l := door_z - DOOR_W * 0.5
	var door_r := door_z + DOOR_W * 0.5
	if door_l > z_min + 0.05:
		var len1 := door_l - z_min
		_make_box(Vector3(WALL_T, WALL_H, len1),
			Vector3(x, WALL_H * 0.5, z_min + len1 * 0.5), col, tag + "_S")
		_register_wall(Rect2(x - WALL_T * 0.5, z_min, WALL_T, len1))
	if door_r < z_max - 0.05:
		var len2 := z_max - door_r
		_make_box(Vector3(WALL_T, WALL_H, len2),
			Vector3(x, WALL_H * 0.5, door_r + len2 * 0.5), col, tag + "_N")
		_register_wall(Rect2(x - WALL_T * 0.5, door_r, WALL_T, len2))
	_make_box(Vector3(WALL_T, WALL_H - 2.4, DOOR_W),
		Vector3(x, 2.4 + (WALL_H - 2.4) * 0.5, door_z), col, tag + "_Lintel")

# ============================================================
# RECEPTION
# ============================================================
func _build_reception() -> void:
	var wood := Color(0.42, 0.28, 0.15)
	var dark_wood := Color(0.25, 0.16, 0.08)
	_make_box(Vector3(5, 1.1, 1.0), Vector3(-3.0, 0.55, -20.0), wood, "ReceptionDesk")
	_make_box(Vector3(5.2, 0.1, 1.2), Vector3(-3.0, 1.15, -20.0), dark_wood, "ReceptionCounter")
	_make_box(Vector3(0.7, 0.55, 0.1), Vector3(-4.0, 1.55, -20.2),
		Color(0.05, 0.05, 0.08), "Monitor")

	var chair_col := Color(0.15, 0.4, 0.7)
	for row in range(3):
		for col in range(3):
			var px := 4.0 + col * 1.4
			var pz := -22.0 + row * 1.4
			_make_box(Vector3(1.0, 0.1, 1.0), Vector3(px, 0.5, pz), chair_col, "ChairSeat")
			_make_box(Vector3(0.1, 0.9, 1.0), Vector3(px + 0.45, 0.85, pz), chair_col, "ChairBack")

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

# ============================================================
# ROOM PROPS
# ============================================================
func _build_room_props() -> void:
	for room in ROOMS:
		var kind: String = str(room["kind"])
		var x_min: float = float(room["x_min"])
		var x_max: float = float(room["x_max"])
		var z_min: float = float(room["z_min"])
		var z_max: float = float(room["z_max"])
		var cx: float = (x_min + x_max) * 0.5
		var cz: float = (z_min + z_max) * 0.5
		var name: String = str(room["name"])

		match kind:
			"pharm":
				for i in range(3):
					var y := 1.0 + i * 1.1
					_make_box(Vector3(0.5, 0.1, 6.0), Vector3(x_max - 0.5, y, cz),
						Color(0.5, 0.4, 0.3), "Shelf_%s_%d" % [name, i])
					for b in range(4):
						_make_box(Vector3(0.25, 0.3, 0.25),
							Vector3(x_max - 0.5, y + 0.2, cz - 2.0 + b * 1.3),
							[Color(0.9,0.3,0.3), Color(0.3,0.5,0.9), Color(0.3,0.8,0.4)][b % 3],
							"Bottle")
			"imaging":
				_make_cylinder(1.8, 0.6, Vector3(cx, 1.0, cz - 0.5), Color(0.9,0.9,0.92), "CT_Ring_L")
				_make_cylinder(1.8, 0.6, Vector3(cx, 1.0, cz + 0.5), Color(0.9,0.9,0.92), "CT_Ring_R")
				_make_box(Vector3(3.0, 0.5, 4.0), Vector3(cx, 0.5, cz), Color(0.5,0.55,0.6), "CT_Table")
			"storage", "depot":
				for i in range(3):
					for j in range(2):
						_make_box(Vector3(1.3, 1.1, 1.3),
							Vector3(x_min + 2.0 + i * 1.5, 0.55 + j * 1.1, cz),
							Color(0.65, 0.45, 0.25), "Crate")
			"staff":
				for i in range(4):
					_make_box(Vector3(0.55, 2.0, 0.4),
						Vector3(x_min + 1.0, 1.0, cz - 3.0 + i * 1.0),
						Color(0.35, 0.4, 0.5), "Locker")
				_make_box(Vector3(2.0, 0.1, 1.0), Vector3(cx + 2.0, 0.9, cz + 1.0),
					Color(0.65, 0.55, 0.45), "BreakTable")
			"icu":
				for i in range(2):
					var bx := cx - 2.5 + i * 5.0
					_make_box(Vector3(0.5, 1.8, 0.5), Vector3(bx - 1.5, 0.9, cz + 2.0),
						Color(0.15, 0.15, 0.2), "Vent")
			"surgery":
				_make_box(Vector3(2.0, 0.9, 4.0), Vector3(cx, 0.45, cz),
					Color(0.5, 0.55, 0.6), "OR_Table")
				_make_box(Vector3(1.9, 0.15, 3.9), Vector3(cx, 0.95, cz),
					Color(0.85, 0.88, 0.92), "OR_Pad")
				_make_cylinder(0.08, 1.4, Vector3(cx, 3.4, cz), Color(0.4,0.4,0.45), "OR_LightArm")
				_make_cylinder(0.5, 0.15, Vector3(cx, 2.7, cz), Color(0.15,0.15,0.18), "OR_Light")
			"cafe":
				for i in range(3):
					var tx := cx - 4.0 + i * 4.0
					_make_box(Vector3(1.5, 0.1, 1.5), Vector3(tx, 0.85, cz),
						Color(0.7, 0.6, 0.5), "CafeTable")
					_make_cylinder(0.1, 0.85, Vector3(tx, 0.42, cz),
						Color(0.4,0.4,0.45), "CafeLeg")
			"er":
				for i in range(3):
					var bx := cx - 4.0 + i * 4.0
					_make_box(Vector3(1.8, 0.4, 3.0), Vector3(bx, 0.8, cz),
						Color(0.35, 0.37, 0.4), "ER_Bed%d" % i)
					_make_box(Vector3(1.7, 0.2, 2.8), Vector3(bx, 1.1, cz),
						Color(0.95, 0.96, 0.98), "ER_Pad%d" % i)
			"triage":
				_make_box(Vector3(6.0, 0.1, 2.0), Vector3(cx, 0.9, cz),
					Color(0.5, 0.55, 0.6), "TriageDesk")
			"reception":
				_make_box(Vector3(6.0, 0.1, 2.0), Vector3(cx, 0.9, cz),
					Color(0.45, 0.3, 0.15), "RecDesk")
			"waiting":
				for r in range(3):
					for c in range(3):
						_make_box(Vector3(1.0, 0.1, 1.0),
							Vector3(cx - 2.0 + c * 1.4, 0.5, cz - 2.0 + r * 1.4),
							Color(0.15, 0.4, 0.7), "WChair")

func _build_entrance_canopy() -> void:
	var s_z := BZ_MIN - WALL_T * 0.5
	_make_box(Vector3(0.3, 3.5, 0.3), Vector3(-3.5, 1.75, s_z - 2.0),
		Color(0.7, 0.7, 0.72), "Pillar_L")
	_make_box(Vector3(0.3, 3.5, 0.3), Vector3( 3.5, 1.75, s_z - 2.0),
		Color(0.7, 0.7, 0.72), "Pillar_R")
	_make_box(Vector3(9, 0.25, 4), Vector3(0, 3.6, s_z - 2.0),
		Color(0.6, 0.62, 0.65), "Canopy")
	_make_box(Vector3(8.0, 1.2, 0.15), Vector3(0, 5.0, s_z - 0.5),
		Color(0.1, 0.35, 0.6), "MainSign")

# ============================================================
# SKYLINE
# ============================================================
func _build_skyline() -> void:
	for i in range(20):
		var side := -1.0 if i % 2 == 0 else 1.0
		var depth_z := float(i / 2) * 28.0 - 80.0
		var h := randi_range(18, 40)
		var w := randf_range(12, 20)
		var col := Color(0.3, 0.33, 0.38).lerp(Color(0.5, 0.55, 0.62), randf())
		_make_box(Vector3(w, h, w), Vector3(side * 100.0, h * 0.5, depth_z),
			col, "Skyline_%d" % i)

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
	panel.offset_right = 560; panel.offset_bottom = 200
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
	help.text = "Right-drag: orbit  |  Wheel: zoom  |  WASD: pan  |  R: reset  |  Tab: toggle roof"
	help.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	help.add_theme_font_size_override("font_size", 12)
	vbox.add_child(help)

	funds_label = Label.new()
	funds_label.text = "CAPITAL STATUS: $80000"
	funds_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	funds_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(funds_label)

	var supp_l := Label.new(); supp_l.text = "SUPPLIES"; vbox.add_child(supp_l)
	supplies_bar = ProgressBar.new()
	supplies_bar.custom_minimum_size = Vector2(500, 22)
	supplies_bar.show_percentage = false
	vbox.add_child(supplies_bar)

	var bed_l := Label.new(); bed_l.text = "BED OCCUPANCY"; vbox.add_child(bed_l)
	beds_bar = ProgressBar.new()
	beds_bar.custom_minimum_size = Vector2(500, 22)
	beds_bar.show_percentage = false
	vbox.add_child(beds_bar)

	status_label = Label.new(); status_label.text = "Shift: DAY"; vbox.add_child(status_label)

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
	hbox.add_child(order_button)

	recruit_button = Button.new()
	recruit_button.text = "RECRUIT STAFF  ($5000)"
	recruit_button.custom_minimum_size = Vector2(220, 55)
	hbox.add_child(recruit_button)

func _update_entrance_door(delta: float) -> void:
	var someone_near := false
	for p in patients:
		if p is Node3D:
			var pn: Node3D = p
			if pn.position.distance_to(Vector3(0, 0, BZ_MIN)) < 5.0:
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
	node.configure(role, self)
	actors_root.add_child(node)
	if role == HumanoidScript.Role.PATIENT:
		patients.append(node)
	else:
		staff.append(node)
	return node

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

func deliver_supplies(amount: int) -> void:
	supplies = min(supplies + amount, MAX_SUPPLIES)
	truck = null
	_update_hud()

func _on_recruit_staff() -> void:
	if funds < 5000:
		return
	funds -= 5000
	var roles: Array[int] = [HumanoidScript.Role.DOCTOR, HumanoidScript.Role.NURSE]
	var role: int = roles.pick_random()
	_spawn_humanoid(role)
	_update_hud()

func _update_hud() -> void:
	funds_label.text = "CAPITAL STATUS: $%d" % funds
	supplies_bar.value = supplies
	beds_bar.value = occupied_beds
	status_label.text = "Staff: %d  |  Patients: %d  |  Beds: %d/%d" % [
		staff.size(), patients.size(), occupied_beds, bed_positions.size()
	]

func _process(delta: float) -> void:
	population_clock += delta
	if population_clock >= POPULATION_INTERVAL:
		population_clock = 0.0
		if patients.size() < MAX_PATIENTS:
			_spawn_humanoid(HumanoidScript.Role.PATIENT)
	_update_entrance_door(delta)
