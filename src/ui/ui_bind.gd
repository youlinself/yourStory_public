class_name UiBind
extends RefCounted

## 安全查找场景内唯一名节点并绑定按钮信号


static func find_named(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	var unique_path := "%%%s" % node_name
	if root.has_node(unique_path):
		return root.get_node(unique_path)
	return root.find_child(node_name, true, false)


static func connect_pressed(root: Node, node_name: String, callable: Callable) -> void:
	var btn := find_named(root, node_name) as Button
	if btn:
		btn.pressed.connect(callable)
