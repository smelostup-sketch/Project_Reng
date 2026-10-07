extends CanvasLayer
## P1 (ROADMAP_UI): пауза-меню и панель настроек поверх UI-кита (Q7.10).
## ESC (ui_cancel): игра -> пауза -> настройки -> назад (по уровням).
## Панель настроек строится ИЗ реестра SettingsService (data-driven).
## Звук — шина UI (sfx/ui_*.wav из кита). Курсор: captured в бою, visible в меню.

const GOLD := Color(0.941, 0.902, 0.827)      # F0E6D2
const GOLD_DIM := Color(0.784, 0.667, 0.431)  # C8AA6E

var settings: Node  # autoload SettingsService
var font_title: FontFile
var font_body: FontFile
var btn_style: StyleBoxTexture
var ui_player: AudioStreamPlayer
var sfx: Dictionary = {}

var menu_buttons_box: VBoxContainer
var settings_rows_box: VBoxContainer
var menu_panel: NinePatchRect
var settings_panel: NinePatchRect
var menu_title: Label
var settings_title: Label


func _ready() -> void:
	settings = get_node("/root/SettingsService")
	font_title = load("res://Assets/UI/fonts/PlayfairDisplay.ttf")
	font_body = load("res://Assets/UI/fonts/Inter.ttf")
	btn_style = _make_button_style()
	for name in ["ui_hover", "ui_press", "ui_confirm", "ui_back", "ui_panel_open"]:
		sfx[name] = load("res://Assets/UI/sfx/%s.wav" % name)
	ui_player = AudioStreamPlayer.new()
	ui_player.bus = "UI"
	add_child(ui_player)

	var root := get_node("Root") as Control
	menu_panel = root.get_node("MenuBG")
	settings_panel = root.get_node("SettingsBG")
	menu_title = menu_panel.get_node("Box/Title")
	settings_title = settings_panel.get_node("Box/Title")
	menu_buttons_box = menu_panel.get_node("Box/Buttons")
	settings_rows_box = settings_panel.get_node("Box/Scroll/Rows")
	for lbl in [menu_title, settings_title]:
		lbl.add_theme_font_override("font", font_title)
		lbl.add_theme_font_size_override("font_size", 44)
		lbl.add_theme_color_override("font_color", GOLD)
	_build_menu_buttons()
	root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed("ui_cancel") and not event.echo:
		var root := get_node("Root") as Control
		if not root.visible:
			open_pause()
		elif settings_panel.visible:
			show_pause_panel()
			_play("ui_back")
		else:
			resume()
		get_viewport().set_input_as_handled()


# === СОСТОЯНИЯ ===
func open_pause() -> void:
	var root := get_node("Root") as Control
	root.visible = true
	show_pause_panel()
	get_tree().paused = true
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
	_play("ui_panel_open")


func resume() -> void:
	var root := get_node("Root") as Control
	root.visible = false
	get_tree().paused = false
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_CAPTURED)
	_play("ui_confirm")


func show_pause_panel() -> void:
	menu_panel.visible = true
	settings_panel.visible = false


func open_settings() -> void:
	menu_panel.visible = false
	settings_panel.visible = true
	_rebuild_settings_rows()
	_play("ui_press")


# === ПОСТРОЕНИЕ (единый источник стилей) ===
func _make_button_style() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://Assets/UI/textures/button_tight.jpg")
	sb.texture_margin_left = 260
	sb.texture_margin_right = 260
	sb.texture_margin_top = 170
	sb.texture_margin_bottom = 170
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


func _make_button(text: String, icon_path: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 64)
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, btn_style)
	b.add_theme_font_override("font", font_body)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", GOLD_DIM)
	if icon_path != "":
		b.icon = load(icon_path)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 28)
	b.mouse_entered.connect(func() -> void: _play("ui_hover"))
	b.pressed.connect(callback)
	return b


func _build_menu_buttons() -> void:
	for child in menu_buttons_box.get_children():
		child.queue_free()
	menu_buttons_box.add_child(_make_button("Продолжить", "res://Assets/UI/icons/back.svg", resume))
	menu_buttons_box.add_child(_make_button("Настройки", "res://Assets/UI/icons/gear.svg", open_settings))
	menu_buttons_box.add_child(_make_button("Выйти", "res://Assets/UI/icons/exit.svg", func() -> void:
		_play("ui_back")
		get_tree().quit()))


func _rebuild_settings_rows() -> void:
	for child in settings_rows_box.get_children():
		child.queue_free()
	var current_section := ""
	for entry in settings.registry:
		if entry["section"] != current_section:
			current_section = entry["section"]
			var header := Label.new()
			header.text = current_section
			header.add_theme_font_override("font", font_title)
			header.add_theme_font_size_override("font_size", 26)
			header.add_theme_color_override("font_color", GOLD_DIM)
			settings_rows_box.add_child(header)
		settings_rows_box.add_child(_make_row(entry))


func _make_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.texture = load(entry["icon"])
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var label := Label.new()
	label.text = entry["label"]
	label.add_theme_font_override("font", font_body)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", GOLD)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var id: String = entry["id"]
	match int(entry["type"]):
		SettingsService.Type.FLOAT:
			var slider := HSlider.new()
			slider.min_value = entry["min"]
			slider.max_value = entry["max"]
			slider.step = entry["step"]
			slider.value = settings.get_value(id)
			slider.custom_minimum_size = Vector2(220, 24)
			var value_label := Label.new()
			value_label.add_theme_font_override("font", font_body)
			value_label.add_theme_font_size_override("font_size", 18)
			value_label.add_theme_color_override("font_color", GOLD_DIM)
			value_label.custom_minimum_size = Vector2(64, 0)
			value_label.text = "%.2f" % float(settings.get_value(id))
			slider.value_changed.connect(func(v: float) -> void:
				settings.set_value(id, v)
				value_label.text = "%.2f" % v
				_play("ui_hover"))
			row.add_child(slider)
			row.add_child(value_label)
		SettingsService.Type.BOOL:
			var check := CheckBox.new()
			check.button_pressed = bool(settings.get_value(id))
			check.add_theme_font_override("font", font_body)
			check.toggled.connect(func(v: bool) -> void:
				settings.set_value(id, v)
				_play("ui_press"))
			row.add_child(check)
		_:
			pass
	return row


func _play(sound_id: String) -> void:
	if ui_player and sfx.has(sound_id):
		ui_player.stream = sfx[sound_id]
		ui_player.play()
