# MazeTileMap.gd
extends TileMap
class_name MazeTileMap

var empty_cells: Array = []
var world_bounds := Rect2()

@export var ghost_house_rect: Rect2 = Rect2(Vector2(0, 0), Vector2(64, 64))

func _ready():
	var cells = get_used_cells(0)
	for cell in cells:
		var data = get_cell_tile_data(0, cell)
		if data and data.get_custom_data("isEmpty"):
			empty_cells.push_front(cell)
	var used_rect: Rect2i = get_used_rect()
	var tl := to_global(map_to_local(used_rect.position))
	var br := to_global(map_to_local(used_rect.position + used_rect.size))
	world_bounds = Rect2(tl, br - tl)

func get_random_empty_cell_position() -> Vector2:
	return _cell_to_world(empty_cells.pick_random())

func _cell_to_world(cell: Vector2i) -> Vector2:
	return to_global(map_to_local(cell))

func is_inside_bounds(p: Vector2, padding: float = 0.0) -> bool:
	var r := world_bounds.grow(-padding)
	return r.has_point(p)

func clamp_to_bounds(p: Vector2, padding: float = 0.0) -> Vector2:
	var r := world_bounds.grow(-padding)
	return Vector2(
		clampf(p.x, r.position.x, r.position.x + r.size.x),
		clampf(p.y, r.position.y, r.position.y + r.size.y)
	)

func is_inside_ghost_house(p: Vector2, padding: float = 0.0) -> bool:
	var r := ghost_house_rect.grow(-padding)
	return r.has_point(p)

# ===== Helpers para walkability =====
func _world_to_cell(p: Vector2) -> Vector2i:
	var local := to_local(p)
	return local_to_map(local)

func is_walkable_world(p: Vector2) -> bool:
	var cell := _world_to_cell(p)
	var data := get_cell_tile_data(0, cell)
	return data != null and data.get_custom_data("isEmpty") == true and !is_inside_ghost_house(p, 0.0)

func get_nearest_walkable_world(p: Vector2, padding: float = 0.0) -> Vector2:
	# procura célula vazia mais próxima dentro dos limites e fora da ghost house
	var best_pos := clamp_to_bounds(p, padding)
	var best_d := INF
	for cell in empty_cells:
		var wp := _cell_to_world(cell)
		if !is_inside_bounds(wp, padding): continue
		if is_inside_ghost_house(wp, 0.0): continue
		var d := p.distance_to(wp)
		if d < best_d:
			best_d = d
			best_pos = wp
	return best_pos
