extends Node3D

const HumanoidScript := preload("res://scripts/Humanoid.gd")
const TruckScript    := preload("res://scripts/Truck.gd")
const CameraControllerScript := preload("res://scripts/CameraController.gd")

var funds: int = 80000
const MAX_SUPPLIES: int = 400

const BX_MIN := -44.0
const BX_MAX :=  44.0
const BZ_MIN := -28.0
const BZ_MAX :=  28.0
const WALL_T := 0.4
const WALL_H := 6.0
const DOOR_W := 3.0

const ROOMS := [
	{ "name": "Reception",  "x_min": -22.0, "x_max":  -6.0, "z_min": -24.0, "z_max": -14.0, "kind": "reception", "door": "N" },
	{ "name": "Waiting",    "x_min":   6.0, "x_max":  22.0, "z_min": -24.0, "z_max": -14.0, "kind": "waiting",   "door": "N" },
	{ "name": "Triage",     "x_min": -40.0, "x_max": -22.0, "z_min": -24.0, "z_max": -14.0, "kind": "triage",    "door": "N" },
	{ "name": "Pharmacy",   "x_min":  22.0, "x_max":  40.0, "z_min": -24.0, "z_max": -14.0, "kind": "pharm",     "door": "N" },
	{ "name": "ER",         "x_min": -22.0, "x_max":  -6.0, "z_min": -14.0, "z_max":  -8.0, "kind": "er",        "door": "N" },
	{ "name": "Radiology",  "x_min":   6.0, "x_max":  22.0, "z_min": -14.0, "z_max":  -8.0, "kind": "imaging",   "door": "N" },
	{ "name": "Ward_A",     "x_min": -40.0, "x_max": -24.0, "z_min":  -8.0, "z_max":   4.0, "kind": "ward",      "door": "E" },
	{ "name": "Ward_B",     "x_min": -40.0, "x_max": -24.0, "z_min":   4.0, "z_max":  16.0, "kind": "ward",      "door": "E" },
	{ "name": "Storage",    "x_min": -24.0, "x_max": -14.0, "z_min":   2.0, "z_max":  10.0, "kind": "storage",   "door": "E" },
	{ "name": "Staff",      "x_min": -24.0, "x_max": -14.0, "z_min":  10.0, "z_max":  18.0, "kind": "staff",     "door": "E" },
	{ "name": "Ward_C",     "x_min":  24.0, "x_max":  40.0, "z_min":  -8.0, "z_max":   4.0, "kind": "ward",      "door": "W" },
	{ "name": "Ward_D",     "x_min":  24.0, "x_max":  40.0, "z_min":   4.0, "z_max":  16.0, "kind": "ward",      "door": "W" },
	{ "name": "Depot",      "x_min":  14.0, "x_max":  24.0, "z_min":   2.0, "z_max":  10.0, "kind": "depot",     "door": "W" },
	{ "name": "Cafeteria",  "x_min":  14.0, "x_max":  24.0, "z_min":  10.0, "z_max":  18.0, "kind": "cafe",      "door": "W" },
	{ "name": "ICU",        "x_min": -14.0, "x_max":   0.0, "z_min":  18.0, "z_max":  28.0, "kind": "icu",       "door": "S" },
	{ "name": "Surgery",    "x_min":   0.0, "x_max":  14.0, "z_min":  18.0, "z_max":  28.0, "kind": "surgery",   "door": "S" },
	{ "name": "Recovery",   "x_min": -30.0, "x_max": -14.0, "z_min":  18.0, "z_max":  28.0, "kind": "ward",      "door": "S" },
	{ "name": "Oncology",   "x_min":  14.0, "x_max":  30.0, "z_min":  18.0, "z_max":  28.0, "kind": "ward",      "door": "S" },
]

const DISEASES := [
	{ "name": "Broken Bone", "supply": "Cast" },
	{ "name": "Appendicitis", "supply": "Antibiotics" },
	{ "name": "Flu", "supply": "Antivirals" },
	{ "name": "Heart Attack", "supply": "Stents" },
	{ "name": "Stroke", "supply": "Clot Busters" },
	{ "name": "Pneumonia", "supply": "Antibiotics" },
	{ "name": "Food Poisoning", "supply": "IV Fluids" },
	{ "name": "Migraine", "supply": "Painkillers" },
	{ "name": "Laceration", "supply": "Bandages" },
	{ "name": "Concussion", "supply": "Painkillers" },
	{ "name": "Asthma Attack", "supply": "Inhalers" },
	{ "name": "Allergic Reaction", "supply": "Antihistamines" }
]

const SUPPLY_UNIT_PRICE := {
	"Cast": 200, "Antibiotics": 80, "Antivirals": 120, "Stents": 600,
	"Clot Busters": 500, "IV Fluids": 40, "Painkillers": 20,
	"Bandages": 10, "Inhalers": 160, "Antihistamines": 60
}
const ORDER_BASE_FEE := 500

# Mirror Humanoid.State so Game.gd can reference states by name.
const S_ARRIVING := 0
const S_AT_RECEPTION := 1
const S_GOING_TO_ROOM := 2
const S_WAITING_FOR_DOCTOR := 3
const S_RECOVERING := 4
const S_LEAVING := 5
const S_WORKING := 6
const S_TREATING := 7

# First-person physics
const FP_JUMP_VELOCITY := 6.0
const FP_GRAVITY := 18.0

var supply_inventory: Dictionary = {
	"Cast": 20, "Antibiotics": 40, "Antivirals": 30, "Stents": 10,
	"Clot Busters": 10, "IV Fluids": 50, "Painkillers": 60,
	"Bandages": 80, "Inhalers": 20, "Antihistamines": 30
}

var bed_positions: Array[Vector3] = []
var bed_wards: Array[String] = []
var bed_occupied: Array[bool] = []
var occupied_beds: int = 0

var nav: NavGraph = null
var wall_rects: Array[Rect2] = []

var entrance_left: MeshInstance3D
var entrance_right: MeshInstance3D
var entrance_open_amount: float = 0.0
const ENTRANCE_CLOSED_X := 1.2

var roof_mesh: MeshInstance3D

var patients: Array = []
var staff: Array = []
var truck: Node3D = null

var population_clock: float = 0.0
const POPULATION_INTERVAL := 5.0
const MAX_PATIENTS := 10

var actors_root: Node3D
var top_down_camera: Camera3D
var fp_controller: CharacterBody3D
var fp_camera: Camera3D
var is_first_person: bool = false
var fp_yaw: float = 0.0
var fp_pitch: float = 0.0
var fp_speed: float = 8.0
var mouse_sensitivity: float = 0.15
var fp_jump_queued: bool = false

# Cached top-down camera transform so we can restore it exactly on exit.
var top_down_home_position: Vector3 = Vector3(0, 60, -90)
var top_down_home_rotation: Vector3 = Vector3(-32, 0, 0)

var hud_root: Control
var funds_value_label: Label
var supplies_chip_container: GridContainer
var supplies_chips: Dictionary = {}
var beds_value_label: Label
var beds_bar: ProgressBar
var order_button: Button
var recruit_button: Button
var view_button: Button

var chart_panel: Control
var chart_slide_value: float = 0.0
var chart_width: float = 420.0
var chart_shown: bool = false
var active_popup_patient: Node = null
var ch_name: Label
var ch_dob: Label
var ch_entry: Label
var ch_disease: Label
var ch_cure: Label
var ch_health: ProgressBar
var ch_portrait: TextureRect

var order_panel: Control
var order_slide_value: float = 0.0
var order_shown: bool = false
var order_items: Dictionary = {}
var order_total_label: Label
var order_lines: Dictionary = {}

func _ready() -> void:
	_generate_beds()
	_build_nav_graph()
	_build_scene()
	_build_skyline()
	_spawn_initial_staff()
	_update_hud()

func _generate_beds() -> void:
	for room in ROOMS:
		if str(room["kind"]) in ["ward", "icu"]:
			var cx := (float(room["x_min"]) + float(room["x_max"])) * 0.5
			var cz := (float(room["z_min"]) + float(room["z_max"])) * 0.5
			bed_positions.append(Vector3(cx - 2.5, 1.2, cz)); bed_wards.append(str(room["name"]))
			bed_positions.append(Vector3(cx + 2.5, 1.2, cz)); bed_wards.append(str(room["name"]))
	bed_occupied.resize(bed_positions.size())
	for i in range(bed_occupied.size()): bed_occupied[i] = false

func _door_position(room: Dictionary) -> Vector3:
	var x_min := float(room["x_min"]); var x_max := float(room["x_max"])
	var z_min := float(room["z_min"]); var z_max := float(room["z_max"])
	var cx := (x_min + x_max) * 0.5; var cz := (z_min + z_max) * 0.5
	match str(room["door"]):
		"S": return Vector3(cx, 0.5, z_min - 0.2)
		"N": return Vector3(cx, 0.5, z_max + 0.2)
		"E": return Vector3(x_max + 0.2, 0.5, cz)
		"W": return Vector3(x_min - 0.2, 0.5, cz)
	return Vector3(cx, 0.5, cz)

func _build_nav_graph() -> void:
	nav = NavGraph.new()
	nav.add_node("entrance_out",  Vector3(  0.0, 0.5, -34.0))
	nav.add_node("entrance_in",   Vector3(  0.0, 0.5, -28.5))
	nav.add_node("reception",     Vector3(  0.0, 0.5, -20.0))
	nav.add_node("c_1",           Vector3(  0.0, 0.5, -15.0))
	nav.add_node("c_2",           Vector3(  0.0, 0.5,  -7.0))
	nav.add_node("c_3",           Vector3(  0.0, 0.5,   0.0))
	nav.add_node("c_4",           Vector3(  0.0, 0.5,  10.0))
	nav.add_node("c_5",           Vector3(  0.0, 0.5,  21.0))

	for room in ROOMS:
		var name := str(room["name"])
		nav.add_node("door_" + name, _door_position(room))
		nav.add_node("room_" + name, Vector3(
			(float(room["x_min"]) + float(room["x_max"])) * 0.5, 0.5,
			(float(room["z_min"]) + float(room["z_max"])) * 0.5))
	for i in range(bed_positions.size()):
		nav.add_node("bed_%d" % i, bed_positions[i] + Vector3(0, 0, 1.6))

	nav.link("entrance_out", "entrance_in")
	nav.link("entrance_in", "reception")
	nav.link("reception", "c_1")
	nav.link("c_1", "c_2")
	nav.link("c_2", "c_3")
	nav.link("c_3", "c_4")
	nav.link("c_4", "c_5")

	for room in ROOMS:
		var name := str(room["name"])
		var door_pos: Vector3 = nav.get_pos("door_" + name)
		var nearest := "c_3"; var best := 99999.0
		for cid in ["c_1", "c_2", "c_3", "c_4", "c_5"]:
			var d: float = nav.get_pos(cid).distance_to(door_pos)
			if d < best: best = d; nearest = cid
		nav.link(nearest, "door_" + name)
		nav.link("door_" + name, "room_" + name)

	for i in range(bed_positions.size()):
		nav.link("room_" + bed_wards[i], "bed_%d" % i)

func get_nav_path(from_pos: Vector3, to_pos: Vector3) -> Array:
	if nav == null: return []
	return nav.find_path(nav.nearest_node_id(from_pos), nav.nearest_node_id(to_pos))

func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.53, 0.65, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.76)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.15; sun.shadow_enabled = true
	add_child(sun)

	top_down_home_position = Vector3(0, 60, -90)
	top_down_home_rotation = Vector3(-32, 0, 0)

	top_down_camera = Camera3D.new()
	top_down_camera.position = top_down_home_position
	top_down_camera.rotation_degrees = top_down_home_rotation
	top_down_camera.fov = 55; top_down_camera.current = true
	top_down_camera.set_script(CameraControllerScript); add_child(top_down_camera)

	fp_controller = CharacterBody3D.new()
	fp_controller.position = Vector3(0, 2, -30)
	fp_controller.collision_layer = 4
	fp_controller.collision_mask = 1 | 4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4; cap.height = 1.8
	col.shape = cap; col.position.y = 0.9
	fp_controller.add_child(col); add_child(fp_controller)
	fp_camera = Camera3D.new()
	fp_camera.position = Vector3(0, 1.6, 0)
	fp_camera.current = false; fp_controller.add_child(fp_camera)

	actors_root = Node3D.new(); add_child(actors_root)
	_make_wall_phys(Vector3(600, 0.1, 600), Vector3(0, -0.05, 0))

	_build_ground(); _build_roads(); _build_floor_shell()
	_build_room_walls(); _build_room_props(); _build_beds_floor()
	_build_reception(); _build_entrance_canopy()
	_build_roof()
	_build_hud(); _build_patient_chart(); _build_order_panel()

func _build_ground() -> void:
	_make_box(Vector3(600, 0.1, 600), Vector3(0, -0.05, 0), Color(0.28, 0.42, 0.25), "Ground")
	_make_box(Vector3(150, 0.12, 100), Vector3(0, 0.02, 0), Color(0.42, 0.43, 0.46), "Forecourt")

func _build_roads() -> void:
	_make_box(Vector3(12, 0.02, 80), Vector3(0, 0.14, -70), Color(0.16, 0.16, 0.18), "Driveway")
	_make_box(Vector3(150, 0.02, 8), Vector3(0, 0.14, -90), Color(0.16, 0.16, 0.18), "CrossStreet")

func _build_floor_shell() -> void:
	var W := BX_MAX - BX_MIN; var D := BZ_MAX - BZ_MIN
	_make_box(Vector3(W + 0.4, 0.2, D + 0.4), Vector3(0, 0.1, 0), Color(0.9, 0.92, 0.94), "Floor")
	_make_box(Vector3(80, 0.02, 6.0), Vector3(0, 0.21, -11.0), Color(0.8, 0.82, 0.86), "HallS")
	_make_box(Vector3(80, 0.02, 6.0), Vector3(0, 0.21, 14.0), Color(0.8, 0.82, 0.86), "HallN")
	_make_box(Vector3(6.0, 0.02, 44), Vector3(0, 0.21, 3.0), Color(0.8, 0.82, 0.86), "HallV")

	var s_z := BZ_MIN - WALL_T * 0.5
	_make_box(Vector3((-2.0) - BX_MIN, WALL_H, WALL_T), Vector3((BX_MIN + (-2.0)) * 0.5, WALL_H * 0.5, s_z), Color(0.92, 0.9, 0.86), "SW_L")
	_make_wall_phys(Vector3((-2.0) - BX_MIN, WALL_H, WALL_T), Vector3((BX_MIN + (-2.0)) * 0.5, WALL_H * 0.5, s_z))
	_register_wall(Rect2(BX_MIN, s_z - WALL_T * 0.5, (-2.0) - BX_MIN, WALL_T))
	_make_box(Vector3(BX_MAX - 2.0, WALL_H, WALL_T), Vector3((2.0 + BX_MAX) * 0.5, WALL_H * 0.5, s_z), Color(0.92, 0.9, 0.86), "SW_R")
	_make_wall_phys(Vector3(BX_MAX - 2.0, WALL_H, WALL_T), Vector3((2.0 + BX_MAX) * 0.5, WALL_H * 0.5, s_z))
	_register_wall(Rect2(2.0, s_z - WALL_T * 0.5, BX_MAX - 2.0, WALL_T))
	_make_box(Vector3(4.0, WALL_H - 3.0, WALL_T), Vector3(0, 3.0 + (WALL_H - 3.0) * 0.5, s_z), Color(0.92, 0.9, 0.86), "SW_Lintel")

	var n_z := BZ_MAX + WALL_T * 0.5
	_make_box(Vector3(W + WALL_T * 2, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, n_z), Color(0.92, 0.9, 0.86), "NW")
	_make_wall_phys(Vector3(W + WALL_T * 2, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, n_z))
	_register_wall(Rect2(BX_MIN, BZ_MAX, W, WALL_T))

	var w_x := BX_MIN - WALL_T * 0.5
	_make_box(Vector3(WALL_T, WALL_H, D + WALL_T * 2), Vector3(w_x, WALL_H * 0.5, 0), Color(0.92, 0.9, 0.86), "WW")
	_make_wall_phys(Vector3(WALL_T, WALL_H, D + WALL_T * 2), Vector3(w_x, WALL_H * 0.5, 0))
	_register_wall(Rect2(BX_MIN - WALL_T, BZ_MIN, WALL_T, D))

	var e_x := BX_MAX + WALL_T * 0.5
	_make_box(Vector3(WALL_T, WALL_H, D + WALL_T * 2), Vector3(e_x, WALL_H * 0.5, 0), Color(0.92, 0.9, 0.86), "EW")
	_make_wall_phys(Vector3(WALL_T, WALL_H, D + WALL_T * 2), Vector3(e_x, WALL_H * 0.5, 0))
	_register_wall(Rect2(BX_MAX, BZ_MIN, WALL_T, D))

	entrance_left = _make_box(Vector3(1.9, 2.8, 0.1), Vector3(-ENTRANCE_CLOSED_X, 1.4, s_z + WALL_T * 0.5 - 0.02), Color(0.55, 0.78, 0.88), "EntranceDoor_L")
	entrance_right = _make_box(Vector3(1.9, 2.8, 0.1), Vector3( ENTRANCE_CLOSED_X, 1.4, s_z + WALL_T * 0.5 - 0.02), Color(0.55, 0.78, 0.88), "EntranceDoor_R")

func _build_room_walls() -> void:
	var wc := Color(0.88, 0.88, 0.9)
	for room in ROOMS:
		var x_min := float(room["x_min"]); var x_max := float(room["x_max"])
		var z_min := float(room["z_min"]); var z_max := float(room["z_max"])
		var name := str(room["name"]); var ds := str(room["door"]); var dp: Vector3 = nav.get_pos("door_" + name)
		_hwall(x_min, x_max, z_min, ds == "S", dp.x, wc, name + "_S")
		_hwall(x_min, x_max, z_max, ds == "N", dp.x, wc, name + "_N")
		_vwall(z_min, z_max, x_min, ds == "W", dp.z, wc, name + "_W")
		_vwall(z_min, z_max, x_max, ds == "E", dp.z, wc, name + "_E")

func _hwall(x_min: float, x_max: float, z: float, has_door: bool, door_x: float, col: Color, tag: String) -> void:
	var length := x_max - x_min
	if length <= 0.05: return
	if not has_door:
		_make_box(Vector3(length, WALL_H, WALL_T), Vector3((x_min + x_max) * 0.5, WALL_H * 0.5, z), col, tag)
		_make_wall_phys(Vector3(length, WALL_H, WALL_T), Vector3((x_min + x_max) * 0.5, WALL_H * 0.5, z))
		_register_wall(Rect2(x_min, z - WALL_T * 0.5, length, WALL_T)); return
	var dl := door_x - DOOR_W * 0.5; var dr := door_x + DOOR_W * 0.5
	if dl > x_min + 0.05:
		var l := dl - x_min
		_make_box(Vector3(l, WALL_H, WALL_T), Vector3(x_min + l * 0.5, WALL_H * 0.5, z), col, tag + "_L")
		_make_wall_phys(Vector3(l, WALL_H, WALL_T), Vector3(x_min + l * 0.5, WALL_H * 0.5, z))
		_register_wall(Rect2(x_min, z - WALL_T * 0.5, l, WALL_T))
	if dr < x_max - 0.05:
		var l2 := x_max - dr
		_make_box(Vector3(l2, WALL_H, WALL_T), Vector3(dr + l2 * 0.5, WALL_H * 0.5, z), col, tag + "_R")
		_make_wall_phys(Vector3(l2, WALL_H, WALL_T), Vector3(dr + l2 * 0.5, WALL_H * 0.5, z))
		_register_wall(Rect2(dr, z - WALL_T * 0.5, l2, WALL_T))
	_make_box(Vector3(DOOR_W, WALL_H - 2.4, WALL_T), Vector3(door_x, 2.4 + (WALL_H - 2.4) * 0.5, z), col, tag + "_Lintel")
	_make_wall_phys(Vector3(DOOR_W, WALL_H - 2.4, WALL_T), Vector3(door_x, 2.4 + (WALL_H - 2.4) * 0.5, z))

func _vwall(z_min: float, z_max: float, x: float, has_door: bool, door_z: float, col: Color, tag: String) -> void:
	var length := z_max - z_min
	if length <= 0.05: return
	if not has_door:
		_make_box(Vector3(WALL_T, WALL_H, length), Vector3(x, WALL_H * 0.5, (z_min + z_max) * 0.5), col, tag)
		_make_wall_phys(Vector3(WALL_T, WALL_H, length), Vector3(x, WALL_H * 0.5, (z_min + z_max) * 0.5))
		_register_wall(Rect2(x - WALL_T * 0.5, z_min, WALL_T, length)); return
	var dl := door_z - DOOR_W * 0.5; var dr := door_z + DOOR_W * 0.5
	if dl > z_min + 0.05:
		var l := dl - z_min
		_make_box(Vector3(WALL_T, WALL_H, l), Vector3(x, WALL_H * 0.5, z_min + l * 0.5), col, tag + "_S")
		_make_wall_phys(Vector3(WALL_T, WALL_H, l), Vector3(x, WALL_H * 0.5, z_min + l * 0.5))
		_register_wall(Rect2(x - WALL_T * 0.5, z_min, WALL_T, l))
	if dr < z_max - 0.05:
		var l2 := z_max - dr
		_make_box(Vector3(WALL_T, WALL_H, l2), Vector3(x, WALL_H * 0.5, dr + l2 * 0.5), col, tag + "_N")
		_make_wall_phys(Vector3(WALL_T, WALL_H, l2), Vector3(x, WALL_H * 0.5, dr + l2 * 0.5))
		_register_wall(Rect2(x - WALL_T * 0.5, dr, WALL_T, l2))
	_make_box(Vector3(WALL_T, WALL_H - 2.4, DOOR_W), Vector3(x, 2.4 + (WALL_H - 2.4) * 0.5, door_z), col, tag + "_Lintel")
	_make_wall_phys(Vector3(WALL_T, WALL_H - 2.4, DOOR_W), Vector3(x, 2.4 + (WALL_H - 2.4) * 0.5, door_z))

func _build_reception() -> void:
	_make_box(Vector3(6, 1.1, 1.0), Vector3(0.0, 0.55, -20.0), Color(0.42, 0.28, 0.15), "RecDesk")
	_make_box(Vector3(6.2, 0.1, 1.2), Vector3(0.0, 1.15, -20.0), Color(0.25, 0.16, 0.08), "RecCounter")

func _build_beds_floor() -> void:
	for i in range(bed_positions.size()):
		var bp := bed_positions[i]
		_make_box(Vector3(1.8, 0.4, 3.0), Vector3(bp.x, 0.8, bp.z), Color(0.35, 0.37, 0.4), "BedFrame")
		_make_box(Vector3(1.7, 0.2, 2.8), Vector3(bp.x, 1.1, bp.z), Color(0.95, 0.96, 0.98), "BedMattress")
		_make_box(Vector3(1.6, 0.08, 1.3), Vector3(bp.x, 1.2, bp.z + 0.6), Color(0.4, 0.55, 0.75), "BedBlanket")

func _build_room_props() -> void:
	for room in ROOMS:
		var kind := str(room["kind"])
		var x_min := float(room["x_min"]); var x_max := float(room["x_max"])
		var z_min := float(room["z_min"]); var z_max := float(room["z_max"])
		var cx := (x_min + x_max) * 0.5; var cz := (z_min + z_max) * 0.5
		match kind:
			"pharm":
				for i in range(3):
					_make_box(Vector3(0.5, 0.1, 6.0), Vector3(x_max - 0.5, 1.0 + i * 1.1, cz), Color(0.5, 0.4, 0.3), "Shelf")
					_make_wall_phys(Vector3(0.5, 0.1, 6.0), Vector3(x_max - 0.5, 1.0 + i * 1.1, cz))
			"imaging":
				_make_box(Vector3(3.0, 0.5, 4.0), Vector3(cx, 0.5, cz), Color(0.5,0.55,0.6), "Table")
				_make_wall_phys(Vector3(3.0, 0.5, 4.0), Vector3(cx, 0.5, cz))
			"staff":
				_make_box(Vector3(2.0, 0.1, 1.0), Vector3(cx + 2.0, 0.9, cz + 1.0), Color(0.65, 0.55, 0.45), "Table")
				_make_wall_phys(Vector3(2.0, 0.1, 1.0), Vector3(cx + 2.0, 0.9, cz + 1.0))
			"surgery":
				_make_box(Vector3(2.0, 0.9, 4.0), Vector3(cx, 0.45, cz), Color(0.5, 0.55, 0.6), "OR_Table")
				_make_wall_phys(Vector3(2.0, 0.9, 4.0), Vector3(cx, 0.45, cz))

func _build_roof() -> void:
	var W := BX_MAX - BX_MIN + WALL_T * 2
	var D := BZ_MAX - BZ_MIN + WALL_T * 2
	roof_mesh = _make_box(
		Vector3(W, 0.3, D),
		Vector3(0, WALL_H + 0.15, 0),
		Color(0.35, 0.32, 0.3),
		"HospitalRoof")
	roof_mesh.visible = false

func _register_wall(rect: Rect2) -> void: wall_rects.append(rect)
func _make_wall_phys(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new(); body.position = pos
	var col := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = size; col.shape = box; body.add_child(col); add_child(body)

func _make_box(size: Vector3, pos: Vector3, col: Color, node_name: String = "Box") -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = node_name
	var box := BoxMesh.new(); box.size = size; mi.mesh = box; mi.position = pos
	var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 0.85
	mi.material_override = m; add_child(mi); return mi

func _build_skyline() -> void:
	for i in range(20):
		var side := -1.0 if i % 2 == 0 else 1.0
		var dz := float(i / 2) * 28.0 - 80.0
		var h := randi_range(18, 40); var w := randf_range(12, 20)
		_make_box(Vector3(w, h, w), Vector3(side * 100.0, h * 0.5, dz), Color(0.3, 0.33, 0.38), "Skyline_%d" % i)

func _build_entrance_canopy() -> void:
	var s_z := BZ_MIN - WALL_T * 0.5
	_make_box(Vector3(0.3, 3.5, 0.3), Vector3(-3.5, 1.75, s_z - 2.0), Color(0.7, 0.7, 0.72), "Pillar_L")
	_make_box(Vector3(9, 0.25, 4), Vector3(0, 3.6, s_z - 2.0), Color(0.6, 0.62, 0.65), "Canopy")

func _spawn_initial_staff() -> void:
	for i in range(6):
		var role: int = [1, 2].pick_random()
		_spawn_humanoid(role)

func _spawn_humanoid(role: int) -> Node3D:
	var node := CharacterBody3D.new()
	node.set_script(HumanoidScript)
	node.configure(role, self)
	actors_root.add_child(node)
	if role == 0:
		var disease = DISEASES.pick_random()
		node.set_meta("patient_name", ["John Doe", "Jane Smith", "Alice Brown", "Bob White", "Charlie Green", "Diana Prince", "Evan Wright"].pick_random())
		node.set_meta("disease", disease["name"])
		node.set_meta("cure", disease["supply"])
		node.set_meta("dob", "19%02d-%02d-%02d" % [randi_range(50,99), randi_range(1,12), randi_range(1,28)])
		node.set_meta("entry", Time.get_date_string_from_system())
		node.set_meta("progress", 0.0)
		patients.append(node)
	else:
		staff.append(node)
	return node

func _toggle_view() -> void:
	is_first_person = not is_first_person
	# Restore the top-down camera exactly to its home transform every time we
	# leave FP mode. This prevents the camera from being offset by the
	# CameraControllerScript's accumulated pan/zoom state.
	if not is_first_person:
		if top_down_camera:
			top_down_camera.position = top_down_home_position
			top_down_camera.rotation_degrees = top_down_home_rotation
			# Reset any custom state the CameraControllerScript may keep.
			if top_down_camera.has_method("reset_view"):
				top_down_camera.reset_view()
	top_down_camera.current = not is_first_person
	fp_camera.current = is_first_person
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if is_first_person else Input.MOUSE_MODE_VISIBLE)
	if roof_mesh:
		roof_mesh.visible = is_first_person
	# Release any focused button so Space/Enter don't re-trigger it.
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	if is_first_person:
		fp_controller.position = Vector3(0, 2, -30)
		fp_yaw = 0.0; fp_pitch = 0.0
		fp_controller.velocity = Vector3.ZERO
		fp_jump_queued = false
		if view_button: view_button.text = "EXIT FIRST PERSON (Q)"
	else:
		if view_button: view_button.text = "FIRST PERSON"

func _input(event: InputEvent) -> void:
	if is_first_person:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_Q:
				_toggle_view()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_SPACE:
				fp_jump_queued = true
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseMotion:
			fp_yaw -= event.relative.x * mouse_sensitivity
			fp_pitch -= event.relative.y * mouse_sensitivity
			fp_pitch = clampf(fp_pitch, -89.0, 89.0)
			fp_controller.rotation_degrees.y = fp_yaw
			fp_camera.rotation_degrees.x = fp_pitch
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if chart_shown or order_shown: return
			_try_click_patient_fp(event.position)
			return
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if chart_shown or order_shown: return
		var from = top_down_camera.project_ray_origin(event.position)
		var to = from + top_down_camera.project_ray_normal(event.position) * 200
		var query = PhysicsRayQueryParameters3D.create(from, to, 2)
		var result = get_world_3d().direct_space_state.intersect_ray(query)
		if result and result["collider"].has_meta("disease"):
			_toggle_or_open_patient(result["collider"]); return
		var best: Node = null; var best_d := 2.0
		for p in patients:
			var d = _dist_point_ray(p.position + Vector3(0,1,0), from, to)
			if d < best_d: best_d = d; best = p
		if best != null: _toggle_or_open_patient(best)

func _try_click_patient_fp(mouse_pos: Vector2) -> void:
	var from: Vector3 = fp_camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + fp_camera.project_ray_normal(mouse_pos) * 30.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		var collider = result["collider"]
		if collider is Node and collider.has_meta("disease"):
			_toggle_or_open_patient(collider)
			return
	# Fallback: screen-space pick against patients.
	var best: Node = null
	var best_dist := 60.0
	for p in patients:
		var pnode: Node3D = p
		if pnode.position.distance_to(fp_controller.position) > 20.0: continue
		var world: Vector3 = pnode.position + Vector3(0, 1.2, 0)
		if fp_camera.is_position_behind(world): continue
		var screen: Vector2 = fp_camera.unproject_position(world)
		var d: float = screen.distance_to(mouse_pos)
		if d < best_dist:
			best_dist = d
			best = p
	if best != null:
		_toggle_or_open_patient(best)

# If the same patient's chart is already open, close it. Otherwise, open it.
func _toggle_or_open_patient(patient: Node) -> void:
	if chart_shown and active_popup_patient == patient:
		_close_chart()
		return
	open_patient_chart(patient)

func _dist_point_ray(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab = b - a; var ap = p - a
	var t = clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _build_hud() -> void:
	var hud := CanvasLayer.new(); add_child(hud)
	hud_root = Control.new()
	hud_root.anchor_left = 0.0; hud_root.anchor_top = 0.0
	hud_root.anchor_right = 0.0; hud_root.anchor_bottom = 0.0
	hud_root.offset_left = 20; hud_root.offset_top = 20
	hud_root.offset_right = 460; hud_root.offset_bottom = 460
	hud.add_child(hud_root)
	var bg := Panel.new(); bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	var bg_style := StyleBoxFlat.new(); bg_style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	bg_style.corner_radius_top_left = 10; bg_style.corner_radius_top_right = 10
	bg_style.corner_radius_bottom_left = 10; bg_style.corner_radius_bottom_right = 10
	bg_style.border_width_left = 3; bg_style.border_color = Color(0.2, 0.55, 0.85)
	bg.add_theme_stylebox_override("panel", bg_style)
	hud_root.add_child(bg)
	var pad := MarginContainer.new(); pad.anchor_right = 1.0; pad.anchor_bottom = 1.0
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]: pad.add_theme_constant_override(s, 16)
	hud_root.add_child(pad)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 10); pad.add_child(root)
	var title_row := HBoxContainer.new(); title_row.add_theme_constant_override("separation", 6); root.add_child(title_row)
	var title := Label.new(); title.text = "ST. LUKES HOSPITAL"
	title.add_theme_font_size_override("font_size", 18); title.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	title_row.add_child(title)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_row.add_child(spacer)
	var shift_label := Label.new(); shift_label.text = "DAY SHIFT"
	shift_label.add_theme_font_size_override("font_size", 11); shift_label.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
	title_row.add_child(shift_label)
	root.add_child(HSeparator.new())
	var funds_card := PanelContainer.new()
	var fc_style := StyleBoxFlat.new(); fc_style.bg_color = Color(0.05, 0.15, 0.1, 0.9)
	fc_style.corner_radius_top_left = 6; fc_style.corner_radius_top_right = 6
	fc_style.corner_radius_bottom_left = 6; fc_style.corner_radius_bottom_right = 6
	fc_style.content_margin_left = 12; fc_style.content_margin_right = 12
	fc_style.content_margin_top = 8; fc_style.content_margin_bottom = 8
	funds_card.add_theme_stylebox_override("panel", fc_style)
	root.add_child(funds_card)
	var funds_row := HBoxContainer.new(); funds_row.add_theme_constant_override("separation", 10); funds_card.add_child(funds_row)
	var funds_icon := Label.new(); funds_icon.text = "$"
	funds_icon.add_theme_font_size_override("font_size", 28); funds_icon.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
	funds_row.add_child(funds_icon)
	var funds_col := VBoxContainer.new(); funds_row.add_child(funds_col)
	var flbl := Label.new(); flbl.text = "CAPITAL"
	flbl.add_theme_font_size_override("font_size", 10); flbl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
	funds_col.add_child(flbl)
	funds_value_label = Label.new(); funds_value_label.text = "$80,000"
	funds_value_label.add_theme_font_size_override("font_size", 24); funds_value_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
	funds_col.add_child(funds_value_label)
	var supplies_hdr := Label.new(); supplies_hdr.text = "SUPPLIES"
	supplies_hdr.add_theme_font_size_override("font_size", 11); supplies_hdr.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95))
	root.add_child(supplies_hdr)
	supplies_chip_container = GridContainer.new(); supplies_chip_container.columns = 2
	supplies_chip_container.add_theme_constant_override("h_separation", 6); supplies_chip_container.add_theme_constant_override("v_separation", 6)
	root.add_child(supplies_chip_container)
	for supply in SUPPLY_UNIT_PRICE.keys():
		var chip := PanelContainer.new()
		var chip_style := StyleBoxFlat.new(); chip_style.bg_color = Color(0.12, 0.16, 0.22, 1.0)
		chip_style.corner_radius_top_left = 5; chip_style.corner_radius_top_right = 5
		chip_style.corner_radius_bottom_left = 5; chip_style.corner_radius_bottom_right = 5
		chip_style.content_margin_left = 8; chip_style.content_margin_right = 8
		chip_style.content_margin_top = 5; chip_style.content_margin_bottom = 5
		chip.add_theme_stylebox_override("panel", chip_style)
		chip.custom_minimum_size = Vector2(180, 46); supplies_chip_container.add_child(chip)
		var chip_vbox := VBoxContainer.new(); chip_vbox.add_theme_constant_override("separation", 2); chip.add_child(chip_vbox)
		var chip_row := HBoxContainer.new(); chip_vbox.add_child(chip_row)
		var chip_name := Label.new(); chip_name.text = supply
		chip_name.add_theme_font_size_override("font_size", 11); chip_name.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
		chip_row.add_child(chip_name)
		var chip_spacer := Control.new(); chip_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; chip_row.add_child(chip_spacer)
		var chip_count := Label.new(); chip_count.text = "0"
		chip_count.add_theme_font_size_override("font_size", 13); chip_count.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		chip_row.add_child(chip_count)
		var chip_bar := ProgressBar.new(); chip_bar.custom_minimum_size = Vector2(0, 8)
		chip_bar.show_percentage = false; chip_bar.max_value = 200.0
		var bar_fill := StyleBoxFlat.new(); bar_fill.bg_color = Color(0.3, 0.7, 1.0)
		bar_fill.corner_radius_top_left = 3; bar_fill.corner_radius_top_right = 3
		bar_fill.corner_radius_bottom_left = 3; bar_fill.corner_radius_bottom_right = 3
		chip_bar.add_theme_stylebox_override("fill", bar_fill)
		chip_vbox.add_child(chip_bar)
		supplies_chips[supply] = { "count": chip_count, "bar": chip_bar }
	root.add_child(HSeparator.new())
	var beds_hdr := Label.new(); beds_hdr.text = "BED OCCUPANCY"
	beds_hdr.add_theme_font_size_override("font_size", 11); beds_hdr.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95))
	root.add_child(beds_hdr)
	var beds_row := HBoxContainer.new(); beds_row.add_theme_constant_override("separation", 8); root.add_child(beds_row)
	beds_bar = ProgressBar.new(); beds_bar.custom_minimum_size = Vector2(280, 20)
	beds_bar.show_percentage = false; beds_bar.max_value = 100.0
	var bed_fill := StyleBoxFlat.new(); bed_fill.bg_color = Color(1.0, 0.55, 0.2)
	bed_fill.corner_radius_top_left = 4; bed_fill.corner_radius_top_right = 4
	bed_fill.corner_radius_bottom_left = 4; bed_fill.corner_radius_bottom_right = 4
	beds_bar.add_theme_stylebox_override("fill", bed_fill)
	beds_row.add_child(beds_bar)
	beds_value_label = Label.new(); beds_value_label.text = "0 / 0"
	beds_value_label.add_theme_font_size_override("font_size", 14); beds_value_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	beds_row.add_child(beds_value_label)
	var btn_layer := CanvasLayer.new(); add_child(btn_layer)
	var btn_row := HBoxContainer.new()
	btn_row.anchor_left = 0.5; btn_row.anchor_top = 1.0
	btn_row.anchor_right = 0.5; btn_row.anchor_bottom = 1.0
	btn_row.offset_left = -360; btn_row.offset_top = -80
	btn_row.offset_right = 360; btn_row.offset_bottom = -25
	btn_row.add_theme_constant_override("separation", 20); btn_layer.add_child(btn_row)
	order_button = Button.new(); order_button.text = "ORDER SUPPLIES"
	order_button.custom_minimum_size = Vector2(220, 55); _style_button(order_button, Color(0.15, 0.4, 0.75), Color(0.25, 0.55, 0.95))
	order_button.pressed.connect(_open_order_panel); btn_row.add_child(order_button)
	recruit_button = Button.new(); recruit_button.text = "RECRUIT STAFF"
	recruit_button.custom_minimum_size = Vector2(220, 55); _style_button(recruit_button, Color(0.15, 0.55, 0.3), Color(0.25, 0.75, 0.45))
	recruit_button.pressed.connect(_on_recruit_staff); btn_row.add_child(recruit_button)
	view_button = Button.new(); view_button.text = "FIRST PERSON"
	view_button.custom_minimum_size = Vector2(220, 55); _style_button(view_button, Color(0.55, 0.35, 0.15), Color(0.75, 0.55, 0.25))
	view_button.focus_mode = Control.FOCUS_NONE
	view_button.pressed.connect(_toggle_view); btn_row.add_child(view_button)
	order_button.focus_mode = Control.FOCUS_NONE
	recruit_button.focus_mode = Control.FOCUS_NONE

func _style_button(b: Button, base: Color, hover: Color) -> void:
	var normal := StyleBoxFlat.new(); normal.bg_color = base
	normal.corner_radius_top_left = 8; normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8; normal.corner_radius_bottom_right = 8
	normal.content_margin_left = 16; normal.content_margin_right = 16
	normal.content_margin_top = 10; normal.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", normal)
	var hov := StyleBoxFlat.new(); hov.bg_color = hover
	hov.corner_radius_top_left = 8; hov.corner_radius_top_right = 8
	hov.corner_radius_bottom_left = 8; hov.corner_radius_bottom_right = 8
	b.add_theme_stylebox_override("hover", hov)
	var pressed := StyleBoxFlat.new(); pressed.bg_color = base.darkened(0.3)
	pressed.corner_radius_top_left = 8; pressed.corner_radius_top_right = 8
	pressed.corner_radius_bottom_left = 8; pressed.corner_radius_bottom_right = 8
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_font_size_override("font_size", 15)

func _build_patient_chart() -> void:
	var canvas := CanvasLayer.new(); add_child(canvas)
	chart_width = 420.0
	chart_panel = Control.new()
	chart_panel.anchor_left = 1.0; chart_panel.anchor_top = 0.0
	chart_panel.anchor_right = 1.0; chart_panel.anchor_bottom = 1.0
	chart_panel.offset_left = 0.0; chart_panel.offset_right = chart_width
	canvas.add_child(chart_panel)
	var bg := Panel.new(); bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	var bg_style := StyleBoxFlat.new(); bg_style.bg_color = Color(0.96, 0.94, 0.88)
	bg_style.border_width_left = 4; bg_style.border_color = Color(0.4, 0.3, 0.2)
	bg.add_theme_stylebox_override("panel", bg_style); chart_panel.add_child(bg)
	var pad := MarginContainer.new(); pad.anchor_right = 1.0; pad.anchor_bottom = 1.0
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]: pad.add_theme_constant_override(s, 20)
	chart_panel.add_child(pad)
	var vbox := VBoxContainer.new(); vbox.add_theme_constant_override("separation", 10); pad.add_child(vbox)
	var title := Label.new(); title.text = "PATIENT RECORD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22); title.add_theme_color_override("font_color", Color(0.2, 0.1, 0.05))
	vbox.add_child(title)
	ch_portrait = TextureRect.new(); ch_portrait.custom_minimum_size = Vector2(140, 140)
	ch_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ch_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(ch_portrait)
	ch_name = _mk_lbl(vbox); ch_dob = _mk_lbl(vbox); ch_entry = _mk_lbl(vbox)
	vbox.add_child(HSeparator.new())
	ch_disease = _mk_lbl(vbox); ch_disease.add_theme_color_override("font_color", Color(0.6, 0.1, 0.1))
	ch_cure = _mk_lbl(vbox); ch_cure.add_theme_color_override("font_color", Color(0.1, 0.4, 0.1))
	var hlbl := Label.new(); hlbl.text = "Healing Progress:"
	hlbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1)); vbox.add_child(hlbl)
	ch_health = ProgressBar.new(); ch_health.custom_minimum_size = Vector2(380, 24); ch_health.max_value = 100
	vbox.add_child(ch_health)
	var close_btn := Button.new(); close_btn.text = "Close Chart"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_chart); vbox.add_child(close_btn)

func _mk_lbl(parent: Node) -> Label:
	var l := Label.new(); l.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	parent.add_child(l); return l

func _generate_avatar(seed_str: String) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new(); rng.seed = seed_str.hash()
	var skin := Color(0.9, 0.72, 0.55)
	var hair_col := Color(rng.randf_range(0.1,0.5), rng.randf_range(0.1,0.4), rng.randf_range(0.0,0.2))
	var shirt := Color(rng.randf_range(0.1,0.8), rng.randf_range(0.1,0.8), rng.randf_range(0.1,0.8))
	for y in range(16):
		for x in range(16):
			var c := Color(0,0,0,0)
			if x >= 5 and x <= 10 and y >= 2 and y <= 6: c = skin
			if y == 2 and x >= 4 and x <= 11: c = hair_col
			if y == 1 and x >= 5 and x <= 10: c = hair_col
			if y >= 7 and y <= 14 and x >= 3 and x <= 12: c = shirt
			if y == 4 and (x == 6 or x == 9): c = Color.BLACK
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func open_patient_chart(patient: Node) -> void:
	active_popup_patient = patient; _close_order_panel_quiet()
	ch_name.text = "Name: " + str(patient.get_meta("patient_name"))
	ch_dob.text = "DOB: " + str(patient.get_meta("dob"))
	ch_entry.text = "Entry: " + str(patient.get_meta("entry"))
	ch_disease.text = "Diagnosis: " + str(patient.get_meta("disease"))
	ch_cure.text = "Required Cure: " + str(patient.get_meta("cure"))
	ch_health.value = patient.get_meta("progress")
	ch_portrait.texture = _generate_avatar(str(patient.get_meta("patient_name")))
	chart_shown = true

func _close_chart() -> void: chart_shown = false; active_popup_patient = null

func _build_order_panel() -> void:
	var canvas := CanvasLayer.new(); add_child(canvas)
	order_panel = Control.new()
	order_panel.anchor_left = 1.0; order_panel.anchor_top = 0.0
	order_panel.anchor_right = 1.0; order_panel.anchor_bottom = 1.0
	order_panel.offset_left = 0.0; order_panel.offset_right = 460.0
	canvas.add_child(order_panel)
	var bg := Panel.new(); bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	var bg_style := StyleBoxFlat.new(); bg_style.bg_color = Color(0.92, 0.95, 0.98)
	bg_style.border_width_left = 4; bg_style.border_color = Color(0.2, 0.35, 0.55)
	bg.add_theme_stylebox_override("panel", bg_style); order_panel.add_child(bg)
	var pad := MarginContainer.new(); pad.anchor_right = 1.0; pad.anchor_bottom = 1.0
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]: pad.add_theme_constant_override(s, 18)
	order_panel.add_child(pad)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 8); pad.add_child(root)
	var title := Label.new(); title.text = "PHARMACY ORDER FORM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22); title.add_theme_color_override("font_color", Color(0.1, 0.2, 0.4))
	root.add_child(title)
	var hint := Label.new(); hint.text = "Pick up to 4 supplies. Min 1 unit each."
	hint.add_theme_font_size_override("font_size", 11); hint.add_theme_color_override("font_color", Color(0.3, 0.3, 0.4))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(hint)
	root.add_child(HSeparator.new())
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(420, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; root.add_child(scroll)
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation", 4); scroll.add_child(list)
	for supply in SUPPLY_UNIT_PRICE.keys():
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6)
		var name_lbl := Label.new(); name_lbl.text = supply; name_lbl.custom_minimum_size = Vector2(160, 26)
		name_lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2)); row.add_child(name_lbl)
		var price_lbl := Label.new(); price_lbl.text = "$" + str(SUPPLY_UNIT_PRICE[supply]) + "/ea"
		price_lbl.custom_minimum_size = Vector2(70, 26); price_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.2))
		row.add_child(price_lbl)
		var minus_btn := Button.new(); minus_btn.text = "-"; minus_btn.custom_minimum_size = Vector2(30, 26)
		minus_btn.focus_mode = Control.FOCUS_NONE
		minus_btn.pressed.connect(_change_order_qty.bind(supply, -1)); row.add_child(minus_btn)
		var qty_lbl := Label.new(); qty_lbl.text = "0"; qty_lbl.custom_minimum_size = Vector2(36, 26)
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; qty_lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
		row.add_child(qty_lbl)
		var plus_btn := Button.new(); plus_btn.text = "+"; plus_btn.custom_minimum_size = Vector2(30, 26)
		plus_btn.focus_mode = Control.FOCUS_NONE
		plus_btn.pressed.connect(_change_order_qty.bind(supply, 1)); row.add_child(plus_btn)
		var sub_lbl := Label.new(); sub_lbl.text = "$0"; sub_lbl.custom_minimum_size = Vector2(70, 26)
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; sub_lbl.add_theme_color_override("font_color", Color(0.15, 0.45, 0.15))
		row.add_child(sub_lbl)
		list.add_child(row)
		order_lines[supply] = { "qty": qty_lbl, "sub": sub_lbl }
	root.add_child(HSeparator.new())
	order_total_label = Label.new(); order_total_label.text = "Order Total: $0   (Base fee: $500)"
	order_total_label.add_theme_font_size_override("font_size", 15); order_total_label.add_theme_color_override("font_color", Color(0.1, 0.2, 0.4))
	root.add_child(order_total_label)
	var btn_row := HBoxContainer.new(); btn_row.add_theme_constant_override("separation", 8); root.add_child(btn_row)
	var place_btn := Button.new(); place_btn.text = "PLACE ORDER"; place_btn.custom_minimum_size = Vector2(200, 42)
	place_btn.focus_mode = Control.FOCUS_NONE
	place_btn.pressed.connect(_place_order); btn_row.add_child(place_btn)
	var cancel_btn := Button.new(); cancel_btn.text = "Cancel"; cancel_btn.custom_minimum_size = Vector2(200, 42)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(_close_order_panel); btn_row.add_child(cancel_btn)

func _open_order_panel() -> void:
	if truck != null: return
	_close_chart(); order_shown = true; _refresh_order_ui()
func _close_order_panel() -> void: order_shown = false
func _close_order_panel_quiet() -> void: order_shown = false

func _change_order_qty(supply: String, delta: int) -> void:
	var current := int(order_items.get(supply, 0))
	var new_val = clamp(current + delta, 0, 99)
	if current == 0 and new_val > 0:
		var distinct := 0
		for k in order_items.keys():
			if int(order_items[k]) > 0: distinct += 1
		if distinct >= 4: return
	order_items[supply] = new_val
	if new_val == 0: order_items.erase(supply)
	_refresh_order_ui()

func _refresh_order_ui() -> void:
	var total: int = ORDER_BASE_FEE
	var any := false
	for supply in order_lines.keys():
		var qty: int = int(order_items.get(supply, 0))
		var sub: int = qty * int(SUPPLY_UNIT_PRICE[supply])
		total += sub
		if qty > 0: any = true
		order_lines[supply]["qty"].text = str(qty)
		order_lines[supply]["sub"].text = "$" + str(sub)
	order_total_label.text = "Order Total: $" + str(total) + "   (Base fee: $500)"
	order_total_label.add_theme_color_override("font_color",
		Color(0.1, 0.2, 0.4) if (any and total <= funds) else Color(0.6, 0.1, 0.1))

func _place_order() -> void:
	if truck != null: return
	var total: int = ORDER_BASE_FEE
	var distinct := 0
	for k in order_items.keys():
		var q := int(order_items[k])
		if q > 0: distinct += 1; total += q * int(SUPPLY_UNIT_PRICE[k])
	if distinct == 0: return
	if total > funds: return
	funds -= total
	var cargo := {}
	for k in order_items.keys():
		var q := int(order_items[k])
		if q > 0: cargo[k] = q
	order_items.clear(); _close_order_panel()
	var t := Node3D.new(); t.set_script(TruckScript); t.configure(self, cargo)
	add_child(t); truck = t; _update_hud()

func deliver_supplies(cargo: Dictionary) -> void:
	for k in cargo.keys():
		supply_inventory[k] = int(supply_inventory.get(k, 0)) + int(cargo[k])
	truck = null; _update_hud()

func _process(delta: float) -> void:
	if is_first_person:
		var dir := Vector3.ZERO
		var yaw_rad := deg_to_rad(fp_yaw)
		var forward := Vector3(-sin(yaw_rad), 0, -cos(yaw_rad))
		var right   := Vector3( cos(yaw_rad), 0, -sin(yaw_rad))
		if Input.is_key_pressed(KEY_W): dir += forward
		if Input.is_key_pressed(KEY_S): dir -= forward
		if Input.is_key_pressed(KEY_D): dir += right
		if Input.is_key_pressed(KEY_A): dir -= right
		if dir.length_squared() > 0.0: dir = dir.normalized()
		fp_controller.velocity.x = dir.x * fp_speed
		fp_controller.velocity.z = dir.z * fp_speed
		if not fp_controller.is_on_floor():
			fp_controller.velocity.y -= FP_GRAVITY * delta
		elif fp_jump_queued:
			fp_controller.velocity.y = FP_JUMP_VELOCITY
			fp_jump_queued = false
		else:
			fp_controller.velocity.y = 0
		fp_jump_queued = false
		fp_controller.move_and_slide()

	var ct = 1.0 if chart_shown else 0.0
	chart_slide_value = lerpf(chart_slide_value, ct, delta * 10.0)
	chart_panel.offset_left  = -chart_width * chart_slide_value
	chart_panel.offset_right = chart_width - chart_width * chart_slide_value
	var ot = 1.0 if order_shown else 0.0
	order_slide_value = lerpf(order_slide_value, ot, delta * 10.0)
	order_panel.offset_left  = -460.0 * order_slide_value
	order_panel.offset_right = 460.0 - 460.0 * order_slide_value

	population_clock += delta
	if population_clock >= POPULATION_INTERVAL:
		population_clock = 0.0
		if patients.size() < MAX_PATIENTS: _spawn_humanoid(0)
	_update_entrance_door(delta)

	for i in range(patients.size()):
		var p = patients[i]

		if p.state == S_WAITING_FOR_DOCTOR:
			for d in staff:
				if d.role in [1, 2] and d.state == S_WORKING:
					d.state = S_TREATING
					d.treating_patient = p
					p.state = S_RECOVERING
					break

		if p.state == S_RECOVERING:
			var prog: float = float(p.get_meta("progress")) + delta * 8.0
			p.set_meta("progress", prog)
			p.update_health_bar(prog)
			if active_popup_patient == p: ch_health.value = prog
			if prog >= 100.0:
				var cure = str(p.get_meta("cure"))
				supply_inventory[cure] = max(0, int(supply_inventory.get(cure, 0)) - 1)
				funds += 4500
				bed_occupied[p.bed_index] = false
				occupied_beds = max(0, occupied_beds - 1)
				p.state = S_LEAVING
				for d in staff:
					if d.state == S_TREATING and d.treating_patient == p:
						d.state = S_WORKING
						d.treating_patient = null
						d.work_timer = 0.0
				if active_popup_patient == p: _close_chart()
				_update_hud()

func _update_entrance_door(delta: float) -> void:
	var near := false
	for p in patients:
		if p.position.distance_to(Vector3(0, 0, BZ_MIN)) < 5.0: near = true; break
	var target := 1.0 if near else 0.0
	entrance_open_amount = lerpf(entrance_open_amount, target, delta * 5.0)
	if entrance_left: entrance_left.position.x = -ENTRANCE_CLOSED_X - entrance_open_amount * 1.4
	if entrance_right: entrance_right.position.x = ENTRANCE_CLOSED_X + entrance_open_amount * 1.4

func request_bed(patient: Node) -> int:
	for i in range(bed_positions.size()):
		if not bed_occupied[i]:
			bed_occupied[i] = true; occupied_beds += 1; _update_hud(); return i
	return -1

func get_bed_position(idx: int) -> Vector3:
	return bed_positions[idx] if (idx >= 0 and idx < bed_positions.size()) else Vector3.ZERO

func get_patient_needing_doctor():
	for p in patients:
		if p.state == S_WAITING_FOR_DOCTOR: return p
	return null

func unregister_patient(p: Node) -> void: patients.erase(p)

func _on_recruit_staff() -> void:
	if funds < 5000: return
	funds -= 5000
	_spawn_humanoid([1, 2].pick_random()); _update_hud()

func _update_hud() -> void:
	if funds_value_label:
		funds_value_label.text = "$" + _fmt_thousands(funds)
		funds_value_label.add_theme_color_override("font_color",
			Color(0.35, 1.0, 0.5) if funds >= 5000 else Color(1.0, 0.4, 0.4))
	if supplies_chips.size() > 0:
		for supply in supplies_chips.keys():
			var chip = supplies_chips[supply]
			var count = int(supply_inventory.get(supply, 0))
			chip["count"].text = str(count)
			chip["bar"].value = float(min(count, 200))
			chip["count"].add_theme_color_override("font_color",
				Color(1.0, 0.4, 0.4) if count < 5 else Color(1.0, 1.0, 1.0))
	if beds_bar:
		beds_bar.value = (float(occupied_beds) / float(max(1, bed_positions.size()))) * 100.0
	if beds_value_label:
		beds_value_label.text = str(occupied_beds) + " / " + str(bed_positions.size())

func _fmt_thousands(n: int) -> String:
	var s := str(n); var out := ""; var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out; count += 1
		if count % 3 == 0 and i > 0: out = "," + out
	return out
