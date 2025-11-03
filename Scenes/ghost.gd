extends Area2D
class_name Ghost

enum GhostState { SCATTER, CHASE, RUN_AWAY, EATEN, STARTING_AT_HOME, FRIGHTENED}
enum GhostType  { BLINKY, PINKY, INKY, CLYDE }

signal direction_change(current_direction: String)
signal run_away_timeout




# ===== Config / references =====
@export var ghost_type: GhostType = GhostType.BLINKY
@export var player: Player
@export var blinky_ref: Node2D                 # only used by INKY

# Chase diversity knobs
@export var tiles_ahead: int = 4               # Pinky/inky offset base (~4 tiles)
@export var clyde_distance_threshold: float = 112.0
@export var target_jitter_px: float = 10.0     # small random wobble on targets
@export var lateral_offset_px: float = -1.0    # -1 = auto by type; otherwise fixed px

# Speed / base
@export var scatter_wait_time: float = 8.0
@export var eaten_speed: float = 240.0
@export var speed: float = 120.0
@export var movement_targets: TargetsData
@export var tile_map: MazeTileMap
@export var color: Color
@export var chasing_target: Node2D
@export var points_manager: PointsManager
@export var is_starting_at_home: bool = false
@export var starting_position: Node2D
@export var ghost_eaten_sound_player: AudioStreamPlayer2D
@export var starting_texture: Texture2D

# Home / release pacing
@export var entry_delay: float = 0.0
@export var home_delay_on_level_start: float = 0.2
@export var home_delay_on_player_move: float = 0.05
@export var release_on_first_input: bool = true
@export var at_home_speed_multiplier: float = 1.25

# ===== Diversity & anti-bunching =====
@export var anti_bunch_radius: float = 64.0     # push targets apart within this radius
@export var anti_bunch_push: float = 14.0       # push strength
@export var extra_target_jitter_px: float = 4.0 # extra noise on top of target_jitter_px
@export_range(0.9, 1.1, 0.01) var speed_variation: float = 1.0  # tiny per-ghost speed diff

# ===== Lane split (queue buster) =====
@export var lane_split_px: float = 16.0         # lateral offset towards a personal "lane"
var _lane_sign := 1.0                           # +1 / -1 per ghost

# children
@onready var at_home_timer: Timer = $AtHomeTimer
@onready var eyes_sprite: EyesSprite = $EyesSprite
@onready var body_sprite: BodySprite = $BodySprite
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D
@onready var scatter_timer: Timer = $ScatterTimer
@onready var update_chasing_target_position_timer: Timer = $UpdateChasingTargetPositionTimer
@onready var run_away_timer: Timer = $RunAwayTimer
@onready var points_label: Label = $PointsLabel


# state
var current_scatter_index: int = 0
var current_at_home_index: int = 0
var direction: String = ""
var current_state: GhostState = GhostState.SCATTER
var is_blinking: bool = false

var scatter_nodes: Array[Node2D] = []
var at_home_nodes: Array[Node2D] = []

# scatter/chase schedule (sec)
var scatter_chase_pattern = [7.0, 20.0, 7.0, 20.0, 5.0, 20.0, 5.0, INF]
var scatter_chase_index = 0
var mode_timer: Timer

# anti-stuck
var _last_pos: Vector2
var _stuck_time := 0.0
const STUCK_SPEED_EPS := 2.0
const STUCK_TIMEOUT := 0.75

# collision cooldown (fix for "ghosts stop / don't eat later")
var _player_collision_cooldown: Timer
const PLAYER_LAYER_INDEX := 1



func _ready() -> void:
	add_to_group("Ghost")  # for anti-bunching queries

	# desync timers so they don’t mirror each other
	var desync := randf_range(0.0, 0.22)
	scatter_timer.wait_time = scatter_wait_time + desync
	update_chasing_target_position_timer.wait_time = randf_range(0.07, 0.14) + desync

	at_home_timer.timeout.connect(_leave_home_and_scatter)
	navigation_agent_2d.path_desired_distance = 2.5
	navigation_agent_2d.target_desired_distance = 2.5

	# --- Queue busting: local avoidance (RVO) ---
	navigation_agent_2d.avoidance_enabled = true
	navigation_agent_2d.avoidance_layers = 1
	navigation_agent_2d.avoidance_mask = 1
	navigation_agent_2d.radius = 7.0
	navigation_agent_2d.neighbor_distance = 72.0
	navigation_agent_2d.max_neighbors = 8
	navigation_agent_2d.time_horizon = 0.6

	navigation_agent_2d.target_reached.connect(on_position_reached)
	body_sprite.starting_texture = starting_texture

	mode_timer = Timer.new()
	mode_timer.one_shot = true
	add_child(mode_timer)
	mode_timer.timeout.connect(_on_mode_timer_timeout)

	# collision cooldown timer
	_player_collision_cooldown = Timer.new()
	_player_collision_cooldown.one_shot = true
	_player_collision_cooldown.wait_time = 0.35
	_player_collision_cooldown.timeout.connect(_enable_player_collision)
	add_child(_player_collision_cooldown)

	# tiny per-ghost variations so they don't sync perfectly
	speed *= randf_range(0.97, 1.03)
	eaten_speed *= randf_range(0.97, 1.03)
	speed_variation = randf_range(0.96, 1.04)
	update_chasing_target_position_timer.wait_time *= randf_range(0.9, 1.1)

	# Deterministic lane side by type (keeps ghost identity)
	match ghost_type:
		GhostType.BLINKY: _lane_sign = +1.0
		GhostType.PINKY:  _lane_sign = -1.0
		GhostType.INKY:   _lane_sign = +1.0
		GhostType.CLYDE:  _lane_sign = -1.0

	_last_pos = global_position
	call_deferred("setup")

	# listen to "first try to move"
	var p: Node = player if player else get_tree().get_first_node_in_group("Player")
	if p and p.has_signal("started_moving"):
		p.connect("started_moving", Callable(self, "_on_player_started_moving"))

	# optional global delay before any release (kept for level pacing)
	await get_tree().create_timer(entry_delay).timeout
	if is_starting_at_home and at_home_timer.time_left == 0.0 and !release_on_first_input:
		_on_player_started_moving()

func _nudge_replan() -> void:
	# Sem caminho ou praticamente sem movimento? Replaneia um alvo.
	var no_path := navigation_agent_2d.get_current_navigation_path().is_empty()
	var barely_moved := (global_position - _last_pos).length() < 1.0
	if no_path or barely_moved:
		_replan_target()
		
func _process(delta: float) -> void:
	_ensure_nav_map_bound()
	if !run_away_timer.is_stopped() and run_away_timer.time_left < run_away_timer.wait_time * 0.5 and !is_blinking:
		start_blinking()

	_move_with_agent(delta)
	_watchdog(delta)

func _move_with_agent(delta: float) -> void:
	var next_position := navigation_agent_2d.get_next_path_position()
	var current_speed: float = eaten_speed if current_state == GhostState.EATEN else speed
	if current_state == GhostState.STARTING_AT_HOME:
		current_speed *= at_home_speed_multiplier
	current_speed *= speed_variation  # small individual difference
	var new_velocity: Vector2 = (next_position - global_position).normalized() * current_speed * delta
	_update_direction_from_velocity(new_velocity)
	position += new_velocity

func _update_direction_from_velocity(v: Vector2) -> void:
	var new_dir := direction
	if v.x > 0.1: new_dir = "right"
	elif v.x < -0.1: new_dir = "left"
	elif v.y > 0.1: new_dir = "down"
	elif v.y < -0.1: new_dir = "up"
	if new_dir != direction:
		direction = new_dir
		direction_change.emit(direction)

func _watchdog(delta: float) -> void:
	var moved := (global_position - _last_pos).length()
	if moved < STUCK_SPEED_EPS * delta:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = global_position

	# If path vanished or we got stuck, replan aggressively
	var needs_replan := navigation_agent_2d.get_current_navigation_path().is_empty() or _stuck_time > STUCK_TIMEOUT
	if needs_replan:
		_replan_target()
		_stuck_time = 0.0

func _replan_target() -> void:
	match current_state:
		GhostState.SCATTER:
			_scatter_next()
		GhostState.CHASE:
			_update_chase_target()
		GhostState.RUN_AWAY:
			if tile_map:
				navigation_agent_2d.target_position = tile_map.get_random_empty_cell_position()
		GhostState.EATEN:
			if at_home_nodes.size() > 0:
				navigation_agent_2d.target_position = at_home_nodes[0].position
		GhostState.STARTING_AT_HOME:
			move_to_next_home_position()
			
func _ensure_nav_map_bound() -> void:
	if tile_map == null:
		return
	var current_map := tile_map.get_navigation_map(0)
	if current_map == RID():
		return
	var agent_map := NavigationServer2D.agent_get_map(navigation_agent_2d.get_rid())
	if agent_map != current_map:
		# rebind to the fresh map + kick a replan
		navigation_agent_2d.set_navigation_map(current_map)
		NavigationServer2D.agent_set_map(navigation_agent_2d.get_rid(), current_map)
		_replan_target()
		

func setup() -> void:
	_resolve_target_paths()

	# shuffle scatter corner index so each ghost starts in a different corner
	if scatter_nodes.size() > 0:
		current_scatter_index = randi() % scatter_nodes.size()

	set_collision_mask_value(1, true)
	position = starting_position.position
	navigation_agent_2d.set_navigation_map(tile_map.get_navigation_map(0))
	NavigationServer2D.agent_set_map(navigation_agent_2d.get_rid(), tile_map.get_navigation_map(0))
	eyes_sprite.show_eyes()
	body_sprite.move()
	_ensure_nav_map_bound()

	if is_starting_at_home:
		start_at_home()
	else:
		_enter_scatter_mode()

	start_pattern_cycle()
	_last_pos = global_position
	_stuck_time = 0.0

func _resolve_target_paths() -> void:
	scatter_nodes.clear()
	at_home_nodes.clear()
	if movement_targets == null:
		push_warning("Assign a TargetsData resource to 'movement_targets'.")
		return
	for p in movement_targets.scatter_targets:
		var n := get_node_or_null(p)
		if n is Node2D: scatter_nodes.append(n)
	for p in movement_targets.at_home_targets:
		var n2 := get_node_or_null(p)
		if n2 is Node2D: at_home_nodes.append(n2)

func start_at_home() -> void:
	current_state = GhostState.STARTING_AT_HOME
	at_home_timer.stop()
	at_home_timer.wait_time = maxf(0.01, home_delay_on_level_start)
	at_home_timer.start()
	if at_home_nodes.size() > 0:
		navigation_agent_2d.target_position = at_home_nodes[current_at_home_index].position

func _leave_home_and_scatter() -> void:
	current_state = GhostState.SCATTER
	is_starting_at_home = false
	if scatter_nodes.size() > 0:
		navigation_agent_2d.target_position = scatter_nodes[current_scatter_index].position

# ===== Immediate release on first input =====
func _on_player_started_moving() -> void:
	if !release_on_first_input:
		if is_starting_at_home and at_home_timer:
			var target_delay: float = maxf(0.01, home_delay_on_player_move)
			at_home_timer.start(target_delay)
		return

	if is_starting_at_home:
		is_starting_at_home = false
		current_state = GhostState.SCATTER
		if scatter_nodes.size() > 0:
			navigation_agent_2d.target_position = scatter_nodes[current_scatter_index].position
	if mode_timer.is_stopped():
		start_pattern_cycle()
	_enter_chase_mode()

func scatter() -> void:
	current_state = GhostState.SCATTER
	if scatter_nodes.size() > 0:
		navigation_agent_2d.target_position = scatter_nodes[current_scatter_index].position

func _respawn_at_home() -> void:
	# Back to body, inside the house
	body_sprite.show()
	body_sprite.move()
	eyes_sprite.show_eyes()

	current_state = GhostState.STARTING_AT_HOME
	is_starting_at_home = true

	# small pause inside the house
	at_home_timer.stop()
	at_home_timer.wait_time = maxf(0.05, home_delay_on_level_start)
	at_home_timer.start()

	# wiggle inside house while waiting
	if at_home_nodes.size() > 0:
		global_position = at_home_nodes[0].global_position
	else:
		global_position = Vector2.ZERO	

	# wait, then leave house and resume chase
	await at_home_timer.timeout
	is_starting_at_home = false
	_enter_chase_mode()
	
func on_position_reached() -> void:
	match current_state:
		GhostState.SCATTER:
			_scatter_next()
		GhostState.CHASE:
			pass
		GhostState.RUN_AWAY:
			if tile_map:
				navigation_agent_2d.target_position = tile_map.get_random_empty_cell_position()
		GhostState.EATEN:
			_respawn_at_home()
		GhostState.STARTING_AT_HOME:
			move_to_next_home_position()

func _scatter_next() -> void:
	if scatter_nodes.size() == 0: return
	current_scatter_index = (current_scatter_index + 1) % scatter_nodes.size()
	navigation_agent_2d.target_position = scatter_nodes[current_scatter_index].position

func move_to_next_home_position() -> void:
	current_at_home_index = 1 if current_at_home_index == 0 else 0
	if at_home_nodes.size() > 0:
		navigation_agent_2d.target_position = at_home_nodes[current_at_home_index].position

# ===== Scatter/Chase schedule =====
func start_pattern_cycle():
	scatter_chase_index = 0
	_enter_scatter_mode()

func _enter_scatter_mode():
	current_state = GhostState.SCATTER
	update_chasing_target_position_timer.stop()
	if scatter_nodes.size() > 0:
		navigation_agent_2d.target_position = scatter_nodes[current_scatter_index].position
	if scatter_chase_index < scatter_chase_pattern.size():
		mode_timer.start(scatter_chase_pattern[scatter_chase_index] + randf_range(0.0, 0.35)) # desync switches
		scatter_chase_index += 1
	_enable_player_collision()   # ensure collisions are active

func _enter_chase_mode():
	current_state = GhostState.CHASE
	update_chasing_target_position_timer.wait_time = randf_range(0.07, 0.14) # per-ghost cadence
	update_chasing_target_position_timer.start()
	_update_chase_target()
	if scatter_chase_index < scatter_chase_pattern.size():
		mode_timer.start(scatter_chase_pattern[scatter_chase_index] + randf_range(0.0, 0.35))
		scatter_chase_index += 1
	_enable_player_collision()   # ensure collisions are active

func _on_mode_timer_timeout():
	if current_state == GhostState.SCATTER:
		_enter_chase_mode()
	else:
		_enter_scatter_mode()

func _on_update_chasing_target_position_timer_timeout() -> void:
	_update_chase_target()
	# desync cadence each cycle so they don't replan in lockstep
	update_chasing_target_position_timer.wait_time = randf_range(0.07, 0.16)
	update_chasing_target_position_timer.start()

# ===== Classic chase behaviors + diversity =====
func _tile_step_len() -> float:
	if tile_map and tile_map.tile_set:
		return float(tile_map.tile_set.tile_size.x)
	return 16.0

func _player_dir() -> Vector2:
	if player:
		var d := player.movement_direction
		if d == Vector2.ZERO:
			d = player.next_movement_direction
		return d.normalized()
	return Vector2.ZERO

func _auto_lateral_offset_by_type() -> float:
	match ghost_type:
		GhostType.BLINKY: return 0.0
		GhostType.PINKY:  return 8.0
		GhostType.INKY:   return -10.0
		GhostType.CLYDE:  return 16.0
	return 0.0

func _perp(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)

func _apply_lateral_offset(base_target: Vector2) -> Vector2:
	var dir := _player_dir()
	if dir == Vector2.ZERO:
		return base_target
	var lat := lateral_offset_px
	if lat < 0.0:
		lat = _auto_lateral_offset_by_type()
	return base_target + _perp(dir).normalized() * lat

func _pinky_target() -> Vector2:
	var step := _tile_step_len()
	var dir := _player_dir()
	var base := (player.global_position if player else global_position) + dir * float(max(0, tiles_ahead)) * step
	return _apply_lateral_offset(base)

func _inky_target() -> Vector2:
	var step := _tile_step_len()
	var dir := _player_dir()
	var ahead := (player.global_position if player else global_position) + dir * float(max(0, tiles_ahead)) * step
	var blinky_pos := (blinky_ref.global_position if is_instance_valid(blinky_ref) else global_position)
	var vec := ahead - blinky_pos
	var base := ahead + vec
	return _apply_lateral_offset(base)

func _clyde_target() -> Vector2:
	if !player: return _scatter_fallback()
	var dist := global_position.distance_to(player.global_position)
	if dist <= clyde_distance_threshold:
		return _scatter_fallback()
	return _apply_lateral_offset(player.global_position)

func _blinky_target() -> Vector2:
	var base := (player.global_position if player else (chasing_target.position if chasing_target else global_position))
	return _apply_lateral_offset(base)

func _scatter_fallback() -> Vector2:
	if scatter_nodes.size() > 0:
		return scatter_nodes[current_scatter_index].position
	return global_position

func _ghosts_nearby() -> Array[Ghost]:
	var list: Array = get_tree().get_nodes_in_group("Ghost")
	var out: Array[Ghost] = []
	for n in list:
		if n != self and n is Ghost and is_instance_valid(n):
			out.append(n)
	return out

func _apply_anti_bunching_to_target(tgt: Vector2) -> Vector2:
	var result := tgt
	for g in _ghosts_nearby():
		var d := global_position.distance_to(g.global_position)
		if d > 0.0 and d < anti_bunch_radius:
			var push_dir := (result - g.global_position).normalized()
			result += push_dir * (anti_bunch_push * (1.0 - d / anti_bunch_radius))
	return result

func _lane_split_offset(tgt: Vector2) -> Vector2:
	var to_tgt := (tgt - global_position)
	if to_tgt == Vector2.ZERO:
		return Vector2.ZERO
	var perp := Vector2(-to_tgt.y, to_tgt.x).normalized()
	return perp * lane_split_px * _lane_sign

func _update_chase_target() -> void:
	var tgt := Vector2.ZERO
	match ghost_type:
		GhostType.BLINKY:
			tgt = _blinky_target()
		GhostType.PINKY:
			tgt = _pinky_target()
		GhostType.INKY:
			tgt = _inky_target()
		GhostType.CLYDE:
			tgt = _clyde_target()

	# base jitter + a bit more to split paths naturally
	var jitter := target_jitter_px + extra_target_jitter_px
	if jitter > 0.0:
		tgt += Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))

	# soft anti-bunching so ghosts don't stack
	tgt = _apply_anti_bunching_to_target(tgt)

	# lane split: each ghost keeps a side around the destination
	tgt += _lane_split_offset(tgt)

	navigation_agent_2d.target_position = tgt

# ===== Run away / eaten =====
func start_chasing_pacman_after_being_eaten() -> void:
	_enter_chase_mode()
	body_sprite.show()
	body_sprite.move()

func run_away_from_pacman(duration: float = 6.0) -> void:
	# Visual de frightened (azul) e parar lógica de perseguição
	body_sprite.run_away()
	eyes_sprite.hide_eyes()

	run_away_timer.stop()
	run_away_timer.wait_time = duration
	run_away_timer.start()

	current_state = GhostState.RUN_AWAY
	update_chasing_target_position_timer.stop()
	is_blinking = false

	# Fugir para uma célula vazia aleatória
	if tile_map:
		navigation_agent_2d.target_position = tile_map.get_random_empty_cell_position()
		
func start_blinking() -> void:
	is_blinking = true
	body_sprite.start_blinking()

func _on_run_away_timer_timeout() -> void:
	run_away_timeout.emit()
	is_blinking = false
	eyes_sprite.show_eyes()
	body_sprite.move()
	_enter_chase_mode()

func get_eaten() -> void:
	ghost_eaten_sound_player.play()
	body_sprite.hide()
	eyes_sprite.show_eyes()
	points_label.show()
	# Disable collisions so Pac-Man can't hit ghost eyes
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	points_label.text = "%d" % points_manager.points_for_ghost_eaten
	await points_manager.pause_on_ghost_eaten()
	points_label.hide()
	run_away_timer.stop()
	run_away_timeout.emit()
	current_state = GhostState.EATEN
	if at_home_nodes.size() > 0:
		navigation_agent_2d.target_position = at_home_nodes[0].global_position

# ===== Player collision handling (FIX) =====
func _disable_player_collision_temporarily():
	set_collision_mask_value(PLAYER_LAYER_INDEX, false)
	if _player_collision_cooldown.is_stopped():
		_player_collision_cooldown.start()

func _enable_player_collision():
	set_collision_mask_value(PLAYER_LAYER_INDEX, true)

func _on_body_entered(body: Node) -> void:
	var pl := body as Player
	if current_state == GhostState.RUN_AWAY:
		get_eaten()
	elif current_state in [GhostState.CHASE, GhostState.SCATTER]:
		_disable_player_collision_temporarily()
		update_chasing_target_position_timer.stop()
		if pl:
			pl.die()
		scatter_timer.wait_time = 600.0
		_enter_scatter_mode()
		_replan_target()
