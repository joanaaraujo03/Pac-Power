extends Node2D
class_name PowerFoodSpawner

@export var maze: MazeTileMap
@export var power_food_scene: PackedScene
@export var player: Node2D
@export var points_manager: PointsManager   # <-- NEW: drag your PointsManager here in the editor

@export var spawn_every_min: float = 8.0
@export var spawn_every_max: float = 12.0
@export var max_concurrent: int = 3
@export var lifetime_sec: float = 12.0
@export var min_distance_from_player: float = 80.0
@export var min_distance_between_fruits: float = 64.0
@export var allowed_fruits: Array[String] = [
	"fruit_apple",
	"fruit_orange",
	"fruit_melon"
]
@export var fruit_scale: float = 1.5

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _timer: Timer
var _active: Array[Area2D] = []
var _lifetimers: Dictionary = {}

func _ready() -> void:
	if maze == null or power_food_scene == null:
		push_error("PowerFoodSpawner: liga 'maze' e 'power_food_scene' no Inspetor.")
		return
	_rng.randomize()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)
	_schedule_next()

func _schedule_next(delay: float = -1.0) -> void:
	var d: float = delay
	if d < 0.0:
		d = _rng.randf_range(spawn_every_min, spawn_every_max)
	_timer.start(d)

func _on_timer_timeout() -> void:
	if _active.size() < max_concurrent:
		if _try_spawn():
			_schedule_next()
		else:
			_schedule_next(0.5)
	else:
		_schedule_next()

func _try_spawn() -> bool:
	var fruit_type: String = allowed_fruits[_rng.randi_range(0, allowed_fruits.size() - 1)]

	var world_pos: Vector2 = Vector2.ZERO
	var ok: bool = false
	for i in 8:
		world_pos = maze.get_random_empty_cell_position()
		if _is_valid_spawn_position(world_pos):
			ok = true
			break
	if not ok:
		return false

	var inst: Node = power_food_scene.instantiate()

	# set fruit type before _ready()
	if "fruit_type" in inst:
		inst.fruit_type = fruit_type

	# ✅ wire PointsManager
	if "points_manager" in inst and points_manager:
		inst.points_manager = points_manager

	if inst is Area2D:
		var pf: Area2D = inst as Area2D
		pf.position = world_pos
		pf.scale = Vector2.ONE * fruit_scale

		if pf.has_signal("pellet_eaten"):
			pf.connect("pellet_eaten", Callable(self, "_on_pellet_eaten").bind(pf))

		pf.tree_exited.connect(func() -> void:
			_active.erase(pf)
			if _lifetimers.has(pf):
				var t: Timer = _lifetimers[pf]
				if is_instance_valid(t):
					t.stop()
					t.queue_free()
				_lifetimers.erase(pf)
		)

		add_child(pf)
		_active.append(pf)

		if lifetime_sec > 0.0:
			var lt: Timer = Timer.new()
			lt.one_shot = true
			lt.timeout.connect(func() -> void:
				if is_instance_valid(pf) and pf.is_inside_tree():
					pf.queue_free()
			)
			_lifetimers[pf] = lt
			add_child(lt)
			lt.start(lifetime_sec)

		return true

	return false

func _is_valid_spawn_position(p: Vector2) -> bool:
	if is_instance_valid(player) and player.is_inside_tree():
		if player.global_position.distance_to(p) < min_distance_from_player:
			return false
	for f in _active:
		if is_instance_valid(f):
			if f.global_position.distance_to(p) < min_distance_between_fruits:
				return false
	return true

func _on_pellet_eaten(_allow_eat: bool, pf: Area2D) -> void:
	if _active.has(pf):
		_active.erase(pf)
	if _lifetimers.has(pf):
		var t: Timer = _lifetimers[pf]
		if is_instance_valid(t):
			t.stop()
			t.queue_free()
		_lifetimers.erase(pf)
	_schedule_next(0.75)
