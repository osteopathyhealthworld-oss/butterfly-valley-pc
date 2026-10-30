extends RefCounted
## Состояние главы не зависит от 3D и частоты кадров. Платёж атомарный:
## проверяется вся цена, затем списывается. Работы жителей завершаются на месте.

const GEO = preload("res://scripts/valley_geography.gd")
const PROJECTS = preload("res://scripts/valley_projects.gd")
const DAY_SECONDS := 1080.0
const STORM_BEGIN := 690.0
const STORM_END := 840.0
const GOODS := ["wood", "stone", "herbs", "seeds", "food", "resin"]
const GOOD_NAMES := {"wood":"ветки", "stone":"камни", "herbs":"травы", "seeds":"семена", "food":"провизия", "resin":"смола"}
const GOOD_FORMS := {"wood":["ветка","ветки","веток"],"stone":["камень","камня","камней"],
	"herbs":["пучок трав","пучка трав","пучков трав"],"seeds":["семя","семени","семян"],
	"food":["порция еды","порции еды","порций еды"],"resin":["порция смолы","порции смолы","порций смолы"]}
const PEOPLE := [
	{"id":"iris", "name":"Ирис", "role":"травница", "home":Vector2(-27,-20), "work":Vector2(-30,-6), "product":"herbs", "color":Color("#a3c6aa")},
	{"id":"nara", "name":"Нара", "role":"садовница", "home":Vector2(-30,-39), "work":Vector2(-28,-31), "product":"food", "color":Color("#dfbf71")},
	{"id":"siver", "name":"Сивер", "role":"каменщик", "home":Vector2(45,-46), "work":Vector2(43,-22), "product":"stone", "color":Color("#a9bccf")},
	{"id":"grom", "name":"Гром", "role":"смотритель троп", "home":Vector2(7,-42), "work":Vector2(13,-3), "product":"wood", "color":Color("#c4a0a6")}
]

var data: Dictionary = {}
var stock: Dictionary = {}
var notices: Array[String] = []
var projects = PROJECTS.new()

func setup(saved: Dictionary, bag: Dictionary) -> void:
	stock = bag
	var first := int(saved.get("version",0)) < 1
	for good in GOODS:
		stock[good] = clampi(int(stock.get(good,0)),0,999)
	if first:
		# Однократный стартовый набор; загрузка сохранения его не повторяет.
		for good in {"wood":6,"stone":4,"herbs":3,"seeds":4,"food":4}:
			stock[good] = int(stock[good]) + int({"wood":6,"stone":4,"herbs":3,"seeds":4,"food":4}[good])
	data = {
		"version":2, "time":maxf(0.0,float(saved.get("time",0.0))),
		"habitat":clampf(float(saved.get("habitat",65.0)),0.0,100.0),
		"village":{"wood":4,"stone":3,"herbs":2,"food":6},
		"bridge":str(saved.get("bridge","")), "meadow":bool(saved.get("meadow",false)),
		"roof":bool(saved.get("roof",false)), "beacon":bool(saved.get("beacon",false)),
		"priority":str(saved.get("priority","supplies")), "residents":[],
		"taken":{}, "talked":[], "visits":[], "outcomes":[], "log":[],
		"last_storm":int(saved.get("last_storm",-1)), "last_dawn":int(saved.get("last_dawn",0)),
		"tutorial":bool(saved.get("tutorial",false)), "finished":bool(saved.get("finished",false)),
		"tracked":str(saved.get("tracked","bridge")),
		"projects":{}, "work_orders":{}, "project_focus":str(saved.get("project_focus","workshop")),
		"ledger":{"gathered":0,"spent":0,"npc_delivered":0,"traded":0,"project_delivered":0},
		"stamina":clampf(float(saved.get("stamina",100.0)),0.0,100.0)
	}
	for key in ["taken","village","ledger","projects","work_orders"]:
		if saved.get(key) is Dictionary:
			for k in saved[key]:
				data[key][k] = saved[key][k].duplicate(true) if saved[key][k] is Dictionary else saved[key][k]
	for key in ["talked","visits","outcomes","log"]:
		if saved.get(key) is Array:
			data[key] = saved[key].duplicate(true)
	for definition in PEOPLE:
		var previous := {}
		for resident in saved.get("residents",[]):
			if resident is Dictionary and resident.get("id") == definition["id"]:
				previous = resident
		var home: Vector2 = definition["home"]
		data["residents"].append({
			"id":definition["id"], "x":float(previous.get("x",home.x)), "z":float(previous.get("z",home.y)),
			"energy":clampf(float(previous.get("energy",90.0)),0.0,100.0),
			"hunger":clampf(float(previous.get("hunger",15.0)),0.0,100.0),
			"friendship":clampi(int(previous.get("friendship",0)),0,100),
			"goal":"choose", "working":0.0, "social_cd":0.0,
			"cargo":str(previous.get("cargo","")), "cargo_count":maxi(0,int(previous.get("cargo_count",0))),
			"last_gift_day":int(previous.get("last_gift_day",-1)),
			"delivered":maxi(0,int(previous.get("delivered",0))), "helped":maxi(0,int(previous.get("helped",0)))
		})
	if not ["supplies","habitat","safety"].has(data["priority"]):
		data["priority"] = "supplies"
	projects.setup(data["projects"],data["work_orders"],data["village"])
	projects.focus = data["project_focus"]
	projects.clock = float(data["time"])
	# Готовые постройки из первой версии сохраняются без новой оплаты.
	if str(data["bridge"]) != "" and not data["projects"].has("bridge"):
		projects.start("bridge",str(data["bridge"]),3)
	if data["roof"] and not data["projects"].has("roof"):
		projects.start("roof","stone",2)
	_sync_project_flags()
	projects.focus = data["project_focus"]

func attach_builder(builder: Dictionary) -> void:
	# В старом сохранении у Бруно отдельный запас. Объединяем его один раз;
	# последующие snapshot хранят stock как совместимую копию общего амбара.
	if not bool(builder.get("stock_shared",false)):
		for good in ["wood","stone"]:
			data["village"][good] = int(data["village"][good]) + int(builder["stock"].get(good,0))
	builder["stock_shared"] = true
	builder["stock"] = data["village"]
	var stage := int(builder["stage"])
	if not projects.projects.has("workshop"):
		projects.start("workshop","stone",stage)
	var p: Dictionary = projects.projects["workshop"]
	p["stage"] = maxi(int(p["stage"]),stage)
	if int(builder["paidStage"]) == int(p["stage"]) + 1:
		var step: Dictionary = projects.steps("workshop")[int(p["stage"])]
		for good in step["cost"]:
			p["delivered"][good] = int(p["delivered"].get(good,0)) + int(step["cost"][good])
		p["legacy_paid_stage"] = int(builder["paidStage"])
		if builder["phase"] == "build":
			p["work"] = maxf(0.0,float(step["seconds"])-float(builder["timer"]))
		builder["paidStage"] = 0
	# Старое задание может вести к уже оплаченной стройке. Очередь теперь
	# выбирает работу; груз в bag и посаженные деревья при этом сохраняются.
	builder["phase"] = "decide"
	builder["target"] = {}
	builder["timer"] = 0.0
	projects.focus = data["project_focus"]

func _sync_project_flags() -> void:
	if projects.is_complete("bridge") and str(data["bridge"]) == "":
		data["bridge"] = str(projects.projects["bridge"]["variant"])
		if data["bridge"] == "willow": data["habitat"] = minf(100.0,float(data["habitat"])+8.0)
	if projects.is_complete("roof"): data["roof"] = true

func project_service(owner: String, at: Vector2, seconds: float) -> Dictionary:
	var result: Dictionary = projects.service(owner,at,seconds)
	project_result(result)
	return result

func project_result(result: Dictionary) -> void:
	if result.is_empty(): return
	if result["event"] == "delivered":
		data["ledger"]["project_delivered"] = int(data["ledger"]["project_delivered"]) + int(result["amount"])
		var a := resident(str(result["owner"]))
		if not a.is_empty(): a["helped"] = int(a["helped"]) + 1
	if result["event"] in ["stage","complete"]:
		_sync_project_flags()
		_log("%s: %s. %s" % [PROJECTS.TITLES[result["project"]],result["name"],
			"Постройка готова." if result["event"]=="complete" else "Работа продолжается."])

func project_id(site: String) -> String:
	return "roof" if site == "stores" else site

func project_status(id: String) -> String:
	if not projects.projects.has(id): return "Проект ещё не выбран."
	var p: Dictionary = projects.projects[id]
	if projects.is_complete(id): return "Готово."
	var prefix := "Приостановлено. " if p["paused"] else ""
	var stage := int(p["stage"])
	var step: Dictionary = projects.steps(id)[stage]
	var text := "%sЭтап %d/%d: %s · %d%%." % [prefix,stage+1,projects.steps(id).size(),step["name"],int(float(p["work"])/float(step["seconds"])*100.0)]
	var missing := projects.needed(id)
	var parts: PackedStringArray = []
	for good in missing:
		if int(missing[good])>0: parts.append(quantity(good,int(missing[good])))
	if not parts.is_empty(): text += " Доставить: " + ", ".join(parts) + "."
	var carrying := 0
	for job in projects.orders.values():
		if job["kind"]=="haul" and job["project"]==id: carrying += int(job["count"])
	if carrying>0: text += " В поручениях: %d." % carrying
	if projects.ready_to_build(id): text += " Материалы этапа на месте; можно помочь со стройкой."
	if str(p["blocked"])!="": text += " " + str(p["blocked"])
	return text

func _project_offers(id: String) -> Array[Dictionary]:
	if not projects.projects.has(id) or projects.is_complete(id): return []
	var result: Array[Dictionary] = [
		_offer("contribute","Принести материалы из сумки",{},"До двух единиц каждого недостающего материала переходят на эту площадку."),
		_offer("help","Помочь со стройкой",{},"Паки работает пять секунд. Нужные материалы должны быть на площадке."),
		_offer("prioritise","Выполнять этот проект первым",{},"Жители закончат текущий перенос и возьмут новые поручения для этой постройки."),
		_offer("pause","Продолжить проект" if projects.projects[id]["paused"] else "Приостановить проект",{},"Уже доставленные материалы и готовые этапы сохраняются. Груз в пути возвращается в амбар.")]
	result[1]["enabled"] = projects.ready_to_build(id)
	return result

func day() -> int:
	return int(float(data["time"]) / DAY_SECONDS)

func phase_time() -> float:
	return fposmod(float(data["time"]),DAY_SECONDS)

func weather() -> String:
	var t := phase_time()
	if t >= STORM_BEGIN and t < STORM_END:
		return "storm"
	if t >= STORM_END and t < 930.0:
		return "mist"
	if t >= STORM_BEGIN - 140.0 and t < STORM_BEGIN:
		return "overcast"
	return "clear"

func hour() -> float:
	return fposmod(8.0 + phase_time() / DAY_SECONDS * 24.0,24.0)

func is_night() -> bool:
	return hour() >= 20.0 or hour() < 6.0

func advance(seconds: float, moving: bool = false, running: bool = false) -> void:
	# Ограничение защищает от скачка часов после сворачивания игры.
	var dt := clampf(seconds,0.0,1.0)
	var old := float(data["time"])
	data["time"] = old + dt
	projects.clock = float(data["time"])
	var drain := 1.8 if running else (0.12 if moving else -2.2)
	data["stamina"] = clampf(float(data["stamina"]) - drain * dt,0.0,100.0)
	if day() > int(data["last_dawn"]):
		data["last_dawn"] = day()
		data["habitat"] = minf(100.0,float(data["habitat"]) + (6.0 if data["meadow"] else 1.0))
		for key in data["taken"].keys():
			if int(str(key).split(":")[0]) < day()-1: data["taken"].erase(key)
		_log("Новый день: жители вернулись к делам. Источники ресурсов восстановились.")
	if phase_time() >= STORM_END and int(data["last_storm"]) < day():
		data["last_storm"] = day()
		_resolve_storm()

func _resolve_storm() -> void:
	var protected := bool(data["roof"])
	var lost := 0 if protected else mini(2,int(data["village"]["food"]))
	data["village"]["food"] = int(data["village"]["food"]) - lost
	var bees := bool(data["meadow"]) and float(data["habitat"]) >= 50.0
	if bees:
		data["village"]["herbs"] = int(data["village"]["herbs"]) + 3
	var report := "Ливень прошёл. "
	report += "Амбар сухой, припасы сохранены. " if protected else "В амбаре промокло %d порции; крышу можно починить к следующему дождю. " % lost
	report += "Цветущий луг дал три пучка трав. " if bees else "На лугу пока мало цветов для бабочек. "
	if data["bridge"] == "willow":
		data["habitat"] = minf(100.0,float(data["habitat"]) + 4.0)
	data["outcomes"].append({"day":day(),"roof":protected,"habitat":bees,"lost":lost,"beacon":data["beacon"]})
	data["outcomes"] = data["outcomes"].slice(-8)
	_log(report)

func can_pay(cost: Dictionary) -> bool:
	for good in cost:
		if int(stock.get(good,0)) < int(cost[good]):
			return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for good in cost:
		stock[good] = int(stock[good]) - int(cost[good])
		data["ledger"]["spent"] = int(data["ledger"]["spent"]) + int(cost[good])
	return true

func price_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for good in cost:
		if int(cost[good])>0: parts.append(quantity(good,int(cost[good])))
	return ", ".join(parts)

func quantity(good: String, amount: int) -> String:
	var forms: Array = GOOD_FORMS.get(good,[good,good,good])
	var last := absi(amount)%10
	var form := 2
	if absi(amount)%100 < 11 or absi(amount)%100 > 14:
		if last==1: form=0
		elif last in [2,3,4]: form=1
	return "%d %s" % [amount,forms[form]]

func inventory_text(container: Dictionary) -> String:
	var parts: PackedStringArray = []
	for good in GOODS:
		if container.has(good): parts.append(quantity(good,int(container[good])))
	return " · ".join(parts)

func options(site: String) -> Array[Dictionary]:
	if site == "bridge" and projects.projects.has("bridge"):
		return _project_offers("bridge")
	if site == "workshop":
		var work_offers := _project_offers("workshop")
		work_offers.append(_offer("follow","Позвать Бруно с собой",{},"Бруно оставит стройку и пойдёт за Паки. Груз останется у него до возвращения к работе. Готовые этапы сохранятся."))
		work_offers.append(_offer("resume","Вернуть Бруно к работе",{},"Бруно снова выполняет общественные поручения."))
		return work_offers
	match site:
		"board": return [
			_offer("supplies","Поручить жителям пополнять запасы",{},"Ирис ищет травы, Нара выращивает еду, Сивер и Гром носят материалы."),
			_offer("habitat","Попросить беречь цветущий луг",{},"Садовница и травница рассадят цветы, расходуя травы из общего амбара."),
			_offer("safety","Готовиться к ливню",{},"Заказать ремонт крыши за 4 ветки и 2 камня общего амбара. Жители сами доставят материалы; Сивер или Бруно построит."),
			_offer("rest","Отдохнуть до вечера",{"food":1},"Сумерки наступят сразу; ты восстановишь силы. Припасы за время отдыха не прибавятся.")]
		"bridge": return [
			_offer("stone","Заказать каменную переправу",{},"Нужно доставить 3 ветки и 4 камня. Жители берут их из общего амбара; Паки может принести свои. Три этапа стройки."),
			_offer("willow","Заказать живую ивовую переправу",{},"Нужно 5 веток и 1 смола. Смолу приготовь у алхимика и принеси на площадку. После стройки луг получит +8; в ливень переправа медленнее.")]
		"stores":
			var offers: Array[Dictionary] = _project_offers("roof")
			if not projects.projects.has("roof"):
				offers.append(_offer("roof","Заказать ремонт крыши",{},"4 ветки и 2 камня из общего амбара: доставка и два этапа стройки. Готовая крыша защищает еду от дождя."))
			offers.append_array([
			_offer("donate","Передать материалы жителям",{"wood":2,"stone":1},"Материалы действительно переходят на общий склад; дружба с Сивером +3."),
			_offer("withdraw","Взять две ветки со склада",{},"Только при наличии двух веток; остаётся меньше на общественные дела."),
			_offer("trade_herbs","Обменять ветки на два пучка трав",{"wood":1 if int(resident("iris").get("friendship",0))>=10 else 2},"Травы берутся из общего амбара. При доверии Ирис от 10 обмен дешевле.")])
			return offers
		"garden": return [
			_offer("plant","Посеять цветы",{"seeds":2},"Состояние луга +8; Нара станет доверять больше."),
			_offer("food","Забрать созревшие овощи",{},"Две порции в день. Дождь поливает и старые грядки."),
			_offer("seeds","Разобрать семенные коробочки",{"herbs":1},"Получить три семени.")]
		"craft": return [
			_offer("resin","Сварить древесную смолу",{"herbs":2,"wood":1},"Одна порция смолы для живой переправы или маяка."),
			_offer("tea","Приготовить травяной чай",{"herbs":2},"Две порции провизии; одна порция восстанавливает силы."),
			_offer("eat","Поесть и передохнуть",{"food":1},"Восстановить 55 единиц сил.")]
		"meadow": return [
			_offer("restore","Восстановить цветущий луг",{"seeds":3,"herbs":2},"После дождя появляются дополнительные травы и бабочки. Дружба с Ирис +8."),
			_offer("harvest","Собрать травы бережно",{},"Два пучка в день; при здоровом луге — три.")]
		"quarry": return [
			_offer("careful","Собрать осыпавшийся камень",{},"Два камня; без вреда для луга, три подхода в день."),
			_offer("rush","Разобрать поросшую террасу",{},"Шесть камней; состояние луга −15, дружба с Ирис −4. Один раз в день.")]
		"beacon": return [
			_offer("light","Зажечь маяк на холме",{"wood":2,"resin":1},"Во время тумана или ночью маяк поможет каравану. Днём можно подготовить огонь."),
			_offer("signal","Подать сигнал каравану",{},"Нужны работающий маяк, переправа и ночное небо или туман.")]
		"round", "long", "deep": return [
			_offer("survey","Зарисовать берег в журнале",{},"Первое наблюдение приносит семена. Три озера открывают рецепт полевого гербария."),
			_offer("forage","Собрать упавшие ветки",{},"Три ветки в день на каждом берегу; живые деревья остаются целыми.")]
	return []

func _offer(id: String, title: String, cost: Dictionary, effect: String) -> Dictionary:
	return {"id":id,"title":title,"cost":cost,"effect":effect}

func act(site: String, choice: String, context: Dictionary = {}) -> Dictionary:
	var offer := {}
	for item in options(site):
		if str(item["id"]) == choice:
			offer = item
	if offer.is_empty():
		return _answer(false,"Такого действия здесь нет.")
	if site == "board" and choice!="rest":
		data["priority"] = choice
		data["tutorial"] = true
		if choice == "safety" and not data["roof"]:
			projects.start("roof")
			_focus_project("roof")
		return _answer(true,"Поручение принято. Жители закончат текущий перенос и выберут новое дело.")
	if site=="bridge" and choice in ["stone","willow"]:
		if projects.start("bridge",choice):
			_focus_project("bridge")
			return _answer(true,"Проект выбран. Жители доставят материалы из общего амбара. Можно принести свои и помочь со стройкой.")
		return _answer(false,"Проект переправы уже выбран. Повторной оплаты нет.")
	if site=="stores" and choice=="roof":
		if projects.start("roof"):
			_focus_project("roof")
			return _answer(true,"Ремонт крыши поставлен в очередь. Еда будет защищена после завершения обоих этапов.")
		return _answer(false,"Ремонт крыши уже заказан.")
	if choice in ["contribute","help","prioritise","pause"]:
		return _project_action(project_id(site),choice,context)
	if site == "bridge" and str(data["bridge"]) != "":
		return _answer(false,"Переправа уже укреплена.")
	if (choice == "roof" and data["roof"]) or (choice == "restore" and data["meadow"]) or (choice == "light" and data["beacon"]):
		return _answer(false,"Уже готово. Ресурсы сохранены.")
	if site == "beacon" and choice == "signal":
		if data["finished"]:
			return _answer(false,"Караван уже пришёл. Можно продолжать исследование и помогать жителям.")
		if not data["beacon"] or str(data["bridge"]) == "":
			return _answer(false,"Для каравана нужны зажжённый маяк и восстановленная переправа.")
		if not is_night() and weather() != "mist":
			return _answer(false,"Сигнал будет виден ночью или в тумане после ливня. Отдохни у лагеря или исследуй озёра.")
	if choice == "withdraw" and int(data["village"]["wood"]) < 2:
		return _answer(false,"На общем складе пока нет двух веток.")
	if choice == "trade_herbs" and int(data["village"]["herbs"])<2:
		return _answer(false,"В амбаре пока нет двух пучков трав; Ирис принесёт их после сбора.")
	var quota_key := "%d:%s:%s" % [day(),site,choice]
	var limited := ["careful","rush","harvest","forage","food"].has(choice)
	var quota := 3 if choice == "careful" else 1
	if limited and int(data["taken"].get(quota_key,0)) >= quota:
		return _answer(false,"На сегодня всё собрано. Источник восстановится утром; рядом есть другие маршруты.")
	if not can_pay(offer["cost"]):
		return _answer(false,"Не хватает материалов. Нужно: " + price_text(offer["cost"]))
	if ["careful","rush","forage","harvest"].has(choice) and float(data["stamina"]) < 10.0:
		return _answer(false,"Паки устал. Постой немного или поешь у стола алхимика.")
	pay(offer["cost"])
	if limited:
		data["taken"][quota_key] = int(data["taken"].get(quota_key,0)) + 1
	var message := "Готово."
	match site:
		"board":
			var target := float(day())*DAY_SECONDS+540.0
			if float(data["time"])>=target:
				if int(data["last_storm"])<day():
					_resolve_storm()
					data["last_storm"]=day()
				target+=DAY_SECONDS
			data["time"]=target
			data["stamina"]=100.0
			message="Паки отдохнул. В долине наступил вечер."
		"stores":
			if choice == "trade_herbs":
				data["village"]["herbs"] = int(data["village"]["herbs"])-2
				data["village"]["wood"] = int(data["village"]["wood"])+int(offer["cost"]["wood"])
				_give("herbs",2)
				data["ledger"]["traded"] = int(data["ledger"]["traded"])+1
			elif choice == "donate":
				data["village"]["wood"] = int(data["village"]["wood"]) + 2
				data["village"]["stone"] = int(data["village"]["stone"]) + 1
				_befriend("siver",3)
			else:
				data["village"]["wood"] = int(data["village"]["wood"])-2
				_give("wood",2)
			message = "Припасы перенесены между сумкой и общим складом."
		"garden":
			if choice == "plant":
				data["habitat"] = minf(100.0,float(data["habitat"])+8.0)
				_befriend("nara",3)
			elif choice == "food": _give("food",2)
			else: _give("seeds",3)
			message = "Нара: Спасибо! Здесь стало больше цветов." if choice == "plant" else "Получено: провизия." if choice == "food" else "Получено: три семени."
		"craft":
			if choice == "resin": _give("resin",1)
			elif choice == "tea": _give("food",2)
			else: data["stamina"] = minf(100.0,float(data["stamina"])+55.0)
			message = "Смола готова." if choice == "resin" else "Чай разлит в две фляги." if choice == "tea" else "Паки поел и восстановил силы."
		"meadow":
			if choice == "restore":
				data["meadow"] = true
				data["habitat"] = minf(100.0,float(data["habitat"])+18.0)
				_befriend("iris",8)
				message = "На лугу высажены цветы. После дождя здесь появятся новые бабочки и травы."
			else:
				_give("herbs",3 if float(data["habitat"])>=65.0 else 2)
				message = "Травы собраны. Цветы для бабочек остались."
		"quarry":
			_give("stone",6 if choice=="rush" else 2)
			data["stamina"] = maxf(0.0,float(data["stamina"])-12.0)
			if choice == "rush":
				data["habitat"] = maxf(0.0,float(data["habitat"])-15.0)
				_befriend("iris",-4)
			message = "Камни в сумке. Терраса оголена; Ирис огорчилась." if choice=="rush" else "Два камня в сумке. Растения на террасе сохранены."
		"beacon":
			if choice == "light":
				data["beacon"] = true
				message = "Маяк зажжён. Подай сигнал ночью или в тумане после дождя."
			else:
				data["finished"] = true
				_give("seeds",3)
				message = "Караван увидел свет! Долина снова связана с большой дорогой. В журнале — итоги твоих решений."
		_:
			if choice == "survey":
				if not data["visits"].has(site):
					data["visits"].append(site)
					_give("seeds",2)
					message = "Берег отмечен в журнале. Получено два семени."
					if data["visits"].size() == 3:
						_give("herbs",3)
						message += " Три озера изучены: полевой гербарий и три пучка трав."
				else: message = "Этот берег уже есть в журнале."
			else:
				_give("wood",3)
				data["stamina"] = maxf(0.0,float(data["stamina"])-8.0)
				message = "Три упавшие ветки в сумке."
	_log(message)
	return _answer(true,message)

func _focus_project(id: String) -> void:
	projects.focus = id
	data["project_focus"] = id

func _project_action(id: String, choice: String, context: Dictionary) -> Dictionary:
	if not projects.projects.has(id) or projects.is_complete(id): return _answer(false,"Постройка уже готова.")
	match choice:
		"prioritise":
			_focus_project(id)
			return _answer(true,"Этот проект получит новые поручения первым. Грузы в пути будут доставлены.")
		"pause":
			projects.pause(id)
			return _answer(true,"Проект приостановлен. Носильщики вернут груз; материалы на площадке сохранены." if projects.projects[id]["paused"] else "Работа возобновлена.")
	var at: Vector2 = context.get("position",Vector2(INF,INF))
	if at.distance_to(PROJECTS.POINTS[id])>6.0:
		return _answer(false,"Подойди к площадке, чтобы доставить материалы или помочь.")
	if choice=="contribute":
		var moved: Dictionary = projects.contribute(id,stock,at)
		if moved.is_empty(): return _answer(false,"В сумке нет недостающих материалов либо их уже несут жители.")
		return _answer(true,"На площадку доставлено: " + price_text(moved) + ".")
	if int(context.get("stage",-1)) != int(projects.projects[id]["stage"]):
		return _answer(false,"Жители уже закончили этот этап. Припасы сохранены; проверь следующий этап.")
	var result: Dictionary = projects.work(id,"paki",at,5.0)
	if result.is_empty(): return _answer(false,"Для работы нужны материалы на площадке и действующий проект.")
	project_result(result)
	return _answer(true,"Паки помог со стройкой. " + project_status(id))

func _answer(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message}

func _give(good: String, amount: int) -> void:
	stock[good] = int(stock[good]) + amount
	data["ledger"]["gathered"] = int(data["ledger"]["gathered"]) + amount

func resident(id: String) -> Dictionary:
	for a in data["residents"]:
		if a["id"] == id: return a
	return {}

func _befriend(id: String, amount: int) -> void:
	var a := resident(id)
	if not a.is_empty(): a["friendship"] = clampi(int(a["friendship"])+amount,0,100)

func talk(id: String, gift: bool = false) -> String:
	var a := resident(id)
	if a.is_empty(): return "Житель уже ушёл."
	if not data["talked"].has(id):
		data["talked"].append(id)
		_befriend(id,2)
	if gift:
		if int(a["last_gift_day"]) == day(): return "Сегодня ты уже помог этому жителю."
		if not pay({"food":1}): return "Для угощения нужна одна порция провизии."
		a["last_gift_day"] = day()
		_befriend(id,5)
		a["energy"] = minf(100.0,float(a["energy"])+25.0)
		a["hunger"] = maxf(0.0,float(a["hunger"])-35.0)
		return "Спасибо за угощение! Сил прибавилось; доверие +5."
	if data["finished"]:
		return "Караван добрался до долины! Теперь можно спокойно заняться садом и дорогами. Общие припасы по-прежнему нужны всем."
	if id=="iris" and float(data["habitat"])<55.0:
		return "Ирис: После расчистки террас стало меньше цветов. Посей семена у сада или помоги восстановить северный луг — бабочкам снова будет где кормиться."
	if id=="nara" and int(data["village"]["food"])<3:
		return "Нара: В амбаре почти не осталось еды. Я вернусь к овощам; ты тоже можешь собрать урожай у моего сада."
	if id=="siver" and data["roof"]:
		return "Сивер: Крыша теперь держится. Ливень не испортит припасы. Продолжу носить камень в общий амбар."
	if id=="grom" and data["bridge"]!="":
		return "Гром: Переправа открыта. Иди по северной тропе к маяку; ночью или в тумане его огонь увидят с большой дороги."
	match id:
		"iris": return "Ирис: Собирай только часть трав. На северном лугу можно посеять цветы; я принесу травы в амбар."
		"nara": return "Нара: Я выращиваю еду и собираю её в общий амбар. Семенные коробочки можно разобрать у сада."
		"siver": return "Сивер: Поручи нам готовиться к ливню. Жители доставят к амбару четыре ветки и два камня, а мы с Бруно починим крышу."
		_: return "Гром: За мостом дорога идёт к маяку. В тумане зажги огонь и подай сигнал каравану."

func choose_goal(a: Dictionary, definition: Dictionary) -> String:
	if weather() == "storm": return "shelter"
	if int(a["cargo_count"]) > 0: return "deliver"
	if float(a["energy"]) < 20.0: return "rest"
	if float(a["hunger"]) > 82.0 and int(data["village"]["food"])>0: return "rest"
	if is_night(): return "rest"
	if projects.orders.has(a["id"]): return "project"
	# Еда и ингредиенты остаются доступны, пока остальные заняты стройкой.
	if a["id"]=="nara" and int(data["village"]["food"])<6: return "work"
	if a["id"]=="iris" and int(data["village"]["herbs"])<3: return "work"
	if ["iris","nara"].has(a["id"]) and data["priority"] == "habitat" and float(data["habitat"]) < 95.0:
		return "plant" if int(data["village"]["herbs"])>0 else "work"
	if a["goal"]=="choose" and not projects.claim(str(a["id"])).is_empty(): return "project"
	if int(data["village"].get(definition["product"],0)) >= 18:
		return "social"
	return "work"

func goal_point(a: Dictionary, definition: Dictionary) -> Vector2:
	match str(a["goal"]):
		"project": return projects.target(str(a["id"]))
		"rest","shelter": return definition["home"]
		"deliver": return GEO.point("stores") + Vector2(-2,-1)
		"plant": return GEO.point("garden")
		"social": return GEO.point("board") + Vector2(2,0)
	return definition["work"]

func finish_job(a: Dictionary, definition: Dictionary) -> void:
	match str(a["goal"]):
		"work":
			a["cargo"] = definition["product"]
			a["cargo_count"] = 2 if int(a["friendship"]) >= 10 else 1
			a["energy"] = maxf(0.0,float(a["energy"])-4.0)
		"deliver":
			var good := str(a["cargo"])
			data["village"][good] = int(data["village"].get(good,0)) + int(a["cargo_count"])
			data["ledger"]["npc_delivered"] = int(data["ledger"]["npc_delivered"]) + int(a["cargo_count"])
			a["delivered"] = int(a["delivered"]) + int(a["cargo_count"])
			a["cargo_count"] = 0
			a["cargo"] = ""
		"plant":
			# Жители используют травы из общего склада как семенной материал.
			if int(data["village"]["herbs"]) > 0:
				data["village"]["herbs"] = int(data["village"]["herbs"])-1
				data["habitat"] = minf(100.0,float(data["habitat"])+3.0)
				a["helped"] = int(a["helped"])+1
		"rest","shelter":
			if float(a["hunger"]) > 25.0 and int(data["village"]["food"]) > 0:
				data["village"]["food"] = int(data["village"]["food"])-1
				a["hunger"] = maxf(0.0,float(a["hunger"])-45.0)
			a["energy"] = minf(100.0,float(a["energy"])+25.0)
		"social":
			a["energy"] = minf(100.0,float(a["energy"])+8.0)

func _log(message: String) -> void:
	data["log"].append(message)
	data["log"] = data["log"].slice(-12)
	notices.append(message)

func snapshot() -> Dictionary:
	return data.duplicate(true)
