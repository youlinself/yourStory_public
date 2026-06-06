class_name TurnToolActionCheck
extends RefCounted

const TurnToolRegistryScript := preload("res://src/game/logic/narrative/turn_tool_registry.gd")
const ActionCheckPlannerScript := preload("res://src/game/logic/rules/action_check_planner.gd")


static func run_requests(
	requests: Array,
	read_model: GameReadModel,
	pending_check: Dictionary,
	default_player_action: String,
) -> Dictionary:
	var out_check := pending_check.duplicate(true) if pending_check is Dictionary else {}
	var tool_results: Array = []
	for req in requests:
		if not req is Dictionary:
			continue
		if str(req.get("tool", "")) != TurnToolRegistryScript.TOOL_ACTION_CHECK:
			continue
		if not out_check.is_empty() and out_check.get("needs_check", false):
			tool_results.append(
				TurnToolRegistryScript.make_result(
					TurnToolRegistryScript.TOOL_ACTION_CHECK,
					true,
					{"check": out_check, "note": "已存在 pending_check，未重掷"},
				)
			)
			continue
		var args: Dictionary = req.get("args", {}) if req.get("args") is Dictionary else {}
		var action := str(args.get("player_action", default_player_action)).strip_edges()
		if action.is_empty():
			tool_results.append(
				TurnToolRegistryScript.make_result(
					TurnToolRegistryScript.TOOL_ACTION_CHECK,
					false,
					{},
					"缺少 player_action",
				)
			)
			continue
		out_check = ActionCheckPlannerScript.plan_and_roll(action, read_model)
		tool_results.append(
			TurnToolRegistryScript.make_result(
				TurnToolRegistryScript.TOOL_ACTION_CHECK,
				true,
				{"check": out_check},
			)
		)
	return {"check_result": out_check, "tool_results": tool_results}
