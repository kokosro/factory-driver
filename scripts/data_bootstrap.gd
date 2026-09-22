extends Node
## The data folder, settled before anything reads it: an autoload
## (project.godot, DataBootstrap), so it runs before the main scene's car
## reads its store and before the mission manager's recorder opens a file.
## Reads where the data folder is (DataDir.read_root: the FD_DATA_DIR
## variable, the bootstrap file, or the default) and, in the running game
## only, seeds a folder new to the game with a copy of what the previous
## location holds (DataDir.seed_on_startup). Behind the store's own switch
## (OdometerStore.enabled): the headless suite reads the root the same way
## and copies nothing. Nothing else lives here.

## What the seed did this run, for the SETTINGS page: DataDir.seed()'s
## dictionary, empty where nothing was seeded (the suite).
var seeded: Dictionary = {}


func _ready() -> void:
	DataDir.read_root()
	if OdometerStore.enabled():
		seeded = DataDir.seed_on_startup()
