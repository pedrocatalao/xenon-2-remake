class_name Level3
extends RefCounted

# Level 3 of XENON2.EXE, the routines the level's tables point to (load module offsets) :
# init 0xac4e, hook 0x9a99, wall objects 0x9daa, wave types 0xabcc (table cs:0xaf77).
# "code" marks behaviour ported from the code, "unconfirmed" a detail left open there.

var main: Node

# ---------------------------------------------------------------- wave types

# code 0xabdf : type 3 is a snake of 7 parts (definition cs:0x95be), its energy 10 (cs:0x9598
# put in the large energy for the creation, 0x3479) whatever the loop. Head, 5 bodies, tail,
# id 0xe4, large, linked (removed silently with the head, 0x3a5c), 500 points from the head,
# each part 14 steps after the one before. Their update (0x99fb, 0x9a03, 0x9a0b) runs the
# path, box and fire (0x480e) but no animation, and takes the frame from the heading.
# code 0xabf5 : type 4 (cs:0x9630), one part, id 0xe8, 200 points, S3 138 until its first
# update (0x9a2b) picks the animation of the screen edge it is nearest.

static func wave_types() -> Dictionary:
	var snake: Array = []
	var routines := ["0x99fb", "0x9a03", "0x9a03", "0x9a03", "0x9a03", "0x9a03", "0x9a0b"]
	var frames := [118, 105, 105, 105, 105, 105, 109]

	for i in 7:
		snake.append({
			"id": 0xe4,
			"score": 500 if i == 0 else 14 * i,
			"hit": "0x3a39",
			"large": true,
			"linked": true,
			"silent": true,
			"frames": ["S3/%03d" % frames[i]],
			"start_delay": 14 * i,
			"energy": 10,
			"update": routines[i],
		})

	var edge := [{
		"id": 0xe8,
		"score": 200,
		"hit": "0x3aa7",
		"large": false,
		"linked": false,
		"silent": false,
		"frames": ["S3/138"],
		"start_delay": 0,
		"update": "0x9a2b",
	}]

	return {3: snake, 4: edge}


# cs:0xace9, 0xacf9, 0xad09 : the snake's frames by heading octant (0 right, clockwise)

const SNAKE_FRAMES := {
	"0x99fb": [124, 125, 118, 119, 120, 121, 122, 123],
	"0x9a03": [108, 107, 106, 105, 108, 107, 106, 105],
	"0x9a0b": [115, 116, 109, 110, 111, 112, 113, 114],
}

# cs:0xad19 : type 4's animations by edge (k / 2 : left, top, right, bottom), 2 ticks a frame

const EDGE_FRAMES := [[150, 151, 152, 153], [138, 139, 140, 141], [146, 147, 148, 149], [142, 143, 144, 145]]


static func wave_update(enemy: Dictionary) -> void:

	# after the path step and the placing, before the box (0x9a28 and 0x9a91 end with 0x3589)

	var update: String = enemy.get("update", "")

	if SNAKE_FRAMES.has(update):

		# code 0x9a11 : octant ((heading + 0x10) >> 4) & 0xe of the heading after the step,
		# 0 while waiting at the start

		var steps: int = enemy["steps"]
		var after: Array = enemy["path"]["after"]
		var heading: int = after[steps - 1] if steps > 0 and steps <= after.size() else 0
		enemy["key"] = "S3/%03d" % SNAKE_FRAMES[update][((heading + 0x10) >> 5) & 7]
	elif update == "0x9a2b":

		# code 0x9a2e : the edge from the position, signed compares, then the generic update
		# (0x480b) from now on

		var x: int = enemy["x"]
		var y: int = enemy["y"]
		var k := 0

		if x < 0:
			if y < 0:
				k = 2 if y < x else 0
			else:
				k = 6 if 0xc0 - y < x else 0
		elif y < 0:
			k = 2 if y < 0x140 - x else 4
		else:
			k = 4 if y - 0xc0 < x - 0x140 else 6

		var frames: Array = []

		for f in EDGE_FRAMES[k >> 1]:
			frames.append("S3/%03d" % f)
			frames.append("S3/%03d" % f)

		enemy["frames"] = frames
		enemy["age"] = 0
		enemy["key"] = frames[0]
		enemy["update"] = ""


func _init(owner: Node) -> void:
	main = owner

	# test option : --scroll past the stop at 0xaf0 starts with it let go

	if main.scroll < 0xaf0:
		main.scroll_min = 0


# ---------------------------------------------------------------- the worm

# ds:0x9231 the worm killed (0x9232, the second slot, killed from the start), ds:0x9233 its
# tail updated since the last hook, ds:0x9208 the worms made (the first takes path 60),
# ds:0x91f4 the pattern for the next paths, ds:0x920a its energy (cs:0x9588 = 80), set once
# for the level, so kept across worms and lives

var killed := false
var tail_seen := false
var worms := 0
var pattern := 0xe496
var worm_energy := 80

# ds:0x9235 : the middle guardian's head ran since the last hook, ds:0x9204 / 0x9206 its eyes'
# energy (cs:0x958a = 20), ds:0x920e its eyes left

var heartbeat := false
var eye_energy := [20, 20]
var eyes_left := 2

# cs:0xad21 : the parts, delay to the next, update, first frame (S3)

const WORM_PARTS := [[0x1c, "head", 159], [0x1c, "neck", 175], [0x15, "neck", 175],
	[0x0e, "body", 105], [0x0e, "body", 105], [0x0e, "body", 105], [0x0e, "body", 105],
	[0x0e, "body", 105], [0x0e, "body", 105], [0x0e, "body", 105], [0x0e, "tail", 109]]

# cs:0xad65 : the head's animation by octant (0 right, clockwise), 2 ticks a frame, one
# frame static ; cs:0xad75, 0xad85, 0xad95 : neck, body, tail frames by octant

const HEAD_ANIMS := [[167, 168, 169, 168], [170], [171, 172, 173, 172], [174],
	[159, 160, 161, 160], [162], [163, 164, 165, 164], [166]]
const NECK_FRAMES := [179, 180, 181, 182, 175, 176, 177, 178]
const WORM_BODY := [108, 105, 106, 107, 108, 105, 106, 107]
const WORM_TAIL := [115, 116, 109, 110, 111, 112, 113, 114]

# cs:0xaf83 : the holes drawn over the worm while it is out (grid, x, map y)

const HOLES := [
	[[[-94], [-108], [-122]], 0, 272],
	[[[-94], [-108], [-122]], 0, 80],
	[[[-135, -136]], 144, 0],
	[[[-93], [-107], [-121]], 304, 96],
	[[[-93], [-107], [-121]], 304, 256],
]


func hook() -> void:

	# code 0x9a99 : held at 0xaf0 while the middle guardian's head lives (it sets ds:0x9235
	# every frame) : no way back, the stars still move by the asked scroll, the map not.
	# When a frame passes without the head, the way on is free.

	if main.scroll_min == 0xaf0 and main.scroll == 0xaf0:
		main.scroll_max = 0xaf0
		main._move_stars(main.scroll_asked)
		main.scroll_asked = 0

		if heartbeat:
			heartbeat = false
		else:
			main.scroll_min = 0

	# code 0x9acf : above scroll 0xd0 the back limit is at least 0xa30. In the worm's zone at
	# least 0x20, a worm when the last one's tail is gone (0x9b22), and once it is killed 10
	# pairs of bonuses and the level done.

	if main.scroll > 0xd0:
		if main.scroll_max < 0xa30:
			main.scroll_max = 0xa30

		return

	if main.scroll_max < 0x20:
		main.scroll_max = 0x20

	if not killed and not tail_seen:
		_spawn_worm()

	tail_seen = false

	if killed and not main.level_done:
		main._bonus_pairs(10)
		main.level_done = true


func _spawn_worm() -> void:

	# code 0x9b63 : the path, the first worm 60, then 60 + (the pattern turned right by 5,
	# & 7) while that is 1 to 6

	var variant := 0

	if worms != 1:
		variant = worms
		worms += 1
	else:
		while variant < 1 or variant > 6:
			pattern = ((pattern >> 5) | (pattern << 11)) & 0xffff
			variant = pattern & 7

	var path: Dictionary = main.paths[60 + variant]
	var start: Vector2i = path["start"]
	var origin := Vector2i(start.x, start.y - main.scroll - main.scroll_asked)

	# code 0x9ba6 : 11 parts at the front of the enemies list (so the tail ends first), each
	# behind the one before by the table's delay, 8 steps a frame, heading up (0xc0), 2000
	# points never given. The head takes the hits (0x9d4d), the others stop shots (0x3a99).

	var delay := 0
	var head: Dictionary = {}

	for entry in WORM_PARTS:
		var part := {
			"kind": "l3_worm",
			"role": entry[1],
			"path": path,
			"origin": origin,
			"steps": delay,
			"speed": 8,
			"heading": 0xc0,
			"x": origin.x,
			"y": origin.y,
			"key": "S3/%03d" % entry[2],
			"hit": "0x9d4d" if entry[1] == "head" else "0x3a99",
			"type50": true,
			"large": false,
			"energy": 0,
			"score": 2000,
			"fire_counter": 0,
			"box": [1000, 0, 1000, 0],
			"flash": false,
			"dead": false,
			"group": 0,
			"head": null,
			"segments": [],
		}

		if entry[1] == "head":
			head = part
			part["frames"] = [[part["key"], 0]]
			part["anim"] = 0
			part["count"] = 0
		else:
			head["segments"].append(part)

		part["box"] = main._box_of(part["key"], part["x"], part["y"])
		main.enemies.push_front(part)
		delay -= entry[0]


func _octant(heading: int) -> int:
	return ((heading + 0x10) >> 5) & 7


func _update_worm(part: Dictionary) -> void:

	# code 0x9c4f (head), 0x9cd6 (neck), 0x9cfb (body), 0x9d20 (tail) : with the scroll, the
	# path (each part removes itself at its end), the frame by the heading's octant

	var origin: Vector2i = part["origin"]
	origin.y += main.scroll_applied
	part["origin"] = origin

	if part["role"] == "tail":
		tail_seen = true

	var path: Dictionary = part["path"]
	var points: Array = path["points"]
	var total := points.size()
	var ended: bool = part["steps"] >= total

	if not ended:
		part["steps"] += part["speed"]
		ended = part["steps"] > total

	if ended:
		part["dead"] = true
		return

	var steps: int = part["steps"]
	var start: Vector2i = path["start"]
	var point: Vector2i = start if steps <= 0 else points[steps - 1]
	part["x"] = origin.x + point.x - start.x
	part["y"] = origin.y + point.y - start.y
	var old: int = part["heading"]

	if steps > 0:
		part["heading"] = path["after"][steps - 1]

	var octant := _octant(part["heading"])

	match part["role"]:
		"head":

			# the animation steps, and starts again only when the octant changes

			main._step_animation(part, part["frames"], 0)

			if octant != _octant(old):
				var frames: Array = []

				for f in HEAD_ANIMS[octant]:
					frames.append(["S3/%03d" % f, 2 if HEAD_ANIMS[octant].size() > 1 else 0])

				part["frames"] = frames
				part["anim"] = 0
				part["count"] = frames[0][1]

			part["key"] = part["frames"][part["anim"]][0]

			# code 0x9c97 : 20 (cs:0x958c) to the fire byte, on the carry 8 shots, every way
			# (7 to 0), speed 12, frozen on S3 183 (their ticks read from the frame word)

			part["fire_counter"] += 20

			if part["fire_counter"] >= 0x100:
				part["fire_counter"] &= 0xff

				for d in range(7, -1, -1):
					main._enemy_bullet(part["x"], part["y"], d, "S3/183", 12)
		"neck":
			part["key"] = "S3/%03d" % NECK_FRAMES[octant]
		"body":
			part["key"] = "S3/%03d" % WORM_BODY[octant]
		"tail":
			part["key"] = "S3/%03d" % WORM_TAIL[octant]

	part["box"] = main._box_of(part["key"], part["x"], part["y"])


func _worm_hit(head: Dictionary, damage: int) -> void:

	# code 0x9d4d : every part flashes, the damage off the worm's energy. Dead : every part
	# removed, 20 large explosions about the screen, effect 6, every enemy freed.

	head["flash"] = true

	for part in head["segments"]:
		part["flash"] = true

	worm_energy -= damage

	if worm_energy > 0:
		return

	killed = true
	tail_seen = false

	for enemy in main.enemies:
		enemy["dead"] = true

	main.enemies.clear()
	main._explosions(0, 0, 320, 192, main.LARGE_EXPLOSION, 20)


func draw_overlay() -> void:

	# code 0xac01 : the holes, over everything, while the worm is out

	if not tail_seen:
		return

	for hole in HOLES:
		var sy: int = hole[2] - main.scroll

		if sy < 0xc0 and sy > -48:
			main._draw_grid(hole[0], hole[1], sy, false)


# ---------------------------------------------------------------- common

func _key(frame: int) -> String:
	return "S3/%03d" % frame


func _anim(list: Array, ticks: int) -> Array:
	var out: Array = []

	for f in list:
		out.append([_key(f), ticks])

	return out


func _set_anim(item: Dictionary, frames: Array) -> void:
	item["frames"] = frames
	item["anim"] = 0
	item["count"] = frames[0][1]
	item["key"] = frames[0][0]


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
		"key": "S3/126",
	}
	object.merge(fields, true)
	return object


func _bullet(x: int, y: int, direction: int, frames: Array, speed: int) -> Dictionary:

	# code 0x1ed3, the animation set over it when given

	main._enemy_bullet(x, y, direction, frames[0][0], speed)
	var bullet: Dictionary = main.effects[0]

	if frames.size() > 1:
		bullet["frames"] = frames
		bullet["anim"] = 0
		bullet["count"] = frames[0][1]

	return bullet


# ---------------------------------------------------------------- the middle guardian

# cs:0xadc3 : (role, animation, offset from the head) ; the arms are a root, 4 segments and a
# claw each

const GUARDIAN_PARTS := [
	["head", [[156, 0]], Vector2i.ZERO],
	["side", [[154, 4], [155, 4]], Vector2i(-32, 0)],
	["side", [[157, 4], [158, 4]], Vector2i(32, 0)],
	["eye", [[129, 0]], Vector2i(5, 56)],
	["eye", [[129, 0]], Vector2i(25, 56)],
	["root", [[126, 0]], Vector2i(-10, 51)],
	["root", [[126, 0]], Vector2i(42, 51)],
]

# cs:0x9870 : an eye opens ; cs:0xae6f : the claw by heading sector, two frames by bit 2 of
# the frame count

const EYE_OPEN := [[130, 2], [131, 2], [132, 20], [131, 2], [130, 2], [129, 0]]
const CLAW_FRAMES := [[20, 21], [22, 23], [24, 25], [26, 27], [12, 13], [14, 15], [16, 17], [18, 19]]


func _spawn_guardian() -> void:

	# code 0xa0e5 : 17 objects at the end of the enemies list (type 0x54 : not counted, the
	# smart bomb skips them), large explosions, 1000 points from the head. The head follows
	# path 83 (looping) at 6 steps a frame from its pos less (32, 40).

	var path: Dictionary = main.paths[83]
	var start: Vector2i = path["start"]
	var head: Dictionary = {}

	for entry in GUARDIAN_PARTS:
		var role: String = entry[0]
		var frames: Array = []

		for f in entry[1]:
			frames.append([_key(f[0]), f[1]])

		var part := _object("l3_mid", {
			"role": role,
			"offset": entry[2],
			"frames": frames,
			"anim": 0,
			"count": frames[0][1],
			"key": frames[0][0],
			"large": true,
			"score": 1000,
			"hit": "none",
			"z_immune": true,
			"silent": false,
		})

		if role == "head":
			head = part
			part["path"] = path
			part["steps"] = 0
			part["origin"] = Vector2i(start.x - 0x20, start.y - 0x28)
			part["fire_counter"] = 0
			part["x"] = part["origin"].x
			part["y"] = part["origin"].y
		else:
			part["head"] = head
			head["segments"].append(part)

		if role == "eye":
			part["pool"] = 1 if entry[2].x == 5 else 0
			part["fire_counter"] = 0

		main.enemies.append(part)

		if role == "root":

			# the arm : 4 segments and a claw following the root

			var links: Array = []

			for i in 5:
				var link := _object("l3_mid", {
					"role": "claw" if i == 4 else "link",
					"head": head,
					"large": true,
					"hit": "none",
					"z_immune": true,
				})
				head["segments"].append(link)
				links.append(link)
				main.enemies.append(link)

			part["links"] = links
			part["speed"] = 0
			part["delta"] = 0
			part["heading"] = 0x40 << 16
			part["turn"] = 0

	heartbeat = true


func _update_mid(part: Dictionary) -> void:
	match part["role"]:
		"head":
			_update_mid_head(part)
		"side":
			_follow(part)
		"eye":
			_update_eye(part)
		"root":
			_update_root(part)


func _follow(part: Dictionary) -> void:

	# code 0x9e89 : animation, at the head plus its offset

	main._step_animation(part, part["frames"], 0)
	part["key"] = part["frames"][part["anim"]][0]
	var head: Dictionary = part["head"]
	var offset: Vector2i = part["offset"]
	part["x"] = head["x"] + offset.x
	part["y"] = head["y"] + offset.y
	part["box"] = main._box_of(part["key"], part["x"], part["y"])


func _update_mid_head(head: Dictionary) -> void:

	# code 0x9e32 : the heartbeat, the path (0x480b), a shot at the ship on the carry of
	# 20 (cs:0x9592) a frame, from (x + 16, y + 60), speed 6, S3 199 to 202

	heartbeat = true
	main._step_animation(head, head["frames"], 0)
	var path: Dictionary = head["path"]
	var points: Array = path["points"]
	head["steps"] = mini(head["steps"] + 6, points.size())
	var start: Vector2i = path["start"]
	var point: Vector2i = points[head["steps"] - 1]
	var origin: Vector2i = head["origin"]
	head["x"] = origin.x + point.x - start.x
	head["y"] = origin.y + point.y - start.y
	head["box"] = main._box_of(head["key"], head["x"], head["y"])
	head["fire_counter"] += 20

	if head["fire_counter"] >= 0x100:
		head["fire_counter"] = main._random() & 0x3f
		var d: int = main._direction(main.ship_x - head["x"], main.ship_y - head["y"])
		_bullet(head["x"] + 0x10, head["y"] + 0x3c, d, _anim([199, 200, 201, 202], 1), 6)


func _update_eye(eye: Dictionary) -> void:

	# code 0x9ea4 : dead, its dead frame (S3 133 or 134) and no box ; open, hittable ;
	# closed, opens on the carry of 30 (cs:0x9596) a frame

	_follow(eye)

	if eye_energy[eye["pool"]] <= 0:
		eye["key"] = _key(133 if eye["pool"] == 0 else 134)
		eye["box"] = [1000, 0, 1000, 0]
		eye["hit"] = "none"
		return

	eye["hit"] = "0x9f1c"

	if eye["count"] != 0:
		return

	eye["box"] = [1000, 0, 1000, 0]
	eye["fire_counter"] += 30

	if eye["fire_counter"] >= 0x100:
		eye["fire_counter"] = main._random() & 0x3f
		var frames: Array = []

		for f in EYE_OPEN:
			frames.append([_key(f[0]), f[1]])

		_set_anim(eye, frames)


func _eye_hit(eye: Dictionary, damage: int) -> void:

	# code 0x9f1c : the whole guardian flashes, the eye's energy down. Dead : a small
	# explosion at it. Both dead : every part explodes, the head gives 1000, 4 pairs of
	# bonuses.

	var head: Dictionary = eye["head"]
	head["flash"] = true

	for part in head["segments"]:
		part["flash"] = true

	eye_energy[eye["pool"]] -= damage

	if eye_energy[eye["pool"]] > 0:
		return

	eye["box"] = [1000, 0, 1000, 0]
	eye["hit"] = "none"
	main._explode(eye, false)
	eyes_left -= 1

	if eyes_left > 0:
		return

	for part in head["segments"]:
		if not part["dead"]:
			main._explode(part, true)
			part["dead"] = true

	main._kill_enemy(head)
	main._bonus_pairs(4)


func _update_root(root: Dictionary) -> void:

	# code 0x9f7f : idle, by a 3 in 256 chance the arm reaches out towards the ship, its
	# speed 1 up to 14 and back to 0. The links (0xa027, claw 0xa090) each go speed steps
	# from the one before along a heading turning a little each step, so the arm curls.

	_follow(root)

	if root["speed"] == 0:
		if main._random() & 0xff >= 3:
			root["heading"] = 0x40 << 16
			_place_arm(root)
			return

		main.sound_priority = 1

		# Amiga level 3 code $55c6a : $f on $418

		main.amiga_1 = 0xf
		root["speed"] = 1
		root["delta"] = 1
		var d: int = main._direction(main.ship_x - root["x"], main.ship_y - root["y"])
		root["heading"] = ((d * 32 - 0x60) & 0xff) << 16
		var r: int = (main._random() & 0x1f) + 0x20
		root["turn"] = ((4 * r) & 0xff) << 8
	else:
		root["speed"] += root["delta"]

		if root["speed"] == 14:
			root["delta"] = -root["delta"]

	_place_arm(root)


func _place_arm(root: Dictionary) -> void:
	var x: int = root["x"]
	var y: int = root["y"]
	var xf := 0
	var yf := 0
	var heading: int = root["heading"]
	var speed: int = root["speed"]

	for link in root["links"]:
		for i in speed:
			var angle := heading >> 16
			var dy := int(main.sine[angle]) * 4
			var dx := int(main.sine[angle + 64]) * 4
			yf += dy & 0xff
			y += (dy >> 8) + (yf >> 8)
			yf &= 0xff
			xf += dx & 0xff
			x += (dx >> 8) + (xf >> 8)
			xf &= 0xff
			heading = (heading + root["turn"]) & 0xffffff

		link["x"] = x
		link["y"] = y

		if link["role"] == "claw":
			var sector := (heading >> 21) & 7
			link["key"] = _key(CLAW_FRAMES[sector][1 if main.frame_count & 4 else 0])

			if speed == 14:
				main.sound_request = 1

				# Amiga level 3 code $55d8e : $c on $414

				main.amiga_2 = 0xc
		else:
			link["key"] = _key(126)

		link["box"] = main._box_of(link["key"], x, y)


# ---------------------------------------------------------------- wall objects 0x9daa

# type 1 : the telescopic arm, segment frame by side, the tip's animation (cs:0x98b2, 0x98cc)

const ARM_TIP := [[[31, 0], [31, 2], [32, 1], [33, 0], [32, 2]], [[28, 0], [28, 2], [29, 1], [30, 0], [29, 2]]]

# type 2 : the walker's animations (cs:0x98e6 right, 0x9918 left, turns 0x98fc, 0x992e)

const WALK_RIGHT := [6, 7, 8, 7]
const WALK_LEFT := [0, 1, 2, 1]
const TURN_RIGHT := [[8, 3], [9, 3], [10, 3], [11, 3], [10, 3], [9, 3], [8, 0]]
const TURN_LEFT := [[2, 3], [3, 3], [4, 3], [5, 3], [4, 3], [3, 3], [2, 0]]

# type 4 : the wall gun's tiles by side (cs:0xaf57, 0xaf65), death tiles

const GUN_SEQ := [[223, 224, 225, 226, 225, 224, 223], [227, 228, 229, 230, 229, 228, 227]]
const GUN_DEATH := [231, 232]

# type 5 : the turret's tiles (cs:0xae8f), its mouth (cs:0xaebf) and top (cs:0xaf2f) states,
# the burst's frames by direction (cs:0xaf1f)

const TURRET := [[170, 211, 212, 171], [185, 213, 214, 186], [145, 146, 147, 148],
	[157, -158, -159, 160], [169, 191, 192, 172], [0, 199, 200, 0]]
const MOUTH := [[191, 192, 199, 200], [193, 194, 201, 202], [195, 196, 203, 204], [197, 198, 205, 206],
	[195, 196, 203, 204], [207, 208, 209, 210], [195, 196, 203, 204], [193, 194, 201, 202], [191, 192, 199, 200]]
const TOP := [[211, 212, 213, 214], [215, 216, 219, 220], [217, 218, 221, 222], [215, 216, 219, 220], [211, 212, 213, 214]]
const BURST := [[47, 48, 49], [50, 51, 52], [53, 54, 55], [56, 57, 58], [59, 60, 61], [62, 63, 64], [65, 66, 67], [68, 69, 70, 69]]

# type 6 : the crawler by direction (cs:0xadb3, ds:0x4062 to 0x40d2)

const CRAWL_FRAMES := [84, 76, 96, 92, 72, 80, 88, 100]
const CRAWL_SPAWN_X := [8, 8, 15, 0, 8, 8, 0, 15]
const CRAWL_SPAWN_Y := [0, 15, 8, 8, 15, 0, 8, 8]
const CRAWL_DX := [1, 1, 0, 0, -1, -1, 0, 0]
const CRAWL_DY := [0, 0, 1, 1, 0, 0, -1, -1]
const CRAWL_PROBE := [-20, 20, 1, -1, 20, -20, -1, 1]
const CRAWL_TURN_X := [-6, -6, 0, 0, 6, 6, 0, 0]
const CRAWL_TURN_Y := [0, 0, -6, -6, 0, 0, 6, 6]
const CRAWL_NEXT := [5, 4, 7, 6, 1, 0, 3, 2]


func spawn_wall(wall: Dictionary) -> void:
	var type := int(wall["type"])
	var side := int(wall["side"])
	var x := int(wall["x"]) - 8
	var world_y := int(wall["world_y"]) - 8

	match type:
		1:
			_spawn_arm(int(wall["x"]) - 8 + (0x20 if side != 0 else 0), int(wall["world_y"]) - main.scroll, side)
		2:
			_spawn_walker(x, int(wall["world_y"]) + 8 - main.scroll)
		3:
			_spawn_guardian()
		4:

			# code 0xa40f : a wall gun of one tile, energy 6 (cs:0x957c), 100 points

			var seq: Array = GUN_SEQ[0 if side == 0 else 1]
			var cell := (world_y >> 4) * 20 + (x >> 4)
			main.map_words[cell] = (seq[0] << 6) | 1
			main.enemies.push_front(_object("l3_gun", {
				"side": side,
				"x": x,
				"world_y": world_y,
				"cell": cell,
				"seq": seq,
				"first": [seq[0]],
				"death": [GUN_DEATH[0 if side == 0 else 1]],
				"size": 1,
				"state": 0,
				"fire_counter": 0,
				"energy": 6,
				"score": 100,
				"hit": "0x3b76",
			}))
		5:
			_spawn_turret(x, world_y)
		6:
			_spawn_crawler(x, world_y, int(wall["b"]))


func _spawn_arm(bx: int, sy: int, side: int) -> void:

	# code 0xa1d2 : 8 segments (energy 12 shared through the innermost, 400 points, small
	# explosions), the innermost leads. Hidden while idle but for the tip.
	# unconfirmed : the two bracket objects (0xb8, 0xbc) only narrow the hit test ; here a
	# hidden segment has no box.

	var head: Dictionary = {}
	var frame := 35 if side == 0 else 34

	for k in range(7, -1, -1):
		var part := _object("l3_arm", {
			"side": side,
			"x": bx,
			"y": sy,
			"base": bx,
			"factor": (7 - k) * (-1 if side != 0 else 1),
			"role": "head" if k == 7 else ("tip" if k == 0 else "middle"),
			"key": _key(frame),
			"energy": 12,
			"score": 400,
			"hit": "0x3a39",
			"linked": true,
			"silent": false,
			"extension": 0,
			"velocity": 0,
			"target": 0,
			"shown": false,
		})

		if k == 7:
			head = part
		else:
			part["head"] = head
			head["segments"].append(part)

		if k == 0:
			var tip: Array = []

			for f in ARM_TIP[0 if side == 0 else 1]:
				tip.append([_key(f[0]), f[1]])

			_set_anim(part, tip)
			part["shown"] = true

		main.enemies.push_front(part)


func _update_arm(part: Dictionary) -> void:

	# code 0xa5a4 (innermost), 0xa656 (middle), 0xa613 (tip)

	part["y"] += main.scroll_applied

	if part["y"] >= 0xe8:
		part["dead"] = true
		return

	var head: Dictionary = part if part["role"] == "head" else part["head"]

	if part["role"] == "head":
		part["shown"] = false

		if part["velocity"] == 0:
			if part["target"] < 0:
				part["target"] += 1
				part["box"] = [1000, 0, 1000, 0]
				return

			if absi(part["y"] - main.ship_y) > 0x20:
				part["box"] = [1000, 0, 1000, 0]
				return

			part["velocity"] = 2
			part["target"] = (main._random() & 6) + 10

		part["shown"] = true
		part["extension"] += part["velocity"]

		if part["extension"] == 0:
			part["velocity"] = 0
			part["target"] = -5
		elif part["extension"] == part["target"]:
			part["velocity"] = -part["velocity"]

		part["box"] = main._box_of(part["key"], part["x"], part["y"])
		return

	part["x"] = part["base"] + part["factor"] * head["extension"]

	if part["role"] == "tip":
		main._step_animation(part, part["frames"], 0)
		part["key"] = part["frames"][part["anim"]][0]

		if (head["velocity"] == 2 and head["extension"] == 2) or (head["target"] > 0 and head["target"] == head["extension"]):
			part["count"] = 1
	else:
		part["shown"] = head["velocity"] != 0

	if part["shown"]:
		part["box"] = main._box_of(part["key"], part["x"], part["y"])
	else:
		part["box"] = [1000, 0, 1000, 0]


func _spawn_walker(x: int, y: int) -> void:

	# code 0xa33f : energy 6 (cs:0x9568), large explosion, 300 points

	var walker := _object("l3_walker", {
		"x": x,
		"y": y,
		"velocity": -2 if x > 0xa0 else 2,
		"turning": 0,
		"energy": 6,
		"large": true,
		"score": 300,
	})
	_set_anim(walker, _anim(WALK_LEFT if x > 0xa0 else WALK_RIGHT, 3))
	walker["box"] = main._box_of(walker["key"], x, y)
	main.enemies.push_front(walker)


func _update_walker(w: Dictionary) -> void:

	# code 0xa689 : walks to the middle, turns there (shooting at its 11th frame), walks
	# back, bounces at the screen's edges

	w["y"] += main.scroll_applied

	if w["y"] > main.scroll_max + 0xd0 - main.scroll:
		w["dead"] = true
		return

	main._step_animation(w, w["frames"], 0)
	w["key"] = w["frames"][w["anim"]][0]

	if w["turning"] == 0:
		w["x"] += w["velocity"]

		if w["x"] <= -0x20:
			w["x"] = 0
			w["velocity"] = -w["velocity"]
			_set_anim(w, _anim(WALK_RIGHT, 3))
		elif w["x"] >= 0x160:
			w["x"] = 0x140
			w["velocity"] = -w["velocity"]
			_set_anim(w, _anim(WALK_LEFT, 3))
		elif w["x"] == 0x88:
			w["turning"] = 1
			_set_anim(w, _turn_anim(TURN_RIGHT))
		elif w["x"] == 0xb8:
			w["turning"] = 1
			_set_anim(w, _turn_anim(TURN_LEFT))
	elif w["count"] == 0:
		w["turning"] = 0

		if w["x"] <= 0xa0:
			w["x"] = 0x68
			_set_anim(w, _anim(WALK_LEFT, 3))
		else:
			w["x"] = 0xd8
			_set_anim(w, _anim(WALK_RIGHT, 3))

		w["velocity"] = -w["velocity"]
	else:
		w["turning"] += 1

		if w["turning"] == 11:

			# code 0xa738 : a zig-zag shot

			var bx: int = w["x"] - 5
			var right := bx > 0xa0
			var b := _bullet(bx + (10 if right else 0), w["y"] + 4, 5 if w["x"] >= 0xa0 else 3, [[_key(37 if right else 36), 0]], 6)
			b["zigzag"] = true

	w["box"] = main._box_of(w["key"], w["x"], w["y"])


func _turn_anim(list: Array) -> Array:
	var out: Array = []

	for f in list:
		out.append([_key(f[0]), f[1]])

	return out


func zigzag(bullet: Dictionary) -> void:

	# code 0xa7b4 : after the move, below x 0x80 down right, from 0xc0 down left

	var x: int = bullet["x"] >> 16

	if x < 0x80:
		bullet["direction"] = 3
		bullet["key"] = _key(36)
	elif x >= 0xc0:
		bullet["direction"] = 5
		bullet["key"] = _key(37)


func _update_gun(gun: Dictionary) -> void:

	# code 0xab25

	if gun["world_y"] > main.scroll_max + 0xd0:
		gun["dead"] = true
		return

	var x: int = gun["x"]
	var sy: int = gun["world_y"] - main.scroll
	gun["box"] = [x + 2, sy + 2, x + 0xe, sy + 0xe]

	if gun["state"] == 0:
		gun["fire_counter"] += 0x10

		if gun["fire_counter"] >= 0x100:
			gun["fire_counter"] = main._random() & 0x3f
			gun["state"] = 1

		return

	main.map_words[gun["cell"]] = (gun["seq"][gun["state"] >> 1] << 6) | 1
	gun["state"] += 1

	if gun["state"] == 8:

		# code 0xaba1 : S3 117, speed 7, up (side 0) or down

		if gun["side"] == 0:
			main._enemy_bullet(x + 8, sy, 0, _key(117), 7)
		else:
			main._enemy_bullet(x + 8, sy + 10, 4, _key(117), 7)
	elif gun["state"] == 14:
		gun["state"] = 0


func _spawn_turret(x: int, world_y: int) -> void:

	# code 0xa3bf : 4 x 6 tiles, the mouth first (energy 24, cs:0x956a)

	var cell := (world_y >> 4) * 20 + (x >> 4)

	for row in 6:
		for column in 4:
			var t: int = TURRET[row][column]
			main.map_words[cell + row * 20 + column] = 0 if t == 0 else ((absi(t) << 6) | (0 if t < 0 else 1))

	main.enemies.push_front(_object("l3_turret", {
		"x": x,
		"world_y": world_y,
		"cell": cell,
		"stage": 1,
		"state": 0,
		"fire_counter": 0,
		"energy": 24,
		"hit": "0xa8d4",
	}))


func _write_quad(cell: int, quad: Array) -> void:
	main._write_tiles(cell, quad, 4)


func _update_turret(t: Dictionary) -> void:

	# code 0xa7df (mouth), 0xa9cf (top)

	if t["world_y"] > main.scroll_max + 0xd0:
		t["dead"] = true
		return

	var x: int = t["x"]
	var sy: int = t["world_y"] - main.scroll

	if t["stage"] == 1:
		t["box"] = [x + 0x10, sy + 0x40, x + 0x2f, sy + 0x5a]

		if t["state"] == 0 and main._random() & 0xff >= 0x14:
			return

		_write_quad(t["cell"] + 4 * 20 + 1, MOUTH[t["state"] >> 1])
		t["state"] += 1

		if t["state"] == 18:
			t["state"] = 0
		elif t["state"] >= 4 and t["state"] <= 11:

			# code 0xa882 : the shot, S3 71, speed 6, down by the state

			t["fire_counter"] += 0x28

			if t["fire_counter"] >= 0x100:
				t["fire_counter"] = main._random() & 0x3f
				var d: int = {4: 4, 6: 3, 8: 5, 10: 4}.get(t["state"] & ~1, 4)
				main._enemy_bullet(x + 0x20, sy + 0x58, d, _key(71), 6)
		elif t["state"] == 12 and main._random() & 0xff < 0xe0:
			t["state"] = 4

		return

	t["box"] = [x + 0x10, sy + 4, x + 0x2f, sy + 0x1b]

	if t["state"] == 0:
		t["fire_counter"] += 0x18

		if t["fire_counter"] < 0x100:
			return

		t["fire_counter"] = main._random() & 0x3f

	_write_quad(t["cell"] + 1, TOP[t["state"] >> 1])
	t["state"] += 1

	if t["state"] == 10:
		t["state"] = 0
	elif t["state"] == 4:

		# code 0xaa5a : 8 shots every way, speed 8

		for d in range(7, -1, -1):
			_bullet(x + 0x20, sy + 0x18, d, _anim(BURST[d], 1), 8)


func _turret_hit(t: Dictionary, damage: int) -> void:

	# code 0xa8d4 (mouth), 0xaa9e (top) : a flash ; dead, a large explosion, its tiles
	# cleared, 500 points, the mouth gives way to the top (energy 24, cs:0x957e)

	t["flash"] = true
	t["energy"] -= damage

	if t["energy"] > 0:
		return

	var x: int = t["x"]
	var sy: int = t["world_y"] - main.scroll
	var cell: int = t["cell"]
	main.score += 500

	if t["stage"] == 1:
		main._explode_at(x + 0x20, sy + 0x40, main.LARGE_EXPLOSION)

		for row in [2, 3, 4]:
			for column in 4:
				main.map_words[cell + row * 20 + column] = 0

		main.map_words[cell + 5 * 20 + 1] = 0
		main.map_words[cell + 5 * 20 + 2] = 0
		t["stage"] = 2
		t["state"] = 0
		t["energy"] = 24
		t["box"] = [1000, 0, 1000, 0]
		t["flash"] = false
		return

	main._explode_at(x + 0x20, sy + 0x10, main.LARGE_EXPLOSION)

	for row in [0, 1]:
		for column in 4:
			main.map_words[cell + row * 20 + column] = 0

	t["dead"] = true


func _spawn_crawler(x: int, world_y: int, d: int) -> void:

	# code 0x9db3 : energy 3 (cs:0x9562), small explosion, 100 points

	var c := _object("l3_crawler", {
		"x": x + CRAWL_SPAWN_X[d],
		"y": world_y - main.scroll + CRAWL_SPAWN_Y[d],
		"direction": d,
		"fire_counter": 0,
		"energy": 3,
		"score": 100,
	})
	_set_anim(c, _anim(range(CRAWL_FRAMES[d], CRAWL_FRAMES[d] + 4), 2))
	c["box"] = main._box_of(c["key"], c["x"], c["y"])
	main.enemies.push_front(c)


func _update_crawler(c: Dictionary) -> void:

	# code 0xa469 : along the wall, a step a frame, a turn when the wall ends or blocks

	main._step_animation(c, c["frames"], 0)
	c["key"] = c["frames"][c["anim"]][0]
	c["y"] += main.scroll_applied

	if c["y"] > main.scroll_max + 0xd0 - main.scroll:
		c["dead"] = true
		return

	var d: int = c["direction"]
	var check := false

	if CRAWL_DX[d] != 0:
		c["x"] += CRAWL_DX[d]
		check = (c["x"] & 0xf) == (0 if CRAWL_DX[d] > 0 else 0xf)
	else:

		# the test for upward moves reads the flags of dx (0), so == 0 for both ways

		c["y"] += CRAWL_DY[d]
		check = ((c["y"] + main.scroll) & 0xf) == 0

	if check:
		var turn := false

		if c["x"] == 0 or c["x"] >= 0x140 or c["x"] < 0:
			turn = true
		else:
			var cell: int = (c["x"] >> 4) + ((c["y"] + main.scroll) >> 4) * 20

			if cell >= 0 and cell < main.map_words.size() and main.map_words[cell] != 0:
				c["x"] -= CRAWL_DX[d]
				c["y"] -= CRAWL_DY[d]
				turn = true
			else:
				var probe: int = cell + CRAWL_PROBE[d]
				turn = probe < 0 or probe >= main.map_words.size() or main.map_words[probe] == 0

		if turn:
			c["x"] += CRAWL_TURN_X[d]
			c["y"] += CRAWL_TURN_Y[d]
			d = CRAWL_NEXT[d]
			c["direction"] = d
			_set_anim(c, _anim(range(CRAWL_FRAMES[d], CRAWL_FRAMES[d] + 4), 2))

	# code 0xa560 : 2 a frame (cs:0x956c), on the carry a shot at the ship, S3 128, speed 6

	c["fire_counter"] += 2

	if c["fire_counter"] >= 0x100:
		c["fire_counter"] = main._random() & 0x3f
		var dir: int = main._direction(main.ship_x - c["x"], main.ship_y - c["y"])
		main._enemy_bullet(c["x"], c["y"], dir, _key(128), 6)

	c["box"] = main._box_of(c["key"], c["x"], c["y"])


# ---------------------------------------------------------------- dispatch from main

const HITS := ["0x9d4d", "0x9f1c", "0xa8d4"]


func update_enemy(enemy: Dictionary) -> void:
	match enemy["kind"]:
		"l3_worm":
			_update_worm(enemy)
		"l3_mid":
			if enemy["role"] in ["head", "side", "eye", "root"]:
				_update_mid(enemy)
		"l3_arm":
			_update_arm(enemy)
		"l3_walker":
			_update_walker(enemy)
		"l3_gun":
			_update_gun(enemy)
		"l3_turret":
			_update_turret(enemy)
		"l3_crawler":
			_update_crawler(enemy)


func hit(enemy: Dictionary, damage: int) -> void:
	match enemy["hit"]:
		"0x9d4d":
			_worm_hit(enemy, damage)
		"0x9f1c":
			_eye_hit(enemy, damage)
		"0xa8d4":
			_turret_hit(enemy, damage)


func draw_enemy(enemy: Dictionary) -> void:
	match enemy["kind"]:
		"l3_gun":
			if enemy["flash"]:
				main.world.draw_texture(main._tile_flash(enemy["first"][0]), Vector2(enemy["x"], enemy["world_y"] - main.scroll))
		"l3_turret":

			# code 0xa978, 0xaaff : the flash of the stage's tiles

			if enemy["flash"]:
				var x: int = enemy["x"]
				var sy: int = enemy["world_y"] - main.scroll

				if enemy["stage"] == 1:
					main._draw_grid([[-145, -146, -147, -148], [-157, -158, -159, -160], [-169, 0, 0, -172]], x, sy + 0x20, true)
				else:
					main._draw_grid([[-211, -212], [-213, -214]], x + 0x10, sy, true)
		"l3_arm":
			if enemy["shown"]:
				main._draw_sprite(enemy["key"], enemy["x"], enemy["y"], enemy["flash"])
		_:
			main._draw_sprite(enemy["key"], enemy["x"], enemy["y"], enemy["flash"])

	enemy["flash"] = false