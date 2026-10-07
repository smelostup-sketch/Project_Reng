extends SceneTree
## Сим проблемы 5: засадный прыжок (leap) ОДИНАКОВ на врага и на манекен.
## SIM_TARGET=DUMMY|ENEMY. Обе цели проходят один и тот же сценарий:
## стелс (нормализация стенда вместо куста) -> прыжок в сторону цели ->
## засада (_start_ambush) -> полёт -> атака в полёте (флаг leap) -> приземление.
## Цель ставится по фактическому форварду игрока (камера лерпит rotation.y к yaw,
## поэтому look_at на стенде бесполезен — целевая точка считается после сходимости).
## Лог: res://q_tools/sim_leap_out.txt

var frame := 0
var t0 := 0
var sim_target := "DUMMY"
var player: CharacterBody3D = null
var dummy: CharacterBody3D = null
var enemy: CharacterBody3D = null
var target: Node3D = null
var other: Node3D = null
var state_comp: Node = null
var aic: Node = null
var cc: Node = null
var stacks: Node = null
var log_f: FileAccess = null
var passed := 0
var failed := 0
var d := {}
var dist0 := 0.0
var expected_speed := 0.0
var t_jump := -1.0
var hit_latched := false


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _on_hit_detected(_target: Node) -> void:
	hit_latched = true


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_leap_out.txt", FileAccess.WRITE)
	var env := OS.get_environment("SIM_TARGET")
	if env != "":
		sim_target = env
	log_f.store_line("SIM_LEAP TARGET=%s" % sim_target)


func _setup_scene() -> void:
	# Единый протокол изоляции (паттерн sim_core): instantiate + глушение физики
	# врага в ОДНОМ блоке frame-1 (READY включает _physics_process скрипта
	# автоматически ПОСЛЕ глушения в _initialize — отсюда фантомные атаки).
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	player = inst.get_node("PLayerCharacterBody3D")
	dummy = inst.get_node("DummyMannequin")
	enemy = inst.get_node("EnemyCharacterBody3D")
	state_comp = player.get_node("StateComponent")
	aic = player.get_node("AttackInputComponent")
	cc = player.get_node("CombatComponent")
	stacks = player.get_node("StacksComponent")
	dummy.set("block_chance", 0.0)  # нормализация стенда: кубик блока не детерминирован
	enemy.set_physics_process(false)
	cc.hit_detected.connect(_on_hit_detected)
	if sim_target == "ENEMY":
		target = enemy
		other = dummy
	else:
		target = dummy
		other = enemy
	# НЕ-цель уводится: засада выбирает ближайшую цель из групп, лишний корпус
	# в 40 м не влияет на выбор, но исключает случайные контакты.
	other.global_position = other.global_position + Vector3(0.0, 0.0, 40.0)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
		t0 = Time.get_ticks_msec()
		return false
	var t := (Time.get_ticks_msec() - t0) / 1000.0

	# Расстановка: камера сходится к начальному yaw за ~0.3с — ставим цель
	# ровно по форварду игрока на дистанцию 4 м (калибровка стенда: внутри
	# leap_max_range=10, вне досягаемости меча, открытая площадка).
	if not d.has("placed") and t >= 0.8 and player.is_on_floor():
		d["placed"] = true
		var fwd := -player.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		target.global_position = player.global_position + fwd * 4.0

	if not d.has("stealth") and d.has("placed") and t >= 1.0:
		d["stealth"] = true
		# Нормализация стенда: в живой игре стелс даёт куст (_check_bush_overlap).
		state_comp.set_stealthed(true)

	if not d.has("jump") and d.has("stealth") and t >= 1.2 and player.is_on_floor():
		d["jump"] = true
		dist0 = player.global_position.distance_to(target.global_position)
		var leap_time: float = state_comp.get("leap_time_to_target")
		expected_speed = clampf(dist0 / leap_time,
			float(state_comp.get("min_leap_speed")), float(state_comp.get("max_leap_speed")))
		t_jump = t
		state_comp.set("jump_requested", true)

	if t_jump >= 0.0:
		# Триггер засады: is_leaping + направление + скорость + стелс израсходован.
		if not d.has("trig") and state_comp.get("is_leaping"):
			d["trig"] = true
			var to_target := (target.global_position - player.global_position)
			to_target.y = 0.0
			to_target = to_target.normalized()
			var leap_dir: Vector3 = state_comp.get_leap_direction()
			var vel_xz := Vector2(player.velocity.x, player.velocity.z).length()
			check("ambush leap triggered (is_leaping)", true)
			check("leap direction toward target (dot=%.2f)" % leap_dir.dot(to_target),
				leap_dir.dot(to_target) > 0.9)
			check("leap speed %.2f ~= expected %.2f (dist/leap_time clamped)" % [vel_xz, expected_speed],
				absf(vel_xz - expected_speed) < 0.5)
			check("stealth consumed by ambush", state_comp.get("is_stealthed") == false)
		# Атака в полёте: пресс сразу после триггера, жест — следующим кадром.
		if d.has("trig") and not d.has("press"):
			d["press"] = true
			aic.press_attack()
		elif d.has("press") and not d.has("gest"):
			d["gest"] = true
			aic.process_mouse_delta(Vector2(5.0, 0.0))  # -> LEFT (конвенция sim_v7)
		# Флаг leap-атаки живёт от commit до hit — ловим защёлкой каждый кадр.
		if cc.get("last_attack_was_in_leap") == true:
			d["leap_flag"] = true
		# Сближение с целью в полёте.
		if not d.has("approach") and t >= t_jump + 0.25:
			d["approach"] = true
			var dist_now := player.global_position.distance_to(target.global_position)
			check("closing distance to target (%.2f -> %.2f)" % [dist0, dist_now],
				dist_now < dist0)
		if not d.has("flagchk") and t >= t_jump + 0.4:
			d["flagchk"] = true
			check("attack committed in flight carries leap flag (last_attack_was_in_leap)",
				d.has("leap_flag"))
		# Приземление: leap завершён, игрок на земле.
		if not d.has("land") and t >= t_jump + 2.5:
			d["land"] = true
			check("leap finished on landing (is_leaping=false, on_floor=true)",
				state_comp.get("is_leaping") == false and player.is_on_floor())

	if frame >= 1000 or (d.has("land") and t >= t_jump + 2.7):
		if not d.has("trig"):
			check("ambush leap triggered (is_leaping)", false)
			check("leap direction toward target", false)
			check("leap speed ~= expected", false)
			check("stealth consumed by ambush", false)
		if not d.has("flagchk"):
			check("attack committed in flight carries leap flag", false)
		if not d.has("land"):
			check("leap finished on landing", false)
		if hit_latched:
			check("leap hit granted purple stack", stacks.get("has_purple") == true)
		else:
			log_f.store_line("INFO physical contact in flight did not occur — purple stack on leap hit is a LIVE check")
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true
	return false
