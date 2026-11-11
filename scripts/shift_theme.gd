class_name ShiftTheme
extends RefCounted
## A colour theme per shift. Only the station's look changes (walls, floor, ceiling,
## haze, ambient and hub light). Meaning colours never change: red = faulted,
## cyan = repaired, gold = interactive text. The theme depends only on the shift
## number, so a retry keeps the same theme, and the same shift is always the same.

const THEMES := [
	{
		"name": "MIDNIGHT",
		"wall": Color8(53, 58, 121),
		"floor": Color8(33, 37, 69),
		"ceiling": Color8(27, 31, 63),
		"ambient": Color8(53, 58, 121),
		"fog": Color8(33, 37, 69),
		"background": Color8(16, 20, 43),
		"hub_light": Color(0.8, 0.86, 1.0),
	},
	{
		"name": "EMERALD",
		"wall": Color8(40, 96, 78),
		"floor": Color8(22, 52, 46),
		"ceiling": Color8(17, 42, 38),
		"ambient": Color8(40, 96, 78),
		"fog": Color8(22, 52, 46),
		"background": Color8(10, 28, 26),
		"hub_light": Color(0.82, 1.0, 0.9),
	},
	{
		"name": "EMBER",
		"wall": Color8(116, 80, 48),
		"floor": Color8(60, 40, 28),
		"ceiling": Color8(46, 31, 24),
		"ambient": Color8(116, 80, 48),
		"fog": Color8(60, 40, 28),
		"background": Color8(26, 16, 14),
		"hub_light": Color(1.0, 0.9, 0.78),
	},
	{
		"name": "ORCHID",
		"wall": Color8(112, 58, 124),
		"floor": Color8(58, 30, 66),
		"ceiling": Color8(44, 24, 52),
		"ambient": Color8(112, 58, 124),
		"fog": Color8(58, 30, 66),
		"background": Color8(26, 12, 32),
		"hub_light": Color(0.96, 0.84, 1.0),
	},
	{
		"name": "STEEL",
		"wall": Color8(76, 92, 112),
		"floor": Color8(38, 46, 58),
		"ceiling": Color8(30, 37, 48),
		"ambient": Color8(76, 92, 112),
		"fog": Color8(38, 46, 58),
		"background": Color8(14, 18, 26),
		"hub_light": Color(0.9, 0.95, 1.0),
	},
]


## The theme for a shift number (1-based). Shift 1 is MIDNIGHT; they repeat after the last.
static func for_shift(run_number: int) -> Dictionary:
	var index := posmod(run_number - 1, THEMES.size())
	return THEMES[index]
