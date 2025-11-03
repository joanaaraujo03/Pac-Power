extends Node
class_name Main

@onready var ui: UI = $UI

func _ready() -> void:
	# Pause the world; UI runs because UI.gd uses PROCESS_MODE_ALWAYS
	get_tree().paused = true
	if ui and !ui.start_pressed.is_connected(_on_start_pressed):
		ui.start_pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	get_tree().paused = false
