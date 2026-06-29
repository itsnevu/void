class_name MeleeSwingAbility
extends AbilityResource
## Generic "swing a melee weapon" ability. Owns the hitbox spawn, damage
## resolution, and animation hook. The ability lives in combat/ - any
## melee weapon (sword, axe, dagger, future hammer) references it from its
## item.tres without re-implementing the swing.
##
## Per-weapon tuning happens via the @export fields below: a heavy axe might
## bump base_damage and spawn_offset; a dagger might shrink both.


## Spawned in front of [param user] when the swing fires.
@export var arc_scene: PackedScene = preload("res://source/common/gameplay/combat/melee_arc.tscn")
## Damage as a fraction of the wielder's AD (LoL-style). 1.0 = a swing deals
## 100% of your AD; a heavy slow weapon might go 1.3, a fast dagger 0.7. AD comes
## from base + the Strength attribute + gear (incl. the weapon's own AD bonus),
## so a stronger character / better weapon scales every swing.
@export var ad_ratio: float = 1.0
## How far forward (along [param direction]) the hitbox spawns from the
## character's origin. The CollisionShape inside the arc scene already has
## its own forward offset + radius - this just biases the whole spawn so
## tuning reach is one number instead of two. Keep small (0-8) for most
## weapons; bump higher for polearms / spears.
@export var spawn_offset: float = 0.0
## Animation to play when the swing fires. Library prefix included
## (e.g. "weapon/sword.swing"). The weapon scene loads the library on equip.
@export var swing_animation: StringName

## On-hit slow (Crippling Strike): flat move_speed cut + duration, handed to the
## arc so each struck Player gets a timed negative buff. 0 = no slow.
@export var slow_amount: float = 0.0
@export var slow_duration_s: float = 0.0

## Overrides the arc scene's hitbox radius (0 = keep the scene default). Lets a
## "devastating" T3 swing actually hit a bigger area than the basic swing while
## reusing the same arc scene - pair it with a matching [member impact_reach].
@export var arc_radius: float = 0.0

@export_group("Slash VFX")
## Tint of the slash crescent thrown on swing. Default steel-white for plain
## weapons; WeaponItem.fancy_slash pushes a violet here for special weapons.
@export var slash_color: Color = Color(0.92, 0.96, 1.0)
## Size multiplier for the crescent (a greatweapon reads bigger than a dagger).
@export var slash_scale: float = 1.0
## Brighter additive double-stroke for special weapons (arcane blade, void axe).
@export var slash_fancy: bool = false
## Optional swing/whoosh sound (res:// path), played client-side on swing. Empty
## = silent. NOTE: no whoosh asset ships yet - drop one in assets/audio/sfx and
## set this (per weapon via WeaponItem, or here for the shared default).
@export var slash_sound: String = ""


func use_ability(user: Entity, direction: Vector2) -> void:
	# Animation runs on every peer (client AND server) so the swing reads
	# visually on every screen. Character.play_action_animation is a no-op
	# on the headless server, so we can call it unconditionally.
	if user is Character:
		(user as Character).play_action_animation(swing_animation)

	# Slash flourish + optional sound: client-only, timed with the swing anim.
	# (Telegraphed heavy swings skip it - their CastTelegraph IS the wind-up read.)
	if GameMode.is_client() and cast_time_s <= 0.0 and user is Character:
		_spawn_slash(user, direction)

	# Telegraphed heavy swing: show the danger zone on clients while the wind-up
	# plays, and DELAY the damage so it lands with the visual (targets can step
	# out). The weapon's wind-up length matches cast_time_s.
	if cast_time_s > 0.0:
		if GameMode.is_client():
			_spawn_telegraph(user, direction)
		if GameMode.is_world_server() and user != null:
			user.get_tree().create_timer(cast_time_s).timeout.connect(_fire_arc.bind(user, direction))
		return

	# Hitbox + damage are server-authoritative. Clients trust the server's
	# combat.hit broadcast for damage feedback (numbers, flash, sound).
	if not GameMode.is_world_server():
		return
	_fire_arc(user, direction)


## Spawns the actual damage hitbox. Split out so a telegraphed swing can defer
## it past the wind-up. Server-only; guards against a caster freed/killed mid-cast.
func _fire_arc(user: Entity, direction: Vector2) -> void:
	if not GameMode.is_world_server() or not is_instance_valid(user):
		return
	if user is Character and (user as Character).is_dead:
		return
	if arc_scene == null:
		return
	var arc: MeleeArc = arc_scene.instantiate()
	arc.source = user if user is Character else null
	arc.slow_amount = slow_amount
	arc.slow_duration_s = slow_duration_s
	# Optional bigger hitbox for heavy swings - duplicate the shape so we resize
	# THIS arc only, never the shared CircleShape2D sub-resource.
	if arc_radius > 0.0:
		var shape_node: CollisionShape2D = arc.get_node_or_null(^"CollisionShape2D")
		if shape_node != null and shape_node.shape is CircleShape2D:
			var circle: CircleShape2D = shape_node.shape.duplicate()
			circle.radius = arc_radius
			shape_node.shape = circle
	# A swing deals ad_ratio x the wielder's AD (base + Strength + gear), so both
	# leveling and a better weapon raise every hit.
	var ad: float = (user as Character).stats_component.get_stat(Stat.AD) if user is Character else 0.0
	arc.damage = ad * ad_ratio
	var dir_norm: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	arc.global_position = user.global_position + dir_norm * spawn_offset
	arc.rotation = dir_norm.angle()
	user.get_parent().add_child(arc)


## Client-only slash crescent (and optional whoosh) thrown along the swing.
## Spawned in the world like the hitbox so it sits in front of the wielder.
func _spawn_slash(user: Entity, direction: Vector2) -> void:
	if user == null or user.get_parent() == null:
		return
	var dir_norm: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	var slash: SlashEffect = SlashEffect.new()
	user.get_parent().add_child(slash)
	# Spawn at the HAND, not the character origin (which sits at the feet in this
	# top-down view) - otherwise the arc draws on the ground under the character.
	var origin: Vector2 = user.global_position
	if user is Character and (user as Character).right_hand_spot != null:
		origin = (user as Character).right_hand_spot.global_position
	slash.global_position = origin + dir_norm * (spawn_offset + 4.0)
	slash.setup(dir_norm, slash_color, slash_scale, slash_fancy)
	if not slash_sound.is_empty() and is_instance_valid(Client) and Client.audio_manager != null:
		Client.audio_manager.play_sfx(slash_sound, user.global_position)


## Client-visual danger marker shown during a telegraphed swing's wind-up, at
## the strike point and sized to the hitbox so what's marked is what hits.
func _spawn_telegraph(user: Entity, direction: Vector2) -> void:
	if user == null or user.get_parent() == null:
		return
	var dir_norm: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	var tele: CastTelegraph = CastTelegraph.new()
	tele.radius = arc_radius if arc_radius > 0.0 else 32.0
	tele.duration = cast_time_s
	user.get_parent().add_child(tele)
	tele.global_position = user.global_position + dir_norm * spawn_offset
