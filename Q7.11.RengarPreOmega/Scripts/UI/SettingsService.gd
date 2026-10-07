extends Node
## P1 (ROADMAP_UI): единственный владелец настроек игры.
## Реестр — данные (id/тип/границы/default/подпись/секция); панель настроек
## строится ИЗ реестра (data-driven, без задвоения). Хранилище — ConfigFile
## user://settings.cfg. Применение — явные привязки к существующим экспортам
## и шинам (никакой строковой рефлексии по сценам).
## Автозагрузка: project.godot [autoload] SettingsService.

signal setting_changed(id: String, value: Variant)

enum Type { FLOAT, INT, BOOL }

const CFG_PATH := "user://settings.cfg"

# Реестр настроек: порядок = порядок строк в панели.
var registry: Array[Dictionary] = [
	{"id": "mouse_sens", "type": Type.FLOAT, "min": 0.0005, "max": 0.02, "step": 0.0005, "def": 0.004, "label": "Чувствительность мыши", "section": "Управление", "icon": "res://Assets/UI/icons/controls.svg"},
	{"id": "cam_distance", "type": Type.FLOAT, "min": 2.5, "max": 10.0, "step": 0.5, "def": 4.0, "label": "Дистанция камеры", "section": "Управление", "icon": "res://Assets/UI/icons/video.svg"},
	{"id": "cam_invert", "type": Type.BOOL, "def": false, "label": "Инверсия камеры (вертикаль)", "section": "Управление", "icon": "res://Assets/UI/icons/controls.svg"},
	{"id": "vol_master", "type": Type.FLOAT, "min": 0.0, "max": 1.0, "step": 0.05, "def": 1.0, "label": "Общая громкость", "section": "Звук", "icon": "res://Assets/UI/icons/audio.svg"},
	{"id": "vol_sfx", "type": Type.FLOAT, "min": 0.0, "max": 1.0, "step": 0.05, "def": 1.0, "label": "Громкость эффектов", "section": "Звук", "icon": "res://Assets/UI/icons/audio.svg"},
	{"id": "vol_ui", "type": Type.FLOAT, "min": 0.0, "max": 1.0, "step": 0.05, "def": 1.0, "label": "Громкость интерфейса", "section": "Звук", "icon": "res://Assets/UI/icons/audio.svg"},
	{"id": "fullscreen", "type": Type.BOOL, "def": false, "label": "Полноэкранный режим", "section": "Видео", "icon": "res://Assets/UI/icons/video.svg"},
	{"id": "vsync", "type": Type.BOOL, "def": true, "label": "Вертикальная синхронизация", "section": "Видео", "icon": "res://Assets/UI/icons/video.svg"},
	{"id": "debug_logging", "type": Type.BOOL, "def": true, "label": "Журнал боя [Combat]", "section": "Разработка", "icon": "res://Assets/UI/icons/gear.svg"},
	{"id": "verbose_logging", "type": Type.BOOL, "def": false, "label": "Подробный журнал (отказы ядра)", "section": "Разработка", "icon": "res://Assets/UI/icons/gear.svg"},
	{"id": "debug_hitboxes", "type": Type.BOOL, "def": false, "label": "Хитбоксы оружия (F8)", "section": "Разработка", "icon": "res://Assets/UI/icons/shield.svg"},
]

var values: Dictionary = {}


func _ready() -> void:
	_load_from_disk()
	# Применение отложено: сцена ещё не готова в _ready автозагрузки.
	_apply_all.call_deferred()


func get_value(id: String):
	return values.get(id, _def_of(id))


func set_value(id: String, value: Variant) -> void:
	values[id] = value
	_apply(id, value)
	_save_to_disk()
	setting_changed.emit(id, value)


func reset_to_defaults() -> void:
	for entry in registry:
		set_value(entry["id"], entry["def"])


# === ПРИМЕНЕНИЕ (явные привязки; цели — существующие экспорты/шины) ===
func _apply_all() -> void:
	for entry in registry:
		_apply(entry["id"], get_value(entry["id"]))


func _apply(id: String, value: Variant) -> void:
	match id:
		"mouse_sens":
			var cam := _camera()
			if cam: cam.set("mouse_sens", value)
		"cam_distance":
			var cam := _camera()
			if cam: cam.set("distance", value)
		"cam_invert":
			var cam := _camera()
			if cam: cam.set("invert_vertical", value)
		"vol_master", "vol_sfx", "vol_ui":
			_set_bus_volume({"vol_master": "Master", "vol_sfx": "SFX", "vol_ui": "UI"}[id], float(value))
		"fullscreen":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_mode(
					DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"debug_logging", "verbose_logging", "debug_hitboxes":
			for cc in _combat_components():
				match id:
					"debug_logging": cc.set("debug_logging", value)
					"verbose_logging": cc.set("verbose_logging", value)
					"debug_hitboxes": cc.set("debug_hitboxes_enabled", value)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db := linear_to_db(linear) if linear > 0.001 else -80.0
	AudioServer.set_bus_volume_db(idx, db)


func _camera() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("main_camera")


func _combat_components() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for group_name in ["player", "enemy", "dummy_enemy"]:
		for body in get_tree().get_nodes_in_group(group_name):
			var cc := body.get_node_or_null("CombatComponent")
			if cc:
				out.append(cc)
	return out


func _def_of(id: String):
	for entry in registry:
		if entry["id"] == id:
			return entry["def"]
	return null


# === ХРАНЕНИЕ (ConfigFile) ===
func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for id in values:
		cfg.set_value("settings", id, values[id])
	cfg.save(CFG_PATH)


func _load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	for entry in registry:
		if cfg.has_section_key("settings", entry["id"]):
			values[entry["id"]] = cfg.get_value("settings", entry["id"])


func reload_from_disk() -> void:
	values.clear()
	_load_from_disk()
