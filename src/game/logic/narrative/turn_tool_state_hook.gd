class_name TurnToolStateHook
extends RefCounted

const TurnToolRegistryScript := preload("res://src/game/logic/narrative/turn_tool_registry.gd")
const NarrativeHookNormalizerScript := preload(
	"res://src/game/logic/narrative/narrative_hook_normalizer.gd"
)


static func preview_hook(
	hook: Dictionary,
	read_model: GameReadModel,
	game_state: Dictionary,
) -> Dictionary:
	if hook.is_empty():
		return {
			"ok": true,
			"hook": {},
			"can_apply": false,
			"warnings": PackedStringArray(),
			"tool_results": [
				TurnToolRegistryScript.make_result(
					TurnToolRegistryScript.TOOL_STATE_HOOK,
					true,
					{"hook": {}, "can_apply": false},
				),
			],
		}
	var normalized := NarrativeHookNormalizerScript.normalize(hook, read_model, game_state)
	var warnings := _validate_hook_fields(normalized, read_model)
	var can_apply := NarrativeHookNormalizerScript.can_apply(normalized)
	if not can_apply and warnings.is_empty():
		warnings.append("缺少 datetime_display 或 weather，无法应用状态 hook")
	return {
		"ok": warnings.is_empty() or can_apply,
		"hook": normalized,
		"can_apply": can_apply,
		"warnings": warnings,
		"tool_results": [
			TurnToolRegistryScript.make_result(
				TurnToolRegistryScript.TOOL_STATE_HOOK,
				can_apply or warnings.is_empty(),
				{"hook": normalized, "can_apply": can_apply, "warnings": Array(warnings)},
				"" if can_apply or warnings.is_empty() else "状态 hook 校验未通过",
			),
		],
	}


static func run_requests(
	requests: Array,
	base_hook: Dictionary,
	read_model: GameReadModel,
	game_state: Dictionary,
) -> Dictionary:
	var merged := base_hook.duplicate(true)
	for req in requests:
		if not req is Dictionary:
			continue
		if str(req.get("tool", "")) != TurnToolRegistryScript.TOOL_STATE_HOOK:
			continue
		var args: Dictionary = req.get("args", {}) if req.get("args") is Dictionary else {}
		var proposed: Variant = args.get("hook", {})
		if proposed is Dictionary:
			merged.merge(proposed as Dictionary, true)
	return preview_hook(merged, read_model, game_state)


static func _validate_hook_fields(hook: Dictionary, read_model: GameReadModel) -> PackedStringArray:
	var warnings: PackedStringArray = []
	var region_id := str(hook.get("current_region_id", "")).strip_edges()
	if not region_id.is_empty() and read_model.get_region(region_id).is_empty():
		warnings.append("未知区域 id: %s" % region_id)
	var kn_id := str(hook.get("current_key_node_id", "")).strip_edges()
	if not kn_id.is_empty():
		var found := false
		for node in read_model.get_key_nodes():
			if str(node.get("id", "")).strip_edges() == kn_id:
				found = true
				break
		if not found:
			warnings.append("未知 key_node id: %s" % kn_id)
	var inv_delta: Variant = hook.get("inventory_delta", [])
	if inv_delta is Array:
		for entry in inv_delta:
			if not entry is Dictionary:
				continue
			var item_id := str(entry.get("id", "")).strip_edges()
			if item_id.is_empty():
				continue
			if not _item_exists_in_catalog(read_model, item_id):
				warnings.append("inventory_delta 未知物品 id: %s" % item_id)
	return warnings


static func _item_exists_in_catalog(read_model: GameReadModel, item_id: String) -> bool:
	var catalog := read_model.get_items_catalog()
	return catalog.has(item_id)
