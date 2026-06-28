extends Control
## HUD stamina bar — sibling of ManaBar (same pattern): subscribes to the local
## player's stat sync and mirrors ENERGY / ENERGY_MAX. Stamina gates physical
## abilities (melee swings, charge shots), the martial counterpart of mana.


@onready var label: Label = $ProgressBar/Label
@onready var progress_bar: ProgressBar = $ProgressBar


func _ready() -> void:
	ClientState.local_player_ready.connect(
		func(local_player: LocalPlayer) -> void:
			local_player.stats_component.stats.stat_changed.connect(_on_stat_changed)
			_on_stat_changed(Stat.ENERGY, local_player.stats_component.get_stat(Stat.ENERGY))
			_on_stat_changed(Stat.ENERGY_MAX, local_player.stats_component.get_stat(Stat.ENERGY_MAX))
	)


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.ENERGY:
		progress_bar.value = value
		_update_label()
	if stat_name == Stat.ENERGY_MAX:
		progress_bar.max_value = value
		_update_label()


func _update_label() -> void:
	label.text = "%d / %d" % [progress_bar.value, progress_bar.max_value]
