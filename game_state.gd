# game_state.gd  (Phase E — run configuration singleton)
extends Node

# Seed for the next generated level. Set from the main menu; read by main.gd.
var seed: int = 12345

# Last generated level's graph summary (for debugging/replay).
var last_graph_summary: String = ""