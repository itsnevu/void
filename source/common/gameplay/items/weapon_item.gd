class_name WeaponItem
extends GearItem


## Mastery category this weapon belongs to (&"sword", &"bow", &"wand",
## &"hammer"). Killing with it earns mastery xp for the category; empty = no
## mastery (tools, special-case weapons). See docs/mastery.md.
@export var category: StringName
## Max ability weight (= node tier) the special slot accepts - the gear half
## of the mastery system: higher-tier weapons channel heavier abilities.
@export_range(1, 3) var capacity: int = 1

@export var right_hand_scene: PackedScene

@export var left_hand_scene: PackedScene

## Optional per-skin nudge for the in-hand sprite, when a skin's art sits
## differently than the type scene's default (e.g. a taller blade). ZERO =
## use the scene's placement as-is. See Weapon.apply_skin.
@export var sprite_offset: Vector2 = Vector2.ZERO

## Per-skin uniform scale for the in-hand sprite. 1.0 = native pixel size (what
## the small 16-wide weapon art is drawn for). Chunky skin art (a 48-wide
## sword sheet) sets this < 1 so it doesn't dwarf the character.
@export var sprite_scale: float = 1.0

## Flip the in-hand sprite horizontally RELATIVE to the type-scene default.
## The scene draws blades flipped one way; skins whose art faces the other way
## set this true so the blade points forward, not back across the body.
@export var flip_sprite: bool = false

## Per-weapon melee tuning, applied to THIS weapon's primary swing ability on
## equip (each weapon instance owns its abilities, so this never leaks across
## weapons). <= 0 keeps the shared swing ability's own value, so ordinary
## swords leave these untouched. A heavy axe wants a long cooldown + high
## ad_ratio (slow, hits hard); a dagger a short cooldown + low ad_ratio
## (fast, light). See [MeleeSwingAbility].
@export var attack_cooldown_override: float = 0.0
@export var ad_ratio_override: float = 0.0
## Swing reach: overrides the hitbox circle radius (0 = arc scene default, 22).
## A longer blade / big axe wants a bigger value, a dagger a smaller one. The
## slash VFX auto-sizes to match. See [MeleeSwingAbility.arc_radius].
@export var arc_radius_override: float = 0.0
## Forward bias of the whole hitbox along the swing (0 = ability default). Pairs
## with arc_radius for a touch more/less reach. See [MeleeSwingAbility.spawn_offset].
@export var reach_override: float = 0.0
## Per-weapon swing sound (res:// path), overriding the swing ability's default.
## E.g. a heavy axe gets its own thud while swords share the basic slash.
@export var slash_sound_override: String = ""

## Special-weapon slash VFX: a brighter, larger [param slash_color] crescent on
## swing instead of the plain steel arc. Pushed onto this weapon's swing ability
## at equip. Leave false for ordinary weapons. See [SlashEffect].
@export var fancy_slash: bool = false
@export var slash_color: Color = Color(0.66, 0.4, 0.95)


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	# Mastery weapons lead with type + ability-slot capacity ("Sword - Power 2/3").
	# Tools (empty category) skip it. Then the inherited modifiers + level gate.
	if not category.is_empty():
		lines.append({"text": "%s - Power %d/3" % [String(category).capitalize(), capacity], "kind": &"weapon"})
	lines.append_array(super())
	return lines


func equip(character: Character) -> void:
	super.equip(character)

	if right_hand_scene:
		var right_hand_weapon: Weapon = right_hand_scene.instantiate()
		right_hand_weapon.character = character
		character.equipment_component.mounted_nodes[slot.key] = right_hand_weapon
		character.right_hand_spot.add_child(right_hand_weapon)
		# Skin the in-hand sprite from this item's icon, so one type-scene
		# (sword.tscn) serves every sword skin (fire, rustic, ...).
		right_hand_weapon.apply_skin(item_icon, sprite_offset, sprite_scale, flip_sprite)
		# Per-weapon swing feel (attack speed + hit weight): a dagger swings fast
		# and light, an axe slow and heavy, all off the SAME shared swing ability
		# - overridden here on this instance only (Weapon._ready already gave it
		# its own ability copy, so the shared .tres is untouched).
		_apply_swing_overrides(right_hand_weapon)
	
	if left_hand_scene:
		var left_hand_weapon: Weapon = left_hand_scene.instantiate()
		left_hand_weapon.character = character
		character.left_hand_spot.add_child(left_hand_weapon)
	else:
		if character.left_hand_spot.get_child_count():
			character.left_hand_spot.get_child(0).queue_free()
			#character.left_hand_spot.remove_child(character.left_hand_spot.get_child(0))


## Stamp this weapon's per-item cooldown / ad_ratio onto its primary swing,
## when set (> 0). Runs after the weapon's _ready, so abilities[0] is the
## instance's own MeleeSwingAbility copy; a no-op for non-melee weapons.
func _apply_swing_overrides(weapon: Weapon) -> void:
	if weapon.abilities.is_empty() or weapon.abilities[0] is not MeleeSwingAbility:
		return
	var swing: MeleeSwingAbility = weapon.abilities[0] as MeleeSwingAbility
	if attack_cooldown_override > 0.0:
		swing.cooldown = attack_cooldown_override
	if ad_ratio_override > 0.0:
		swing.ad_ratio = ad_ratio_override
	if arc_radius_override > 0.0:
		swing.arc_radius = arc_radius_override
		# Slash crescent grows/shrinks with reach so the VFX matches the hitbox.
		swing.slash_scale = clampf(arc_radius_override / 24.0, 0.6, 1.8)
	if not is_zero_approx(reach_override):
		swing.spawn_offset = reach_override
	if not slash_sound_override.is_empty():
		swing.slash_sound = slash_sound_override
	if fancy_slash:
		swing.slash_fancy = true
		swing.slash_color = slash_color


func unequip(character: Character) -> void:
	super.unequip(character)

	var weapon: Node = character.equipment_component.mounted_nodes.get(slot.key, null)
	if weapon:
		weapon.queue_free()
	character.equipment_component.mounted_nodes.erase(slot.key)
	for child in character.left_hand_spot.get_children():
		child.queue_free()
