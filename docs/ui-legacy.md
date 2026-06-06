# UI 遗留场景说明

- `res://sences/main_menu.tscn`：旧主菜单，引用已不存在的 `res://src/main_menu.gd`。**运行入口为** `res://sences/main_menu/main_menu.tscn`。
- `res://sences/game/panels/relationship_panel.tscn`：独立关系面板，**未接入** `DataPanelsUI` 导航；人物关系实际使用 `character_detail_panel.tscn`。

美化新功能请勿改以上遗留场景，除非产品决定接入或删除。
