## PromptBuilder 压缩上下文（`godot --headless -s tests/prompt_builder_compact_test.gd`）
extends SceneTree


func _initialize() -> void:
	var failed := 0
	failed += _test_compact_map()
	failed += _test_compact_skills()
	failed += _test_compact_adventure()
	failed += _test_protagonist_prompt_plain_schema()
	failed += _test_compact_base_config()

	if failed == 0:
		print("[OK] prompt_builder_compact tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_compact_map() -> int:
	var full := {
		"overview": "测试概览",
		"regions": [{"id": "r1", "name": "区域1", "adjacent_region_ids": []}],
		"key_nodes": [{"id": "n1", "name": "节点", "region_id": "r1"}],
		"map_pages": [{"id": "page1", "cells": []}],
	}
	var text := PromptBuilder.compact_map_structure_json(full)
	if text.contains("map_pages"):
		push_error("compact map should omit map_pages")
		return 1
	if not text.contains("overview"):
		push_error("compact map should keep overview")
		return 1
	return 0


func _test_compact_skills() -> int:
	var db := {
		"skills": {
			"s1": {"name": "闪避", "desc": "很长很长的描述不应出现"},
			"s2": {"name": "洞察", "desc": "另一段描述"},
		},
	}
	var text := PromptBuilder.compact_skills_db_json(db)
	if text.contains("desc"):
		push_error("compact skills should omit desc")
		return 1
	if not text.contains("闪避"):
		push_error("compact skills should keep name")
		return 1
	return 0


func _test_compact_adventure() -> int:
	var adv := {
		"opening_hook": "钩子",
		"immediate_goal": "目标",
		"failure_pressure": "压力",
		"dm_secrets": "不应出现",
	}
	var text := PromptBuilder.compact_adventure_module_json(adv)
	if text.contains("dm_secrets"):
		push_error("compact adventure should omit dm_secrets")
		return 1
	if not text.contains("opening_hook"):
		push_error("compact adventure should keep opening_hook")
		return 1
	return 0


func _test_protagonist_prompt_plain_schema() -> int:
	var base := JSON.stringify({"novel_type": "历史", "world_setting": {}}, "\t")
	var skills := JSON.stringify([{"id": "s1", "name": "闪避"}], "\t")
	var map := JSON.stringify({"overview": "o", "regions": [], "key_nodes": []}, "\t")
	var adv := JSON.stringify(
		{"opening_hook": "h", "immediate_goal": "g", "failure_pressure": "p"},
		"\t",
	)
	var prompt := PromptBuilder.build_world_protagonist_prompt(base, skills, map, adv)
	if prompt.is_empty():
		push_error("protagonist prompt should not be empty")
		return 1
	if prompt.contains("```json"):
		push_error("protagonist prompt should not contain ```json fence after plain schema injection")
		return 1
	if not prompt.contains("最终输出格式（必须遵守）"):
		push_error("protagonist prompt should end with format lock section")
		return 1
	if not prompt.contains("禁止使用 Markdown 代码围栏"):
		push_error("protagonist prompt should include plain schema preamble")
		return 1
	return 0


func _test_compact_base_config() -> int:
	var long_text := "中".repeat(2000)
	var base := {
		"novel_type": "神话",
		"world_setting": {
			"nature_env": {"weather": long_text, "weather_keywords": ["晴"]},
		},
	}
	var text := PromptBuilder.compact_base_config_json(base, 800)
	if text.length() >= 2500:
		push_error("compact base config should truncate long paragraphs")
		return 1
	if not text.contains("神话"):
		push_error("compact base config should keep novel_type")
		return 1
	return 0
