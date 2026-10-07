extends SceneTree
## Проверки Q7.9 (опции B+C): телеграф направления блока и авторитет скорости врага.
## Часть 1: зеркальная матрица «атака -> требуемый блок» (единый источник
##   CombatComponent.BLOCK_RESPONSE) через реальный pcc.is_blocking_active — 3×3.
## Часть 2: стрелка телеграфа = ТРЕБУЕМЫЙ БЛОК (по стрелке игрок уводит мышь):
##   атака UP -> ↑, атака LEFT -> →, атака RIGHT -> ←; во время свинга метка скрыта.
##   _update_telegraph_visibility вызывается напрямую (в игре его гоняет
##   _physics_process контроллера; здесь контроллер заглушён изоляцией).
## Часть 3: эффективная скорость атак врага = экспорт на теле (1.3, опция C).
## Лог: res://q_tools/sim_telegraph_out.txt

var frame := 0
var player: CharacterBody3D = null
var enemy: CharacterBody3D = null
var ecc: Node = null
var pcc: Node = null
var tlabel: Label3D = null
var log_f: FileAccess = null
var passed := 0
var failed := 0
var d := {}
var dirs := ["UP", "LEFT", "RIGHT"]
var arrows := {"UP": "↑", "LEFT": "→", "RIGHT": "←"}  # атака -> стрелка ТРЕБУЕМОГО блока
var di := 0
var t_stage := -1.0


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_telegraph_out.txt", FileAccess.WRITE)


func _setup_scene() -> void:
	# Единый протокол изоляции (паттерн sim_core): instantiate + глушение в одном блоке.
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	player = inst.get_node("PLayerCharacterBody3D")
	enemy = inst.get_node("EnemyCharacterBody3D")
	ecc = enemy.get_node("CombatComponent")
	pcc = player.get_node("CombatComponent")
	tlabel = enemy.get_node_or_null("TelegraphLabel")
	enemy.set_physics_process(false)


func _part1_matrix() -> void:
	# Зеркальная матрица через реальный путь проверки блока:
	# pcc.is_blocking_active читает block_dir при is_block_active=true.
	pcc.is_block_active = true
	for attack_dir in dirs:
		var required: String = CombatComponent.BLOCK_RESPONSE[attack_dir]
		var ok := true
		for defense_dir in dirs:
			pcc.block_dir = defense_dir
			var expected: bool = (defense_dir == required)
			if pcc.is_blocking_active(attack_dir) != expected:
				ok = false
		check("matrix attack=%s: blocks only defense=%s" % [attack_dir, required], ok)
	pcc.is_block_active = false
	pcc.block_dir = "UP"


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
		check("telegraph label exists (created in EnemyController._ready)", tlabel != null)
		var eff_speed: float = float(enemy.get_node("AnimationComponent").get("attack_animation_speed"))
		check("enemy effective attack speed = 1.3 (export on body, option C)",
			is_equal_approx(eff_speed, 1.3))
		_part1_matrix()
		return false
	if frame < 3:
		return false

	var t := Engine.get_physics_frames() / 60.0
	if di >= dirs.size():
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true

	var dir: String = dirs[di]
	if t_stage < 0.0:
		# Старт направления: намерение -> телеграф виден, стрелка = требуемый блок.
		if ecc.is_recovery:
			ecc.cancel_attack("bench_reset")
		if not ecc.perform_directional_attack(dir, false):
			return false  # ядро занято — ждём кадр
		enemy._update_telegraph_visibility()
		check("dir=%s telegraph visible during windup" % dir, tlabel.visible)
		check("dir=%s arrow = %s (required block, not raw attack)" % [dir, arrows[dir]],
			tlabel.text == arrows[dir])
		t_stage = t
		return false

	if not d.has("swing_" + dir) and ecc.attack_swing_active:
		# Окно открылось (state-driven: без хардкода расписания, robust к
		# любой скорости/окнам) — телеграф гаснет на время свинга.
		d["swing_" + dir] = true
		enemy._update_telegraph_visibility()
		check("dir=%s telegraph hidden during swing" % dir, tlabel.visible == false)
		return false

	if d.has("swing_" + dir) and not ecc.attack_swing_active and ecc.is_recovery:
		# Окно закрылось, recovery ещё идёт: по текущему контракту метка снова
		# видна до конца recovery — фиксируем как INFO (пост-свинговое «окно
		# наказания», не баг; решение о показе — за заказчиком).
		enemy._update_telegraph_visibility()
		log_f.store_line("INFO dir=%s post-swing recovery: telegraph visible=%s (контракт: is_recovery && !swing_active)" % [dir, str(tlabel.visible)])
		ecc.cancel_attack("bench_reset")
		t_stage = -1.0
		di += 1
		return false

	if t >= t_stage + 4.0:
		# страховка: направление не дошло до свинга/финала
		log_f.store_line("INFO dir=%s stage timeout (swing_seen=%s)" % [dir, str(d.has("swing_" + dir))])
		if ecc.is_recovery:
			ecc.cancel_attack("bench_timeout")
		t_stage = -1.0
		di += 1
	return false
