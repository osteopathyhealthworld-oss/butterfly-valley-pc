extends Control
## Точная схема игрового рельефа; координаты общие с навигацией и заданиями.
const GEO=preload("res://scripts/valley_geography.gd")
var chapter: Node3D
const LABELS:Dictionary={"round":"Круглое", "long":"Длинное", "deep":"Бездонное", "quarry":"Карьер", "beacon":"Румболовский маяк", "meadow":"Луг бабочек"}

func _ready() -> void:
	resized.connect(queue_redraw)
	tooltip_text="Нажми на точку, чтобы отметить место."
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var nearest:Dictionary={}
		var distance:=15.0
		for place in GEO.PLACES:
			var d:float=event.position.distance_to(_point(place["pos"]))
			if d<distance:
				distance=d
				nearest=place
		if chapter!=null:
			for id in chapter.sim.projects.projects:
				var d: float=event.position.distance_to(_point(chapter.sim.PROJECTS.POINTS[id]))
				if d<distance:
					distance=d
					nearest={"id":id}
		if not nearest.is_empty() and chapter!=null:
			chapter._track(str(nearest["id"]))
			accept_event()

func _point(p: Vector2) -> Vector2:
	return Vector2((p.x+160.0)/340.0*size.x,(170.0-p.y)/350.0*size.y)

func _draw() -> void:
	draw_style_box(_background(),Rect2(Vector2.ZERO,size))
	for center in [Vector2(-24,125),Vector2(38,-119),Vector2(-78,-118)]:
		for ring in range(3):
			draw_arc(_point(center),float(16+ring*9),0,TAU,40,Color(0.58,0.63,0.42,0.35),1.0)
	for lake in GEO.LAKES:
		var polygon:=PackedVector2Array()
		for i in range(48):
			var angle:=TAU*float(i)/48.0
			polygon.append(_point(lake["center"]+Vector2(cos(angle),sin(angle))*lake["radii"]))
		draw_colored_polygon(polygon,Color("#547e86"))
	var river:=PackedVector2Array()
	for x in range(-160,181,5): river.append(_point(Vector2(x,9.0+sin(float(x)*0.035)*1.25)))
	draw_polyline(river,Color("#568990"),5.0,true)
	for route in GEO.ROUTES:
		var line:=PackedVector2Array()
		for p in route: line.append(_point(p))
		draw_polyline(line,Color("#c8b48b"),2.0,true)
	for place in GEO.PLACES:
		var at:=_point(place["pos"])
		draw_circle(at,4.0,Color("#e8d9af"))
		if LABELS.has(place["id"]):
			var offset:=Vector2(6,-14) if place["id"]=="quarry" else Vector2(6,-4)
			draw_string(ThemeDB.fallback_font,at+offset,str(LABELS[place["id"]]),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#f4ecd6"))
	draw_string(ThemeDB.fallback_font,_point(GEO.point("board"))+Vector2(-45,20),"Поселение",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#f4ecd6"))
	if chapter!=null:
		for id in chapter.sim.projects.projects:
			var point:=_point(chapter.sim.PROJECTS.POINTS[id])
			var color:=Color("#acc59a") if chapter.sim.projects.is_complete(id) else Color("#efb968")
			draw_rect(Rect2(point-Vector2(3,3),Vector2(6,6)),color)
		var destination:=_point(chapter._waypoint)
		draw_arc(destination,8.0,0,TAU,24,Color("#ffe6a6"),1.5,true)
		var hero:Node3D=chapter.game.player
		var at:=_point(Vector2(hero.position.x,hero.position.z))
		draw_circle(at,5.0,Color("#e9bb78"))
		for a in chapter.sim.data["residents"]:
			draw_circle(_point(Vector2(float(a["x"]),float(a["z"]))),2.5,Color("#afceae"))
	draw_string(ThemeDB.fallback_font,Vector2(size.x-90,20),"СЕВЕР ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#f1dfb6"))

func _background() -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("#263f3f")
	style.set_corner_radius_all(10)
	return style
