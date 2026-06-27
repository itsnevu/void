extends Control


@onready var label: Label = $ProgressBar/Label
@onready var progress_bar: ProgressBar = $ProgressBar


func _ready() -> void:
	ClientState.local_player_ready.connect(
		func(local_player: LocalPlayer) -> void:
			local_player.stats_component.stats.stat_changed.connect(_on_stat_changed)
			_on_stat_changed(Stat.HEALTH, local_player.stats_component.get_stat(Stat.HEALTH))
			_on_stat_changed(Stat.HEALTH_MAX, local_player.stats_component.get_stat(Stat.HEALTH_MAX))
	)


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.HEALTH:
		_on_health_changed(value)
	if stat_name == Stat.HEALTH_MAX:
		_on_max_health_changed(value)


func _on_health_changed(new_health: float) -> void:
	progress_bar.value = new_health
	update_label()


func _on_max_health_changed(new_max_health: float) -> void:
	progress_bar.max_value = new_max_health
	update_label()


func update_label() -> void:
	label.text = "%d / %d" % [progress_bar.value, progress_bar.max_value]
