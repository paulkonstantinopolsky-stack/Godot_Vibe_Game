extends Node3D

@export var door_left: Node3D
@export var door_right: Node3D

var confetti: CPUParticles3D

func _ready() -> void:
	_setup_confetti_particles()

func open_doors() -> void:
	if confetti:
		var cam = get_viewport().get_camera_3d()
		if cam:
			var dir_to_cam: Vector3 = confetti.global_position.direction_to(cam.global_position)
			dir_to_cam.y += 0.3
			dir_to_cam = dir_to_cam.normalized()
			confetti.direction = confetti.global_transform.basis.inverse() * dir_to_cam

		confetti.emitting = true

	if door_left and door_right:
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(door_left, "rotation_degrees:y", -100.0, 0.5)
		tw.tween_property(door_right, "rotation_degrees:y", 100.0, 0.5)
		tw.chain().tween_callback(_unlock_coin)

func _unlock_coin() -> void:
	for child in get_children():
		if child.has_method("unlock"):
			child.unlock()

func _setup_confetti_particles() -> void:
	confetti = CPUParticles3D.new()
	add_child(confetti)

	confetti.position = Vector3(0, -0.1, 0.2)
	confetti.emitting = false
	confetti.amount = 120
	confetti.lifetime = 1.5
	confetti.one_shot = true
	confetti.explosiveness = 0.95
	confetti.local_coords = false

	# Внешний вид: сочные и плотные кусочки конфетти
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.14)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true

	mesh.material = mat
	confetti.mesh = mesh

	confetti.spread = 50.0
	confetti.initial_velocity_min = 6.0
	confetti.initial_velocity_max = 12.0
	confetti.damping_min = 3.0
	confetti.damping_max = 6.0

	confetti.angle_min = 0.0
	confetti.angle_max = 360.0
	confetti.angular_velocity_min = -300.0
	confetti.angular_velocity_max = 300.0

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.7, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	confetti.scale_amount_curve = scale_curve

	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 0.2, 0.2))
	grad.add_point(0.33, Color(0.2, 1.0, 0.2))
	grad.add_point(0.66, Color(0.2, 0.5, 1.0))
	grad.add_point(1.0, Color(1.0, 0.8, 0.2))
	confetti.color_initial_ramp = grad

func close_doors_magic() -> void:
	if door_left and door_right:
		var tw = create_tween().bind_node(self).set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(door_left, "rotation_degrees:y", 0.0, 0.4)
		tw.tween_property(door_right, "rotation_degrees:y", 0.0, 0.4)
