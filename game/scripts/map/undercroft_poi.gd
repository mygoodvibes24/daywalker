extends Node3D
## The Undercroft Depths as a Hunt point of interest (registered with hunt_director.register_poi
## by map/undercroft.gd). It sits on the plaza well, shows on the map and the compass, and counts
## as cleared once the rival daywalker below is dead. It spawns nothing: the crypt runs its own duel.
## Speaks poi.gd's duck API.

var depths # map/undercroft.gd
var type := "undercroft"
var def := {
	"label": "Undercroft Depths",
	"color": Color(0.95, 0.25, 0.2),
	"blurb": "Down the well under the cathedral. Someone is waiting, and he wants a fight.",
	"tithe": 0, "reward": -1, "day": [], "night": [],
}
var display_name := "Undercroft Depths"
var cleared := false
var roused := false


func is_combat() -> bool:
	return true


## Members standing on the street for this site: none (the rival lives down in the crypt).
func total_alive() -> int:
	return 0


func distance_to(p: Vector3) -> float:
	return Vector2(global_position.x - p.x, global_position.z - p.z).length()


func tick(_delta: float, _ppos: Vector3, _budget: int) -> int:
	if depths != null and depths.rival_dead:
		cleared = true
	return 0


func on_light_changed(_day: bool) -> void:
	pass


func recall(_keep: Callable = Callable()) -> void:
	pass


func interaction(_ppos: Vector3) -> Dictionary:
	return {}
