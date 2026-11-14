# preset_sigil.gd  (Phase 3 — crafting shell)
class_name PresetSigil
extends Resource

@export var name: String = "Unnamed Sigil"
@export var description: String = ""
@export var attractor_family: String = "Lorenz"
@export var params: Dictionary = {}
@export var color: Color = Color.WHITE

# Create a default preset library.
static func default_presets() -> Array[PresetSigil]:
	var presets: Array[PresetSigil] = []
	
	var p1 := PresetSigil.new()
	p1.name = "Tidecaller's Weave"
	p1.description = "A gentle Lorenz attractor. Slow, wide loops."
	p1.attractor_family = "Lorenz"
	p1.params = {"sigma": 10.0, "rho": 28.0, "beta": 2.667}
	p1.color = Color(0.3, 0.6, 1.0)
	presets.append(p1)
	
	var p2 := PresetSigil.new()
	p2.name = "Stormcaller's Spiral"
	p2.description = "High rho, tight spirals. Volatile."
	p2.attractor_family = "Lorenz"
	p2.params = {"sigma": 10.0, "rho": 40.0, "beta": 2.667}
	p2.color = Color(1.0, 0.5, 0.3)
	presets.append(p2)
	
	var p3 := PresetSigil.new()
	p3.name = "Warden's Shield"
	p3.description = "Low sigma, stable loops. Defensive."
	p3.attractor_family = "Lorenz"
	p3.params = {"sigma": 5.0, "rho": 20.0, "beta": 2.667}
	p3.color = Color(0.3, 0.8, 0.4)
	presets.append(p3)
	
	return presets