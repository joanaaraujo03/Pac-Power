extends Sprite2D
class_name BodySprite

@onready var animation_player = $"../AnimationPlayer"
var starting_texture: Texture2D

func _ready():
	move()

func move():
	texture = starting_texture
	self.modulate = (get_parent() as Ghost).color
	animation_player.play("moving")

func run_away():
	# Pac-Man scared color (soft blue). Adjust if you prefer.
	self.modulate = Color(0.30, 0.60, 1.00)
	animation_player.play("running_away")

func start_blinking():
	# In AnimationPlayer, make "blinking" alternate modulate between blue and white
	animation_player.play("blinking")
