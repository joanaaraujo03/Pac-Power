extends CharacterBody2D
class_name Player

signal player_died(life: int)
signal started_moving

var base_speed: float = 120.0
var speed_boost_active: bool = false
var shield_active: bool = false
var phase_active: bool = false
var power_timer: Timer
var _mask_original: int

const SHIELD_AURA := preload("res://Assets/Power/shield_aura.png")

var next_movement_direction := Vector2.ZERO
var movement_direction := Vector2.ZERO
var shape_query := PhysicsShapeQueryParameters2D.new()

var _shield_t: float = 0.0

@export var shield_aura_scale: float = 0.04
@export var shield_aura_alpha: float = 1
@export var shield_pulse_speed: float = 2.0
@export var shield_pulse_amount: float = 0.15
@export var shield_pulse_alpha: float = 0.15
@export var speed: float = 300.0
@export var start_position: Node2D
@export var pacman_death_sound_player: AudioStreamPlayer2D
@export var pellets_manager: PelletsManager
@export var lifes: int = 2
@export var ui: UI

@export var walls_layer_index: int = 2
@export var maze: MazeTileMap
@export var phase_bounds_padding: float = 8.0

@onready var direction_pointer = $DirectionPointer
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _has_started := false

# ===== FIX VARS (added) =====
var _default_collision_mask: int
var _default_modulate := Color(1, 1, 1)

func _ready():
	add_to_group("Player")
	shape_query.shape = collision_shape_2d.shape
	_sync_shape_query_mask()
	base_speed = speed

	power_timer = Timer.new()
	power_timer.one_shot = true
	add_child(power_timer)
	power_timer.timeout.connect(_on_power_timeout)

	# remember the default mask for hard-restore on death/reset (FIX)
	_default_collision_mask = collision_mask

	if ui:
		ui.set_lifes(lifes)

	reset_player()

func reset_player():
	# hard-restore collisions & clear any leftover phase tint (FIX)
	_restore_collision_after_death_or_reset()

	animation_player.play("default")
	position = start_position.position
	set_physics_process(true)
	next_movement_direction = Vector2.ZERO
	movement_direction = Vector2.ZERO
	shield_active = false
	phase_active = false
	speed_boost_active = false
	_has_started = false
	if ui:
		ui.clear_all_power_timers()
	queue_redraw()

func _physics_process(delta):
	get_input()

	if !_has_started and (next_movement_direction != Vector2.ZERO or movement_direction != Vector2.ZERO):
		_has_started = true
		started_moving.emit()

	if movement_direction == Vector2.ZERO:
		movement_direction = next_movement_direction
	if can_move_in_direction(next_movement_direction, delta):
		movement_direction = next_movement_direction

	velocity = movement_direction * speed
	move_and_slide()

	if phase_active and maze:
		global_position = maze.clamp_to_bounds(global_position, phase_bounds_padding)

func _process(delta: float) -> void:
	if ui and (speed_boost_active or shield_active or phase_active):
		ui.update_phase_time(power_timer.time_left)
	if shield_active:
		_shield_t += delta
		queue_redraw()

func get_input():
	if Input.is_action_pressed("left"):
		next_movement_direction = Vector2.LEFT
		rotation_degrees = 0
	elif Input.is_action_pressed("right"):
		next_movement_direction = Vector2.RIGHT
		rotation_degrees = 180
	elif Input.is_action_pressed("down"):
		next_movement_direction = Vector2.DOWN
		rotation_degrees = 270
	elif Input.is_action_pressed("up"):
		next_movement_direction = Vector2.UP
		rotation_degrees = 90

func can_move_in_direction(dir: Vector2, delta: float) -> bool:
	if phase_active:
		if maze:
			var next_pos := global_transform.origin + dir * speed * delta * 2.0
			if maze.is_inside_ghost_house(next_pos, 0.0):
				return false
			return maze.is_inside_bounds(next_pos, phase_bounds_padding)
		return true

	shape_query.transform = global_transform.translated(dir * speed * delta * 2.0)
	var result = get_world_2d().direct_space_state.intersect_shape(shape_query)
	return result.size() == 0

func die():
	if shield_active:
		return
	# ensure phase/walls are restored right away on death (FIX)
	_restore_collision_after_death_or_reset()

	pellets_manager.power_pellet_sound_player.stop()
	if !pacman_death_sound_player.playing:
		pacman_death_sound_player.play()
	animation_player.play("death")
	set_physics_process(false)

func _on_animation_player_animation_finished(anim_name):
	if anim_name == "death":
		lifes -= 1
		if ui:
			ui.set_lifes(lifes)
		player_died.emit(lifes)
		if lifes != 0:
			reset_player()
		else:
			position = start_position.position
			set_collision_layer_value(1, false)

# ==== Powers ====
func apply_power_food(power_type: int, duration: float, magnitude: float) -> void:
	# Only one active power — new fruit replaces the old
	_cancel_all_powers()

	# Start single countdown for the new power
	power_timer.start(duration)

	match power_type:
		PowerFood.PowerType.SPEED:
			speed = base_speed * max(0.1, magnitude)
			speed_boost_active = true
		PowerFood.PowerType.SHIELD:
			shield_active = true
			queue_redraw()
		PowerFood.PowerType.PHASE:
			_start_phase(duration)

	if ui:
		ui.update_phase_time(power_timer.time_left)
		
		
func _start_phase(duration: float) -> void:
	if phase_active:
		power_timer.start(duration)
		return
	phase_active = true
	_mask_original = collision_mask
	set_collision_mask_value(walls_layer_index, false)
	_sync_shape_query_mask()
	modulate = Color(1.0, 0.8, 0.4)

func _end_phase() -> void:
	if !phase_active:
		return
	phase_active = false
	collision_mask = _mask_original
	_sync_shape_query_mask()
	modulate = Color(1, 1, 1)

	# === Fix: se acabar dentro de parede/ghost house, reposiciona para a célula vazia mais próxima ===
	if maze:
		var p := global_position
		var needs_snap := (!maze.is_walkable_world(p) or maze.is_inside_ghost_house(p, 0.0) or !maze.is_inside_bounds(p, phase_bounds_padding))
		if needs_snap:
			var safe := maze.get_nearest_walkable_world(p, phase_bounds_padding)
			global_position = safe

func _cancel_all_powers() -> void:
	if power_timer and !power_timer.is_stopped():
		power_timer.stop()
	# reset speed boost
	if speed_boost_active:
		speed = base_speed
		speed_boost_active = false
	# reset shield
	if shield_active:
		shield_active = false
		queue_redraw()
	# end phase safely (restores mask + snaps if needed)
	if phase_active:
		_end_phase()
	# clear HUD countdown
	if ui:
		ui.clear_all_power_timers()

func _on_power_timeout() -> void:
	if ui:
		ui.show_zero_then_clear()
	if speed_boost_active:
		speed = base_speed
		speed_boost_active = false
	if shield_active:
		shield_active = false
		queue_redraw()
	if phase_active:
		_end_phase()

func _sync_shape_query_mask() -> void:
	shape_query.collision_mask = collision_mask

func _draw() -> void:
	if shield_active and SHIELD_AURA:
		var tex := SHIELD_AURA
		var base_size := tex.get_size() * shield_aura_scale
		var s := sin(TAU * shield_pulse_speed * _shield_t)
		var scale_factor := 1.0 + shield_pulse_amount * s
		var size := base_size * scale_factor
		var alpha := clampf(shield_aura_alpha + shield_pulse_alpha * s, 0.0, 1.0)
		var rect := Rect2(-size * 0.5, size)
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, alpha))

func has_started_moving() -> bool:
	return _has_started


func _restore_collision_after_death_or_reset() -> void:
	# Always restore default mask and wall collisions
	collision_mask = _default_collision_mask
	set_collision_mask_value(walls_layer_index, true)
	_sync_shape_query_mask()
	# Clear any leftover phase/tint flags
	phase_active = false
	modulate = _default_modulate
