extends SceneTree
## Замер тайминговой цепочки «блок игрока vs атака врага» (проблема: блок не работает в живой игре).
## Для каждого направления атаки врага (RIGHT, LEFT, UP) измеряет в реальном времени:
##   t_intent  — perform_directional_attack принят ядром (появление телеграфа ⚡);
##   t_open    — окно хитбокса открылось (monitoring; телеграф гаснет, swing_active=true);
##   t_hit     — урон игроку фактически прошёл (hp уменьшился);
##   t_close   — окно закрылось (method track disable).
## Затем считает бюджет реакции игрока:
##   budget = t_hit - block_activation_time (позднейшее нажатие ПКМ относительно телеграфа).
## ВРЕМЯ: симуляционное (Engine.get_physics_frames()/60), НЕ wall-clock:
## итерации headless и хостовые задержки искажают стенные часы (предшественник
## предупреждал; замер wall-clock давал фантомные timeout). Сим-время = то, что
## видит игрок на 60 fps.
## Живой замер блока: нажатие -> is_block_active (валидация block_activation_time).
## Дистанция боя = экспорт stop_distance EnemyController (родословная: живая логика врага).
## Лог: res://q_tools/sim_block_timing_out.txt

var frame := 0
var player: CharacterBody3D = null
var enemy: CharacterBody3D = null
var ecc: Node = null
var pcc: Node = null
var php: Node = null
var hb_r: Area3D = null
var hb_l: Area3D = null
var log_f: FileAccess = null
var dirs := ["RIGHT", "LEFT", "UP"]
var stage := {}
var di := 0
var hp_full := 100.0
var combat_dist := 1.5
var block_charge_press_t := -1.0
var block_charge_done := false
var setup_done := false
var scene_ready := false
var player_combat_pos := Vector3.ZERO


func _any_enemy_hitbox_on() -> bool:
	return hb_r.monitoring or hb_l.monitoring


func _log_line(s: String) -> void:
	log_f.store_line(s)


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_block_timing_out.txt", FileAccess.WRITE)
	log_f.store_line("SIM_BLOCK_TIMING dirs=RIGHT,LEFT,UP")


func _setup_scene() -> void:
	# Единый протокол изоляции (паттерн sim_core): instantiate + глушение физики
	# врага в ОДНОМ блоке frame-1 — READY включает _physics_process скрипта
	# автоматически, поэтому глушить нужно ПОСЛЕ _ready и ДО первого тика цели.
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	player = inst.get_node("PLayerCharacterBody3D")
	enemy = inst.get_node("EnemyCharacterBody3D")
	ecc = enemy.get_node("CombatComponent")
	pcc = player.get_node("CombatComponent")
	php = player.get_node("HealthComponent")
	hb_r = enemy.get_node("EnemyWeaponAttachment/Sword/WeaponHitbox")
	hb_l = enemy.get_node("EnemyLeftWeaponAttachment/Sword/WeaponHitbox")
	enemy.set_physics_process(false)
	hp_full = float(php.get("max_hp"))
	combat_dist = float(enemy.get("stop_distance"))
	scene_ready = true


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
		return false
	var t := Engine.get_physics_frames() / 60.0
	if not setup_done and t >= 0.6 and player.is_on_floor():
		setup_done = true
		var fwd := -player.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		enemy.global_position = player.global_position + fwd * combat_dist
		var look_target := player.global_position
		look_target.y = enemy.global_position.y
		enemy.look_at(look_target, Vector3.UP)
		player_combat_pos = player.global_position
		_log_line("SETUP combat_dist=%.2f (stop_distance export) enemy_effective_attack_speed=%.2f (Q7.9: экспорт на теле врага — единый источник)" % [
			combat_dist, float(enemy.get_node("AnimationComponent").get("attack_animation_speed"))])
	if not setup_done:
		return false
	if t > 25.0:  # страховка по сим-времени (хостовые задержки wall-clock не влияют)
		_log_line("SUMMARY directions_measured=%d TIMEOUT_GLOBAL" % di)
		log_f.close()
		quit(1)
		return true

	# Живой замер зарядки блока (один раз, в начале): пресс -> активация.
	if not block_charge_done:
		if block_charge_press_t < 0.0 and t >= 1.0:
			block_charge_press_t = t
			pcc.set_block_input_pressed()
			pcc.process_mouse_delta(Vector2(0.0, -5.0))  # UP-жест
		if block_charge_press_t >= 0.0 and pcc.is_block_active:
			block_charge_done = true
			_log_line("BLOCK_CHARGE press->active = %.3fs (export block_activation_time=%.2f)" % [
				t - block_charge_press_t, float(pcc.get("block_activation_time"))])
			pcc.set_block_input_released()
		return false

	# Последовательные замеры по направлениям.
	if di < dirs.size():
		var dir: String = dirs[di]
		if not stage.has("intent"):
			# Нормализация стенда между замерами: HP полон, игрок возвращён в
			# боевую точку (нокбэк предыдущих замеров уводит его из досягаемости),
			# ядро врага свободно.
			php.set("hp", hp_full)
			php.set("is_dead", false)
			player.global_position = player_combat_pos
			player.velocity = Vector3.ZERO
			if ecc.is_recovery:
				ecc.cancel_attack("bench_reset")
			if ecc.perform_directional_attack(dir, false):
				stage["intent"] = t
				_log_line("--- DIR=%s ---" % dir)
			return false
		if not stage.has("open") and _any_enemy_hitbox_on():
			stage["open"] = t
		if not stage.has("hit") and float(php.get("hp")) < hp_full:
			stage["hit"] = t
		if stage.has("open") and not stage.has("close") and not _any_enemy_hitbox_on():
			stage["close"] = t
			var charge: float = float(pcc.get("block_activation_time"))
			var telegraph: float = stage["open"] - stage["intent"]
			_log_line("DIR=%s telegraph(⚡)=%.3fs window=%.3f..%.3f hit=%s" % [
				dir, telegraph, stage["open"] - stage["intent"], stage["close"] - stage["intent"],
				("%.3f" % (stage["hit"] - stage["intent"])) if stage.has("hit") else "НЕТ (промах)"])
			if stage.has("hit"):
				var hit_time: float = stage["hit"] - stage["intent"]
				var budget: float = hit_time - charge
				_log_line("DIR=%s budget_for_rmb_press = hit - charge = %.3f - %.2f = %+.3fs -> %s" % [
					dir, hit_time, charge, budget,
					"ЧЕЛОВЕЧЕСКИ НЕВОЗМОЖНО (<0.25с)" if budget < 0.25 else "в пределах реакции"])
				_log_line("DIR=%s окно нажатия ПКМ (блок успевает к удару): [%.3f .. %.3f]с после телеграфа (длительность блока %.2fс)" % [
					dir, maxf(hit_time - charge - float(pcc.get("block_active_duration")), 0.0),
					hit_time - charge, float(pcc.get("block_active_duration"))])
			stage = {}
			di += 1
		# страховка от зависания: 6с на направление
		if stage.has("intent") and t - float(stage["intent"]) > 6.0 and not stage.has("close"):
			var evp: AnimationPlayer = enemy.get_node("EnemyVisual/AnimationPlayer")
			_log_line("DIR=%s TIMEOUT stage=%s" % [dir, str(stage)])
			_log_line("DIR=%s DIAG hb_r.monitoring=%s hb_l.monitoring=%s swing_active=%s clip=%s pos=%.2f len=%.2f speed=%.2f" % [
				dir, str(hb_r.monitoring), str(hb_l.monitoring),
				str(ecc.attack_swing_active), str(evp.current_animation),
				evp.current_animation_position,
				(evp.get_animation(evp.current_animation).length if evp.has_animation(evp.current_animation) else -1.0),
				evp.speed_scale])
			stage = {}
			di += 1
		return false

	_log_line("SUMMARY directions_measured=%d" % di)
	log_f.close()
	quit(0)
	return true
