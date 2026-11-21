extends AnimatedSprite2DEntity
class_name 须佐佐助

@export_group("巨鹰登场")
@export_range(0, 700) var entry_fly_distance: float = 300.0
@export_range(0, 400) var entry_fly_height: float = 160.0
@export_range(0, 200) var entry_leap_lift: float = 70.0

@onready var entry_eagle: AnimatedSprite2D = $Visuals/AnimatedSprite2D/EntryEagle

func _ready():
	var requested_entry := entry_action
	res_path = "res://assets/entities/骨架（已由TK拼好）/main.tres"
	super._ready()
	if requested_entry == EntryAction.NONE:
		entry_action = EntryAction.NONE
	effects_container.register_effect("骨架_s1_铠甲消散", preload("res://assets/entities/骨架（已由TK拼好）/eff/s1/n/effects_base.tscn"), true)

func _begin_entry():
	super._begin_entry()
	if entry_action == EntryAction.CUSTOM and current_animation == "jumpin":
		_update_eagle_entry()

func _physics_process(delta):
	if entry_action == EntryAction.CUSTOM and current_animation == "jumpin":
		_update_eagle_entry()
		return
	entry_eagle.hide()
	super._physics_process(delta)

func _update_eagle_entry():
	var pose := float(animated_sprite.frame) + animated_sprite.frame_progress
	var ride := clampf(pose / 2.0, 0.0, 1.0)
	var leap := clampf((pose - 2.0) / 9.0, 0.0, 1.0)
	var remaining := entry_fly_distance * (1.0 - 0.6 * ride) * (1.0 - leap)
	var height := entry_fly_height * (1.0 - leap * leap) + entry_leap_lift * 4.0 * leap * (1.0 - leap)
	is_grounded = pose >= 11.0
	set_position_3d(entry_pos3d + Vector3(facing_direction * remaining, 0, height))

	entry_eagle.visible = pose >= 2.0 and pose < 14.0
	if entry_eagle.visible:
		var flight := (pose - 2.0) / 12.0
		var eagle_x := entry_fly_distance * 0.4 - 550.0 * flight
		entry_eagle.position = Vector2(eagle_x - remaining, height - entry_fly_height - 90.0 * flight) / animated_sprite.scale
		entry_eagle.frame = int((pose - 2.0) / 2.0) % 2
		entry_eagle.modulate.a = 1.0 - smoothstep(0.65, 1.0, flight)
