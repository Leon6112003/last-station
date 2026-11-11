class_name UiStyle
extends RefCounted
## Shared look for the in-game windows (puzzle panels, Manuals, ORACLE).


## A solid dark panel. The default Godot panel is slightly see-through, which let
## the 3D world and HUD text show through the chat window.
static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Rules.COLOR_NAVY.lightened(0.04), 0.98)
	style.border_color = Rules.COLOR_INDIGO
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
