class_name Level2
extends RefCounted

# Level 2 of XENON2.EXE, the routines the level's tables point to (load module offsets) :
# init 0x8e01, hook 0x7f32, wall objects 0x7f79 (table cs:0x90fd), the arena of three
# targets and the snakes from its holes, the guardian at the end and what it spawns. The
# blocks any shot breaks (0x8ca7, 0x8d18, 0x8d5f) are in main.gd (_block_hit, _block_rebuild).
# "code" marks behaviour ported from the code, "unconfirmed" a detail left open there.
#
# Lists : wall objects of types 2, 4 and 5 go on the list ds:0x90ec, which is updated after
# the effects and never tested for hits (tile_objects here). The rest are on main's enemies
# and effects lists.

var main: Node

# ds:0x9230 the arena done, ds:0x9200 targets left, ds:0x9202 bits of the sides whose snake
# head lives, ds:0x922d / 0x922e a snake of that side was updated since the last hook,
# ds:0x922f spawns still taken from the lower slots, ds:0x91f4 / 0x91f6 the slot patterns,
# ds:0x91d4.. the hole counters (1 to 8)

var arena_done := false
var targets_left := 3
var head_bits := 0
var side_seen := [false, false]
var lower_left := 2
var side_patterns := [0x45d2, 0xaa6a]
var holes := [0, 0, 0, 0, 0, 0, 0, 0, 0]
var tile_objects: Array = []
var guardian: Dictionary = {}

const HITS := ["0x3b55", "0x80f5", "0x8114", "0x8745", "0x87d5", "none"]

# ---------------------------------------------------------------- tables

# cs:0x9179 : snake slots (x, world y, entry hole, exit hole, path 0x42 + k), even records
# for side 0, odd for side 1. Records 8 to 15 repeat the last pair.

const SNAKE_SLOTS := [
	[88, 2920, 3, 5, 0], [216, 2920, 6, 4, 19], [88, 2920, 3, 6, 1], [216, 2920, 6, 3, 18],
	[104, 2952, 4, 5, 2], [200, 2952, 5, 4, 17], [104, 2952, 4, 6, 3], [200, 2952, 5, 3, 16],
	[88, 2664, 1, 8, 4], [216, 2664, 8, 1, 10], [88, 2664, 1, 8, 4], [216, 2664, 8, 1, 10],
	[88, 2664, 1, 8, 4], [216, 2664, 8, 1, 10], [88, 2664, 1, 8, 4], [216, 2664, 8, 1, 10],
]

# cs:0x952b, 0x953b : snake frames by heading octant (0 right, clockwise)

const HEAD_FRAMES := [38, 37, 36, 43, 42, 41, 40, 39]
const BODY_FRAMES := [54, 55, 52, 53, 54, 55, 52, 53]

# cs:0x786c, 0x7892 : the snake debris, 2 ticks a frame

const HEAD_DEBRIS := [40, 39, 38, 37, 36, 43, 42, 41]
const BODY_DEBRIS := [52, 53, 54, 55, 52, 53, 54, 55]

# cs:0x9219 : the holes (map word index, set A, set B), 2x2 tiles, all masked (bit 0)

const HOLE_CELLS := [0, 3305, 3445, 3625, 3666, 3671, 3632, 3452, 3312]
const HOLE_LEFT := [[239, 240, 249, 250], [241, 242, 251, 252]]
const HOLE_RIGHT := [[243, 244, 253, 254], [245, 246, 255, 256]]

# ds:0x33b0 : the targets (column, row in tiles), index 2, 1, 0 in creation order

const TARGETS := [[9, 0xb8, 2], [4, 0xa4, 1], [0xe, 0xa4, 0]]

# cs:0x92dd : the target's tile by phase (369 to 373, masked), cs:0x92bf, 0x92b3, 0x92cb : its
# flash grids by index (origin offset in pixels from its cell)

const TARGET_TILES := [369, 370, 371, 372, 373]
const TARGET_FLASH := [
	[[-32, -16], [[-392, -393, -394], [0, 0, -369]]],
	[[0, -16], [[-389, -390, -391], [-369, 0, 0]]],
	[[-16, -32], [[0, 85, 0], [0, 86, 0], [-53, -369, -54]]],
]

# cs:0x92e7 : the guardian's body, 6 x 9 tiles at x 112

const GUARDIAN_BODY := [
	[0, -208, 0, 0, -233, 0],
	[0, -232, 0, 0, -234, 0],
	[-115, -116, -117, -118, -119, -120],
	[-135, -136, 137, 138, -139, -140],
	[-155, -156, 157, 158, 159, -160],
	[-175, -176, 177, 178, 179, -180],
	[-195, -196, -197, -198, -199, -200],
	[-215, -216, -217, -218, -219, -220],
	[-235, -236, 0, 0, -237, -238],
]

# cs:0x94f3 : the hatch at rows 6-7, columns 2-3 (sets 0x9373, 0x937b, 0x9383, 0x937b);
# cs:0x94fb, 0x94ff : the legs at rows 7-8, columns 0-1 and 4-5, by frame & 1

const HATCH_SETS := [[-197, -198, -217, -218], [-311, -312, -323, -324], [-313, -314, -325, -326], [-311, -312, -323, -324]]
const LEFT_LEGS := [[-215, -216, -235, -236], [-315, -316, -327, -328]]
const RIGHT_LEGS := [[-219, -220, -237, -238], [-317, -318, -329, -330]]

# cs:0x7a80, 0x7a92 : the guardian's bullets, a tick a frame

const GUARDIAN_SHOT := [122, 123, 124]
const GUARDIAN_RING := [125, 126, 127, 128]

# code 0x1f0d, 0x1f2d : bullet steps, 16 directions (0 to 7 every 45 degrees, 8 to 15 the
# ones between), 2.14 fixed point

const DX16 := [0, 0x2d41, 0x4000, 0x2d41, 0, -0x2d41, -0x4000, -0x2d41,
	0x187d, 0x3b20, 0x3b20, 0x187d, -0x187d, -0x3b20, -0x3b20, -0x187d]
const DY16 := [-0x4000, -0x2d41, 0, 0x2d41, 0x4000, 0x2d41, 0, -0x2d41,
	-0x3b20, -0x187d, 0x187d, 0x3b20, 0x3b20, 0x187d, -0x187d, -0x3b20]

# ds:0x32de / 0x32ee and ds:0x32fe / 0x330e : steps by direction (0 up, clockwise)

const STEP_4 := [Vector2i(0, -4), Vector2i(3, -3), Vector2i(4, 0), Vector2i(3, 3),
	Vector2i(0, 4), Vector2i(-3, 3), Vector2i(-4, 0), Vector2i(-3, -3)]
const STEP_1 := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

# cs:0x78de, 0x78f4 : the hatchling ; cs:0x950b : the crawler by direction

const HATCHLING := [56, 57, 58, 57]
const HATCHLING_OPEN := [57, 59, 60, 61, 62, 63, 63, 64]
const CRAWLER := [[71, 72], [69, 70], [67, 68], [65, 66], [63, 64], [77, 78], [75, 76], [73, 74]]

# ds:0x331e : crawler waypoints (x, world y, three directions)

const WAYPOINTS := [[52, 44, 3, 3, 3], [268, 44, 5, 5, 5], [116, 108, 7, 2, 4], [204, 108, 6, 1, 4],
	[116, 340, 0, 2, 5], [204, 340, 0, 6, 3], [36, 420, 1, 1, 1], [284, 420, 7, 7, 7]]

# wall type 1 (0x7f82) : tiles by state, side 0 (type 0xec, cs:0x90df) and side 1 (0xe8,
# cs:0x90c1), death tiles cs:0x90bf, 0x90bd

const GUN_TILES := [
	[359, 360, 361, 362, 363, 364, 365, 366, 365, 364, 363, 362, 361, 360, 359],
	[351, 352, 353, 354, 355, 356, 357, 358, 357, 356, 355, 354, 353, 352, 351],
]
const GUN_DEATH := [368, 367]

# wall type 2 (0x7fdb) : quads by state, side 0 (0xf4) and side 1 (0xf0). States 1 to 18 go
# A B B B A C C C A B B B A C C C A B, 19 and 20 the last two, C is the first.

const NEST_ORDER := [0, 1, 1, 1, 0, 2, 2, 2, 0, 1, 1, 1, 0, 2, 2, 2, 0, 1, 3, 4]
const NEST_QUADS := [
	[[269, 270, 287, 288], [271, 272, 289, 290], [267, 268, 285, 286], [273, 274, 291, 292], [275, 276, 293, 294]],
	[[259, 260, 277, 278], [261, 262, 279, 280], [247, 248, 257, 258], [263, 264, 281, 282], [265, 266, 283, 284]],
]

# cs:0x8fe9 : the burst (offset, frames), ds:0x3390 / 0x33a0 its moves by index

const BURST := [[Vector2i(0, -4), 12], [Vector2i(3, -3), 15], [Vector2i(4, 0), 18], [Vector2i(3, 3), 21],
	[Vector2i(0, 4), 24], [Vector2i(-3, 3), 27], [Vector2i(-4, 0), 30], [Vector2i(-4, -3), 33]]
const BURST_DX := [-4, -5, -4, 0, 4, 5, 4, 0]
const BURST_DY := [-4, 0, 4, 5, 4, 0, -4, -5]

# wall type 3 (0x8018) : side 0 (0x104) and side 1 (0x100), cs:0x7a2c, 0x7a56, opening
# cs:0x7a4a, 0x7a74

const POD_FRAMES := [[118, 119, 120, 121, 120, 119], [114, 115, 116, 117, 116, 115]]
const POD_OPEN := [[[95, 2], [96, 1], [97, 0]], [[101, 2], [100, 1], [99, 0]]]

# wall types 4 (0x80a3, cs:0x8fd7) and 5 (0x80bb, cs:0x8f8f) : tiles by state, flags 0 (the
# last of type 4 with bit 0)

const HATCH_ONE := [166, 166, 382, 383, 384, 385, 386, 387, 388]
const HATCH_FOUR := [[295, 296, 301, 302], [297, 298, 303, 304], [299, 300, 305, 306],
	[307, 308, 319, 320], [309, 310, 321, 322], [331, 332, 341, 342], [333, 334, 343, 344],
	[335, 336, 345, 346], [337, 338, 347, 348]]

# ds:0x32ce : the divers' wobble

const WOBBLE := [0, -2, -4, -2, 0, 2, 4, 2]


func _init(owner: Node) -> void:
	main = owner


func _key(frame: int) -> String:
	return "S2/%03d" % frame


func _frames(list: Array, ticks: int) -> Array:
	var out: Array = []

	for frame in list:
		out.append([_key(frame), ticks])

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
		"hit": "0x3aa7",
	}
	object.merge(fields, true)
	return object


# ---------------------------------------------------------------- init 0x8e01

func init() -> void:

	# code 0x8e1e : the guardian (type 0x50), world y 0x60, energy 75 (cs:0x772c), dormant
	# (+0x1a = -1). It stays on the list across restarts (+0x4a, +0x4b).

	guardian = _object("l2_guardian", {
		"world_y": 0x60,
		"energy": 75,
		"hit": "0x8745",
		"type50": true,
		"wait": -1,
		"moving": 0,
		"velocity": 0,
		"spawn": 0,
		"phase": 0,
		"fire_counter": 0,
		"body": GUARDIAN_BODY.duplicate(true),
		"stays": true,
	})
	main.enemies.append(guardian)

	# test option : --scroll past the arena starts with it done (the targets not made)

	if main.scroll < 0x9e0:
		arena_done = true
		targets_left = 0
		main.scroll_min = 0
		return

	# code 0x8e6c : the three targets (type 0x54), energy 12 (cs:0x772e)

	for t in TARGETS:
		main.enemies.append(_object("l2_target", {
			"column": t[0],
			"row": t[1],
			"index": t[2],
			"cell": t[1] * 20 + t[0],
			"energy": 12,
			"hit": "0x87d5",
			"phase": 0,
			"stays": true,
		}))


# ---------------------------------------------------------------- hook 0x7f32

func hook() -> void:

	# code 0x7f32 : snakes while the arena is on and the scroll is 0x9d0 to 0xb50 (0x818c),
	# after it the scroll held at 0x9f0 at most. The side flags are cleared every frame.

	if not arena_done:
		if main.scroll >= 0x9d0 and main.scroll <= 0xb50:
			for side in 2:
				if not side_seen[side]:
					_spawn_snake(side)
	elif main.scroll > 0x9f0:
		main.scroll = 0x9f0
		main.scroll_max = 0x9f0

	side_seen = [false, false]


func _side_pattern(side: int) -> int:

	# code 0x81be : the side's word turned right by 5

	var v: int = side_patterns[side]
	v = ((v >> 5) | (v << 11)) & 0xffff
	side_patterns[side] = v
	return v


func _spawn_snake(side: int) -> void:

	# code 0x81e7 : the slot

	var r := _side_pattern(side)
	var index := r & 6

	if targets_left != 1:
		if lower_left == 0:
			index += 8
		else:
			lower_left -= 1

	var slot: Array = SNAKE_SLOTS[index + side]
	var x: int = slot[0]
	var y: int = slot[1] - main.scroll_asked - main.scroll
	var path: Dictionary = main.paths[0x42 + slot[4]]

	# code 0x8240 : the entry hole opens

	if holes[slot[2]] == 0:
		holes[slot[2]] = 0x18

	# code 0x8250 : a head (type 0x114, 250) and 11 bodies (0x118, 50), energy 2
	# (cs:0x7720), speed 8 (cs:0x7722), each 10 steps later than the one before. They
	# start hidden. unconfirmed : their fire rate (+0x49) is left from the record's last
	# owner ; they do not fire here.

	for i in 12:
		var head := i == 0
		main.enemies.push_front(_object("l2_snake", {
			"head_part": head,
			"side": side,
			"exit": slot[3],
			"path": path,
			"steps": -10 * i,
			"speed": 8,
			"origin": Vector2i(x, y),
			"x": x,
			"y": y,
			"heading": 0,
			"energy": 2,
			"score": 250 if head else 50,
			"hit": "0x80f5" if head else "0x8114",
			"key": _key(36 if head else 52),
			"shown": false,
		}))

	head_bits |= 1 << side


func _update_snake(snake: Dictionary) -> void:

	# code 0x866d : moves with the scroll, marks its side, follows its path (0x480e)

	var origin: Vector2i = snake["origin"]
	origin.y += main.scroll_applied
	snake["origin"] = origin
	side_seen[snake["side"]] = true

	var path: Dictionary = snake["path"]
	var points: Array = path["points"]
	var total := points.size()
	var ended: bool = snake["steps"] >= total

	if not ended:
		snake["steps"] += snake["speed"]
		ended = snake["steps"] > total

	if ended:

		# the path's end removes it, the exit hole opens

		snake["dead"] = true

		if holes[snake["exit"]] == 0:
			holes[snake["exit"]] = 0x18

		return

	var steps: int = snake["steps"]
	var start: Vector2i = path["start"]
	var point: Vector2i = start if steps <= 0 else points[steps - 1]
	snake["x"] = origin.x + point.x - start.x
	snake["y"] = origin.y + point.y - start.y

	if steps > 0:
		snake["heading"] = path["angles"][steps - 1]

	# code 0x86d7 : hidden while waiting, under the map tiles (0x897) while in its first
	# command and at the end, else drawn. unconfirmed : 0x897 repaints the 2x2 map tiles
	# over the sprite, taken as not drawn.

	snake["shown"] = steps > 0 and steps > int(path["first"]) and steps < total
	var octant: int = ((int(snake["heading"]) + 0x10) >> 5) & 7
	snake["key"] = _key((HEAD_FRAMES if snake["head_part"] else BODY_FRAMES)[octant])
	snake["box"] = main._box_of(snake["key"], snake["x"], snake["y"])


func _snake_hit(snake: Dictionary, damage: int) -> void:

	# code 0x80f5 (head), 0x8114 (body) : a flash, the damage (0x3aa7) while below the
	# energy, else it breaks into debris, no score, no explosion. The head clears its side's
	# bit.

	snake["flash"] = true

	if damage < snake["energy"]:
		snake["energy"] -= damage
		return

	if snake["head_part"]:
		head_bits &= ~(1 << snake["side"])

	# code 0x8136 : debris on the effects list, a random flight angle

	var list := HEAD_DEBRIS if snake["head_part"] else BODY_DEBRIS
	var debris := {
		"kind": "l2_debris",
		"x": snake["x"],
		"y": snake["y"],
		"frames": _frames(list, 2),
		"anim": 0,
		"count": 2,
		"angle": main._random() & 0xff,
		"dead": false,
		"box": [1000, 0, 1000, 0],
	}
	debris["key"] = debris["frames"][0][0]
	main.effects.push_front(debris)
	snake["dead"] = true


func _update_debris(debris: Dictionary) -> void:

	# code 0x866d (+0x1a = 0x8000) : flies by the sine table / 4, gone off the screen

	main._step_animation(debris, debris["frames"], 0)
	debris["key"] = debris["frames"][debris["anim"]][0]
	var a: int = debris["angle"]
	var y: int = debris["y"] + (int(main.sine[a]) >> 2)

	if y < 0 or y >= 0xc0:
		debris["dead"] = true
		return

	var x: int = debris["x"] + (int(main.sine[a + 64]) >> 2)

	if x < 0 or x >= 0x140:
		debris["dead"] = true
		return

	debris["x"] = x
	debris["y"] = y


func update_holes() -> void:

	# code 0x895f (by the bottom target) : each counter that runs counts down and its hole
	# shows set A or B by bit 1

	for k in range(1, 9):
		if holes[k] == 0:
			continue

		holes[k] -= 1
		var sets := HOLE_LEFT if k <= 4 else HOLE_RIGHT
		main._write_tiles(HOLE_CELLS[k], sets[1 if holes[k] & 2 else 0], 4)


# ---------------------------------------------------------------- the targets

func _update_target(target: Dictionary) -> void:

	# code 0x88a9

	if main.scroll_base < 0 and main.scroll_max <= 0xb40:
		main.scroll_max = 0xb40

	var index: int = target["index"]
	var active := false

	if index == 2:
		active = targets_left == 1
	elif head_bits != 3:
		active = (main.ship_x < 0xa0) if index == 1 else (main.ship_x >= 0xa0)

	if active:
		var x: int = target["column"] * 16
		var y: int = target["row"] * 16 - main.scroll
		target["box"] = [x, y, x + 15, y + 15]
	else:
		target["box"] = [1000, 0, 1000, 0]

	# code 0x8924 : the phase moves on even frames, held at 4 while open

	var hold: bool = active and head_bits != 3 and target["phase"] == 4

	if main.frame_count & 1 == 0 and not hold:
		target["phase"] = (target["phase"] + 1) & 7

	var p: int = target["phase"]
	main.map_words[target["cell"]] = (TARGET_TILES[p if p <= 4 else 8 - p] << 6) | 1

	if index == 2:
		update_holes()


func _target_hit(target: Dictionary, damage: int) -> void:

	# code 0x87d5 : nothing while both snake heads live (ds:0x9202 = 3), else a flash
	# and the damage

	if head_bits == 3:
		return

	target["flash"] = true
	target["energy"] -= damage

	if target["energy"] > 0:
		return

	# code 0x87ec : the other targets shut until both heads are killed again, the target's
	# tile 395, a small explosion, removed, no score

	head_bits = 3
	main.map_words[target["cell"]] = (395 << 6) | 1
	var box: Array = target["box"]
	main._explode_at(box[0] + 8, box[1] + 8, main.SMALL_EXPLOSION)
	target["dead"] = true
	targets_left -= 1

	if targets_left == 1:

		# code 0x8820 : the scroll goes back, the slot patterns start again

		main.scroll_base = -1
		side_patterns = [0xd251, 0x894d]
	elif targets_left == 0:

		# code 0x8839 : the arena is cleared from the map, every enemy but the guardian
		# takes 0x7f, the waves forgotten, 40 large explosions, 5 pairs of bonuses, the way
		# on is open

		main.scroll_base = 1

		for i in range(0x1950 >> 1, (0x1950 >> 1) + 0x1cc):
			main.map_words[i] = 0

		for enemy in main.enemies.duplicate():
			if enemy.get("kind", "") != "l2_guardian" and enemy["head"] == null:
				main._hit_enemy(enemy, 0x7f)

		side_seen = [false, false]

		for slot in main.groups:
			slot[0] = 0
			slot[1] = 0

		main._explosions(0, 0, 320, 192, main.LARGE_EXPLOSION, 40)
		main._bonus_pairs(5)
		main.scroll_min = 0
		arena_done = true


func _draw_target(target: Dictionary) -> void:

	# code 0x8783 : no sprite, the hit flash over its frame

	if not target["flash"]:
		return

	var flash: Array = TARGET_FLASH[target["index"]]
	var x: int = target["column"] * 16 + flash[0][0]
	var y: int = target["row"] * 16 - main.scroll + flash[0][1]
	main._draw_grid(flash[1], x, y, true)
	target["flash"] = false


# ---------------------------------------------------------------- the guardian

func _update_guardian(g: Dictionary) -> void:

	# code 0x89ae

	if main.scroll_max <= 0x120:
		main.scroll_max = 0x120

	if g["moving"] == 0:
		if g["wait"] < 0:

			# dormant : no box, wakes when the ship is within world y 0xb0

			g["box"] = [1000, 0, 1000, 0]

			if main.ship_y + main.scroll <= 0xb0 and main.ship_x >= 0 and main.ship_x <= 0x13f:
				g["moving"] = 1000
				g["velocity"] = 3
				g["wait"] = 0x154

			return

		g["wait"] -= 1

		if g["wait"] < 0:
			g["spawn"] = 0
			g["moving"] = 1000
			g["velocity"] = -3

	# code 0x8a0f : fire, cs:0x7732 = 10 to the byte counter, on the carry one shot down
	# or a ring of 16, speed 7

	var sy: int = g["world_y"] - main.scroll
	g["fire_counter"] += 10

	if g["fire_counter"] >= 0x100:
		g["fire_counter"] = main._random() & 0x3f

		if main._random() & 3 != 0:
			_guardian_bullet(4, GUARDIAN_SHOT, sy)
		else:
			for d in range(15, -1, -1):
				_guardian_bullet(d, GUARDIAN_RING, sy)

	# code 0x8a8b : the box is the hatch

	g["box"] = [0x98, sy + 0x70, 0xa7, sy + 0x7a]

	if main.scroll >= 0x160:
		return

	var body: Array = g["body"]

	if g["spawn"] != 0:

		# code 0x8ae0 : the hatch opens, then a hatchling

		g["phase"] = (g["phase"] + 2) & 6
		_set_quad(body, 6, 2, HATCH_SETS[g["phase"] >> 1])
		g["spawn"] -= 1

		if g["spawn"] == 0:
			_spawn_hatchling(sy)

		return

	if g["moving"] != 0:

		# code 0x8b81 : effect 0x11 when none plays, the move, the legs

		if main.sound_request == 0:
			main.sound_request = 0x11

		# Amiga level 2 code $56de8 : $3 on $414 while channel 2 has no effect

		if main.amiga_sound.channel_busy(2) == false:
			main.amiga_2 = 3

		g["moving"] -= 1
		g["world_y"] += g["velocity"]

		if g["world_y"] < 0x60:
			g["world_y"] = 0x60
			g["moving"] = 0
		elif g["world_y"] > 0xc0:
			g["world_y"] = 0xc0
			g["moving"] = 0

		var b: int = main.frame_count & 1
		_set_quad(body, 7, 0, LEFT_LEGS[b])
		_set_quad(body, 7, 4, RIGHT_LEGS[b])
		return

	# code 0x8c0d : standing. Under 16 enemies, by chance a spawn in 2 to 9 frames, else
	# a short move. unconfirmed : with 16 or more the move reads the box bottom, not a
	# random number.

	var ax: int = sy + 0x7a

	if main.enemies.size() < 16:
		ax = main._random()

		if ax & 0x2000 == 0:
			g["spawn"] = (ax & 7) + 2
			return

	g["velocity"] = -3 if ax & 0x4000 else 3
	g["moving"] = (ax & 7) + 8


func _set_quad(body: Array, row: int, column: int, words: Array) -> void:
	body[row][column] = words[0]
	body[row][column + 1] = words[1]
	body[row + 1][column] = words[2]
	body[row + 1][column + 1] = words[3]


func _guardian_bullet(direction: int, frames: Array, sy: int) -> void:

	# code 0x1ed3 then the animation set over it : from (0xa0, y + 0x70), speed 7
	# (cs:0x7734). Main's enemy bullets know the 16 directions.

	main._enemy_bullet(0xa0, sy + 0x70, direction, _key(frames[0]), 7)
	var bullet: Dictionary = main.effects[0]
	bullet["frames"] = _frames(frames, 1)
	bullet["anim"] = 0
	bullet["count"] = 1

func _guardian_hit(g: Dictionary, damage: int) -> void:

	# code 0x8745 : a flash, the damage. Dead : removed, 10 pairs of bonuses, 30 large
	# explosions about it, effect 6, every enemy freed, the level done. No score.

	g["flash"] = true
	g["energy"] -= damage

	if g["energy"] > 0:
		return

	g["dead"] = true
	main._bonus_pairs(10)
	main._explosions(0x50, g["world_y"] - main.scroll, 0xa0, 0x70, main.LARGE_EXPLOSION, 30)

	for enemy in main.enemies:
		enemy["dead"] = true

	main.enemies.clear()
	main.level_done = true


func _draw_guardian(g: Dictionary) -> void:

	# code 0x8c3e : while the scroll is under 0x160

	if main.scroll < 0x160:
		main._draw_grid(g["body"], 112, g["world_y"] - main.scroll, g["flash"])

	g["flash"] = false


func _spawn_hatchling(sy: int) -> void:

	# code 0x8b24 : type 0x10c, cannot be hit, from the hatch

	var h := _object("l2_hatchling", {
		"x": 0xa0,
		"y": sy + 0x80,
		"state": 0,
		"direction": main._random() & 7,
		"frames": _frames(HATCHLING, 2),
		"anim": 0,
		"count": 2,
		"hit": "none",
	})
	h["key"] = h["frames"][0][0]
	main.enemies.push_front(h)


func _update_hatchling(h: Dictionary) -> void:

	# code 0x83bd

	main._step_animation(h, h["frames"], 0 if h["state"] != 2 else 6)
	h["key"] = h["frames"][h["anim"]][0]
	h["y"] += main.scroll_applied

	match h["state"]:
		0:
			var step: Vector2i = STEP_4[h["direction"]]
			h["x"] += step.x
			h["y"] += step.y

			if h["x"] <= 0x74:
				h["x"] = 0x74
				h["state"] = 1
				h["direction"] = 4
			elif h["x"] >= 0xcc:
				h["x"] = 0xcc
				h["state"] = 1
				h["direction"] = 0

			var wy: int = h["y"] + main.scroll

			if wy <= 0x6c:
				h["y"] = 0x6c - main.scroll
				h["state"] = 1
				h["direction"] = 6
			elif wy >= 0x154:
				h["y"] = 0x154 - main.scroll
				h["state"] = 1
				h["direction"] = 2
		1:
			if main._random() & 7 == 0:
				h["state"] = 2
				h["frames"] = _frames(HATCHLING_OPEN, 2)
				h["anim"] = 0
				h["count"] = 2
				h["key"] = h["frames"][0][0]
		2:

			# at S2 63 it becomes a crawler going its way

			if h["key"] == _key(63):
				h["dead"] = true
				_spawn_crawler(h["x"], h["y"], h["direction"])


func _spawn_crawler(x: int, y: int, direction: int) -> void:

	# code 0x8475 : type 0x110, energy 2 (cs:0x7724), 30 points, small explosion

	var c := _object("l2_crawler", {
		"x": x,
		"y": y,
		"direction": direction,
		"turning": -1,
		"energy": 2,
		"score": 30,
		"fire_counter": 0,
		"frames": _frames(CRAWLER[direction], 2),
		"anim": 0,
		"count": 2,
	})
	c["key"] = c["frames"][0][0]
	main.enemies.push_front(c)


func _update_crawler(c: Dictionary) -> void:

	# code 0x84e1

	main._step_animation(c, c["frames"], 0)
	c["key"] = c["frames"][c["anim"]][0]
	c["y"] += main.scroll_applied

	if c["turning"] >= 0:

		# turning a step every other frame towards the waypoint's direction

		if main.frame_count & 1 == 0:
			c["box"] = main._box_of(c["key"], c["x"], c["y"])
			return

		var diff: int = (c["turning"] - c["direction"]) & 7

		if diff != 0:
			c["direction"] = (c["direction"] + (-1 if diff > 4 else 1)) & 7
			c["frames"] = _frames(CRAWLER[c["direction"]], 2)
			c["anim"] = 0
			c["count"] = 2
			c["key"] = c["frames"][0][0]
			c["box"] = main._box_of(c["key"], c["x"], c["y"])
			return

		c["turning"] = -1

	# code 0x853d : fire at the ship (cs:0x7726 = 6), S2 94 at speed 8, while on the screen

	if c["y"] >= 0 and c["y"] < 0xc0:
		c["fire_counter"] += 6

		if c["fire_counter"] >= 0x100:
			c["fire_counter"] = main._random() & 0x3f
			var d: int = main._direction(main.ship_x - c["x"], main.ship_y - c["y"])
			main._enemy_bullet(c["x"], c["y"], d, _key(94), 8)

	var step: Vector2i = STEP_1[c["direction"]]
	c["x"] += step.x
	c["y"] += step.y
	var wy: int = c["y"] + main.scroll

	for w in WAYPOINTS:
		if c["x"] == w[0] and wy == w[1]:
			var r := 0

			while r == 0:
				r = main._random() & 3

			c["turning"] = w[1 + r]
			return

	c["box"] = main._box_of(c["key"], c["x"], c["y"])
	main._block_rebuild(c["box"])


# ---------------------------------------------------------------- wall objects 0x7f79

func spawn_wall(wall: Dictionary) -> void:
	var type := int(wall["type"])
	var side := int(wall["side"])
	var x := int(wall["x"]) - 8
	var world_y := int(wall["world_y"]) - 8
	var cell := (world_y >> 4) * 20 + (x >> 4)

	match type:
		1:

			# code 0x7f82 : a wall gun of one tile, energy 4 (cs:0x771c), 100 points

			var tiles: Array = GUN_TILES[0 if side == 0 else 1]
			main.map_words[cell] = (tiles[0] << 6) | 1
			main.enemies.push_front(_object("l2_gun", {
				"side": side,
				"x": x,
				"world_y": world_y,
				"cell": cell,
				"tiles": tiles,
				"first": [tiles[0]],
				"death": [GUN_DEATH[0 if side == 0 else 1]],
				"size": 1,
				"state": 0,
				"energy": 4,
				"score": 100,
				"hit": "0x3b76",
			}))
		2:

			# code 0x7fdb : a nest of 2x2 tiles on the list 0x90ec

			var quads: Array = NEST_QUADS[0 if side == 0 else 1]
			main._write_tiles(cell, quads[2], 4)
			tile_objects.append({"kind": "nest", "x": x, "world_y": world_y, "cell": cell, "quads": quads, "state": 0, "dead": false})
		3:

			# code 0x8018 : a pod going up and down a * 16 rows, 2 energy, 200 points

			var travel := int(wall["a"]) * 16
			var pod := _object("l2_pod", {
				"side": side,
				"x": x,
				"y": world_y - main.scroll,
				"frames": _frames(POD_FRAMES[0 if side == 0 else 1], 2),
				"anim": 0,
				"count": 2,
				"velocity": -1,
				"left": travel,
				"travel": travel,
				"energy": 2,
				"score": 200,
			})
			pod["key"] = pod["frames"][0][0]
			pod["box"] = main._box_of(pod["key"], pod["x"], pod["y"])
			main.enemies.push_front(pod)
		4, 5:

			# code 0x80a3, 0x80bb : hatches on the list 0x90ec

			if type == 4:
				main.map_words[cell] = HATCH_ONE[0] << 6

			tile_objects.append({"kind": "hatch", "type": type, "x": x, "world_y": world_y, "cell": cell, "state": 0, "passes": 1, "dead": false})


func _update_gun(gun: Dictionary) -> void:

	# code 0x7dde

	if gun["world_y"] > main.scroll_max + 0xd0:
		gun["dead"] = true
		return

	var x: int = gun["x"]
	var sy: int = gun["world_y"] - main.scroll
	gun["box"] = [x - 8, sy + 4, x + 12, sy + 12]

	if gun["state"] == 0:
		if main._random() & 0xff < 0x10:
			gun["state"] = 1

		return

	var tiles: Array = gun["tiles"]
	main.map_words[gun["cell"]] = (tiles[gun["state"]] << 6) | 1
	gun["state"] += 1

	if gun["state"] == 7:

		# code 0x7e53 : S2 94 at speed 6, out of the wall

		main._enemy_bullet(x + 8, sy + 8, 2 if gun["side"] == 0 else 6, _key(94), 6)
	elif gun["state"] == 15:
		gun["state"] = 0


func _update_pod(pod: Dictionary) -> void:

	# code 0x7e87

	if pod["y"] > main.scroll_max + 0xd0 - main.scroll:
		pod["dead"] = true
		return

	main._step_animation(pod, pod["frames"], 0)
	pod["key"] = pod["frames"][pod["anim"]][0]
	pod["y"] += main.scroll_applied

	if pod["velocity"] == 0:
		return

	var d: int = pod["y"] - main.ship_y

	if d >= -30 and d <= 10 and main._random() & 0xff < 0x1e:

		# fires one shot, S2 98 at speed 6, and stays open on the effects list

		pod["velocity"] = 0
		main.enemies.erase(pod)
		main.effects.push_front(pod)
		var open: Array = POD_OPEN[0 if pod["side"] == 0 else 1]
		pod["frames"] = []

		for f in open:
			pod["frames"].append([_key(f[0]), f[1]])

		pod["anim"] = 0
		pod["count"] = pod["frames"][0][1]
		pod["key"] = pod["frames"][0][0]

		if pod["side"] == 0:
			main._enemy_bullet(pod["x"] + 3, pod["y"] + 7, 2, _key(98), 6)
		else:
			main._enemy_bullet(pod["x"] + 11, pod["y"] + 7, 6, _key(98), 6)

		return

	pod["y"] += pod["velocity"]
	pod["left"] += pod["velocity"]

	if pod["left"] == 0 or pod["left"] == pod["travel"]:
		pod["velocity"] = -pod["velocity"]

	pod["box"] = main._box_of(pod["key"], pod["x"], pod["y"])


func update_tile_objects() -> void:

	# the list ds:0x90ec, after the effects (0x3682)

	for object in tile_objects.duplicate():
		if object["dead"]:
			tile_objects.erase(object)
			continue

		if object["kind"] == "nest":
			_update_nest(object)
		else:
			_update_hatch(object)


func _update_nest(nest: Dictionary) -> void:

	# code 0x7ce6

	var sy: int = nest["world_y"] - main.scroll

	if nest["state"] == 0:
		if sy >= 0x30:
			nest["state"] = 1

		return

	var quads: Array = nest["quads"]
	main._write_tiles(nest["cell"], quads[NEST_ORDER[nest["state"] - 1]], 4)
	nest["state"] += 1

	if nest["state"] == 0x15:

		# code 0x7d3b : the burst, 8 at (x + 16, y + 16) and about

		for j in 8:
			var entry: Array = BURST[j]
			var offset: Vector2i = entry[0]
			var b: int = entry[1]
			var burst := _object("l2_burst", {
				"x": nest["x"] + 16 + offset.x,
				"y": sy + 16 + offset.y,
				"index": 7 - j,
				"counter": main._random() & 0x1f,
				"frames": _frames([b + 2, b + 1, b, b + 1], 1),
				"anim": 0,
				"count": 1,
				"energy": 1,
				"score": 20,
				"hit": "0x3b55",
			})
			burst["key"] = burst["frames"][0][0]
			main.enemies.push_front(burst)

		nest["dead"] = true


func _update_burst(burst: Dictionary) -> void:

	# code 0x85d0

	main._step_animation(burst, burst["frames"], 0)
	burst["key"] = burst["frames"][burst["anim"]][0]
	burst["counter"] += 1

	if burst["counter"] >= 0x50:
		main._explode(burst, false)
		burst["dead"] = true
		return

	if burst["counter"] & 15 == 0:
		var i: int = ~main._direction(main.ship_x - burst["x"], main.ship_y - burst["y"]) & 7
		burst["index"] = i
		var b: int = BURST[7 - i][1]
		burst["frames"] = _frames([b + 2, b + 1, b, b + 1], 1)
		burst["anim"] = 0
		burst["count"] = 1
		burst["key"] = burst["frames"][0][0]

	var i: int = burst["index"]
	var x: int = burst["x"] + BURST_DX[i]

	if x < 0 or x >= 0x140:
		burst["dead"] = true
		return

	var y: int = burst["y"] + BURST_DY[i] + main.scroll_applied

	if y < 0 or y >= 0xc0:
		burst["dead"] = true
		return

	burst["x"] = x
	burst["y"] = y
	burst["box"] = main._box_of(burst["key"], x, y)

	# code 0x85fe : the ship test as coded, the box bottom against the ship's x range and
	# 2 * index against its y range, so in practice never true

	var ship: Array = main.ship_box
	var bx: int = burst["box"][3]

	if bx >= ship[0] and bx <= ship[2] and 2 * i >= ship[1] and 2 * i <= ship[3]:
		main._damage_ship(4)
		main.ship_flash = true
		burst["dead"] = true


func _update_hatch(hatch: Dictionary) -> void:

	# code 0x7ac4 (type 5), 0x7bef (type 4)

	if hatch["world_y"] >= main.scroll_max + 0xd0:
		hatch["dead"] = true
		return

	var sy: int = hatch["world_y"] - main.scroll

	if sy >= 0xb4:
		return

	if hatch["state"] >= 5:
		if hatch["passes"] == 0:
			hatch["dead"] = true
			return

		if hatch["state"] >= 9:
			hatch["state"] = 0
			hatch["passes"] -= 1

	var four: bool = hatch["type"] == 5

	if hatch["state"] <= 1:
		if four:
			if sy >= 0x64:
				hatch["state"] = 2
			elif main.frame_count & 3 == 0:
				hatch["state"] ^= 1
		else:
			if sy < 0x64:
				return

			hatch["state"] = 2

	var s: int = hatch["state"]
	var cell: int = hatch["cell"]

	if four:
		var quad: Array = HATCH_FOUR[s]

		for k in 4:
			main.map_words[cell + (k >> 1) * 20 + (k & 1)] = quad[k] << 6
	else:
		main.map_words[cell] = (HATCH_ONE[s] << 6) | (1 if s == 8 else 0)

	if s >= 2 and main.frame_count & 3 == 0:
		hatch["state"] += 1

		if hatch["state"] == 4:
			if four:
				_spawn_diver(hatch["x"] + 16, sy + 16, true)
			else:
				_spawn_diver(hatch["x"], sy, false)


func _spawn_diver(x: int, y: int, large: bool) -> void:

	# code 0x7b9a, 0x7c6e : 0xe0 (6 energy, 300 points, large explosion) or 0xe4 (4, 150)

	var fly: Array = _frames([0, 1], 3) if large else [[_key(110), 0]]
	var diver := _object("l2_diver", {
		"x": x,
		"y": y,
		"large": large,
		"energy": 6 if large else 4,
		"score": 300 if large else 150,
		"diving": false,
		"fly": fly,
		"frames": fly,
		"anim": 0,
		"count": fly[0][1],
	})
	diver["key"] = fly[0][0]
	main.enemies.push_front(diver)


func _update_diver(diver: Dictionary) -> void:

	# code 0x830c. unconfirmed : the wobble's phase adds the object's record address, 0 here.

	main._step_animation(diver, diver["frames"], 0)
	diver["key"] = diver["frames"][diver["anim"]][0]
	var t: int = main.frame_count

	if diver["diving"]:
		diver["y"] += 12

		if diver["y"] >= 0xa0:
			diver["diving"] = false
			_set_frames(diver, diver["fly"])
	elif diver["y"] > 0x32:
		diver["y"] -= 5
		diver["x"] += WOBBLE[(t >> 2) & 7]
	elif absi(diver["x"] - main.ship_x) < 10:
		diver["diving"] = true
		if diver["large"]:
			_set_frames(diver, [[_key(1), 1], [_key(2), 3], [_key(3), 3], [_key(4), 0]])
		else:
			_set_frames(diver, [[_key(111), 3], [_key(112), 3], [_key(113), 0]])
	else:
		diver["x"] += 4 if main.ship_x > diver["x"] else -4
		diver["y"] = mini(diver["y"] + WOBBLE[(t >> 1) & 7], 0x32)

	diver["box"] = main._box_of(diver["key"], diver["x"], diver["y"])


func _set_frames(item: Dictionary, frames: Array) -> void:
	item["frames"] = frames
	item["anim"] = 0
	item["count"] = frames[0][1]
	item["key"] = frames[0][0]


# ---------------------------------------------------------------- dispatch from main

func update_enemy(enemy: Dictionary) -> void:
	match enemy["kind"]:
		"l2_snake":
			_update_snake(enemy)
		"l2_target":
			_update_target(enemy)
		"l2_guardian":
			_update_guardian(enemy)
		"l2_hatchling":
			_update_hatchling(enemy)
		"l2_crawler":
			_update_crawler(enemy)
		"l2_gun":
			_update_gun(enemy)
		"l2_pod":
			_update_pod(enemy)
		"l2_burst":
			_update_burst(enemy)
		"l2_diver":
			_update_diver(enemy)


func update_effect(item: Dictionary) -> void:
	match item["kind"]:
		"l2_debris":
			_update_debris(item)
		"l2_pod":
			_update_pod(item)


func hit(enemy: Dictionary, damage: int) -> void:
	match enemy["hit"]:
		"0x3b55":

			# code 0x3b55 : any hit, an explosion at its centre, removed, no score

			main._explode(enemy, enemy["large"])
			enemy["dead"] = true
		"0x80f5", "0x8114":
			_snake_hit(enemy, damage)
		"0x8745":
			_guardian_hit(enemy, damage)
		"0x87d5":
			_target_hit(enemy, damage)


func draw_enemy(enemy: Dictionary) -> void:
	match enemy["kind"]:
		"l2_guardian":
			_draw_guardian(enemy)
		"l2_target":
			_draw_target(enemy)
		"l2_gun":

			# code 0x3bdf : the hit flash of its tile

			if enemy["flash"]:
				main.world.draw_texture(main._tile_flash(enemy["first"][0]), Vector2(enemy["x"], enemy["world_y"] - main.scroll))

			enemy["flash"] = false
		"l2_snake":
			if enemy["shown"]:
				main._draw_sprite(enemy["key"], enemy["x"], enemy["y"], enemy["flash"])

			enemy["flash"] = false
		_:
			main._draw_sprite(enemy["key"], enemy["x"], enemy["y"], enemy["flash"])
			enemy["flash"] = false


func draw_effect(item: Dictionary) -> void:
	main._draw_sprite(item["key"], item["x"], item["y"], false)
