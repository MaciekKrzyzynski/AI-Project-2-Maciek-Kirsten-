extends Node3D

var game: Node = null
var wheels: Array[Node3D] = []
const SPEED := 14.0
const TURN_LERP := 0.15
const PITCH_ACCEL := 8.0
const PITCH_MAX := 4.0
const ARRIVE_RADIUS := 1.5

var body: Node3D
var velocity: Vector3 = Vector3.ZERO
var prev_pos: Vector3 = Vector3.ZERO
var pitch: float = 0.0
var bob_time: float = 0.0
var yaw: float = 0.0

var waypoints: Array[Vector3] = []
var current_wp: int = 1
var cargo: Dictionary = {}

func configure(p_game: Node, p_cargo: Dictionary) -> void:
	game = p_game
	cargo = p_cargo

func _ready() -> void:
	waypoints = [
		Vector3(-60.0, 0.16, -70.0), Vector3(0.0, 0.16, -70.0),
		Vector3(0.0, 0.16, -50.0),   Vector3(0.0, 0.16, -34.0),
	]
	current_wp = 1
	position = waypoints[0]
	prev_pos = position
	yaw = _yaw_to(position, waypoints[current_wp])
	rotation.y = yaw
	body = Node3D.new(); body.name = "Body"; add_child(body)
	_build_truck()

func _build_truck() -> void:
	_add_box(Vector3(2.5, 2.6, 6.0), Vector3(0, 1.5, 0), Color(0.85, 0.85, 0.9), "Trailer")
	_add_box(Vector3(2.55, 1.2, 3.0), Vector3(0, 1.4, 0), Color(0.85, 0.1, 0.1), "TrailerStripe")
	_add_box(Vector3(2.4, 1.9, 2.0), Vector3(0, 1.1, 3.8), Color(0.15, 0.15, 0.18), "Cab")
	_add_box(Vector3(2.1, 0.7, 0.08), Vector3(0, 1.6, 4.85), Color(0.35, 0.55, 0.7), "Windshield")
	for wp in [Vector3(-1.3, 0.48, 2.0), Vector3(1.3, 0.48, 2.0),
			   Vector3(-1.3, 0.48, -2.0), Vector3(1.3, 0.48, -2.0)]:
		var pivot := Node3D.new(); pivot.position = wp; body.add_child(pivot)
		var w := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.475; cyl.bottom_radius = 0.475; cyl.height = 0.5
		w.mesh = cyl; w.rotation.z = deg_to_rad(90)
		var m := StandardMaterial3D.new(); m.albedo_color = Color(0.05, 0.05, 0.05)
		w.material_override = m; pivot.add_child(w); wheels.append(pivot)

func _add_box(size: Vector3, pos: Vector3, col: Color, node_name: String = "Box") -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = node_name
	var box := BoxMesh.new(); box.size = size
	mi.mesh = box; mi.position = pos
	var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 0.85
	mi.material_override = m; body.add_child(mi); return mi

func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from; d.y = 0
	if d.length_squared() < 0.0001: return yaw
	return atan2(d.x, d.z)

func _process(delta: float) -> void:
	if current_wp >= waypoints.size():
		game.deliver_supplies(cargo); queue_free(); return
	var target := waypoints[current_wp]
	yaw = lerp_angle(yaw, _yaw_to(position, target), TURN_LERP)
	rotation.y = yaw
	var fd := position - prev_pos
	prev_pos = position
	velocity = fd / max(delta, 0.0001)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	position += fwd * SPEED * delta
	var fs: float = velocity.dot(fwd)
	pitch = lerpf(pitch, clampf(fs * 0.4, -PITCH_MAX, PITCH_MAX), delta * PITCH_ACCEL)
	body.rotation.x = deg_to_rad(pitch)
	bob_time += delta * 14.0
	body.position.y = sin(bob_time) * 0.02
	for wheel in wheels: wheel.rotation.x += delta * (SPEED * 2.5)
	if position.distance_to(target) < ARRIVE_RADIUS: current_wp += 1
