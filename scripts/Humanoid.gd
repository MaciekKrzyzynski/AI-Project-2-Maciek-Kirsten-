extends Node3D

enum Role { PATIENT, DOCTOR, NURSE }
enum State { ARRIVING, AT_RECEPTION, GOING_TO_ROOM, RECOVERING, LEAVING, WORKING }

var role: int = Role.PATIENT
var state: int = State.ARRIVING
var bed_index: int = -1
var treatment_clock: float = 0.0
var reception_clock: float = 0.0
var animation_step: float = 0.0
var work_timer: float = 0.0

var path_nodes: Array = []
var path_index: int = 0

var target_yaw: float = 0.0
var current_yaw: float = 0.0
const TURN_LERP := 0.15

var stuck_timer: float = 0.0
var last_pos: Vector3 = Vector3.ZERO

var game: Node = null

var torso: MeshInstance3D
var head: MeshInstance3D
var hair: MeshInstance3D
var left_leg: MeshInstance3D
var right_leg: MeshInstance3D
var left_arm: MeshInstance3D
var right_arm: MeshInstance3D
var pivot_l: Node3D
var pivot_r: Node3D
var pivot_al: Node3D
var pivot_ar: Node3D

const WALK_SPEED := 4.0
const WORK_SPEED := 3.2
const ARRIVE_DIST := 0.35
const STUCK_TIMEOUT := 2.5
const GROUND_Y := 0.22

var doctor_destinations: Array[String] = [
	"room_Ward_A", "room_Ward_B", "room_Ward_C", "room_Ward_D",
	"room_Recovery", "room_Oncology",
	"room_ICU", "room_Surgery", "room_ER", "room_Triage",
]
var nurse_destinations: Array[String] = [
	"room_Ward_A", "room_Ward_B", "room_Ward_C", "room_Ward_D",
	"room_Recovery", "room_Oncology",
	"room_ICU", "room_Pharmacy", "room_Storage", "room_Depot",
	"room_Cafeteria", "room_Radiology", "room_Staff",
]

func configure(p_role: int, p_game: Node) -> void:
	role = p_role
	game = p_game

func _ready() -> void:
	_build_body()
	if role == Role.PATIENT:
		position = Vector3(randf_range(-1.0, 1.0), GROUND_Y, -62)
		state = State.ARRIVING
		_request_path_to_node("entrance_out")
	else:
		position = Vector3(randf_range(-1.5, 1.5), GROUND_Y, -12)
		state = State.WORKING
		work_timer = 0.0
		_pick_staff_destination()
	current_yaw = 0.0
	rotation.y = 0.0

func _build_body() -> void:
	var suit_color: Color
	var hair_color: Color
	match role:
		Role.DOCTOR:
			suit_color = Color(0.95, 0.95, 0.98)
			hair_color = Color(0.4, 0.25, 0.15)
		Role.NURSE:
			suit_color = Color(0.4, 0.75, 0.9)
			hair_color = Color(0.95, 0.9, 0.2)
		_:
			suit_color = Color(0.75, 0.65, 0.5)
			hair_color = Color(0.05, 0.05, 0.05)

	torso = _make_box(Vector3(0.6, 1.0, 0.4), Vector3(0, 1.0, 0), suit_color)
	head = _make_sphere(0.24, Vector3(0, 1.65, 0), Color(0.9, 0.72, 0.55))
	hair = _make_box(Vector3(0.5, 0.16, 0.5), Vector3(0, 1.82, 0), hair_color)
	if role == Role.DOCTOR:
		_make_box(Vector3(0.1, 0.1, 0.02), Vector3(0, 1.1, -0.21), Color(0.85, 0.1, 0.1))

	var leg_l := _make_box(Vector3(0.18, 0.55, 0.18), Vector3(-0.18, 0.28, 0), Color(0.2, 0.2, 0.22))
	var leg_r := _make_box(Vector3(0.18, 0.55, 0.18), Vector3( 0.18, 0.28, 0), Color(0.2, 0.2, 0.22))
	var arm_l := _make_box(Vector3(0.14, 0.6, 0.14), Vector3(-0.38, 1.0, 0), suit_color)
	var arm_r := _make_box(Vector3(0.14, 0.6, 0.14), Vector3( 0.38, 1.0, 0), suit_color)

	pivot_l  = _reparent_to_pivot(leg_l, Vector3(-0.18, 0.55, 0))
	pivot_r  = _reparent_to_pivot(leg_r, Vector3( 0.18, 0.55, 0))
	pivot_al = _reparent_to_pivot(arm_l, Vector3(-0.38, 1.3, 0))
	pivot_ar = _reparent_to_pivot(arm_r, Vector3( 0.38, 1.3, 0))

	left_leg = leg_l; right_leg = leg_r
	left_arm = arm_l; right_arm = arm_r

func _make_box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b; mi.position = pos; mi.material_override = _mat(col)
	add_child(mi); return mi

func _make_sphere(radius: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = radius; s.height = radius * 2.0
	mi.mesh = s; mi.position = pos; mi.material_override = _mat(col)
	add_child(mi); return mi

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 0.9
	return m

func _reparent_to_pivot(limb: MeshInstance3D, pivot_pos: Vector3) -> Node3D:
	var pivot := Node3D.new(); pivot.position = pivot_pos; add_child(pivot)
	var ll := limb.position - pivot_pos
	limb.get_parent().remove_child(limb)
	pivot.add_child(limb); limb.position = ll
	return pivot

func _process(delta: float) -> void:
	if game == null:
		return
	_animate_limbs(delta)
	_update_facing(delta)
	if role == Role.PATIENT:
		_patient_update(delta)
	else:
		_staff_update(delta)

func _animate_limbs(delta: float) -> void:
	var walking := false
	if role == Role.PATIENT and state in [State.ARRIVING, State.GOING_TO_ROOM, State.LEAVING, State.AT_RECEPTION]:
		walking = true
	elif role != Role.PATIENT:
		walking = true

	if walking:
		animation_step += delta * 12.0
		var s := sin(animation_step)
		pivot_l.rotation.x = s * deg_to_rad(30)
		pivot_r.rotation.x = -s * deg_to_rad(30)
		pivot_al.rotation.x = -s * deg_to_rad(22)
		pivot_ar.rotation.x = s * deg_to_rad(22)
	else:
		pivot_l.rotation.x = 0; pivot_r.rotation.x = 0
		pivot_al.rotation.x = 0; pivot_ar.rotation.x = 0

func _update_facing(delta: float) -> void:
	current_yaw = lerp_angle(current_yaw, target_yaw, TURN_LERP)
	rotation.y = current_yaw

func _request_path_to_node(node_id: String) -> void:
	path_nodes = []
	path_index = 0
	if game == null or game.nav == null:
		return
	var nav = game.nav
	if not nav.has_node(node_id):
		return
	var start_id: String = nav.nearest_node_id(position)
	path_nodes = nav.find_path(start_id, node_id)

func _path_empty() -> bool:
	return path_nodes.is_empty() or path_index >= path_nodes.size()

func _current_path_target() -> Vector3:
	if _path_empty():
		return position
	var id: String = path_nodes[path_index]
	return game.nav_pos(id)

func _follow_path(delta: float, speed: float) -> bool:
	if _path_empty():
		return true
	var target := _current_path_target()
	_move_toward(target, speed, delta)
	if position.distance_to(target) < ARRIVE_DIST:
		path_index += 1
	return _path_empty()

func _move_toward(target: Vector3, speed: float, delta: float) -> void:
	var diff := target - position
	diff.y = 0
	if diff.length() < 0.02:
		return
	var dir := diff.normalized()
	target_yaw = atan2(dir.x, dir.z)

	var step := speed * delta
	var full := position + Vector3(dir.x, 0, dir.z) * step

	# Wall-aware movement: never step into a wall.
	if game.is_walkable(full):
		position = Vector3(full.x, GROUND_Y, full.z)
	else:
		var try_x := position + Vector3(dir.x, 0, 0) * step
		if absf(dir.x) > 0.01 and game.is_walkable(try_x):
			position = Vector3(try_x.x, GROUND_Y, try_x.z)
		else:
			var try_z := position + Vector3(0, 0, dir.z) * step
			if absf(dir.z) > 0.01 and game.is_walkable(try_z):
				position = Vector3(try_z.x, GROUND_Y, try_z.z)

	stuck_timer += delta
	if position.distance_to(last_pos) < 0.01:
		if stuck_timer > STUCK_TIMEOUT:
			if not _path_empty():
				path_index += 1
			stuck_timer = 0.0
	else:
		stuck_timer = 0.0
	last_pos = position

func _patient_update(delta: float) -> void:
	match state:
		State.ARRIVING:
			if _path_empty():
				_request_path_to_node("entrance_out")
			if _follow_path(delta, WALK_SPEED):
				if position.distance_to(game.nav_pos("entrance_out")) < 1.5:
					state = State.AT_RECEPTION
					_request_path_to_node("reception")

		State.AT_RECEPTION:
			if _path_empty():
				_request_path_to_node("reception")
			if _follow_path(delta, WALK_SPEED):
				reception_clock += delta
				if reception_clock > 1.0:
					var idx: int = game.request_bed()
					if idx >= 0:
						bed_index = idx
						state = State.GOING_TO_ROOM
						_request_path_to_node("bed_%d" % bed_index)
					else:
						state = State.LEAVING
						_request_path_to_node("entrance_out")

		State.GOING_TO_ROOM:
			if _path_empty():
				_request_path_to_node("bed_%d" % bed_index)
			if _follow_path(delta, WALK_SPEED):
				state = State.RECOVERING
				torso.material_override = _mat(Color(0.6, 0.9, 0.6))

		State.RECOVERING:
			treatment_clock += delta
			if treatment_clock >= 6.0:
				game.finish_patient_treatment(bed_index)
				state = State.LEAVING
				_request_path_to_node("entrance_out")

		State.LEAVING:
			if _path_empty():
				_request_path_to_node("entrance_out")
			if _follow_path(delta, WALK_SPEED):
				if position.distance_to(game.nav_pos("entrance_out")) < 2.5:
					game.unregister_patient(self)
					queue_free()

func _staff_update(delta: float) -> void:
	work_timer += delta

	if _path_empty():
		if work_timer > randf_range(2.0, 4.5):
			work_timer = 0.0
			_pick_staff_destination()
		return

	_follow_path(delta, WORK_SPEED)

func _pick_staff_destination() -> void:
	var pool: Array[String]
	match role:
		Role.DOCTOR:
			pool = doctor_destinations
		Role.NURSE:
			pool = nurse_destinations
		_:
			pool = nurse_destinations

	for attempt in range(8):
		var candidate: String = pool.pick_random()
		_request_path_to_node(candidate)
		if not path_nodes.is_empty():
			return
	path_nodes = []
