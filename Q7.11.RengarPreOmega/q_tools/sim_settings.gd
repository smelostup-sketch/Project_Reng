extends SceneTree
## P1: проверки SettingsService + пауза-меню/панель настроек (headless).
## Реестр -> привязки (камера/шины/CombatComponent), ConfigFile round-trip,
## пауза и уровни меню. Лог: res://q_tools/sim_settings_out.txt

var frame := 0
var log_f: FileAccess = null
var passed := 0
var failed := 0
var svc: Node = null
var cam: Node = null
var menu: Node = null
var signal_count := 0


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _on_setting_changed(_id: String, _v: Variant) -> void:
	signal_count += 1


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_settings_out.txt", FileAccess.WRITE)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		var scn := load("res://Основная_сцена.tscn") as PackedScene
		var inst := scn.instantiate()
		root.add_child(inst)
		svc = root.get_node("/root/SettingsService")
		cam = get_first_node_in_group("main_camera")
		menu = inst.get_node("UIMenu")
		svc.setting_changed.connect(_on_setting_changed)
		return false
	if frame == 3:
		# 1. Реестр: id уникальны, FLOAT-дефолты в границах.
		var ids := {}
		var bounds_ok := true
		for entry in svc.registry:
			ids[entry["id"]] = true
			if int(entry["type"]) == int(svc.Type.FLOAT):
				if not (entry["def"] >= entry["min"] and entry["def"] <= entry["max"]):
					bounds_ok = false
		check("registry: ids unique", ids.size() == svc.registry.size())
		check("registry: float defaults within bounds", bounds_ok)
		check("camera in group main_camera (binding point)", cam != null)

		# 2. Привязки.
		signal_count = 0
		svc.set_value("mouse_sens", 0.01)
		check("mouse_sens -> camera.mouse_sens", is_equal_approx(cam.get("mouse_sens"), 0.01))
		svc.set_value("cam_distance", 6.0)
		check("cam_distance -> camera.distance", is_equal_approx(cam.get("distance"), 6.0))
		svc.set_value("cam_invert", true)
		check("cam_invert -> camera.invert_vertical", cam.get("invert_vertical") == true)
		svc.set_value("vol_ui", 0.5)
		var idx := AudioServer.get_bus_index("UI")
		check("vol_ui -> bus UI db ~= linear_to_db(0.5)",
			idx >= 0 and absf(AudioServer.get_bus_volume_db(idx) - linear_to_db(0.5)) < 0.01)
		svc.set_value("debug_logging", false)
		var pcc = get_first_node_in_group("player").get_node("CombatComponent")
		var ecc = get_first_node_in_group("enemy").get_node("CombatComponent")
		check("debug_logging -> all CombatComponents", pcc.debug_logging == false and ecc.debug_logging == false)
		check("setting_changed emitted per set (5)", signal_count == 5)

		# 3. ConfigFile round-trip.
		svc.reload_from_disk()
		check("cfg round-trip: mouse_sens persisted", is_equal_approx(svc.get_value("mouse_sens"), 0.01))

		# 4. Меню: пауза, уровни, строки настроек из реестра.
		menu.open_pause()
		check("open_pause: tree paused + root visible",
			paused == true and menu.get_node("Root").visible == true)
		menu.open_settings()
		var rows: Node = menu.get_node("Root/SettingsBG/Box/Scroll/Rows")
		var sections := {}
		for entry in svc.registry:
			sections[entry["section"]] = true
		check("settings rows = registry + section headers",
			rows.get_child_count() == svc.registry.size() + sections.size())
		check("settings panel visible, pause panel hidden",
			menu.get_node("Root/SettingsBG").visible == true
			and menu.get_node("Root/MenuBG").visible == false)
		menu.resume()
		check("resume: unpaused + hidden",
			paused == false and menu.get_node("Root").visible == false)

		# 5. Сброс к дефолтам.
		svc.reset_to_defaults()
		check("reset_to_defaults -> camera.mouse_sens = 0.004",
			is_equal_approx(cam.get("mouse_sens"), 0.004))

		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true
	return false
