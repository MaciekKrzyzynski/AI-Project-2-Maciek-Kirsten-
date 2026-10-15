extends Node3D

var game: Node = null
var wheels: Array[Node3D] = []
const SPEED := 14.0
const TURN_LERP := 0.15
const PITCH_ACCEL := 8.0
const PITCH_MAX := 4.0
const ARRIVE_RADIUS := 1.5

# If the truck ever lands inside this box, it gets teleported to the current
# waypoint. This is a safety net so it can never visually pass through a wall.
const BLDG_MIN := Vector3(-20.5, -1.0, -10.5)
const BLDG_MAX := Vector3( 20.5, 10.0,  10.5)

var body: Node3D
var velocity: Vector3 = Vector3.ZERO
var prev_pos: Vector3 = Vector3.ZERO
var pitch: float = 0.0
var bob_time: float = 0.0
var yaw: float = 0.0

var waypoints: Array[Vector3] = []
var current_wp: int = 1

func configure(p_game: Node) -> void:
	game = p_game

func _ready() -> void:
	# All waypoints stay south of z = -18, so no segment crosses the building.
	waypoints = [
		Vector3(-45.0, 0.16, -50.0),
		Vector3(  0.0, 0.16, -50.0),
		Vector3(  0.0, 0.16, -30.0),
		Vector3(  0.0, 0.16, -18.0),
		Vector3( 14.0, 0.16, -18.0),
		Vector3( 28.0, 0.16, -18.0),
	]
	current_wp = 1

	position = waypoints[0]
	prev_pos = position
	yaw = _yaw_to(position, waypoints[current_wp])
	rotation.y = yaw

	body = Node3D.new()
	body.name = "Body"
	add_child(body)

	_build_truck()

func _build_truck() -> void:
	_add_box(Vector3(2.5, 2.6, 6.0), Vector3(0, 1.5, 0),
		Color(0.85, 0.85, 0.9), "Trailer")
	_add_box(Vector3(2.55, 1.2, 3.0), Vector3(0, 1.4, 0),
		Color(0.85, 0.1, 0.1), "TrailerStripe")
	_add_box(Vector3(2.6, 0.7, 0.25), Vector3(0, 1.6, -1.0),
		Color(1.0, 1.0, 1.0), "CrossH")
	_add_box(Vector3(2.6, 0.25, 0.7), Vector3(0, 1.6, -1.0),
		Color(1.0, 1.0, 1.0), "CrossV")
	_add_box(Vector3(2.4, 1.9, 2.0), Vector3(0, 1.1, 3.8),
		Color(0.15, 0.15, 0.18), "Cab")
	_add_box(Vector3(2.1, 0.7, 0.08), Vector3(0, 1.6, 4.85),
		Color(0.35, 0.55, 0.7), "Windshield")
	_add_box(Vector3(1.4, 0.18, 0.3), Vector3(0, 2.15, 3.6),
		Color(0.1, 0.1, 0.12), "LightBar")
	_add_box(Vector3(0.5, 0.14, 0.26), Vector3(-0.35, 2.22, 3.6),
		Color(0.9, 0.1, 0.1), "LightRed")
	_add_box(Vector3(0.5, 0.14, 0.26), Vector3( 0.35, 2.22, 3.6),
		Color(0.1, 0.4, 0.95), "LightBlue")
	_add_box(Vector3(0.12, 2.4, 0.12), Vector3(1.2, 1.9, 2.5),
		Color(0.7, 0.7, 0.7), "Exhaust")

	var wheel_positions: Array[Vector3] = [
		Vector3(-1.3, 0.48,  2.0),
		Vector3( 1.3, 0.48,  2.0),
		Vector3(-1.3, 0.48, -2.0),
		Vector3( 1.3, 0.48, -2.0),
	]
	for wp in wheel_positions:
		var pivot := Node3D.new()
		pivot.position = wp
		body.add_child(pivot)
		var w := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.475
		cyl.bottom_radius = 0.475
		cyl.height = 0.5
		w.mesh = cyl
		w.rotation.z = deg_to_rad(90)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.05, 0.05)
		w.material_override = m
		pivot.add_child(w)
		wheels.append(pivot)

func _add_box(size: Vector3, pos: Vector3, col: Color, node_name: String = "Box") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	mi.material_override = m
	body.add_child(mi)
	return mi

func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	d.y = 0
	if d.length_squared() < 0.0001:
		return yaw
	return atan2(d.x, d.z)

func _in_building(p: Vector3) -> bool:
	return p.x >= BLDG_MIN.x and p.x <= BLDG_MAX.x \
	   and p.z >= BLDG_MIN.z and p.z <= BLDG_MAX.z

func _process(delta: float) -> void:
	if current_wp >= waypoints.size():
		game.deliver_supplies(100)
		queue_free()
		return

	var target := waypoints[current_wp]
	var desired_yaw := _yaw_to(position, target)
	yaw = lerp_angle(yaw, desired_yaw, TURN_LERP)
	rotation.y = yaw

	var frame_delta := position - prev_pos
	prev_pos = position
	velocity = frame_delta / max(delta, 0.0001)

	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var next_pos := position + forward * SPEED * delta

	if _in_building(next_pos):
		position = target
		current_wp += 1
		if current_wp >= waypoints.size():
			game.deliver_supplies(100)
			queue_free()
		return

	position = next_pos

	var forward_speed: float = velocity.dot(forward)
	var target_pitch: float = clampf(forward_speed * 0.4, -PITCH_MAX, PITCH_MAX)
	pitch = lerpf(pitch, target_pitch, delta * PITCH_ACCEL)
	body.rotation.x = deg_to_rad(pitch)

	bob_time += delta * 14.0
	body.position.y = sin(bob_time) * 0.02

	for wheel in wheels:
		wheel.rotation.x += delta * (SPEED * 2.5)

	if position.distance_to(target) < ARRIVE_RADIUS:
		current_wp += 1
