extends Node
class_name PointsManager

@onready var ui = $"../UI" as UI

const BASE_POINTS_FOR_GHOST_VALUE = 200
const PELLET_POINTS = 10

var points_for_ghost_eaten = BASE_POINTS_FOR_GHOST_VALUE
var points = 0

func _ready() -> void:
	# ensure UI starts at 0
	if ui:
		ui.set_score(points)

func add_points(amount: int) -> void:
	points += amount
	if ui:
		ui.set_score(points)

func add_pellet_points() -> void:
	add_points(PELLET_POINTS)

func add_fruit_points(amount: int) -> void:
	add_points(amount)

func pause_on_ghost_eaten():
	points += points_for_ghost_eaten
	get_tree().paused = true
	await get_tree().create_timer(1.0).timeout
	get_tree().paused = false

	# sequência clássica: duplica até 1600
	points_for_ghost_eaten = min(points_for_ghost_eaten * 2, 1600)

	if ui:
		ui.set_score(points)

func reset_points_for_ghosts():
	points_for_ghost_eaten = BASE_POINTS_FOR_GHOST_VALUE
