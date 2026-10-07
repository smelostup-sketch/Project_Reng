extends SceneTree
## Регресс-стенд проблемы 4: скорость анимации атаки игрока.
## Проверяет, что после hit_confirm остаток клипа доигрывает НА ATTACK-СКОРОСТИ
## (M&B-style follow-through), а movement-скорость возвращается только по
## animation_finished. Лог: res://q_tools/sim_speed_out.txt
## Колонка speed = AnimationPlayer.speed_scale в реальном времени.

var frame := 0
var player: CharacterBody3D = null
var dummy: CharacterBody3D = null
var enemy: CharacterBody3D = null
var aic: Node = null
var cc: Node = null
var anim: Node = null
var vp: AnimationPlayer = null
var log_f: FileAccess = null
var passed := 0
var failed := 0
var d := {}
var hp0 := 0.0


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_speed_out.txt", FileAccess.WRITE)


func _setup_scene() -> void:
	# Единый протокол изоляции (паттерн sim_core): instantiate + глушение физики
	# врага + телепорты в ОДНОМ блоке frame-1. Глушение в _initialize ненадёжно:
	# READY включает _physics_process скрипта автоматически ПОСЛЕ него (фантомные атаки).
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	player = inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	dummy = inst.get_node_or_null("DummyMannequin") as CharacterBody3D
	enemy = inst.get_node_or_null("EnemyCharacterBody3D") as CharacterBody3D
	if player == null or dummy == null:
		log_f.store_line("SPEEDSIM FAIL nodes")
		log_f.close()
		quit(1)
	aic = player.get_node("AttackInputComponent")
	cc = player.get_node("CombatComponent")
	anim = player.get_node("AnimationComponent")
	vp = player.get_node("VisualModel/AnimationPlayer") as AnimationPlayer
	dummy.set("block_chance", 0.0)
	hp0 = float(dummy.get_node("HealthComponent").get("hp"))
	if enemy != null:
		enemy.set_physics_process(false)
		# Враг уводится от спавна, манекен ставится НА спавн врага —
		# эмпирически поражаемая свингами геометрия.
		var enemy_spawn: Vector3 = enemy.global_position
		enemy.global_position = enemy_spawn + Vector3(0.0, 0.0, 40.0)
		dummy.global_position = enemy_spawn


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		# Единый протокол изоляции (паттерн sim_core): instantiate + глушение +
		# телепорты в одном блоке frame-1. Глушение в _initialize ненадёжно:
		# READY включает _physics_process скрипта автоматически ПОСЛЕ него
		# (фантомные атаки врага на первом тике).
		_setup_scene()
		return false
	if frame == 20:
		aic.press_attack()
	if frame == 22:
		aic.process_mouse_delta(Vector2(5, 0))  # -> LEFT (конвенция sim_v7)

	var clip := str(vp.current_animation)
	var speed := vp.speed_scale
	var atk_speed: float = anim.get("attack_animation_speed")
	var mov_speed: float = anim.get("movement_animation_speed")

	# Фаза 1: клип атаки запущен и играет на attack-скорости.
	if not d.has("swing") and clip == "AttackLeft" and not cc.hit_registered:
		d["swing"] = true
		check("swing plays at attack_animation_speed (%.2f)" % atk_speed,
			is_equal_approx(speed, atk_speed))
	# Фаза 2 (регресс проблемы 4): hit_confirm прошёл, остаток клипа ещё играет —
	# скорость НЕ должна быть сброшена на movement.
	if not d.has("after_hit") and cc.hit_registered and clip == "AttackLeft":
		d["after_hit"] = true
		check("after hit_confirm clip still plays (follow-through)", true)
		check("after hit_confirm speed stays attack_animation_speed (got %.2f, want %.2f)" % [speed, atk_speed],
			is_equal_approx(speed, atk_speed))
	# Фаза 3: клип завершился — movement-скорость возвращена, locomotion восстановлен.
	if d.has("after_hit") and not d.has("restored") and clip != "AttackLeft" and clip != "":
		d["restored"] = true
		check("after clip end speed restored to movement_animation_speed (got %.2f, want %.2f)" % [speed, mov_speed],
			is_equal_approx(speed, mov_speed))
		check("locomotion loop resumed (clip=%s)" % clip,
			clip == "Idle" or clip == "Run" or clip == "Jump")

	if frame % 10 == 0 and frame <= 300:
		log_f.store_line("SPEED f=%03d clip=%-11s speed=%.2f hit=%d" % [
			frame, clip, speed, 1 if cc.hit_registered else 0])

	if frame == 400 or (d.has("restored") and frame > 200):
		if not d.has("after_hit"):
			check("hit_confirm observed during AttackLeft", false)
		if not d.has("restored"):
			check("clip finished and locomotion restored", false)
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true
	return false
