extends Node
## 4B-8's scene-free attachment, the MarksWatch/TelemetryWatch pattern.
## Only a parent with RoadBuilder + TerrainBuilder + ForestWalls qualifies.
## Deferred attachment happens after their synchronous _ready builds; the
## Buildings node is added before its own _ready does any work. The loader
## calls the same idempotent BuildingsShells.of() while its Ring is still
## outside the tree, claims it, and supplies the four new async stages.
## No scene-file edit, no child under Terrain, no collision under Terrain.

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node.get_node_or_null("Road") is RoadBuilder and node.get_node_or_null("Terrain") is TerrainBuilder and node.get_node_or_null("Forest") is ForestWalls:
		_attach.call_deferred(node.get_instance_id())

func _attach(id: int) -> void:
	var scene := instance_from_id(id) as Node
	if scene != null and scene.is_inside_tree() and not scene.is_queued_for_deletion():
		BuildingsShells.of(scene)
