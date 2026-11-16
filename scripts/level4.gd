class_name Level4
extends RefCounted

# Level 4 of XENON2.EXE, the routines the level's tables point to (load module offsets) :
# init 0xc79f, hook 0xb555, wall objects 0xb8ef (table cs:0xc95e). The wave types (0xc771)
# need nothing of their own. "code" marks behaviour ported from the code, "unconfirmed" a
# detail left open there.
#
# Lists : the pistons (wall type 5) are on the list ds:0x90e2, never hit-tested, updated
# after the effects and drawn last (tile_objects here).

var main: Node
var tile_objects: Array = []

# ds:0x9236 / 0x9237 the middle and end guardians made, ds:0x9210 the middle guardian's parts
# left to kill before its core, ds:0x9212 the end guardian's guns left, ds:0x9214 its bob

var middle_made := false
var end_made := false
var middle_left := 5
var guns_left := 2
var bob := 0
var groups_made := 0

const HITS := ["0xc6e5", "0xc4d8", "0xbcab", "0xbcd3", "0xbd46", "0xb8f8", "0xb930"]


func _init(owner: Node) -> void:
	main = owner

	# test option : --scroll past the stop at 0x880 starts with it let go

	if main.scroll < 0x880:
		main.scroll_min = 0


func _key(frame: int) -> String:
	return "S4/%03d" % frame


func _anim(list: Array, ticks: int) -> Array:
	var out: Array = []

	for f in list:
		out.append([_key(f), ticks])

	return out


func _pairs(list: Array) -> Array:
	var out: Array = []

	for f in list:
		out.append([_key(f[0]), f[1]])

	return out


func _set_anim(item: Dictionary, frames: Array) -> void:
	item["frames"] = frames
	item["anim"] = 0
	item["count"] = frames[0][1]
	item["key"] = frames[0][0]


func _step(item: Dictionary) -> void:
	main._step_animation(item, item["frames"], 0)
	item["key"] = item["frames"][item["anim"]][0]


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
		"hit": "0x3aa7",
		"key": "S4/102",
		"fire_counter": 0,
	}
	object.merge(fields, true)
	return object


func _carry(item: Dictionary, field: String, amount: int) -> bool:

	# a byte that fires on its carry, then starts again from a random 0 to 0x3f

	item[field] += amount

	if item[field] < 0x100:
		return false

	item[field] = main._random() & 0x3f
	return true


func _bullet(x: int, y: int, direction: int, frames: Array, speed: int) -> void:
	main._enemy_bullet(x, y, direction, frames[0][0], speed)

	if frames.size() > 1:
		var bullet: Dictionary = main.effects[0]
		bullet["frames"] = frames
		bullet["anim"] = 0
		bullet["count"] = frames[0][1]


# ---------------------------------------------------------------- the hook

func hook() -> void:

	# code 0xb555 : past 0xdf0 no way back above it. Every 16 frames from 0xe50 to 0xae0 a
	# pod comes down from the top, kind by chance, side by bit 5 of the frame count.

	if main.scroll_max >= 0xdf0 and main.scroll <= 0xdf0:
		main.scroll_max = 0xdf0

	if main.frame_count & 15 != 0 or main.scroll > 0xe50 or main.scroll < 0xae0:
		return

	var kind: int = main._random() & 1
	var right: bool = main.frame_count & 0x20 != 0
	var pod := _object("l4_pod", {
		"kind_b": kind == 1,
		"right": right,
		"x": 0x120 if right else 0x20,
		"y": -32,
		"counter": 0,
		"shot_counter": 0,
		"fire_counter": main._random() & 0xff,
		"energy": 8,
		"large": true,
		"score": 300,
	})

	if kind == 1:
		_set_anim(pod, _anim([22, 23, 24, 25, 26, 27] if right else [16, 17, 18, 19, 20, 21], 3))
	else:
		_set_anim(pod, _anim([6, 7, 8, 9, 10, 11] if right else [0, 1, 2, 3, 4, 5], 2))

	pod["box"] = main._box_of(pod["key"], pod["x"], pod["y"])
	main.enemies.push_front(pod)


func _update_pod(pod: Dictionary) -> void:
	_step(pod)

	if pod["kind_b"]:

		# code 0xb899 : down by 1 more than the scroll, a shot down to the middle (S4 114
		# or 113, speed 4, the in-between directions 10 or 13)

		pod["y"] += main.scroll_applied + 1

		if pod["y"] >= 200:
			pod["dead"] = true
			return

		if _carry(pod, "fire_counter", 8):
			if pod["right"]:
				main._enemy_bullet(pod["x"] - 0x1a, pod["y"] + 0x1a, 0xd, _key(113), 4)
			else:
				main._enemy_bullet(pod["x"] + 0x1a, pod["y"] + 0x1a, 0xa, _key(114), 4)
	else:

		# code 0xb613 : down by 4 more than the scroll, a capsule every 48 frames, shots
		# down (S4 110, speed 8). unconfirmed : the shot counter (+0x49) starts at 0 here.

		pod["y"] += main.scroll_applied + 4

		if pod["y"] >= 200:
			pod["dead"] = true
			return

		pod["counter"] += 1

		if pod["counter"] == 13:
			pod["counter"] = 0

		if pod["counter"] == 8 and _carry(pod, "fire_counter", 0x40):
			_spawn_capsule(pod)

		if _carry(pod, "shot_counter", 0x10):
			main._enemy_bullet(pod["x"] - 0x10 if pod["right"] else pod["x"] + 0x14, pod["y"], 4, _key(110), 8)

	pod["box"] = main._box_of(pod["key"], pod["x"], pod["y"])


func _spawn_capsule(pod: Dictionary) -> void:

	# code 0xb64a : on the effects list, it opens, lets a swimmer out and bursts

	var right: bool = pod["right"]
	var base := 81 if right else 91
	var frames := [[base, 10], [base + 1, 2], [base + 2, 2], [base + 3, 2], [base + 4, 2], [base + 5, 1],
		[base + 6, 2], [base + 7, 2], [base + 8, 2], [base + 9, 2], [base, 1], [base, 0]]
	var capsule := {
		"kind": "l4_capsule",
		"right": right,
		"x": 0x120 if right else 0x20,
		"y": pod["y"] - 0x1e,
		"dead": false,
		"box": [1000, 0, 1000, 0],
	}
	_set_anim(capsule, _pairs(frames))
	main.effects.push_front(capsule)


func _update_capsule(capsule: Dictionary) -> void:

	# code 0xb6eb

	capsule["y"] += main.scroll_applied
	_step(capsule)

	if capsule["key"] == _key(96):
		_spawn_swimmer(capsule["x"] + 10, capsule["y"], 0)
	elif capsule["key"] == _key(86):
		_spawn_swimmer(capsule["x"] - 10, capsule["y"], 0x80)

	if capsule["count"] == 0:

		# code 0xb6f4 : the burst at its middle

		capsule["dead"] = true
		var h: Array = main.headers[capsule["key"]]
		var cx: int = ((capsule["x"] - h[4]) * 2 + h[6]) >> 1
		var cy: int = ((capsule["y"] - h[5]) * 2 + h[7] - 1) >> 1
		main.effects.push_front({"kind": "explosion", "x": cx, "y": cy, "frames": main.SMALL_EXPLOSION, "index": 0, "count": 1, "dead": false})


# cs:0xc856 : the swimmer by heading sector (0 right, clockwise), ping-pong

const SWIM := [58, 62, 66, 70, 42, 46, 50, 54]


func _swim_anim(sector: int) -> Array:
	var a: int = SWIM[sector]
	return _anim([a, a + 1, a + 2, a + 3, a + 2, a + 1], 1)


func _spawn_swimmer(x: int, y: int, angle: int) -> void:

	# code 0xb751 : energy 2, 100 points, a wave group of its own, path 72 or 74 at 5 steps
	# a frame

	groups_made += 1
	var id := 0x10000 + groups_made

	for slot in main.groups:
		if slot[0] == 0:
			slot[0] = id
			slot[1] = 1
			break

	var swimmer := _object("l4_swimmer", {
		"x": x,
		"y": y,
		"origin": Vector2i(x, y),
		"path": main.paths[72 if angle == 0 else 74],
		"steps": 0,
		"heading": angle,
		"energy": 2,
		"score": 100,
		"group": id,
	})
	_set_anim(swimmer, _swim_anim(0 if angle == 0 else 4))
	main.enemies.push_front(swimmer)


func _update_swimmer(s: Dictionary) -> void:

	# code 0xb80d : the path (0x480b) ; at its end the group goes and a new path starts
	# from where it is (72 or 73 on the left half, 74 or 75 on the right), so it only goes
	# when shot. The animation follows the heading's sector.

	_step(s)
	var path: Dictionary = s["path"]
	var points: Array = path["points"]
	s["steps"] += 5

	if s["steps"] > points.size():
		main._cancel_group(s["group"])
		var table := [0, 2, 1, 3]
		var n: int = table[((main._random() & 4) >> 1) + (1 if s["x"] >= 0xa0 else 0)]
		s["path"] = main.paths[72 + n]
		s["origin"] = Vector2i(s["x"], s["y"])
		s["steps"] = 0
		s["box"] = main._box_of(s["key"], s["x"], s["y"])
		return

	path = s["path"]
	var start: Vector2i = path["start"]
	var point: Vector2i = path["points"][s["steps"] - 1]
	var origin: Vector2i = s["origin"]
	s["x"] = origin.x + point.x - start.x
	s["y"] = origin.y + point.y - start.y
	var old: int = s["heading"]
	s["heading"] = path["after"][s["steps"] - 1]
	var sector: int = ((s["heading"] + 0x10) >> 5) & 7

	if sector != ((old + 0x10) >> 5) & 7:
		_set_anim(s, _swim_anim(sector))

	s["box"] = main._box_of(s["key"], s["x"], s["y"])


# ---------------------------------------------------------------- chains

func _chain_state(part: Dictionary) -> void:
	part["xf"] = 0
	part["yf"] = 0
	part["rate"] = 0
	part["accel"] = 0
	part["steps"] = 3


func _chain_step(part: Dictionary, prev: Dictionary) -> void:

	# code 0xbebc then 0x4871 : the previous part's place, heading, turn rate, its change
	# and steps copied, then that many steps of 1 pixel, the heading turning

	var x: int = prev["x"]
	var y: int = prev["y"]
	var xf: int = prev["xf"]
	var yf: int = prev["yf"]
	var heading: int = prev["heading"]
	var rate: int = prev["rate"]
	var accel: int = prev["accel"]
	var steps: int = prev["steps"]

	for i in steps:
		var angle := (heading >> 16) & 0xff
		var dy := int(main.sine[angle]) * 4
		var dx := int(main.sine[angle + 64]) * 4
		yf += dy & 0xff
		y += (dy >> 8) + (yf >> 8)
		yf &= 0xff
		xf += dx & 0xff
		x += (dx >> 8) + (xf >> 8)
		xf &= 0xff
		heading = (heading + rate) & 0xffffff
		rate += accel

	part["x"] = x
	part["y"] = y
	part["xf"] = xf
	part["yf"] = yf
	part["heading"] = heading
	part["rate"] = rate
	part["accel"] = accel
	part["steps"] = steps


func _wave(part: Dictionary) -> void:

	# code 0xbfff : heading, turn rate and its change from the frame count, so the tail
	# (and the end guardian's tongue) sways

	var fc: int = main.frame_count
	var t := (fc * 4) & 0x7f

	if t & 0x40:
		t = 0x7f - t

	part["heading"] = (0xa0 + t) << 16
	var t2 := (fc * 2 + 0x50) & 0xff

	if t2 >= 0x80:
		t2 = ~t2 & 0xff

	part["rate"] = (t2 - 0x40) * 256
	var t3 := (fc + 0xa0) & 0x1ff

	if t3 >= 0x100:
		t3 ^= 0x1ff

	part["accel"] = (t3 - 0x80) * 4


# ---------------------------------------------------------------- wall objects 0xb8ef

const GUN_TILES := [[[235, 236, 247, 248], [237, 238, 249, 250], [239, 240, 251, 252]],
	[[229, 230, 241, 242], [231, 232, 243, 244], [233, 234, 245, 246]]]
const LUNGE := [[[31, 0], [31, 4], [32, 8], [33, 0]], [[28, 0], [28, 4], [29, 8], [30, 0]]]
const LUNGE_COVER := [[196, 212, 228], [195, 211, 227]]


func spawn_wall(wall: Dictionary) -> void:
	var type := int(wall["type"])
	var side := int(wall["side"])
	var x := int(wall["x"]) - 8
	var world_y := int(wall["world_y"]) - 8

	match type:
		1:

			# code 0xc5c3 : a wall gun of 2x2 map tiles, energy 16 (cs:0xb004)

			var cell := (world_y >> 4) * 20 + (x >> 4)
			var tiles: Array = GUN_TILES[0 if side == 0 else 1]
			main._write_tiles(cell, tiles[0], 4)
			main.enemies.push_front(_object("l4_gun", {
				"side": side,
				"x": x,
				"world_y": world_y,
				"cell": cell,
				"tiles": tiles,
				"state": 0,
				"energy": 16,
				"hit": "0xc6e5",
			}))
		2:
			_spawn_middle()
		3:

			# code 0xc368 : a creature lunging out of the wall, energy 10 (cs:0xaffe), 200
			# points, a large bonus when killed, then back home

			var hx := x + (16 if side == 0 else 0)
			var hy := world_y + 0x1c
			var c := _object("l4_lunge", {
				"side": side,
				"x": hx,
				"world_y": hy,
				"home": Vector2i(hx, hy),
				"cover": Vector2i(x, world_y),
				"state": 0,
				"way": 0,
				"energy": 10,
				"large": true,
				"score": 200,
				"hit": "0xc4d8",
			})
			_set_anim(c, _pairs(LUNGE[0 if side == 0 else 1]))
			main.enemies.push_front(c)
		4:
			_spawn_end()
		5:

			# code 0xc1f3 : a piston on the list 0x90e2, it cannot be shot

			var p := {
				"kind": "l4_piston",
				"right": side == 0,
				"x": x,
				"y": world_y - main.scroll,
				"n": 0,
				"delta": 1,
				"fire_counter": 0,
				"dead": false,
				"box": [1000, 0, 1000, 0],
			}
			_set_anim(p, _anim([38, 39, 40, 41] if side == 0 else [34, 35, 36, 37], 2))
			tile_objects.append(p)


func _update_gun(gun: Dictionary) -> void:

	# code 0xc61a

	if gun["world_y"] > main.scroll_max + 0xd0:
		gun["dead"] = true
		return

	var x: int = gun["x"]
	var sy: int = gun["world_y"] - main.scroll
	gun["box"] = [x + 2, sy + 2, x + 0x1e, sy + 0x1e]

	if gun["state"] == 0:
		if _carry(gun, "fire_counter", 0x10):
			gun["state"] = 1

		return

	var s: int = gun["state"]
	var tiles: Array = gun["tiles"]
	main._write_tiles(gun["cell"], tiles[0 if s == 5 else 1], 4)
	gun["state"] += 1

	if gun["state"] == 4:

		# code 0xc6ae : S4 111, speed 6, out of the wall

		if gun["side"] == 0:
			main._enemy_bullet(x + 0x12, sy + 0xe, 2, _key(111), 6)
		else:
			main._enemy_bullet(x + 0xa, sy + 0xe, 6, _key(111), 6)
	elif gun["state"] == 6:
		gun["state"] = 0


func _gun_hit(gun: Dictionary, damage: int) -> void:

	# code 0xc6e5 : a flash ; dead, a large explosion, its death tiles, 400 points

	gun["flash"] = true
	gun["energy"] -= damage

	if gun["energy"] > 0:
		return

	var sy: int = gun["world_y"] - main.scroll
	main._explode_at(gun["x"] + 0x10, sy + 0x10, main.LARGE_EXPLOSION)
	main._write_tiles(gun["cell"], gun["tiles"][2], 4)
	main.score += 400
	gun["dead"] = true


func _update_lunge(c: Dictionary) -> void:

	# code 0xc3ea : waits in the wall (no box), by 24 in 256 a frame comes out sideways 6 a
	# frame, then also up or down towards the ship's side, home again once off the screen

	if c["world_y"] > main.scroll_max + 0xd0:
		c["dead"] = true
		return

	_step(c)

	if c["state"] == 0:
		c["box"] = [1000, 0, 1000, 0]

		if main._random() & 0xff < 0x18:
			c["state"] = 1
			c["count"] = 1

		_place_lunge(c, false)
		return

	c["x"] += 6 if c["side"] == 0 else -6

	if c["state"] == 1:
		if c["count"] == 0:
			c["state"] = 2
			c["way"] = main.ship_y - (c["world_y"] - main.scroll)

		_place_lunge(c, true)
		return

	if c["x"] >= 0x28 and c["x"] <= 0x118:
		c["world_y"] += -6 if c["way"] < 0 else 6

	if c["x"] < -0x20 or c["x"] >= 0x160:
		_lunge_home(c)
		return

	_place_lunge(c, true)


func _place_lunge(c: Dictionary, boxed: bool) -> void:
	c["y"] = c["world_y"] - main.scroll

	if boxed:
		c["box"] = main._box_of(c["key"], c["x"], c["y"])


func _lunge_home(c: Dictionary) -> void:

	# code 0xc489

	var home: Vector2i = c["home"]
	c["x"] = home.x
	c["world_y"] = home.y
	c["y"] = home.y - main.scroll
	c["state"] = 0
	c["energy"] = 10
	c["box"] = [1000, 0, 1000, 0]
	_set_anim(c, _pairs(LUNGE[0 if c["side"] == 0 else 1]))


func _lunge_hit(c: Dictionary, damage: int) -> void:

	# code 0xc4d8 : a flash ; dead, a large explosion at it, 200 points, a large bonus
	# (not counted in ds:0x9164), then home again with its energy back

	c["flash"] = true
	c["energy"] -= damage

	if c["energy"] > 0:
		return

	main._explode(c, true)
	main.score += 200
	main._spawn_bonus({"x": c["x"], "y": c["y"], "large": true})
	_lunge_home(c)


func _update_piston(p: Dictionary) -> void:

	# code 0xc230 : out a column of 16 pixels a frame up to 6 and back, on the carry of 2 a
	# frame ; 6 to the ship's energy on every frame of contact

	p["y"] += main.scroll_applied

	if p["y"] > 0x188:
		p["dead"] = true
		return

	_step(p)

	if p["n"] == 0:
		p["delta"] = 1

		if _carry(p, "fire_counter", 2):
			p["n"] += p["delta"]
	else:
		p["n"] += p["delta"]

	if p["n"] == 6:
		p["delta"] = -p["delta"]

	var n: int = p["n"]
	var x: int = p["x"]
	var y: int = p["y"]
	p["box"] = [x, y + 8, x + 16 * n + 16, y + 0x18] if p["right"] else [x - 16 * n, y + 8, x + 16, y + 0x18]

	if not main.dying and main._overlap(p["box"], main.ship_box):
		main._damage_ship(6)
		main.ship_flash = true


func update_tile_objects() -> void:
	for object in tile_objects.duplicate():
		if object["dead"]:
			tile_objects.erase(object)
		else:
			_update_piston(object)


func draw_tile_objects() -> void:

	# code 0xc2d5 : the rod (tiles 253 and 254) and the head

	for p in tile_objects:
		if p["dead"]:
			continue

		var n: int = p["n"]
		var x: int = p["x"]
		var y: int = p["y"]

		if n > 0:
			var top: Array = []
			var bottom: Array = []

			for i in n:
				top.append(-253)
				bottom.append(-254)

			main._draw_grid([top, bottom], x if p["right"] else x + 0x10 - 16 * n, y, false)

		main._draw_sprite(p["key"], x + 16 * n if p["right"] else x - 16 * n + 0xf, y + 8, false)


# ---------------------------------------------------------------- the middle guardian

# cs:0xca5e : (role, x, world y, heading, energy, large)

const MIDDLE_PARTS := [
	["base", 0xa0, 0x9e8, 64, 50, true], ["neck", 0xa0, 0x9e8, 64, 50, true],
	["neck", 0xa0, 0x9e8, 64, 50, true], ["neck", 0xa0, 0x9e8, 64, 50, true],
	["core", 0xa0, 0xa00, 64, 175, true], ["mouth", 0xa0, 0xa00, 64, 50, true],
	["root", 0xa0, 0x8f8, 192, 1, false], ["tail", 0xa0, 0x8f8, 192, 1, false],
	["tail", 0xa0, 0x8f8, 192, 1, false], ["tail", 0xa0, 0x8f8, 192, 1, false],
	["tail", 0xa0, 0x8f8, 192, 1, false], ["tail", 0xa0, 0x8f8, 192, 1, false],
	["tail", 0xa0, 0x8f8, 192, 1, false], ["tail", 0xa0, 0x8f8, 192, 1, false],
	["tail", 0xa0, 0x8f8, 192, 1, false], ["tip", 0xa0, 0x8f8, 192, 20, false],
	["pod", 120, 0x997, 0, 20, false], ["pod", 120, 0x957, 0, 20, false],
	["pod", 200, 0x997, 0, 20, false], ["pod", 200, 0x957, 0, 20, false],
]

const NECK_FRAMES := [14, 13, 12, 15]
const CORE_FRAMES := {2: 157, 3: 158, 4: 151, 5: 152, 6: 153}
const MOUTH_FRAMES := {2: [177, 178, 179, 178], 3: [180, 181, 182, 181], 4: [159, 160, 161, 160],
	5: [162, 163, 164, 163], 6: [165, 166, 167, 166]}
const MOUTH_SHOT := {2: Vector2i(20, 0), 3: Vector2i(14, 14), 4: Vector2i(0, 20), 5: Vector2i(-14, 14), 6: Vector2i(-20, 0)}
const POD_FRAMES := [[199, 200], [201, 202], [203, 204], [205, 206], [191, 192], [193, 194], [195, 196], [197, 198]]
const SHOT_ANIM := [207, 208, 209, 210]

var middle: Array = []


func _spawn_middle() -> void:

	# code 0xc12c : once ; a checkpoint at 0x9b0, 20 parts (type 0x54) at the end of the
	# enemies list, the tail tip and the four pods to kill before the core can be hurt

	if middle_made:
		return

	middle_made = true
	main.checkpoint_scroll = 0x9b0
	main.checkpoint_x = 0xa0
	main._save_weapons()
	middle = []

	for entry in MIDDLE_PARTS:
		var role: String = entry[0]
		var part := _object("l4_middle", {
			"role": role,
			"x": entry[1],
			"y": entry[2] - main.scroll,
			"heading": entry[3] << 16,
			"direction": entry[3],
			"energy": entry[4],
			"large": entry[5],
			"hit": "none",
			"z_immune": true,
			"lunge": 0,
			"lunge_step": 0,
		})
		_chain_state(part)

		match role:
			"base", "neck":
				part["key"] = _key(12)
			"core":
				part["key"] = _key(151)
				part["hit"] = "0xbd46"
			"mouth":
				_set_anim(part, _anim([159, 160, 161, 160], 2))
				part["direction"] = 4
				part["hit"] = "0xbd46"
			"root", "tail":
				part["key"] = _key(74)
			"tip":
				_set_anim(part, _anim([75, 76, 77, 78, 79, 80, 79, 78, 77, 76], 1))
				part["hit"] = "0xbcab"
			"pod":
				_set_anim(part, _anim([191, 192], 4))
				part["hit"] = "0xbcd3"

		part["box"] = main._box_of(part["key"], part["x"], part["y"])
		middle.append(part)
		main.enemies.append(part)

	middle_left = 5


func _update_middle(part: Dictionary) -> void:
	var index := middle.find(part)
	var prev: Dictionary = middle[index - 1] if index > 0 else {}

	match part["role"]:
		"base":
			_update_base(part)
		"neck":
			_chain_step(part, prev)
			part["key"] = _key(NECK_FRAMES[(((part["heading"] >> 16) + 0x10) >> 5) & 3])
		"core":

			# code 0xbf28 : the back limit at least 0x9b0, the frame towards the ship

			if main.scroll_max < 0x9b0:
				main.scroll_max = 0x9b0

			_chain_step(part, prev)
			var d := clampi(main._direction(main.ship_x - part["x"], main.ship_y - part["y"]), 2, 6)
			part["direction"] = d
			part["key"] = _key(CORE_FRAMES[d])
		"mouth":

			# code 0xbf71 : on the core, its animation by the core's way, shots that way

			_step(part)
			part["x"] = prev["x"]
			part["y"] = prev["y"]

			if prev["direction"] != part["direction"]:
				part["direction"] = prev["direction"]
				_set_anim(part, _anim(MOUTH_FRAMES[part["direction"]], 2))

			if _carry(part, "fire_counter", 0xa):
				var d: int = part["direction"]
				var offset: Vector2i = MOUTH_SHOT[d]
				_bullet(part["x"] + offset.x, part["y"] + offset.y, d, _anim(SHOT_ANIM, 1), 6)
		"root":

			# code 0xbff4 : 12 steps, swaying

			part["y"] += main.scroll_applied
			part["steps"] = 0xc
			_wave(part)
		"tail":
			_chain_step(part, prev)
		"tip":

			# code 0xc067 : a ring of 8 shots on the carry of 10 a frame

			_step(part)
			_chain_step(part, prev)

			if _carry(part, "fire_counter", 0xa):
				for d in range(7, -1, -1):
					_bullet(part["x"], part["y"], d, _anim(SHOT_ANIM, 1), 6)
		"pod":

			# code 0xc0be : turns to the ship, a shot at it (S4 111, speed 7) on the carry
			# of 4 a frame ; its box 8 taller each way

			part["y"] += main.scroll_applied
			_step(part)
			var d: int = main._direction(main.ship_x - part["x"], main.ship_y - part["y"])

			if d != part["direction"]:
				part["direction"] = d
				_set_anim(part, _anim(POD_FRAMES[d], 4))

			if _carry(part, "fire_counter", 4):
				main._enemy_bullet(part["x"], part["y"], d, _key(111), 7)

			var box: Array = main._box_of(part["key"], part["x"], part["y"])
			part["box"] = [box[0], box[1] - 8, box[2], box[3] + 8]
			return

	part["box"] = main._box_of(part["key"], part["x"], part["y"])


func _update_base(base: Dictionary) -> void:

	# code 0xbdd5 : turned to the ship (2 to 6) while idle ; by 7 in 256 a frame it lunges,
	# the neck going out 2 to 0x18 steps and back, curling

	base["y"] += main.scroll_applied

	if base["lunge"] == 0:
		var d := clampi(main._direction(main.ship_x - base["x"], main.ship_y - base["y"]), 2, 6)
		base["heading"] = ((d * 32 - 0x40) & 0xff) << 16
		base["rate"] = 0
		base["accel"] = 0

		if main._random() & 0xff >= 7:
			base["key"] = _key(NECK_FRAMES[(((base["heading"] >> 16) + 0x10) >> 5) & 3])
			base["box"] = main._box_of(base["key"], base["x"], base["y"])
			return

		base["lunge_step"] = 2
		var h := (d * 32 - 0x60) & 0xff
		var rate: int = ((main._random() & 0x1f) + 0x20) * 0x400

		if h < 0x20 or h >= 0xa0:
			h = (h + 0x40) & 0xff
			rate = ~rate

		base["heading"] = h << 16
		base["rate"] = rate

	base["lunge"] += base["lunge_step"]

	if base["lunge"] >= 0x18:
		base["lunge_step"] = -base["lunge_step"]

	base["steps"] = base["lunge"] + 4
	base["key"] = _key(NECK_FRAMES[(((base["heading"] >> 16) + 0x10) >> 5) & 3])
	base["box"] = main._box_of(base["key"], base["x"], base["y"])


func _tip_hit(tip: Dictionary, damage: int) -> void:

	# code 0xbcab : a flash ; dead, one part less, the scroll goes back, the tail (tip to
	# root) killed, 100 points each

	tip["flash"] = true
	tip["energy"] -= damage

	if tip["energy"] > 0:
		return

	middle_left -= 1
	main.scroll_base = -1
	var index := middle.find(tip)

	for i in range(index, index - 10, -1):
		var part: Dictionary = middle[i]

		if not part["dead"]:
			part["score"] = 100
			main._kill_enemy(part)


func _pod_hit(pod: Dictionary, damage: int, projectile: Dictionary) -> void:

	# code 0xbcd3 : a shot on its top or bottom edge line is stopped (0x3a99) ; else a flash
	# and the damage, dead 300 points and one part less

	if not projectile.is_empty() and projectile.has("box"):
		var b: Array = pod["box"]
		var shot: Array = projectile["box"]

		if main._overlap(shot, [b[0], b[3], b[2], b[3]]) or main._overlap(shot, [b[0], b[1], b[2], b[1]]):
			projectile["dead"] = true
			return

	pod["flash"] = true
	pod["energy"] -= damage

	if pod["energy"] > 0:
		return

	middle_left -= 1
	pod["score"] = 300
	main._kill_enemy(pod)


func _core_hit(part: Dictionary, damage: int) -> void:

	# code 0xbd43, 0xbd46 : nothing until the tip and the pods are dead, then core and mouth
	# flash and the core takes the damage. Dead : every enemy gone, 40 explosions, 5 pairs
	# of bonuses, its map rows cleared, the stop let go, 2000 points, the scroll at 0x8a0.
	# unconfirmed : the rows are cleared through es, taken as the map (ds:0x1658, rows 143 on)

	if middle_left != 0:
		return

	var core: Dictionary = middle[4]
	core["flash"] = true
	middle[5]["flash"] = true
	core["energy"] -= damage

	if core["energy"] > 0:
		return

	for enemy in main.enemies:
		enemy["dead"] = true

	main.enemies.clear()
	main._explosions(0, 0, 0x140, 0xc0, main.LARGE_EXPLOSION, 40)
	main._bonus_pairs(5)

	for i in range(0x1658 >> 1, (0x1658 >> 1) + 0x140):
		if i < main.map_words.size():
			main.map_words[i] = 0

	main.scroll_min = 0
	main.score += 2000
	main.scroll_base = 1
	main.scroll = 0x8a0
	main.scroll_max = 0x8a0


# ---------------------------------------------------------------- the end guardian

const BOB := [2, 4, 6, 4, 2, 0, 0, 0, -2, -4, -6, -4, -2, 0, 0, 0]
const HEAD_CLOSED := [[-341, -342, -343, -344, -345, -346], [-359, 360, 361, 362, 363, -364],
	[-377, 378, 379, 380, 381, -382], [-395, 396, 397, 398, 399, -400], [0, -413, -414, -415, -416, 0]]
const HEAD_OPEN := [[-341, -342, -343, -344, -345, -346], [-359, 360, 361, 362, 363, -364],
	[-377, 378, 379, 380, 381, -382], [-395, 396, 397, 398, 399, -400], [0, -271, 272, 273, -274, 0],
	[0, 0, -291, -292, 0, 0]]
const GUN_LEFT := {3: [417, 418, 429, 430], 4: [383, 384, 401, 402], 5: [347, 348, 365, 366], 6: [309, 310, 329, 330], -1: [441, 442, 453, 454]}
const GUN_RIGHT := {2: [311, 312, 331, 332], 3: [349, 350, 367, 368], 4: [385, 386, 403, 404], 5: [419, 420, 431, 432], -1: [443, 444, 455, 456]}
const GUN_WAY_LEFT := [6, 3, 3, 3, 4, 5, 6, 6]
const GUN_WAY_RIGHT := [2, 2, 2, 3, 4, 5, 5, 5]
const GUN_SHOT := {2: [187, 188], 3: [183, 184], 4: [185, 186], 5: [189, 190], 6: [187, 188]}
const GUN_DX := [0, 6, 8, 6, 0, -6, -39, -6]
const GUN_DY := [-8, -6, 0, 6, 8, 6, 0, -6]

var end_parts: Array = []


func _spawn_end() -> void:

	# code 0xbc00 : once ; 19 parts (type 0x50) at the end of the enemies list : the head,
	# two guns, a tongue of 16

	if end_made:
		return

	end_made = true
	end_parts = []
	var specs := [["head", 0xa0, 0, 100], ["gun", 0x70, 0x20, 50], ["gun", 0xb0, 0x20, 50], ["root", 0xa0, 0x58, 0]]

	for i in 14:
		specs.append(["tongue", 0xa0, 0x58, 0])

	specs.append(["tongue_tip", 0xa0, 0x58, 0])

	for entry in specs:
		var role: String = entry[0]
		var part := _object("l4_end", {
			"role": role,
			"x": entry[1],
			"y": entry[2] - main.scroll,
			"energy": entry[3],
			"large": true,
			"type50": true,
			"heading": 0,
			"timer": 0,
			"direction": 4,
			"alive": true,
			"hit": {"head": "0xb8f8", "gun": "0xb930"}.get(role, "0x3a99"),
			"key": _key(101 if role == "tongue_tip" else 102),
		})
		_chain_state(part)
		end_parts.append(part)
		main.enemies.append(part)

	guns_left = 2


func _update_end(part: Dictionary) -> void:
	var index := end_parts.find(part)
	var head: Dictionary = end_parts[0]

	match part["role"]:
		"head":

			# code 0xba27 : the back limit at least 0x10, the bob, the box only once both
			# guns are dead, the mouth open 127 frames on the carry of 10 a frame

			if main.scroll_max < 0x10:
				main.scroll_max = 0x10

			bob = main.scroll_applied + BOB[main.frame_count & 15]
			part["y"] += bob

			if guns_left != 0:
				part["box"] = [1000, 0, 1000, 0]
			else:
				part["box"] = [0x94, part["y"] + 0x20, 0xac, part["y"] + 0x28]

			if part["timer"] == 0:
				if _carry(part, "fire_counter", 0xa):
					main.sound_priority = 1

					# Amiga level 4 code $55cec : $f on $418

					main.amiga_1 = 0xf
					part["timer"] = 1
			else:
				part["timer"] += 1

				if part["timer"] == 0x78:
					main.sound_priority = 1

					# Amiga level 4 code $55d00 : $f on $418

					main.amiga_1 = 0xf
				elif part["timer"] == 0x80:
					part["timer"] = 0
		"gun":

			# code 0xbad0 : aims (within its side's ways), a shot on the carry of 6 a frame,
			# speed 6, from a little off its middle (the left way's -39 as in the data)

			part["y"] += bob
			var x: int = part["x"]
			var y: int = part["y"]
			part["box"] = [x + 6, y + 6, x + 0x1a, y + 0x1a]

			if not part["alive"]:
				return

			var raw: int = main._direction(main.ship_x - x - 0x10, main.ship_y - y - 0x10)
			var d: int = (GUN_WAY_LEFT if x < 0xa0 else GUN_WAY_RIGHT)[raw]
			part["direction"] = d

			if _carry(part, "fire_counter", 6):
				_bullet(x + 0x10 + GUN_DX[d], y + 0x10 + GUN_DY[d], d, _anim(GUN_SHOT[d], 1), 6)
		"root":

			# code 0xbb77 : sways down, its reach from the mouth's timer

			part["y"] += bob
			_wave(part)
			part["heading"] ^= 0x80 << 16
			var t: int = head["timer"]
			part["steps"] = mini(mini(t, 0x80 - t), 8)
			part["box"] = main._box_of(part["key"], part["x"], part["y"]) if part["steps"] != 0 else [1000, 0, 1000, 0]
		_:
			var prev: Dictionary = end_parts[index - 1]
			_chain_step(part, prev)
			part["box"] = main._box_of(part["key"], part["x"], part["y"]) if part["steps"] != 0 else [1000, 0, 1000, 0]


func _head_hit(head: Dictionary, damage: int) -> void:

	# code 0xb8f8 : a flash ; dead, every enemy freed, 10 pairs of bonuses, 20 explosions
	# about it, the level done. No score.

	head["flash"] = true
	head["energy"] -= damage

	if head["energy"] > 0:
		return

	var y: int = head["y"]

	for enemy in main.enemies:
		enemy["dead"] = true

	main.enemies.clear()
	main._bonus_pairs(10)
	main._explosions(0x70, y, 0x60, 0x50, main.LARGE_EXPLOSION, 20)
	main.level_done = true


func _gun_end_hit(gun: Dictionary, damage: int) -> void:

	# code 0xb930 : a flash ; dead, one gun less, an explosion (its y less the scroll once
	# more, as coded), its dead tiles, no more hits

	gun["flash"] = true
	gun["energy"] -= damage

	if gun["energy"] > 0:
		return

	guns_left -= 1
	main._explode_at(gun["x"] + 0x10, gun["y"] - main.scroll + 0x20, main.LARGE_EXPLOSION)
	gun["alive"] = false
	gun["direction"] = -1
	gun["hit"] = "none"


# ---------------------------------------------------------------- dispatch from main

func update_enemy(enemy: Dictionary) -> void:
	match enemy["kind"]:
		"l4_pod":
			_update_pod(enemy)
		"l4_swimmer":
			_update_swimmer(enemy)
		"l4_gun":
			_update_gun(enemy)
		"l4_lunge":
			_update_lunge(enemy)
		"l4_middle":
			_update_middle(enemy)
		"l4_end":
			_update_end(enemy)


func update_effect(item: Dictionary) -> void:
	if item["kind"] == "l4_capsule":
		_update_capsule(item)


func hit(enemy: Dictionary, damage: int, projectile: Dictionary) -> void:
	match enemy["hit"]:
		"0xc6e5":
			_gun_hit(enemy, damage)
		"0xc4d8":
			_lunge_hit(enemy, damage)
		"0xbcab":
			_tip_hit(enemy, damage)
		"0xbcd3":
			_pod_hit(enemy, damage, projectile)
		"0xbd46":
			_core_hit(enemy, damage)
		"0xb8f8":
			_head_hit(enemy, damage)
		"0xb930":
			_gun_end_hit(enemy, damage)


func draw_enemy(enemy: Dictionary) -> void:
	match enemy["kind"]:
		"l4_gun":

			# code 0xc746 : the flash of its first tiles

			if enemy["flash"]:
				var t: Array = enemy["tiles"][0]
				main._draw_grid([[-t[0], -t[1]], [-t[2], -t[3]]], enemy["x"], enemy["world_y"] - main.scroll, true)
		"l4_lunge":

			# code 0xc575 : the sprite, under the wall's tiles while it is still in it

			var sy: int = enemy["world_y"] - main.scroll

			if sy <= 0xdc:
				main._draw_sprite(enemy["key"], enemy["x"], sy, enemy["flash"])

				if enemy["state"] < 2:
					var cover: Vector2i = enemy["cover"]
					var tiles: Array = LUNGE_COVER[0 if enemy["side"] == 0 else 1]
					main._draw_grid([[-tiles[0]], [-tiles[1]], [-tiles[2]]], cover.x, cover.y - main.scroll, false)
		"l4_end":
			_draw_end(enemy)
		_:
			main._draw_sprite(enemy["key"], enemy["x"], enemy["y"], enemy["flash"])

	enemy["flash"] = false


func _draw_end(part: Dictionary) -> void:
	match part["role"]:
		"head":

			# code 0xb968, 0xb98b

			main._draw_grid(HEAD_OPEN if part["timer"] != 0 else HEAD_CLOSED, 0x70, part["y"], part["flash"])
		"gun":

			# code 0xb9e3

			var t: Array = (GUN_LEFT if part["x"] < 0xa0 else GUN_RIGHT).get(part["direction"], GUN_LEFT[4])
			main._draw_grid([[-t[0], -t[1]], [-t[2], -t[3]]], part["x"], part["y"], part["flash"])
		_:

			# code 0xba0e : the tongue only while it reaches out

			if part["steps"] != 0:
				main._draw_sprite(part["key"], part["x"], part["y"], false)


func draw_effect(item: Dictionary) -> void:
	main._draw_sprite(item["key"], item["x"], item["y"], false)
