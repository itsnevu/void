class_name SlashEffect
extends Node2D
## A brief melee slash flourish: a bright crescent arc thrown in the swing
## direction that expands and fades in ~0.2s, then frees itself. Pure client
## visual, spawned by [MeleeSwingAbility] when a swing fires.
##
## A STANDALONE self-drawing node (the SpawnEffect / telegraph family), so it
## renders regardless of the wielder's replicated modulate/scale. [code]fancy[/code]
## (special weapons - arcane blade, void axe) adds a brighter additive
## over-stroke; plain weapons get the single steel arc.

const LIFETIME: float = 0.2
const BASE_RADIUS: float = 24.0
## Half-angle of the crescent, radians (~66 deg each side of the swing dir).
const HALF_ARC: float = 1.15

var color: Color = Color(0.92, 0.96, 1.0)
var fancy: bool = false
var _t: float = 0.0


## Aim the arc along [param direction] and stamp its look. Call right after
## adding the effect to the tree and setting its global_position.
func setup(direction: Vector2, slash_color: Color, slash_scale: float, is_fancy: bool) -> void:
	color = slash_color
	fancy = is_fancy
	rotation = direction.angle() if direction != Vector2.ZERO else 0.0
	scale = Vector2.ONE * maxf(0.1, slash_scale)
	z_index = 1 if fancy else 0


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k: float = clampf(_t / LIFETIME, 0.0, 1.0)
	var alpha: float = 1.0 - k
	var radius: float = BASE_RADIUS * (1.0 + 0.3 * k) # slight outward whip
	var points: PackedVector2Array = PackedVector2Array()
	var segments: int = 16
	for i: int in segments + 1:
		var a: float = lerpf(-HALF_ARC, HALF_ARC, float(i) / float(segments))
		points.append(Vector2(cos(a), sin(a)) * radius)
	var stroke: Color = color
	stroke.a = alpha
	draw_polyline(points, stroke, 4.0 if fancy else 3.0, true)
	if fancy:
		# Bright white core over-stroke reads as an arcane/void shimmer.
		var glow: Color = Color(1.0, 1.0, 1.0, alpha * 0.85)
		draw_polyline(points, glow, 1.5, true)
