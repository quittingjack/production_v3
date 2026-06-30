extends Node


func log(node: Node, function_name: String, action: String, params: Dictionary = {}) -> void:
	_emit("INFO", node, function_name, action, params)


func warn(node: Node, function_name: String, action: String, params: Dictionary = {}) -> void:
	var message := _format_message("WARN", node, function_name, action, params)
	if message == "":
		return
	push_warning(message)


func error(node: Node, function_name: String, action: String, params: Dictionary = {}) -> void:
	var message := _format_message("ERROR", node, function_name, action, params)
	if message == "":
		return
	push_error(message)


func _emit(level: String, node: Node, function_name: String, action: String, params: Dictionary = {}) -> void:
	var message := _format_message(level, node, function_name, action, params)
	if message == "":
		return
	print(message)


func _format_message(level: String, node: Node, function_name: String, action: String, params: Dictionary = {}) -> String:
	if node == null or not is_instance_valid(node):
		return ""

	var file_path := ""
	var script: Script = node.get_script() as Script
	if script and script.resource_path != "":
		file_path = str(script.resource_path)

	var params_text := ""
	if not params.is_empty():
		params_text = " | params: %s" % [params]

	return "[%s] [Node: %s] [File: %s] [Fn: %s] %s%s" % [
		level,
		node.name,
		file_path,
		function_name,
		action,
		params_text,
	]
