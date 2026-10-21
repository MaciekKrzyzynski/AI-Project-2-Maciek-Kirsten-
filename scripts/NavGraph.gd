class_name NavGraph
extends RefCounted

class NavNode:
	var id: String
	var pos: Vector3
	var neighbors: Array[String] = []
	func _init(p_id: String, p_pos: Vector3) -> void:
		id = p_id
		pos = p_pos

var nodes: Dictionary = {}

func add_node(id: String, pos: Vector3) -> void:
	nodes[id] = NavNode.new(id, pos)

func link(a: String, b: String) -> void:
	if not nodes.has(a) or not nodes.has(b): return
	var na: NavNode = nodes[a]
	var nb: NavNode = nodes[b]
	if not na.neighbors.has(b): na.neighbors.append(b)
	if not nb.neighbors.has(a): nb.neighbors.append(a)

func get_pos(id: String) -> Vector3:
	if nodes.has(id): return (nodes[id] as NavNode).pos
	return Vector3.ZERO

func has_node(id: String) -> bool:
	return nodes.has(id)

func find_path(start_id: String, goal_id: String) -> Array:
	if not nodes.has(start_id) or not nodes.has(goal_id): return []
	if start_id == goal_id: return [start_id]

	var open_set: Array[String] = [start_id]
	var came_from: Dictionary = {}
	var g_score: Dictionary = { start_id: 0.0 }
	var f_score: Dictionary = { start_id: get_pos(start_id).distance_to(get_pos(goal_id)) }

	while not open_set.is_empty():
		var current: String = open_set[0]
		var current_f: float = f_score.get(current, 999999.0)
		for n in open_set:
			var nf: float = f_score.get(n, 999999.0)
			if nf < current_f:
				current = n
				current_f = nf

		if current == goal_id:
			return _reconstruct(came_from, current)

		open_set.erase(current)
		var cur_node: NavNode = nodes[current]
		for nb in cur_node.neighbors:
			var tentative_g: float = g_score.get(current, 999999.0) + get_pos(current).distance_to(get_pos(nb))
			if tentative_g < g_score.get(nb, 999999.0):
				came_from[nb] = current
				g_score[nb] = tentative_g
				f_score[nb] = tentative_g + get_pos(nb).distance_to(get_pos(goal_id))
				if not open_set.has(nb): open_set.append(nb)
	return []

func _reconstruct(came_from: Dictionary, current: String) -> Array:
	var path: Array = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path

func nearest_node_id(pos: Vector3) -> String:
	var best_id := ""
	var best_dist := 999999.0
	for id in nodes.keys():
		var d: float = (nodes[id] as NavNode).pos.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_id = id
	return best_id
