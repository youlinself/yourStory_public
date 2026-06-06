class_name HistorySessionReadModel
extends RefCounted

var session_id: String = ""
var game_state: Dictionary = {}
var map_db: Dictionary = {}
var mainrole: Dictionary = {}


func load(session_id_value: String) -> bool:
	var id := session_id_value.strip_edges()
	if id.is_empty():
		return false
	var dir := GameHistoryService.load_session_dir(id)
	if dir.is_empty():
		return false

	session_id = id
	game_state = _load_json_from_dir(dir, GameRunningFileManager.GAME_STATE)
	map_db = _load_json_from_dir(dir, GameRunningFileManager.MAP_DB)
	mainrole = _load_json_from_dir(dir, GameRunningFileManager.MAIN_ROLE)

	if game_state.is_empty():
		game_state = RuntimeDbSchemas.empty_game_state()
	return true


func get_events_chronological() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var raw: Variant = game_state.get("event_log", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				events.append(item)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("timestamp", 0)) < int(b.get("timestamp", 0))
	)
	return events


func get_region(region_id: String) -> Dictionary:
	for region in get_regions():
		if str(region.get("id", "")) == region_id:
			return region
	return {}


func get_regions() -> Array:
	var ms: Variant = map_db.get("map_structure", {})
	if not ms is Dictionary:
		return []
	var regions: Variant = ms.get("regions", [])
	return regions if regions is Array else []


func get_region_name(region_id: String) -> String:
	var rid := region_id.strip_edges()
	if rid.is_empty():
		return ""
	return str(get_region(rid).get("name", "")).strip_edges()


static func _load_json_from_dir(dir: String, file_name: String) -> Dictionary:
	var path := dir + file_name
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var data: Variant = json.get_data()
	return data if data is Dictionary else {}
