extends SceneTree
## Сим v7: атака по манекену, стоящему перед игроком.
## SIM_DIR=LEFT|RIGHT. Лог: res://q_tools/sim7_out.txt
## Колонки: pos клипа, monL/monR, hp манекена, hit_registered.

var frame := 0
var sim_dir := "LEFT"
var player: CharacterBody3D = null
var dummy: CharacterBody3D = null
var log_f: FileAccess = null
var iters_per_sec := 0.0
var t0_ms := 0


func _initialize() -> void:
	var env := OS.get_environment("SIM_DIR")
	if env != "":
		sim_dir = env
	log_f = FileAccess.open("res://q_tools/sim7_out.txt", FileAccess.WRITE)
	log_f.store_line("SIM7 DIR=%s" % sim_dir)


func _setup_scene() -> void:
	# Единый протокол изоляции (паттерн sim_core): instantiate + глушение физики
	# врага + телепорты в ОДНОМ блоке frame-1. Глушение в _initialize ненадёжно:
	# READY включает _physics_process скрипта автоматически ПОСЛЕ него.
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	player = inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	dummy = inst.get_node_or_null("DummyMannequin") as CharacterBody3D
	if player == null or dummy == null:
		log_f.store_line("SIM7 FAIL nodes")
		log_f.close()
		quit(1)
	dummy.set("block_chance", 0.0)
	enemy_node = inst.get_node_or_null("EnemyCharacterBody3D")
	if enemy_node != null:
		enemy_node.set_physics_process(false)
		# Враг уводится далеко от своего спавна, а манекен ставится НА спавн
		# врага — эмпирически поражаемая свингами геометрия (до фикса стенда
		# здесь стоял враг и перехватывал удары).
		var enemy_spawn: Vector3 = (enemy_node as Node3D).global_position
		(enemy_node as Node3D).global_position = enemy_spawn + Vector3(0.0, 0.0, 40.0)
		dummy.global_position = enemy_spawn
	t0_ms = Time.get_ticks_msec()


var enemy_node: Node = null


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
		return false
	var aic := player.get_node("AttackInputComponent")
	var vp := player.get_node("VisualModel/AnimationPlayer") as AnimationPlayer
	var cc := player.get_node("CombatComponent")
	var hb_l := player.get_node("PlayerLeftWeaponAttachment/Sword/WeaponHitbox") as Area3D
	var hb_r := player.get_node("PlayerWeaponAttachment/Sword/WeaponHitbox") as Area3D
	if frame == 20:
		aic.press_attack()
	if frame == 22:
		var gesture := Vector2(5, 0)
		if sim_dir == "RIGHT":
			gesture = Vector2(-5, 0)
		elif sim_dir == "UP":
			gesture = Vector2(0, -5)
		aic.process_mouse_delta(gesture)
	if frame >= 24 and frame <= 200 and frame % 2 == 0:
		var elapsed := (Time.get_ticks_msec() - t0_ms) / 1000.0
		log_f.store_line("SIM7 f=%03d t=%.3f clip=%-11s pos=%.2f monL=%d monR=%d hp=%.0f hit=%d rec=%d" % [
			frame, elapsed, str(vp.current_animation), vp.current_animation_position,
			1 if hb_l.monitoring else 0, 1 if hb_r.monitoring else 0,
			float(dummy.get_node("HealthComponent").get("hp")),
			1 if cc.get("hit_registered") else 0,
			1 if cc.get("is_recovery") else 0])
	if frame == 210:
		log_f.store_line("SIM7 END")
		log_f.close()
		quit(0)
		return true
	return false
