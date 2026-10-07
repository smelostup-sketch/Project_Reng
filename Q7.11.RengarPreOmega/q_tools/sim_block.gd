extends SceneTree
## Детерминированные проверки БЛОКА ИГРОКА против атак врага.
## Единый протокол изоляции стендов: враг обесточен в _initialize (до первого
## физического тика) и на кадре 1 уведён от спавна — управляемые атаки врага
## не могут физически задеть игрока; контакт разрешается вызовом того же
## обработчика, который вызывает body_entered (честный путь кода).
## Ввод блока зеркалит Player3d._input: request_block() -> set_block_input_pressed().
## Лог: res://q_tools/sim_block_out.txt

var log_f: FileAccess
var frame := 0
var t0 := 0
var enemy: CharacterBody3D
var player: CharacterBody3D
var dummy: CharacterBody3D
var ecc: Node
var pcc: Node
var aic: Node
var passed := 0
var failed := 0
var d := {}
var hp0 := 0.0
var enemy_dmg := 5.0
var block_success_count := 0
var last_block_defender := ""
var damage_taken_count := 0


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _on_block_successful(defender: String, _direction: String) -> void:
	block_success_count += 1
	last_block_defender = defender


func _on_damage_taken() -> void:
	damage_taken_count += 1


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		log_f = FileAccess.open("res://q_tools/sim_block_out.txt", FileAccess.WRITE)
		var scn := load("res://Основная_сцена.tscn") as PackedScene
		var inst := scn.instantiate()
		root.add_child(inst)
		enemy = inst.get_node("EnemyCharacterBody3D")
		player = inst.get_node("PLayerCharacterBody3D")
		dummy = inst.get_node_or_null("DummyMannequin")
		ecc = enemy.get_node("CombatComponent")
		pcc = player.get_node("CombatComponent")
		aic = player.get_node("AttackInputComponent")
		if dummy != null:
			dummy.set("block_chance", 0.0)
		# Изоляция ДО первого физического тика: EnemyController атакует мгновенно
		# при спавне в пределах stop_distance.
		enemy.set_physics_process(false)
		hp0 = float(player.get_node("HealthComponent").get("hp"))
		enemy_dmg = float(ecc.get("enemy_damage"))
		pcc.block_successful.connect(_on_block_successful)
		pcc.damage_taken.connect(_on_damage_taken)
		t0 = Time.get_ticks_msec()
		return false
	if frame == 2:
		# Уводим врага: окна его управляемых атак не должны физически пересекать
		# игрока (контакт ниже разрешается напрямую, как это делает body_entered).
		enemy.global_position = enemy.global_position + Vector3(0.0, 0.0, 40.0)

	var t := (Time.get_ticks_msec() - t0) / 1000.0

	# --- Сценарий A: активация блока жестом влево, совпавшее направление ---
	if not d.has("a_press") and t >= 0.3:
		d["a_press"] = true
		check("on floor at block request", player.is_on_floor())
		check("request_block accepted (mirrors Player3d._input)", aic.request_block() == true)
		pcc.set_block_input_pressed()
		pcc.process_mouse_delta(Vector2(-5.0, 0.0))  # мышь влево -> защита LEFT
	if not d.has("a_active") and t >= 0.6:
		d["a_active"] = true
		check("block active after hold >= activation_time, dir=LEFT",
			pcc.is_block_active and pcc.block_dir == "LEFT")
		check("attack rejected while block active",
			pcc.perform_directional_attack("LEFT", false) == false)
	if not d.has("a_enemy") and t >= 0.65:
		d["a_enemy"] = true
		check("enemy intent RIGHT accepted (core free)",
			ecc.perform_directional_attack("RIGHT", false) == true)
	if not d.has("a_contact") and t >= 0.75:
		d["a_contact"] = true
		ecc.hit_registered = false  # нормализация стенда: в игре сбрасывает Method Track окна
		ecc._on_enemy_weapon_hitbox_body_entered(player)
		check("matching block (LEFT vs RIGHT): hp unchanged (%.0f == %.0f)" % [
			float(player.get_node("HealthComponent").get("hp")), hp0],
			float(player.get_node("HealthComponent").get("hp")) == hp0)
		check("block_successful emitted once with defender=PLAYER",
			block_success_count == 1 and last_block_defender == "PLAYER")
		check("enemy punished on blocked attack: stunned and attack cancelled",
			str(ecc.ai_state) == "STUNNED" and ecc.is_recovery == false)

	# --- Сценарий B: авто-финал окна, один пресс = один блок, несовпадение ---
	if not d.has("b_expired") and t >= 1.15:
		d["b_expired"] = true
		check("block auto-expired after active_duration", pcc.is_block_active == false)
	if not d.has("b_hold") and t >= 1.45:
		d["b_hold"] = true
		check("still held -> NO reactivation (one press = one block)",
			pcc.is_block_active == false)
		pcc.set_block_input_released()
	if not d.has("b_press") and t >= 1.55:
		d["b_press"] = true
		check("request_block accepted on re-press", aic.request_block() == true)
		pcc.set_block_input_pressed()
		pcc.process_mouse_delta(Vector2(0.0, -5.0))  # мышь вверх -> защита UP
	if not d.has("b_active") and t >= 1.85:
		d["b_active"] = true
		check("re-press reactivates, gesture up -> dir=UP",
			pcc.is_block_active and pcc.block_dir == "UP")
	if not d.has("b_enemy") and t >= 1.9:
		d["b_enemy"] = true
		check("enemy intent RIGHT accepted (stun over, no recovery)",
			ecc.perform_directional_attack("RIGHT", false) == true)
	if not d.has("b_contact") and t >= 1.95:
		d["b_contact"] = true
		var hp_before := float(player.get_node("HealthComponent").get("hp"))
		ecc.hit_registered = false  # нормализация стенда
		ecc._on_enemy_weapon_hitbox_body_entered(player)
		var hp_after := float(player.get_node("HealthComponent").get("hp"))
		check("mismatched block (UP vs RIGHT): damage passed (%.0f -> %.0f, enemy_damage=%.0f)" % [
			hp_before, hp_after, enemy_dmg],
			is_equal_approx(hp_after, hp_before - enemy_dmg))
		check("damage during block locks player input (0.1s)", pcc.is_input_locked == true)

	# --- Сценарий C: блок истёк до удара; контракт стана ---
	if not d.has("c_enemy") and t >= 3.95:
		d["c_enemy"] = true
		check("enemy intent LEFT accepted after recovery 2.0",
			ecc.perform_directional_attack("LEFT", false) == true)
	if not d.has("c_contact") and t >= 4.0:
		d["c_contact"] = true
		var hp_before := float(player.get_node("HealthComponent").get("hp"))
		ecc.hit_registered = false  # нормализация стенда
		ecc._on_enemy_weapon_hitbox_body_entered(player)
		check("block long expired: damage passed again (%.0f -> %.0f)" % [
			hp_before, float(player.get_node("HealthComponent").get("hp"))],
			is_equal_approx(float(player.get_node("HealthComponent").get("hp")), hp_before - enemy_dmg))
		ecc.cancel_attack("sim_reset")  # нормализация стенда между сценариями
		ecc.apply_stun(0.5)
		check("CONTRACT: core accepts attack while stunned (stun gates provider, not core)",
			ecc.perform_directional_attack("UP", false) == true)

	# --- Сценарий D: короткий пресс не активирует; ПКМ без жеста = UP ---
	if not d.has("d_short") and t >= 4.4:
		d["d_short"] = true
		pcc.set_block_input_released()
		pcc.set_block_input_pressed()  # без жеста
	if not d.has("d_short_rel") and t >= 4.55:
		d["d_short_rel"] = true
		pcc.set_block_input_released()  # удержание 0.15s < activation_time 0.2s
	if not d.has("d_short_chk") and t >= 4.7:
		d["d_short_chk"] = true
		check("short hold (< activation_time): block never activated",
			pcc.is_block_active == false and pcc.block_activated_this_hold == false)
	if not d.has("d_press") and t >= 4.8:
		d["d_press"] = true
		pcc.set_block_input_pressed()  # ПКМ без жеста
	if not d.has("d_default") and t >= 5.1:
		d["d_default"] = true
		check("RMB hold without gesture: block active, default dir=UP",
			pcc.is_block_active and pcc.block_dir == "UP")
		pcc.set_block_input_released()

	if frame >= 1200 or (d.has("d_default") and frame % 10 == 0 and t >= 5.3):
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true
	return false
