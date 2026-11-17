class_name Level5
extends RefCounted

# Level 5 of XENON2.EXE, the routines the level's tables point to (load module offsets) :
# init 0xe4af, wall objects 0xd0e8 (table cs:0xe72e). There is no hook (0xd0e7 is a ret) and
# the wave types (0xe475) need nothing of their own. "code" marks behaviour ported from the
# code, "unconfirmed" a detail left open there.

var main: Node

# ds:0x923a / 0x923b : the two turrets of wall type 9 killed

var turret_killed := [false, false]

const HITS := ["0xdeb6", "0xdf13", "0xe2bf", "0xe097", "0xdb2b", "0xda58", "0xd89d", "0xd8f5"]


func _init(owner: Node) -> void:
	main = owner


func _key(frame: int) -> String:
	return "S5/%03d" % frame


func _anim(list: Array, ticks: int) -> Array:
	var out: Array = []

	for f in list:
		out.append([_key(f), ticks])

	return out


func _object(kind: String, fields: Dictionary) -> Dictionary:
	var object := {
		"kind": kind,
		"x": 0,
		"y": 0,
		"box": [1000, 0, 1000, 0],
		"flash": false,
		"dead": false,
		"group": 0,
		"head": null,
		"segments": [],
		"large": false,
		"energy": 1,
		"score": 0,
		"hit": "none",
		"key": "S5/175",
		"fire_counter": 0,
		"state": 0,
	}
	object.merge(fields, true)
	return object


func _carry(item: Dictionary, amount: int) -> bool:
	item["fire_counter"] += amount

	if item["fire_counter"] < 0x100:
		return false

	item["fire_counter"] = main._random() & 0x3f
	return true


func _bullet(x: int, y: int, direction: int, frames: Array, speed: int) -> void:
	main._enemy_bullet(x, y, direction, frames[0][0], speed)

	if frames.size() > 1:
		var bullet: Dictionary = main.effects[0]
		bullet["frames"] = frames
		bullet["anim"] = 0
		bullet["count"] = frames[0][1]


func _word(tile: int, masked: bool) -> int:
	return 0 if tile == 0 else (tile << 6) | (1 if masked else 0)


func _put(cell: int, word: int) -> void:
	if cell >= 0 and cell < main.map_words.size():
		main.map_words[cell] = word


func _peek(cell: int) -> int:
	return main.map_words[cell] if cell >= 0 and cell < main.map_words.size() else -1


# ---------------------------------------------------------------- wall objects 0xd0e8

func spawn_wall(wall: Dictionary) -> void:
	var type := int(wall["type"])
	var side := int(wall["side"])
	var x := int(wall["x"]) - 8
	var world_y := int(wall["world_y"]) - 8
	var cell := (world_y >> 4) * 20 + (x >> 4)

	match type:
		1:
			_spawn_gate(x, world_y, cell)
		2:

			# code 0xe35a : a gun of one tile, energy 10 (cs:0xcc86), 100 points

			var tiles: Array = [297, 298, 299, 300, 301, 302, 303, 297] if side == 0 else [290, 291, 292, 293, 294, 295, 296, 290]
			_put(cell, _word(tiles[0], true))
			main.enemies.push_front(_object("l5_gun", {
				"side": side,
				"x": x,
				"world_y": world_y,
				"cell": cell,
				"tiles": tiles,
				"first": [tiles[0]],
				"death": [224 if side == 0 else 223],
				"size": 1,
				"energy": 10,
				"score": 100,
				"hit": "0x3b76",
			}))
		3:
			_spawn_turret(x, world_y, cell, side, -1)
		4:
			_spawn_ring(x, world_y, cell)
		9:

			# code 0xe126 : a turret made only while not yet killed (ds:0x923a + b)

			var b := int(wall["b"])

			if not turret_killed[b]:
				_spawn_turret(x, world_y, cell, side, b)
		_:
			_spawn_other(wall, type, side, x, world_y, cell)


func _spawn_other(wall: Dictionary, type: int, side: int, x: int, world_y: int, _cell: int) -> void:
	match type:
		5:
			_spawn_middle(world_y)
		6:
			_spawn_boss()
		7:
			_spawn_snake(int(wall["b"]))
		8:
			_spawn_pod(x + (16 if side != 0 else 0), world_y, side)


# ---------------------------------------------------------------- type 1 : the gate

func _spawn_gate(x: int, world_y: int, cell: int) -> void:

	# code 0xdd7f : two posts (energy 10, cs:0xcc7c) and a beam between them that cannot be
	# killed, at the end of the enemies list. Killing a post takes the whole gate, 200
	# points. unconfirmed : nothing removes a gate left behind.

	_put(cell, _word(314, true))
	_put(cell + 1, 0)
	_put(cell + 2, 0)
	_put(cell + 3, _word(315, true))
	var gate: Array = []

	for spec in [["left", 0], ["beam", 16], ["right", 48]]:
		var part := _object("l5_gate", {
			"role": spec[0],
			"x": x + spec[1],
			"world_y": world_y,
			"cell": cell + spec[1] / 16,
			"base": cell,
			"energy": 10,
			"hit": {"left": "0xdeb6", "right": "0xdf13"}.get(spec[0], "none"),
		})
		gate.append(part)
		main.enemies.append(part)

	for part in gate:
		part["gate"] = gate


func _update_gate(part: Dictionary) -> void:
	var x: int = part["x"]
	var sy: int = part["world_y"] - main.scroll

	if part["role"] == "beam":

		# code 0xde2f : the beam's two tiles, 308, 309, 308, none, a frame each

		part["state"] = (part["state"] + 4) & 15
		var t: int = {4: 308, 8: 309, 12: 308, 0: 0}[part["state"]]
		_put(part["cell"], _word(t, true))
		_put(part["cell"] + 1, _word(t, true))
		part["box"] = [x, sy + 2, x + 0x20, sy + 0xe]
		return

	# code 0xde71 : the post's tile, 4 states

	part["state"] = (part["state"] + 1) & 3
	var base := 304 if part["role"] == "left" else 310
	_put(part["cell"], _word(base + part["state"], true))
	part["box"] = [x + 3, sy + 3, x + 0xd, sy + 0xd]


func _gate_hit(part: Dictionary, damage: int) -> void:

	# code 0xdeb6, 0xdf13 : a flash ; dead, a small explosion, the gate's tiles 222, 0, 0,
	# 221, the three parts removed, 200 points

	part["flash"] = true
	part["energy"] -= damage

	if part["energy"] > 0:
		return

	var sy: int = part["world_y"] - main.scroll
	main._explode_at(part["x"] + 8, sy + 8, main.SMALL_EXPLOSION)
	var c: int = part["base"]
	_put(c, _word(222, true))
	_put(c + 1, 0)
	_put(c + 2, 0)
	_put(c + 3, _word(221, true))

	for other in part["gate"]:
		other["dead"] = true

	main.score += 200


# ---------------------------------------------------------------- type 2 : the side gun

func _update_gun(gun: Dictionary) -> void:

	# code 0xe3b3

	if gun["world_y"] > main.scroll_max + 0xd0:
		gun["dead"] = true
		return

	var x: int = gun["x"]
	var sy: int = gun["world_y"] - main.scroll
	gun["box"] = [x + 2, sy + 2, x + 0xe, sy + 0xe]

	if gun["state"] == 0 and not _carry(gun, 0x0f):
		return

	gun["state"] += 1
	_put(gun["cell"], _word(gun["tiles"][gun["state"]], true))

	if gun["state"] == 3:

		# code 0xe42a : out of the wall, speed 8

		if gun["side"] == 0:
			_bullet(x + 0x18, sy + 8, 2, _anim([29, 30], 3), 8)
		else:
			_bullet(x, sy + 8, 6, _anim([31, 32], 3), 8)
	elif gun["state"] == 7:
		gun["state"] = 0


# ---------------------------------------------------------------- type 3 / 9 : the turret

# cs:0xeb16 : 2x2 tiles by direction (0 up, clockwise), [tile, masked] ; cs:0xeb56 the
# shot's offsets ; cs:0xeb76 the shot's frame by direction & 3 and the frame count

const TURRET_TILES := [
	[[225, 0], [226, 0], [241, 1], [242, 0]], [[227, 0], [228, 0], [243, 0], [244, 0]],
	[[229, 0], [230, 0], [245, 0], [246, 0]], [[231, 0], [232, 0], [247, 0], [248, 0]],
	[[233, 0], [234, 0], [249, 0], [250, 0]], [[235, 0], [236, 0], [251, 0], [252, 0]],
	[[237, 0], [238, 0], [253, 0], [254, 0]], [[239, 0], [240, 1], [255, 0], [256, 1]],
]
const TURRET_SHOT := [Vector2i(0, -11), Vector2i(7, -7), Vector2i(14, -2), Vector2i(7, 6),
	Vector2i(0, 11), Vector2i(-7, 7), Vector2i(-13, 0), Vector2i(-7, -7)]


func _spawn_turret(x: int, world_y: int, cell: int, direction: int, slot: int) -> void:

	# code 0xe138 : energy 20 (cs:0xcc80), the wall's edges opened, its tiles by direction

	if _peek(cell - 1) == _word(187, true):
		_put(cell - 1, _word(25, true))
		_put(cell + 19, _word(45, true))

	if _peek(cell + 2) == _word(188, true):
		_put(cell + 2, _word(73, true))
		_put(cell + 22, _word(93, true))

	var t := _object("l5_turret", {
		"x": x,
		"world_y": world_y,
		"cell": cell,
		"direction": direction,
		"slot": slot,
		"energy": 20,
		"hit": "0xe2bf",
	})
	_turret_tiles(t)
	main.enemies.push_front(t)


func _turret_tiles(t: Dictionary) -> void:
	var tiles: Array = TURRET_TILES[t["direction"]]
	var c: int = t["cell"]

	for i in 4:
		_put(c + (i >> 1) * 20 + (i & 1), _word(tiles[i][0], tiles[i][1] == 1))


func _update_turret(t: Dictionary) -> void:

	# code 0xe1b0 : one full turn first, then it turns a step a frame towards the ship and
	# shoots on the carry of 0x12 a frame, speed 8

	if t["world_y"] > main.scroll_max + 0xd0:
		t["dead"] = true
		return

	var x: int = t["x"]
	var sy: int = t["world_y"] - main.scroll
	t["box"] = [x + 4, sy + 4, x + 0x1c, sy + 0x1c]

	if t["state"] == 0 and sy < -16:
		pass
	elif t["state"] != 8:
		t["state"] += 1
		t["direction"] = (t["direction"] + 1) & 7
	else:
		var d: int = main._direction(main.ship_x - x - 16, main.ship_y - sy - 16)

		if d != t["direction"]:
			t["direction"] = (t["direction"] + (1 if ((d - t["direction"]) & 7) < 4 else -1)) & 7

		if _carry(t, 0x12):
			var dir: int = t["direction"]
			var offset: Vector2i = TURRET_SHOT[dir]
			var frame: int = (166 if main.frame_count & 1 else 170) + (dir & 3)
			main._enemy_bullet(x + 16 + offset.x, sy + 16 + offset.y, dir, _key(frame), 8)

	_turret_tiles(t)


func _turret_hit(t: Dictionary, damage: int) -> void:

	# code 0xe2bf : a flash ; dead, marked if of type 9, a large explosion, the wall's edges
	# closed, its tiles cleared, 400 points

	t["flash"] = true
	t["energy"] -= damage

	if t["energy"] > 0:
		return

	if t["slot"] >= 0:
		turret_killed[t["slot"]] = true

	var c: int = t["cell"]
	var sy: int = t["world_y"] - main.scroll
	main._explode_at(t["x"] + 16, sy + 16, main.LARGE_EXPLOSION)

	if _peek(c - 1) == _word(25, true):
		_put(c - 1, _word(187, true))
		_put(c + 19, _word(205, true))

	if _peek(c + 2) == _word(73, true):
		_put(c + 2, _word(188, true))
		_put(c + 22, _word(206, true))

	for i in 4:
		_put(c + (i >> 1) * 20 + (i & 1), 0)

	main.score += 400
	t["dead"] = true


# ---------------------------------------------------------------- type 4 : the ring gun

func _spawn_ring(x: int, world_y: int, cell: int) -> void:

	# code 0xdf97 : energy 20 (cs:0xcc7e)

	if _peek(cell - 1) == _word(185, true):
		_put(cell - 1, _word(23, false))
		_put(cell + 19, _word(43, false))

	if _peek(cell + 2) == _word(186, true):
		_put(cell + 2, _word(23, false))
		_put(cell + 22, _word(43, false))

	_put(cell, _word(257, false))
	_put(cell + 20, _word(273, false))
	main.enemies.push_front(_object("l5_ring", {
		"x": x,
		"world_y": world_y,
		"cell": cell,
		"energy": 20,
		"hit": "0xe097",
	}))


func _update_ring(r: Dictionary) -> void:

	# code 0xdfe9 : its tiles turn (8 states of 2 frames), 8 shots every way on the carry of
	# 0x12 a frame, speed 10

	if r["world_y"] > main.scroll_max + 0xd0:
		r["dead"] = true
		return

	var x: int = r["x"]
	var sy: int = r["world_y"] - main.scroll
	r["box"] = [x + 4, sy + 4, x + 0x1c, sy + 0x1c]
	r["state"] = (r["state"] + 1) & 15

	if _carry(r, 0x12):
		for d in range(7, -1, -1):
			_bullet(x + 16, sy + 16, d, _anim([91, 92, 93, 94], 1), 10)

	var s: int = r["state"] >> 1
	var c: int = r["cell"]
	_put(c, _word(257 + 2 * s, false))
	_put(c + 1, _word(258 + 2 * s, false))
	_put(c + 20, _word(273 + 2 * s, false))
	_put(c + 21, _word(274 + 2 * s, false))


func _ring_hit(r: Dictionary, damage: int) -> void:

	# code 0xe097 : a flash ; dead, a large explosion, the wall's edges closed, its tiles
	# cleared, 500 points

	r["flash"] = true
	r["energy"] -= damage

	if r["energy"] > 0:
		return

	var c: int = r["cell"]
	var sy: int = r["world_y"] - main.scroll
	main._explode_at(r["x"] + 16, sy + 16, main.LARGE_EXPLOSION)

	if _peek(c - 1) == _word(23, false):
		_put(c - 1, _word(185, true))
		_put(c + 19, _word(203, true))

	if _peek(c + 2) == _word(23, false):
		_put(c + 2, _word(186, true))
		_put(c + 22, _word(204, true))

	for i in 4:
		_put(c + (i >> 1) * 20 + (i & 1), 0)

	main.score += 500
	r["dead"] = true


# ---------------------------------------------------------------- dispatch from main

func update_enemy(enemy: Dictionary) -> void:
	match enemy["kind"]:
		"l5_gate":
			_update_gate(enemy)
		"l5_gun":
			_update_gun(enemy)
		"l5_turret":
			_update_turret(enemy)
		"l5_ring":
			_update_ring(enemy)
		_:
			_update_other(enemy)


func _update_other(enemy: Dictionary) -> void:
	match enemy["kind"]:
		"l5_missile":
			_update_missile(enemy)
		"l5_snake":
			_update_snake(enemy)
		"l5_pod":
			_update_pod(enemy)
		"l5_middle":
			_update_middle(enemy)
		"l5_boss":
			_update_boss(enemy)
		"l5_spit":
			_update_spit(enemy)


func hit(enemy: Dictionary, damage: int, _projectile: Dictionary) -> void:
	match enemy["hit"]:
		"0xdeb6", "0xdf13":
			_gate_hit(enemy, damage)
		"0xe2bf":
			_turret_hit(enemy, damage)
		"0xe097":
			_ring_hit(enemy, damage)
		"0xdb2b":
			_middle_turret_hit(enemy, damage)
		"0xda58":
			_rotor_hit(enemy, damage)
		"0xd89d":
			_boss_part_hit(enemy, damage)
		"0xd8f5":
			_core_hit(enemy, damage)


func draw_enemy(enemy: Dictionary) -> void:
	var sy: int = enemy.get("world_y", 0) - main.scroll

	match enemy["kind"]:
		"l5_gate":
			if enemy["flash"] and enemy["role"] != "beam":
				main._draw_grid([[-(304 if enemy["role"] == "left" else 310)]], enemy["x"], sy, true)
		"l5_gun":
			if enemy["flash"]:
				main._draw_grid([[-enemy["first"][0]]], enemy["x"], sy, true)
		"l5_turret":
			if enemy["flash"]:
				main._draw_grid([[225, 226], [-241, 242]], enemy["x"], sy, true)
		"l5_ring":
			if enemy["flash"]:
				main._draw_grid([[257, 258], [273, 274]], enemy["x"], sy, true)
		_:
			_draw_other(enemy)

	main.flash_drawn(enemy)


func _draw_other(enemy: Dictionary) -> void:
	if enemy["kind"] == "l5_middle" and enemy["role"] == "head":
		_draw_middle_head(enemy)
		return

	if enemy["kind"] == "l5_boss":
		if enemy["role"] == "head":
			_draw_boss_head(enemy)
			return

		if enemy["role"] == "blocker":
			return

	if enemy.get("hidden", false):
		return

	main._draw_sprite(enemy["key"], enemy["x"], enemy["y"], enemy["flash"])


# ---------------------------------------------------------------- shared : missiles, lasers

# ds:0x3370 / 0x3380 : steps by direction (0 up, clockwise)

const STEP := [Vector2i(0, -5), Vector2i(4, -4), Vector2i(5, 0), Vector2i(4, 4),
	Vector2i(0, 5), Vector2i(-4, 4), Vector2i(-5, 0), Vector2i(-4, -4)]


func _turn_towards(item: Dictionary, x_odd_rule: bool) -> void:

	# a step a time towards the ship ; half way round by x's parity (0xd42c) or always back

	var target: int = main._direction(main.ship_x - item["x"], main.ship_y - item["y"])
	var diff: int = (target - item["direction"]) & 7

	if diff == 0:
		return

	var step := 1 if diff < 4 else -1

	if diff == 4:
		step = (1 if item["x"] & 1 else -1) if x_odd_rule else -1

	item["direction"] = (item["direction"] + step) & 7


func _spawn_missile(x: int, y: int, direction: int) -> void:

	# code 0xd38c : energy 6 (cs:0xcc6a), 100 points, gone after 80 frames (cs:0xcc6c)

	var m := _object("l5_missile", {
		"x": x,
		"y": y,
		"direction": direction,
		"counter": main._random() & 0x1f,
		"energy": 6,
		"score": 100,
		"hit": "0x3aa7",
	})
	_missile_anim(m)
	main.enemies.push_front(m)


func _missile_anim(m: Dictionary) -> void:
	var d: int = m["direction"]
	var frames := _anim([123 + 2 * d, 124 + 2 * d], 2)
	m["frames"] = frames
	m["anim"] = 0
	m["count"] = 2
	m["key"] = frames[0][0]


func _update_missile(m: Dictionary) -> void:

	# code 0xd3fa : turns towards the ship every 8 frames, 5 a frame
	# the ship test (0x42eb) reads the box bottom and 2 * direction, as coded

	main._step_animation(m, m["frames"], 0)
	m["key"] = m["frames"][m["anim"]][0]
	m["counter"] += 1

	if m["counter"] >= 80:
		main._explode(m, false)
		m["dead"] = true
		return

	if m["counter"] & 7 == 0:
		var before: int = m["direction"]
		_turn_towards(m, true)

		if m["direction"] != before:
			_missile_anim(m)

	var step: Vector2i = STEP[m["direction"]]
	m["x"] += step.x
	m["y"] += step.y + main.scroll_applied
	m["box"] = main._box_of(m["key"], m["x"], m["y"])
	var ship: Array = main.ship_box
	var bx: int = m["box"][3]
	var by: int = 2 * m["direction"]

	if bx >= ship[0] and bx <= ship[2] and by >= ship[1] and by <= ship[3]:
		main._damage_ship(4)
		main.ship_flash = true
		m["dead"] = true


func _spawn_laser(x: int, y: int, speed: int) -> void:

	# code 0xdcf5 : a bar that grows to 48 by 16 a frame, then flies at 16 ; 6 to the ship
	# on contact, then gone. It cannot be shot.

	main.effects.push_front({
		"kind": "l5_laser",
		"x": x,
		"y": y,
		"length": 0,
		"speed": speed,
		"dead": false,
		"box": [1000, 0, 1000, 0],
	})


func update_effect(item: Dictionary) -> void:
	if item["kind"] != "l5_laser":
		return

	if item["length"] != 48:
		item["length"] = mini(item["length"] + 16, 48)
		item["y"] += main.scroll_applied

		if item["speed"] < 0:
			item["y"] -= 16
	else:
		item["y"] += item["speed"]

		if (item["speed"] > 0 and item["y"] >= 0xc0) or (item["speed"] < 0 and item["y"] + item["length"] < 0):
			item["dead"] = true
			return

	item["box"] = [item["x"], item["y"], item["x"] + 11, item["y"] + item["length"]]

	if not main.dying and main._overlap(item["box"], main.ship_box):
		main._damage_ship(6)
		main.ship_flash = true
		item["dead"] = true


func draw_effect(item: Dictionary) -> void:

	# code f29:1f7e : the bar in colour 7, its caps X2WEAPS 89 (top) and 90 (bottom)

	var x: int = item["x"]
	var y: int = item["y"]
	var length: int = item["length"]
	var top := maxi(y + 1, 0)
	var bottom := mini(y + length - 1, 0xbf)

	if bottom >= top:
		main.world.draw_rect(Rect2(x, top, 12, bottom - top + 1), main.COLOUR_7)

	if item["speed"] < 0 or length == 48:
		main._draw_sprite("X2WEAPS/089", x, y, false)

	if item["speed"] > 0 or length == 48:
		main._draw_sprite("X2WEAPS/090", x, y + length - 1, false)


# ---------------------------------------------------------------- type 7 : the snake

func _spawn_snake(b: int) -> void:

	# code 0xd0f1 : 10 segments on path 110 + b (world coordinates), 12 steps apart, 10 a
	# frame, each energy 20, 200 points, 8 shots every way now and then

	var path: Dictionary = main.paths[110 + b]
	var start: Vector2i = path["start"]

	for k in 10:
		var s := _object("l5_snake", {
			"x": start.x,
			"y": start.y - main.scroll,
			"origin": Vector2i(start.x, start.y - main.scroll),
			"path": path,
			"steps": -12 * k,
			"heading": 0,
			"energy": 20,
			"score": 200,
			"hit": "0x3aa7",
			"fire_counter": 25 * (9 - k),
			"frames": [[_key(57), 0]],
			"anim": 0,
			"count": 0,
			"key": _key(57),
		})
		main.enemies.append(s)


const SNAKE_FRAMES := [[61, 62], [63, 64], [65, 66], [67, 68], [69, 70], [71, 72], [57, 58], [59, 60]]


func _update_snake(s: Dictionary) -> void:

	# code 0xd1b9

	var origin: Vector2i = s["origin"]
	origin.y += main.scroll_applied
	s["origin"] = origin
	s["y"] += main.scroll_applied

	if s["y"] >= 0x190:
		s["dead"] = true
		return

	var path: Dictionary = s["path"]
	var points: Array = path["points"]
	s["steps"] = mini(s["steps"] + 10, points.size())
	var steps: int = s["steps"]
	var start: Vector2i = path["start"]
	var point: Vector2i = start if steps <= 0 else points[steps - 1]
	s["x"] = origin.x + point.x - start.x
	s["y"] = origin.y + point.y - start.y
	var old: int = s["heading"]

	if steps > 0:
		s["heading"] = path["after"][steps - 1]

	main._step_animation(s, s["frames"], 0)
	var bucket: int = ((s["heading"] + 16) >> 5) & 7

	if bucket != ((old + 16) >> 5) & 7:
		s["frames"] = _anim(SNAKE_FRAMES[bucket], 3)
		s["anim"] = 0
		s["count"] = 3

	s["key"] = s["frames"][s["anim"]][0]

	# 4 a frame (cs:0xcc96), on the carry 0, 8 shots S5 175 at 10

	s["fire_counter"] += 4

	if s["fire_counter"] >= 0x100:
		s["fire_counter"] = 0

		for d in range(7, -1, -1):
			main._enemy_bullet(s["x"], s["y"], d, _key(175), 10)

	s["box"] = main._box_of(s["key"], s["x"], s["y"])


# ---------------------------------------------------------------- type 8 : the wall pod

func _spawn_pod(x: int, world_y: int, side: int) -> void:

	# code 0xd286 : energy 20 (cs:0xcc66), large explosion, 250 points, up and down between
	# world y 0xe30 and 0xf20, a missile out of the wall on the carry of 20

	var p := _object("l5_pod", {
		"side": side,
		"x": x,
		"y": world_y - main.scroll,
		"down": true,
		"energy": 20,
		"large": true,
		"score": 250,
		"hit": "0x3aa7",
	})
	_pod_anim(p)
	main.enemies.push_front(p)


func _pod_anim(p: Dictionary) -> void:
	var list: Array = [13, 14, 15, 16] if p["side"] == 0 else [17, 18, 19, 20]

	if not p["down"]:
		list.reverse()

	p["frames"] = _anim(list, 2)
	p["anim"] = 0
	p["count"] = 2
	p["key"] = p["frames"][0][0]


func _update_pod(p: Dictionary) -> void:
	p["y"] += main.scroll_applied

	if p["y"] >= 0x190:
		p["dead"] = true
		return

	main._step_animation(p, p["frames"], 0)
	p["key"] = p["frames"][p["anim"]][0]
	var wy: int = p["y"] + main.scroll

	if p["down"]:
		p["y"] += 1

		if wy + 1 >= 0xf20:
			p["down"] = false
			_pod_anim(p)
	else:
		p["y"] -= 1

		if wy - 1 <= 0xe30:
			p["down"] = true
			_pod_anim(p)

	if _carry(p, 20):
		if p["side"] == 0:
			_spawn_missile(p["x"] + 0x20, p["y"], 2)
		else:
			_spawn_missile(p["x"] - 0x20, p["y"], 6)

	p["box"] = main._box_of(p["key"], p["x"], p["y"])


# ---------------------------------------------------------------- type 5 : the middle guardian

const MIDDLE_GRID := [[-121, -122, -123, -124, -125, -126], [141, 142, 143, 144, 145, 146], [157, 158, 159, 160, 161, 162], [171, 172, 173, 174, 175, 176], [-189, 190, -191, -192, 193, 194], [-207, -208, -209, -210, -211, -212]]
const MIDDLE_MOUTH := [[143, 144, 159, 160, 173, 174], [177, 178, 195, 196, 213, 214], [177, 178, 195, 196, 213, 214], [179, 180, 197, 198, 215, 216], [179, 180, 197, 198, 215, 216], [181, 182, 199, 200, 217, 218], [181, 182, 199, 200, 217, 218], [183, 184, 201, 202, 219, 220], [183, 184, 201, 202, 219, 220]]

var middle_made := false
var middle_head: Dictionary = {}


func _spawn_middle(world_y: int) -> void:

	# code 0xd963 : once ; a head of 6x6 tiles at x 112, 4 aiming turrets (energy 40), the
	# rotor that kills it (energy 200), 4 ornaments, at the end of the enemies list

	if middle_made:
		return

	middle_made = true
	var y: int = world_y - main.scroll
	var parts := [["head", Vector2i.ZERO, 0], ["turret", Vector2i(0, 40), 40], ["turret", Vector2i(16, 56), 40],
		["turret", Vector2i(56, 56), 40], ["turret", Vector2i(72, 40), 40], ["rotor", Vector2i(40, 59), 200],
		["ornament_a", Vector2i(1, 0), 0], ["ornament_a", Vector2i(72, 0), 0],
		["ornament_b", Vector2i(1, 72), 0], ["ornament_b", Vector2i(72, 72), 0]]

	for p in parts:
		var role: String = p[0]
		var part := _object("l5_middle", {
			"role": role,
			"offset": p[1],
			"x": 0x70 + p[1].x,
			"y": y + p[1].y,
			"energy": p[2],
			"hit": {"turret": "0xdb2b", "rotor": "0xda58"}.get(role, "none"),
			"stays": true,
			"z_immune": true,
			"bob": 0,
			"spin": 0,
			"missile_counter": 0,
			"key": _key({"turret": 95, "rotor": 117, "ornament_a": 116, "ornament_b": 109}.get(role, 95)),
			"hidden": role == "head",
		})

		if role == "head":
			middle_head = part
			part["grid"] = MIDDLE_GRID.duplicate(true)

		main.enemies.append(part)


func _follow(part: Dictionary) -> void:
	var offset: Vector2i = part["offset"]
	part["x"] = middle_head["x"] + offset.x
	part["y"] = middle_head["y"] + offset.y


func _update_middle(part: Dictionary) -> void:
	match part["role"]:
		"head":
			_update_middle_head(part)
		"turret":
			_follow(part)

			if part.get("wreck", false):
				part["key"] = _key(103)
				part["box"] = [1000, 0, 1000, 0]
				return

			_update_aiming(part)
		"rotor":

			# code 0xda23 : spins faster as it is hurt

			_follow(part)
			part["spin"] = (part["spin"] + 0x100 - part["energy"]) % 0x600
			part["key"] = _key([117, 118, 119, 120, 119, 118][part["spin"] >> 8])
			part["box"] = main._box_of(part["key"], part["x"], part["y"])
		_:

			# code 0xdab0 : by world y & 3

			_follow(part)
			var i: int = (part["y"] + main.scroll) & 3
			part["key"] = _key(([116, 115, 114, 113] if part["role"] == "ornament_a" else [109, 110, 111, 112])[i])


func _update_aiming(part: Dictionary) -> void:

	# code 0xdad2 : turned to the ship, a shot (S5 175, speed 6) on the carry of 15

	var d: int = main._direction(main.ship_x - part["x"], main.ship_y - part["y"])
	part["key"] = _key(95 + d)

	if _carry(part, 15):
		main._enemy_bullet(part["x"] + 8, part["y"] + 8, d, _key(175), 6)

	part["box"] = main._box_of(part["key"], part["x"], part["y"])


func _update_middle_head(head: Dictionary) -> void:

	# code 0xdb82 : the back limit at least 0x920, it drifts up and down between world y
	# 0x8d0 and 0x910, a laser down every so often, two missiles sideways

	if main.scroll_max < 0x920:
		main.scroll_max = 0x920

	head["y"] += main.scroll_applied
	var wy: int = head["y"] + main.scroll

	if head["bob"] > 0:
		head["y"] += 1
		head["bob"] -= 1
	elif head["bob"] < 0:
		head["y"] -= 1
		head["bob"] += 1
	else:
		var r: int = main._random()

		if r & 0xff < 0xf:
			if r & 1:
				var room := 0x910 - wy

				if room > 0:
					head["bob"] = (main._random() % room) + 1
			else:
				var room := wy - 0x8d0

				if room > 0:
					head["bob"] = -((main._random() % room) + 1)

	if head["state"] == 0:
		if _carry(head, 10):
			head["state"] = 1
	else:
		head["state"] += 1

		if head["state"] == 9:
			head["state"] = 0
		elif head["state"] == 3:
			_spawn_laser(0x96, head["y"] + 0x30, 16)

	head["missile_counter"] += 14

	if head["missile_counter"] >= 0x100:
		head["missile_counter"] = main._random() & 0x3f
		_spawn_missile(0x6e, head["y"] + 0x30, 6)
		_spawn_missile(0xd2, head["y"] + 0x30, 2)


func _draw_middle_head(head: Dictionary) -> void:

	# code 0xdca2 : the grid with its mouth by the laser's state

	var grid: Array = head["grid"]
	var m: Array = MIDDLE_MOUTH[head["state"]]
	grid[1][2] = m[0]
	grid[1][3] = m[1]
	grid[2][2] = m[2]
	grid[2][3] = m[3]
	grid[3][2] = m[4]
	grid[3][3] = m[5]
	main._draw_grid(grid, 112, head["y"], head["flash"])
	main.flash_drawn(head)


func _middle_turret_hit(part: Dictionary, damage: int) -> void:

	# code 0xdb2b : a flash ; dead, a wreck (S5 103), 200 points, a small explosion

	part["flash"] = true
	part["energy"] -= damage

	if part["energy"] > 0:
		return

	part["wreck"] = true
	part["hit"] = "none"
	part["box"] = [1000, 0, 1000, 0]
	main.score += 200
	main._explode_at(part["x"] + 8, part["y"] + 8, main.SMALL_EXPLOSION)


func _rotor_hit(rotor: Dictionary, damage: int) -> void:

	# code 0xda58 : the head flashes ; dead, every enemy gone, 20 explosions, 5 pairs of
	# bonuses, its map tiles (rows 141 to 150, columns 6 to 13) cleared, 1500 points

	middle_head["flash"] = true
	rotor["energy"] -= damage

	if rotor["energy"] > 0:
		return

	for enemy in main.enemies:
		enemy["dead"] = true

	main.enemies.clear()
	main._explosions(0x70, 0x8d0 - main.scroll, 0x60, 0xa0, main.LARGE_EXPLOSION, 20)
	main._bonus_pairs(5)

	for row in 10:
		for column in 8:
			_put(0x1614 / 2 + row * 20 + column, 0)

	main.score += 1500


# ---------------------------------------------------------------- type 6 : the end guardian

const BOSS_GRID := [[0, 0, 0, 0, 0, -320, -321, -322, -323, -324, 0, 0, 0, 0, 0], [0, 0, 0, -325, -326, -327, 328, -329, 330, -331, -332, -333, 0, 0, 0], [-334, 0, 0, -335, -336, 337, 338, 339, 340, 341, -342, -343, 0, 0, -344], [-345, 0, 0, 0, -346, 347, 348, 349, 350, 351, -352, 0, 0, 0, -353], [-354, 0, -355, -356, -357, 358, 359, 360, 361, 362, -363, -364, -365, 0, -366], [-367, -368, -369, -370, -371, 372, 373, 374, 375, 376, -377, -378, -379, -380, -381], [-382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, -396], [-397, -398, -399, -400, 401, 402, 412, 413, 414, 415, 407, -408, -409, -410, -411], [0, 0, 0, -416, -417, -418, 426, 427, 428, -429, -423, -424, 0, 0, 0], [0, 0, 0, 0, 0, -430, 431, 432, 433, -434, 0, 0, 0, 0, 0], [0, 0, 0, -325, -435, -436, 437, 438, 439, -440, -441, -333, 0, 0, 0], [-334, 0, 0, -335, -442, 443, 444, 445, 446, 447, -448, -343, 0, 0, -344], [-345, 0, 0, 0, -346, 347, 348, 349, 350, 351, -352, 0, 0, 0, -353], [-354, 0, -355, -356, -357, 358, 359, 360, 361, 362, -363, -364, -365, 0, -366], [-367, -368, -369, -370, -371, 372, 373, 374, 375, 376, -377, -378, -379, -380, -381], [-382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, -396], [-397, -398, -399, -400, 401, 402, -403, 404, -405, 406, 407, -408, -409, -410, -411], [0, 0, 0, -416, -417, -418, -419, -420, -421, -422, -423, -424, 0, 0, 0]]
const MOUTH_FRAMES := [104, 105, 106, 107, 108, 108, 108, 108, 108, 108, 108, 107, 106, 105, 104]
const CORE_FRAMES := [207, 206, 205, 204, 203, 202, 201, 200, 199, 198, 197]

var boss_made := false
var boss_head: Dictionary = {}
var parts_left := 18
var boss_energy := 20


func _spawn_boss() -> void:

	# code 0xd4a8 : once ; a checkpoint at 0x1a0, the guardian written into the map (rows 6
	# to 23, columns 3 to 17), the scroll at 0x1a0, 22 parts at the end of the enemies list

	if boss_made:
		return

	boss_made = true
	main.checkpoint_scroll = 0x1a0
	main.checkpoint_x = 0xa0
	main._save_weapons()

	for i in 6 * 20:
		_put(i, 0)

	for row in 18:
		for column in 20:
			var t: int = BOSS_GRID[row][column - 3] if column >= 3 and column < 18 else 0
			_put((6 + row) * 20 + column, _word(absi(t), t < 0))

	for i in 300:
		_put(24 * 20 + i, 0)

	main.scroll = 0x1a0
	main.scroll_max = 0x1a0
	parts_left = 18
	boss_energy = 20
	var y := -320
	var specs := [["head", Vector2i.ZERO, 0, false]]

	for o in [Vector2i(0, 224), Vector2i(0, 80)]:
		specs.append(["blocker", o, 0, false])

	for o in [Vector2i(72, 53), Vector2i(154, 58), Vector2i(63, 108), Vector2i(162, 108), Vector2i(72, 197), Vector2i(154, 202), Vector2i(63, 252), Vector2i(162, 252)]:
		specs.append(["turret", o, 30, false])

	for o in [Vector2i(43, 77), Vector2i(188, 77), Vector2i(43, 221), Vector2i(189, 221)]:
		specs.append(["launcher", o, 10, true])

	for o in [Vector2i(62, 18), Vector2i(174, 18), Vector2i(62, 162), Vector2i(174, 162)]:
		specs.append(["light", o, 5, false])

	for o in [Vector2i(80, 281), Vector2i(138, 281)]:
		specs.append(["eye", o, 40, true])

	specs.append(["core", Vector2i(112, 271), 20, true])

	for s in specs:
		var role: String = s[0]
		var part := _object("l5_boss", {
			"role": role,
			"offset": s[1],
			"x": 0x30 + s[1].x,
			"y": y + s[1].y,
			"energy": s[2],
			"large": s[3],
			"type50": true,
			"stays": true,
			"hit": {"blocker": "0x3a99", "turret": "0xd89d", "launcher": "0xd89d", "light": "0xd89d", "eye": "0xd89d", "core": "0xd8f5"}.get(role, "none"),
		})

		match role:
			"turret":
				part["key"] = _key(95)
			"launcher":
				part["frames"] = [[_key(181), 0], [_key(182), 2], [_key(183), 2], [_key(184), 2], [_key(185), 2]]
			"light":
				part["frames"] = _anim([176, 177, 178, 179, 180, 179, 178, 177], 1)
			"eye":
				part["frames"] = _anim([186, 187, 188, 187], 2)
			"core":
				part["key"] = _key(197)

		if part.has("frames"):
			part["anim"] = 0
			part["count"] = part["frames"][0][1]
			part["key"] = part["frames"][0][0]

		if role == "head":
			boss_head = part
			part["mouth"] = 0

		main.enemies.append(part)


func _boss_follow(part: Dictionary) -> void:
	var offset: Vector2i = part["offset"]
	part["x"] = boss_head["x"] + offset.x
	part["y"] = boss_head["y"] + offset.y


func _update_boss(part: Dictionary) -> void:
	match part["role"]:
		"head":
			_update_boss_head(part)
		"blocker":

			# code 0xd5f9 : stops shots ; its bottom is the low byte of y + 16 (no carry)

			_boss_follow(part)
			var y: int = part["y"]
			var y2 := (y & ~0xff) | ((y + 16) & 0xff)
			part["box"] = [part["x"], y, part["x"] + 240, y2]
		"turret":
			_boss_follow(part)

			if part.get("wreck", false):
				part["key"] = _key(103)
				part["box"] = [1000, 0, 1000, 0]
				return

			_update_aiming(part)
		"launcher":

			# code 0xd82a : held, released on the carry of 15 while on the screen ; a laser
			# up as it opens

			_boss_follow(part)
			main._step_animation(part, part["frames"], 0)
			part["key"] = part["frames"][part["anim"]][0]

			if part["key"] == _key(182) and part["count"] == 1:
				_spawn_laser(part["x"] - 2, part["y"] - 0x18, -16)

			if part["count"] == 0 and part["y"] >= 0 and _carry(part, 15):
				part["count"] = 1

			part["box"] = main._box_of(part["key"], part["x"], part["y"])
		"light", "eye":
			_boss_follow(part)
			main._step_animation(part, part["frames"], 0)
			part["key"] = part["frames"][part["anim"]][0]
			part["box"] = main._box_of(part["key"], part["x"], part["y"])
		"core":

			# code 0xd61e : a box only once every other part is dead

			_boss_follow(part)
			part["box"] = main._box_of(part["key"], part["x"], part["y"]) if parts_left == 0 else [1000, 0, 1000, 0]


func _update_boss_head(head: Dictionary) -> void:

	# code 0xd62c : the back limit 0x1a0, the stars at the top, the mouth opening up or
	# down and spitting at 40

	main.scroll_max = 0x1a0

	if main.scroll == 0:
		main._move_stars(main.scroll_asked)

	head["y"] += main.scroll_applied
	var m: int = head["mouth"]

	if m == 0:
		if _carry(head, 7):
			main.sound_priority = 0

			# Amiga level 5 code $55e12 : -1 on $418, no effect

			main.amiga_1 = -1
			head["mouth"] = 2 if main.frame_count & 1 else -2
	else:
		m += 2 if m > 0 else -2
		head["mouth"] = m
		var a := absi(m)

		if a == 20:
			main.sound_priority = 0xc

			# Amiga level 5 code $55dd0 : $13 on $418

			main.amiga_1 = 0x13
		elif a == 40:
			main._stop_sound()
			_spawn_spit(head["x"] + 0x77, head["y"] + (0x65 if m > 0 else 0xf5))
		elif a == 60:
			head["mouth"] = 0


func _draw_boss_head(head: Dictionary) -> void:

	# code 0xd74c, 0xd5dd : the mouth while open ; the hit flash is the whole grid

	if head["flash"]:
		main._draw_grid(BOSS_GRID, head["x"], head["y"], true)
		main.flash_drawn(head)
		return

	var m: int = head["mouth"]

	if m == 0:
		return

	var b := absi(m) & ~3
	var dy := 0x55 if m > 0 else 0xe5
	main._draw_sprite(_key(MOUTH_FRAMES[mini(b >> 2, 14)]), head["x"] + 0x69, head["y"] + dy, false)

	if b >= 20 and b < 40:
		main._draw_sprite(_key(156 + (b >> 2)), head["x"] + 0x77, head["y"] + dy + 0x10, false)


func _spawn_spit(x: int, y: int) -> void:

	# code 0xd798 : energy 4 (cs:0xcc70), 150 points ; turns to the ship every 8 frames, twice
	# as fast once the guardian's parts are dead, 4 to the ship on contact

	var s := _object("l5_spit", {
		"x": x,
		"y": y,
		"direction": 0,
		"counter": 0,
		"energy": 4,
		"score": 150,
		"hit": "0x3aa7",
	})
	_spit_anim(s)
	main.enemies.push_front(s)


func _spit_anim(s: Dictionary) -> void:
	var d: int = s["direction"]
	s["frames"] = _anim([145 + 2 * d, 146 + 2 * d], 2)
	s["anim"] = 0
	s["count"] = 2
	s["key"] = s["frames"][0][0]


func _update_spit(s: Dictionary) -> void:
	main._step_animation(s, s["frames"], 0)
	s["key"] = s["frames"][s["anim"]][0]
	s["counter"] += 1

	if s["counter"] & 7 == 0:
		var before: int = s["direction"]
		_turn_towards(s, false)

		if s["direction"] != before:
			_spit_anim(s)

	var step: Vector2i = STEP[s["direction"]] * (2 if parts_left == 0 else 1)
	s["x"] += step.x
	s["y"] += step.y
	s["box"] = main._box_of(s["key"], s["x"], s["y"])

	if not main.dying and main._overlap(s["box"], main.ship_box):
		main._damage_ship(4)
		main.ship_flash = true
		s["dead"] = true


func _boss_part_hit(part: Dictionary, damage: int) -> void:

	# code 0xd89d : a flash ; dead, one part less, 200 points, an explosion, a turret left
	# as a wreck, the others gone

	part["flash"] = true
	part["energy"] -= damage

	if part["energy"] > 0:
		return

	parts_left -= 1
	main.score += 200
	main._explode(part, part["large"])
	part["hit"] = "none"

	if part["role"] == "turret":
		part["wreck"] = true
		part["box"] = [1000, 0, 1000, 0]
	else:
		part["dead"] = true


func _core_hit(core: Dictionary, damage: int) -> void:

	# code 0xd8f5 : the core and the guardian flash, the guardian's energy (20) down, the
	# core's frame by what is left. Dead : the map cleared, every enemy gone, 10 pairs of
	# bonuses, 40 explosions, the level done.

	core["flash"] = true
	boss_head["flash"] = true
	boss_energy -= damage

	if boss_energy > 0:
		core["key"] = _key(CORE_FRAMES[mini(11 * boss_energy / 20, 10)])
		return

	for i in range(0x1e0 >> 1, (0x4b0 >> 1)):
		_put(i, 0)

	for enemy in main.enemies:
		enemy["dead"] = true

	main.enemies.clear()
	main._bonus_pairs(10)
	main._explosions(0, 0, 0x140, 0xc0, main.LARGE_EXPLOSION, 40)
	main.level_done = true

	for i in range(0, 0x618 >> 1):
		_put(i, 0)