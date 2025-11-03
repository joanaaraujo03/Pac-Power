extends Area2D
class_name PowerFood

signal pellet_eaten(should_allow_eating_ghosts: bool)

enum PowerType { SPEED, SHIELD, PHASE }

@export var fruit_type: String = "fruit_apple"
@export var duration: float = 6.0
@export var magnitude: float = 1.5
@export var score_value: int = 50

@export var points_manager: PointsManager   # <-- set by spawner

@onready var sprite: Sprite2D = $Sprite2D
var power_type: PowerType = PowerType.SPEED

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	_set_fruit_visual()

func _set_fruit_visual() -> void:
	var texture_path := ""
	match fruit_type:
		"fruit_apple":
			texture_path = "res://Assets/Fruits/Fruit_apple.png"
			power_type = PowerType.SPEED
		"fruit_melon":
			texture_path = "res://Assets/Fruits/Fruit_Melon.png"
			power_type = PowerType.SHIELD
		"fruit_orange":
			texture_path = "res://Assets/Fruits/Fruit_Orange.png"
			power_type = PowerType.PHASE

	if ResourceLoader.exists(texture_path):
		sprite.texture = load(texture_path)
	else:
		push_warning("Textura não encontrada: %s" % texture_path)

func _on_body_entered(body: Node) -> void:
	if body is Player and body.has_method("apply_power_food"):
		# doesn't trigger ghost frightened mode
		emit_signal("pellet_eaten", false)
		(body as Player).apply_power_food(power_type, duration, magnitude)

		# ✅ Add fruit points
		if points_manager:
			points_manager.add_fruit_points(score_value)

		queue_free()
