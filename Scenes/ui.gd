extends CanvasLayer
class_name UI

signal start_pressed

@onready var center_container: Control = $MarginContainer/CenterContainer
@onready var life_count_label: Label   = %LifeCountLabel
@onready var game_score_label: Label   = %GameScoreLabel
@onready var game_label: Label         = %GameLabel

const PAC_YELLOW  := Color("#ffcc00")
const MAZE_BLUE   := Color("#0037ff")
const INKY_CYAN   := Color("#00ffff")
const PANEL_BG    := Color(0, 0, 0, 0.75)
const FONT_PATH   := "res://Assets/Fonts/upheavtt.ttf"

var _game_font: FontFile
var _power_label: Label
var _phase_secs_left: float = 0.0

var _menu_root: PanelContainer
var _menu_btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_fonts()
	_build_start_menu()
	show_start_menu()
	await get_tree().process_frame
	_create_power_countdown_label()

# ======= Fonts =======
func _load_fonts() -> void:
	_game_font = load(FONT_PATH)
	if _game_font == null:
		push_warning("⚠️ Font not found at: %s" % FONT_PATH)

# ======= Menu =======
func _build_start_menu() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var panel_w: float = clampf(vp.x * 0.62, 520.0, 860.0)
	var panel_h: float = clampf(vp.y * 0.74, 360.0, 720.0)

	_menu_root = PanelContainer.new()
	add_child(_menu_root)
	var root := _menu_root as Control
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -panel_w * 0.5
	root.offset_right =  panel_w * 0.5
	root.offset_top =   -panel_h * 0.5
	root.offset_bottom = panel_h * 0.5

	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = MAZE_BLUE
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	_menu_root.add_theme_stylebox_override("panel", sb)

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_root.add_child(sc)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 16)
	sc.add_child(vb)

	var title := Label.new()
	title.text = "PAC-POWERS & RULES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", PAC_YELLOW)
	title.add_theme_color_override("font_outline_color", Color(0,0,0,0.9))
	title.add_theme_constant_override("outline_size", 4)
	if _game_font:
		title.add_theme_font_override("font", _game_font)
		title.add_theme_font_size_override("font_size", 26)
	vb.add_child(title)

	var line_top := ColorRect.new()
	line_top.color = MAZE_BLUE
	line_top.custom_minimum_size = Vector2(0, 3)
	vb.add_child(line_top)

	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)

	var rules_header := _menu_header("HOW TO PLAY")
	left.add_child(rules_header)

	var rules := RichTextLabel.new()
	rules.fit_content = true
	rules.scroll_active = false
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD
	rules.bbcode_enabled = true
	rules.parse_bbcode("""
Just like in the classic Pac-Man — eat all pellets to win and avoid the ghosts!

But now you also have [color=#ffcc00]power fruits[/color] that grant temporary abilities.
Use them strategically to survive and outsmart the ghosts!
""")
	rules.add_theme_color_override("default_color", Color.WHITE)
	if _game_font:
		rules.add_theme_font_override("normal_font", _game_font)
		rules.add_theme_font_size_override("normal_font_size", 18)
	left.add_child(rules)

	var fruits_header := _menu_header("POWER FRUITS (6s EACH)")
	right.add_child(fruits_header)

	var fruits := RichTextLabel.new()
	fruits.fit_content = true
	fruits.scroll_active = false
	fruits.autowrap_mode = TextServer.AUTOWRAP_WORD
	fruits.bbcode_enabled = true
	fruits.parse_bbcode("""
• [color=#ff6666]Apple[/color] — Speed boost
• [color=#ffaa33]Orange[/color] — Pass through walls
• [color=#33ff77]Melon[/color] — Protective shield
""")

	# --- Single-power rule note under the fruit list ---
	var one_power_note := RichTextLabel.new()
	one_power_note.fit_content = true
	one_power_note.scroll_active = false
	one_power_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	one_power_note.bbcode_enabled = true
	one_power_note.parse_bbcode("[i]Only one fruit power can be active at a time — picking a new fruit replaces the current one.[/i]")
	# styling
	one_power_note.add_theme_color_override("default_color", Color(1, 1, 1, 0.85))
	if _game_font:
		one_power_note.add_theme_font_override("normal_font", _game_font)
		one_power_note.add_theme_font_size_override("normal_font_size", 16)
	right.add_child(one_power_note)
	
	fruits.add_theme_color_override("default_color", Color.WHITE)
	if _game_font:
		fruits.add_theme_font_override("normal_font", _game_font)
		fruits.add_theme_font_size_override("normal_font_size", 18)
	right.add_child(fruits)

	var line_mid := ColorRect.new()
	line_mid.color = MAZE_BLUE
	line_mid.custom_minimum_size = Vector2(0, 3)
	vb.add_child(line_mid)

	var hint := Label.new()
	hint.text = "Press ENTER or SPACE to start"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1,1,1,0.75))
	if _game_font:
		hint.add_theme_font_override("font", _game_font)
		hint.add_theme_font_size_override("font_size", 16)
	vb.add_child(hint)

	_menu_btn = Button.new()
	_menu_btn.text = "START"
	_menu_btn.focus_mode = Control.FOCUS_NONE
	_menu_btn.custom_minimum_size = Vector2(panel_w * 0.5, 44)
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if _game_font:
		_menu_btn.add_theme_font_override("font", _game_font)
		_menu_btn.add_theme_font_size_override("font_size", 22)
	var bs := StyleBoxFlat.new()
	bs.bg_color = PAC_YELLOW
	bs.corner_radius_top_left = 8
	bs.corner_radius_top_right = 8
	bs.corner_radius_bottom_left = 8
	bs.corner_radius_bottom_right = 8
	bs.content_margin_left = 10
	bs.content_margin_right = 10
	bs.content_margin_top = 8
	bs.content_margin_bottom = 8
	_menu_btn.add_theme_stylebox_override("normal", bs)
	var bs_h := bs.duplicate() as StyleBoxFlat
	bs_h.bg_color = PAC_YELLOW.lerp(INKY_CYAN, 0.15)
	_menu_btn.add_theme_stylebox_override("hover", bs_h)
	_menu_btn.pressed.connect(_on_start_pressed)
	vb.add_child(_menu_btn)

	var line_bot := ColorRect.new()
	line_bot.color = Color(1,1,1,0.08)
	line_bot.custom_minimum_size = Vector2(0, 2)
	vb.add_child(line_bot)

func _menu_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", PAC_YELLOW)
	lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	if _game_font:
		lbl.add_theme_font_override("font", _game_font)
		lbl.add_theme_font_size_override("font_size", 20)
	return lbl

func show_start_menu() -> void:
	if _menu_root:
		_menu_root.visible = true

func hide_start_menu() -> void:
	if _menu_root:
		_menu_root.visible = false

func _on_start_pressed() -> void:
	hide_start_menu()
	start_pressed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if _menu_root and _menu_root.visible:
		if event.is_action_pressed("ui_accept") or (event is InputEventKey and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)):
			_on_start_pressed()

# ======= HUD =======
func set_lifes(lifes: int) -> void:
	life_count_label.text = "%d up" % lifes
	if lifes == 0:
		game_lost()

func set_score(score: int) -> void: 
	game_score_label.text = "SCORE: %d" % score

func game_lost() -> void:
	game_label.text = "Game lost"
	center_container.show()
	clear_all_power_timers()
	get_tree().paused = true

func game_won() -> void:
	game_label.text = "Game won"
	center_container.show()
	clear_all_power_timers()
	get_tree().paused = true 

# ======= Countdown label =======
func _create_power_countdown_label() -> void:
	_power_label = Label.new()
	_power_label.text = ""
	_power_label.visible = false

	var parent := game_score_label.get_parent()
	if parent == null:
		parent = self
	parent.add_child(_power_label)

	_power_label.position = game_score_label.position + Vector2(0, 22)

	if _game_font:
		_power_label.add_theme_font_override("font", _game_font)
		var score_sz := game_score_label.get_theme_font_size("font_size")
		_power_label.add_theme_font_size_override("font_size", score_sz if score_sz > 0 else 26)
	_power_label.add_theme_color_override("font_color", game_score_label.get_theme_color("font_color"))
	_power_label.add_theme_color_override("font_outline_color", game_score_label.get_theme_color("font_outline_color") if game_score_label.has_theme_color("font_outline_color") else Color(0,0,0,0.9))
	_power_label.add_theme_constant_override("outline_size", game_score_label.get_theme_constant("outline_size") if game_score_label.has_theme_constant("outline_size") else 3)

func update_phase_time(remaining_secs: float) -> void:
	_phase_secs_left = max(0.0, remaining_secs)
	if _phase_secs_left <= 0.05:
		_power_label.visible = false
		_power_label.text = ""
		return
	var secs := int(ceil(_phase_secs_left))
	_power_label.text = str(secs)
	_power_label.visible = true

func show_zero_then_clear() -> void:
	_power_label.text = "0"
	_power_label.visible = true
	await get_tree().process_frame
	_power_label.visible = false
	_power_label.text = ""

func clear_all_power_timers() -> void:
	_phase_secs_left = 0.0
	if _power_label:
		_power_label.visible = false
		_power_label.text = ""
