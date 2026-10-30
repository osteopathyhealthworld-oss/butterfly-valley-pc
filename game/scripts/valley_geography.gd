extends RefCounted
## Художественная география по мотивам Всеволожска. Это не цифровая модель высот.
## +Z — север на игровой карте; стартовая долина и старый мост сохранены.

const LAKES := [
	{"id": "round", "name": "Круглое озеро", "center": Vector2(-70, -94), "radii": Vector2(16, 16), "level": 1.2, "depth": 5.0},
	{"id": "long", "name": "Длинное озеро", "center": Vector2(45, -108), "radii": Vector2(11, 27), "level": 2.0, "depth": 6.0},
	{"id": "deep", "name": "Бездонное озеро", "center": Vector2(-25, -139), "radii": Vector2(10, 12), "level": 1.0, "depth": 9.0}
]
const PLACES := [
	{"id": "board", "name": "Площадь у лаборатории", "pos": Vector2(-1, -26), "radius": 5.0},
	{"id": "stores", "name": "Общий амбар", "pos": Vector2(16, -20), "radius": 8.0},
	{"id": "garden", "name": "Сад Нары", "pos": Vector2(-28, -31), "radius": 5.0},
	{"id": "craft", "name": "Стол алхимика", "pos": Vector2(-6, -26), "radius": 3.5},
	{"id": "meadow", "name": "Луг возвращённых бабочек", "pos": Vector2(-40, 37), "radius": 8.0},
	{"id": "quarry", "name": "Песчаный карьер", "pos": Vector2(85, -61), "radius": 7.0},
	{"id": "round", "name": "Берег Круглого", "pos": Vector2(-66, -74), "radius": 5.0},
	{"id": "long", "name": "Берег Длинного", "pos": Vector2(43, -76), "radius": 5.0},
	{"id": "deep", "name": "Берег Бездонного", "pos": Vector2(-25, -122), "radius": 4.0},
	{"id": "beacon", "name": "Румболовский маяк", "pos": Vector2(-23, 117), "radius": 7.0}
]
const ROUTES := [
	[Vector2(-1,-26), Vector2(16,-20), Vector2(24,-27)],
	[Vector2(24,-27), Vector2(32,-43), Vector2(45,-46)],
	[Vector2(-19,-40), Vector2(-30,-54), Vector2(-55,-66), Vector2(-66,-74)],
	[Vector2(16,-20), Vector2(27,-43), Vector2(43,-76)],
	[Vector2(27,-43), Vector2(58,-50), Vector2(85,-61)],
	[Vector2(-30,-54), Vector2(-38,-90), Vector2(-25,-122)],
	[Vector2(8,24), Vector2(-12,30), Vector2(-40,37)],
	[Vector2(15,43), Vector2(2,65), Vector2(-18,91), Vector2(-23,117)],
	[Vector2(12,32), Vector2(48,68), Vector2(92,108), Vector2(152,154)]
]
const BOUNDS := Rect2(-185, -180, 385, 375)

static func point(id: String) -> Vector2:
	for place in PLACES:
		if place["id"] == id:
			return place["pos"]
	return Vector2.ZERO

static func bump(p: Vector2, center: Vector2, radii: Vector2) -> float:
	var offset := (p - center) / radii
	var d := offset.length_squared()
	return 0.0 if d >= 1.0 else (1.0 - d) * (1.0 - d)

static func dry_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	# Оставляем начальные здания, сад и речную переправу на прежней высоте.
	var frontier := smoothstep(48.0, 85.0, p.length())
	var north := 15.0 * bump(p, Vector2(-24, 125), Vector2(77, 72))
	var south := 17.0 * bump(p, Vector2(38, -119), Vector2(110, 79))
	south += 9.0 * bump(p, Vector2(-78, -118), Vector2(72, 61))
	var valley := 1.0 - smoothstep(7.0, 28.0, absf(z - 9.0))
	var terraces := bump(p, Vector2(98,-76), Vector2(28,25))
	var quarry := -7.0 * smoothstep(0.05, 0.65, terraces)
	quarry -= 2.0 * smoothstep(0.65, 0.90, terraces)
	return (north + south + quarry) * frontier * (1.0 - valley)

static func lake_at(x: float, z: float, margin: float = 0.0) -> Dictionary:
	var p := Vector2(x,z)
	for lake in LAKES:
		var r: Vector2 = lake["radii"] + Vector2.ONE * margin
		if ((p - lake["center"]) / r).length_squared() < 1.0:
			return lake
	return {}

static func shape_height(x: float, z: float, original: float) -> float:
	var value := original + dry_height(x,z)
	var p := Vector2(x,z)
	for lake in LAKES:
		var r: Vector2 = lake["radii"]
		if absf(x - lake["center"].x) > r.x + 5.0 or absf(z - lake["center"].y) > r.y + 5.0:
			continue
		var radius: float = ((p - lake["center"]) / r).length()
		if radius < 1.3:
			var edge: float = float(lake["level"]) + (radius - 1.0) * 7.0
			var floor_y := float(lake["level"]) - float(lake["depth"]) * (1.0 - minf(radius,1.0) * 0.65)
			var shaped := maxf(floor_y, edge)
			value = lerpf(shaped, value, smoothstep(1.02,1.3,radius))
	return value

static func clearance(x: float, z: float) -> bool:
	for home in [Vector2(-27,-17.1),Vector2(-30,-36.1),Vector2(45,-43.1),Vector2(7,-39.1)]:
		if Vector2(x,z).distance_squared_to(home)<42.0: return true
	for work in [Vector2(-30,-6),Vector2(43,-22),Vector2(13,-3)]:
		if Vector2(x,z).distance_squared_to(work)<16.0: return true
	for place in PLACES:
		if Vector2(x,z).distance_squared_to(place["pos"]) < pow(float(place["radius"]),2.0):
			return true
	return false

static func region(x: float, z: float) -> String:
	for lake in LAKES:
		if ((Vector2(x,z) - lake["center"]) / (lake["radii"] + Vector2(9,9))).length_squared() < 1.0:
			return str(lake["name"])
	if Vector2(x,z).distance_to(Vector2(98,-76)) < 34.0:
		return "Песчаные террасы карьера"
	if z > 84.0 and x < 45.0:
		return "Румболовские холмы"
	if z < -85.0:
		return "Колтушские высоты"
	if x > 105.0 and z > 55.0:
		return "Дорога к большой воде"
	return ""
