extends Camera3D

# Orbit state
var yaw: float = 0.0
var pitch: float = -32.0
var distance: float = 60.0
var focus_point: Vector3 = Vector3(0, 0, 0)

# Limits
const PITCH_MIN := -85.0
const PITCH_MAX := 5.0
const DIST_MIN := 15.0
const DIST_MAX := 120.0
const ZOOM_STEP := 4.0
const ORBIT_SPEED := 0.3
const PAN_SPEED := 0.05

# Mouse drag state
var _dragging: bool = false

func _ready() -> void:
	_apply_transform()

func _unhandled_input(event: InputEvent) -> void:
	# Right mouse button drag = orbit
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _dragging else Input.MOUSE_MODE_VISIBLE)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance - ZOOM_STEP, DIST_MIN, DIST_MAX)
			_apply_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance + ZOOM_STEP, DIST_MIN, DIST_MAX)
			_apply_transform()

	# Mouse motion while dragging = orbit
	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * ORBIT_SPEED
		pitch = clampf(pitch - mm.relative.y * ORBIT_SPEED, PITCH_MIN, PITCH_MAX)
		_apply_transform()

	# Keyboard
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_R:
				yaw = 0.0
				pitch = -32.0
				distance = 60.0
				focus_point = Vector3(0, 0, 0)
				_apply_transform()
			KEY_SPACE:
				# Snap to strict top-down
				pitch = -89.0
				_apply_transform()
			KEY_TAB:
				# Notify Game.gd to toggle the roof visibility
				var game := get_parent()
				if game != null and game.has_method("toggle_roof"):
					game.toggle_roof()

func _process(delta: float) -> void:
	# WASD pan (moves focus point in the camera's horizontal plane)
	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): pan.z -= 1
	if Input.is_key_pressed(KEY_S): pan.z += 1
	if Input.is_key_pressed(KEY_A): pan.x -= 1
	if Input.is_key_pressed(KEY_D): pan.x += 1

	if pan.length_squared() > 0.0:
		# Move in world X/Z, rotated by current yaw so W is "away from camera"
		var yaw_rad := deg_to_rad(yaw)
		var forward := Vector3(-sin(yaw_rad), 0, -cos(yaw_rad))
		var right := Vector3(cos(yaw_rad), 0, -sin(yaw_rad))
		var move := (forward * -pan.z + right * pan.x) * PAN_SPEED * distance * delta
		focus_point += move
		_apply_transform()

func _apply_transform() -> void:
	var pitch_rad := deg_to_rad(pitch)
	var yaw_rad := deg_to_rad(yaw)

	# Spherical offset from focus point
	var offset := Vector3(
		cos(pitch_rad) * sin(yaw_rad) * distance,
		-sin(pitch_rad) * distance,
		cos(pitch_rad) * cos(yaw_rad) * distance
	)
	position = focus_point + offset
	look_at(focus_point, Vector3.UP)