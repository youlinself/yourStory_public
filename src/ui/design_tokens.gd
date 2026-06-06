class_name DesignTokens
extends RefCounted

## 现代清爽风 UI 设计 token（颜色、字号、间距）

# --- 背景层级 ---
const COLOR_BG_ROOT := Color(0.09, 0.1, 0.12, 1.0)
const COLOR_SURFACE := Color(0.11, 0.12, 0.15, 1.0)
const COLOR_SURFACE_RAISED := Color(0.13, 0.14, 0.17, 1.0)
const COLOR_SURFACE_CARD := Color(0.14, 0.15, 0.19, 1.0)
const COLOR_BORDER := Color(0.28, 0.32, 0.38, 0.85)
const COLOR_BORDER_SUBTLE := Color(0.22, 0.24, 0.3, 0.6)

# --- 布局 ---
## 主菜单中央内容区半宽/半高（与 main_menu CenterContainer 一致，400×500）
const MAIN_MENU_CONTENT_HALF_SIZE := Vector2(200.0, 250.0)
## 开屏 Logo 显示区最大边长（正方形）
const SPLASH_LOGO_MAX_SIZE := Vector2(200.0, 200.0)

# --- 文字 ---
const COLOR_TEXT_PRIMARY := Color(0.9, 0.92, 0.95, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.72, 0.75, 0.8, 1.0)
const COLOR_TEXT_MUTED := Color(0.58, 0.62, 0.68, 1.0)
const COLOR_TEXT_HINT := Color(0.65, 0.65, 0.7, 1.0)
const COLOR_TEXT_ACCENT := Color(0.55, 0.75, 0.95, 1.0)
const COLOR_TEXT_WALLET := Color(0.85, 0.78, 0.45, 1.0)
const COLOR_TEXT_ERROR := Color(0.9, 0.35, 0.35, 1.0)
const COLOR_TEXT_SUCCESS := Color(0.55, 0.82, 0.62, 1.0)
const COLOR_TEXT_LOCATION_FAR := Color(0.72, 0.68, 0.52, 1.0)
const COLOR_TEXT_GOAL := Color(0.72, 0.88, 0.78, 1.0)
const COLOR_TEXT_PRESSURE := Color(0.9, 0.72, 0.55, 1.0)
const COLOR_TEXT_CHECK_OK := Color(0.55, 0.82, 0.62, 1.0)
const COLOR_TEXT_CHECK_WARN := Color(0.85, 0.75, 0.45, 1.0)
const COLOR_TEXT_CHECK_FAIL := Color(0.9, 0.4, 0.4, 1.0)

# --- 交互 ---
const COLOR_ACCENT := Color(0.42, 0.62, 0.92, 1.0)
const COLOR_ACCENT_HOVER := Color(0.5, 0.7, 0.98, 1.0)
const COLOR_CHIP_SELECTED := Color(0.45, 0.9, 0.55, 1.0)
const COLOR_CHIP_NEUTRAL := Color(0.55, 0.62, 0.72, 1.0)
const COLOR_CHIP_ACTION := Color(0.52, 0.72, 0.58, 1.0)

# --- 地图字段（Color + hex 单一来源）---
const MAP_FIELD_KEYS: Array[String] = [
	"location", "terrain", "climate", "resources", "hazards", "access", "settlements",
]

const MAP_FIELD_COLORS: Dictionary = {
	"location": Color(0.35, 0.55, 0.85),
	"terrain": Color(0.45, 0.65, 0.45),
	"climate": Color(0.55, 0.75, 0.95),
	"resources": Color(0.85, 0.75, 0.35),
	"hazards": Color(0.85, 0.45, 0.4),
	"access": Color(0.65, 0.55, 0.85),
	"settlements": Color(0.55, 0.7, 0.75),
}

const MAP_OVERVIEW_HEX := "#d4dae3"
const MAP_PLACEHOLDER_HEX := "#8a909c"
const STORY_USER_HEX := "#8ab4f8"
const STORY_DIALOGUE_PREFIX_HEX := "#9ec5e8"
const STORY_ACTION_HEX := "#8ab4f8"
const STORY_CHECK_HEX := "#9ec5e8"

# --- 地图绘制 ---
const MAP_REGION_FILL := Color(0.28, 0.3, 0.36, 1.0)
const MAP_REGION_CURRENT := Color(0.32, 0.52, 0.78, 1.0)
const MAP_REGION_STROKE := Color(0.88, 0.9, 0.95, 0.9)
const MAP_REGION_PULSE := Color(0.5, 0.78, 0.98, 0.32)
const MAP_KEY_NODE := Color(0.92, 0.78, 0.38, 1.0)
const MAP_KEY_NODE_CURRENT := Color(0.48, 0.92, 0.58, 1.0)
const MAP_KEY_NODE_PULSE := Color(0.48, 0.92, 0.58, 0.28)
const MAP_HERO_CELL_FILL := Color(0.22, 0.55, 0.90, 0.32)
const MAP_HERO_CELL_STROKE := Color(0.52, 0.88, 1.0, 1.0)
const MAP_TRAVEL_CELL_FILL := Color(0.18, 0.72, 0.35, 0.35)
const MAP_TRAVEL_CELL_STROKE := Color(0.3, 1.0, 0.5, 1.0)
const MAP_BLOCKED_CELL_FILL := Color(0.85, 0.15, 0.15, 0.30)
const MAP_SIDEBAR_CURRENT_FILL := Color(0.18, 0.28, 0.42, 1.0)
const MAP_SIDEBAR_CURRENT_BORDER := Color(0.42, 0.62, 0.92, 0.95)
const MAP_LINK := Color(0.4, 0.48, 0.58, 0.55)
const MAP_LINK_HIGHLIGHT := Color(0.48, 0.72, 0.95, 0.88)
const MAP_LEADER := Color(0.72, 0.68, 0.58, 0.42)

# --- 雷达图 ---
const RADAR_GRID := Color(0.35, 0.38, 0.45, 0.5)
const RADAR_FILL := Color(0.32, 0.52, 0.82, 0.32)
const RADAR_STROKE := Color(0.45, 0.72, 0.95, 0.9)

# --- 圆角与间距 ---
const RADIUS_SM := 6
const RADIUS_MD := 8
const RADIUS_LG := 10
const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 16
const SPACE_XL := 24

# --- 字号 ---
const FONT_DISPLAY := 48
const FONT_PAGE_TITLE := 32
const FONT_PANEL_TITLE := 28
const FONT_SECTION := 18
const FONT_BODY := 15
const FONT_BODY_SM := 14
const FONT_CAPTION := 12
const FONT_CHIP := 12

# --- 顶栏导航按钮 ---
const NAV_BUTTON_HEIGHT := 36

# --- 详情面板边距 ---
const PANEL_MARGIN := Vector4(24, 20, 24, 20)


static func map_field_hex(field_key: String) -> String:
	var c: Color = MAP_FIELD_COLORS.get(field_key, COLOR_TEXT_SECONDARY)
	return color_to_hex(c)


static func color_to_hex(c: Color) -> String:
	return "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
