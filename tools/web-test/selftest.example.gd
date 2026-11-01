

func _selftest() -> void:
	await get_tree().create_timer(0.5).timeout
	hud.close_dialog()
	farmnet.delete_save()
	var fn := farmnet
	# 1-й день весны — окно заморозков: ночь заморозков сдвинула бы созревание редиса на день
	fn.farm.weather["frost"] = -1
	for x in [20, 21]:
		fn.request("use", ["farm", x, 12, 0])
		fn.request("use", ["farm", x, 12, 5])
	for i in 3:
		fn.request("use", ["farm", 20, 12, 1])
		fn.request("use", ["farm", 21, 12, 1])
		fn.end_day("")
	hud.close_dialog()
	fn.request("use", ["farm", 20, 12, 0])
	fn.request("use", ["farm", 21, 12, 0])
	me.position = Vector3(20.8, 0, 13.3)
	await get_tree().create_timer(6.0).timeout
	print("TEST radish picked ", fn.farm.count(1, "prod:radish"), " drops left ", fn.farm.drops.size())
	fn.request("ship", ["", 0])
	var m0 := fn.farm.money
	fn.end_day("")
	print("TEST money ", m0, " -> ", fn.farm.money, " day ", day)
	hud.open_inventory()
