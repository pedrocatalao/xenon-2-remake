class_name Shop
extends Node2D

# Port of the shop of XENON2.EXE : routine 0x4a69 and the routines it calls, with the EGA
# and VGA drawing code of segment 0xf29 (offsets below as seg:off or as load module offsets).
#
# The original draws into one of two video pages and shows it with the page flip of
# 0x105ae (stub 0xa51), which first waits for the next game tick (ds:0x3046, 18.2 a second).
# Here the two pages are images and the shop runs as a coroutine that waits at each flip.
# Some routines draw on both pages at once (text, digits, cursor, lamps), the rest on the
# page being drawn.
#
# All tables come from tools/x2shop.py (data/shop.json). The shop palette is ds:0x427d
# (equal to the palette of SHOP.DAT) : the common sprites are recoloured to it.

signal ticked

const BOTTOM_CLIP := 0xc7
const HAND_CLIP := 0x68

# code 0x576d, 0x5829 : the text cursor counts columns of 4 pixels

const TEXT_X := 0x37
const TEXT_Y := 0x76
const TEXT_RIGHT := 0x4b
const LINE_STEP := 7

# code f29:1716 : the credits, 7 digits from screen address 0x1af1

const CREDITS_X := 136
const CREDITS_Y := 172
const POWERS := [1000000, 100000, 10000, 1000, 100, 10, 1]

# code f29:1afa : the shopkeeper strip and the side panel are copied 112 pixels wide from
# x 208, the first 7 and the last 8 pixels of each row left out (f29:1d01)

const STRIP_X := 208
const STRIP_LEFT := 7
const STRIP_WIDTH := 97

# code f29:1ab5 : the text box is cleared in colour 0 from x 215 to 310, y 114 for 69 rows

const BOX_X := 215
const BOX_WIDTH := 96
const BOX_Y := 114
const BOX_ROWS := 0x45

# item indices of the special boxes (code 0x4d38)

const OUT_OF_STOCK := 0x1a
const MORE := 0x1b

# code 0x5319 : items whose description shows the power when selling

const POWER_ITEMS := [1, 0x13, 0x12, 8, 0xa, 0xe, 9, 0xd]

var main: Node
var data: Dictionary
var images := {}
var pages: Array[Image] = []
var black: Image
var shown := 0
var draw_page := 1
var blank := false
var texture: ImageTexture
var view: Sprite2D

# ENHANCED : the pages' xBRZ twins (hd_mirror.gd) and their texture

const HD_MIRROR = preload("res://scripts/hd_mirror.gd")

var hd = HD_MIRROR.new()
var large_texture: ImageTexture
var colours: Array[Color] = []
var glyphs: Array[Image] = []
var digits: Array[Image] = []
var strip: Image
var side: Image
var bottom: Image
var pipes: Array[Image] = []

var running := false
var ticks := 0
var ticks_total := 0
var clip := BOTTOM_CLIP

var level := 1
var final := false
var max_price := 0
var slots: Array = []
var amiga_pay := 0
var voice_random := RandomNumberGenerator.new()
var page_start := 0
var col := 0
var row := 0
var last_col := -1
var last_row := 0
var price := -1
var chosen: Dictionary = {}
var selling := true
var eyes_shut := true
var wink := 0
var brow := 0
var repeat := 0
var talking := false
var door := 0x30
var door2 := 0x44
var text_x := TEXT_X
var text_y := TEXT_Y
var hand_x := 0
var hand_y := 0
var hand_key := ""
var background: Array = []


func _ready() -> void:
	data = main._read_json("res://data/shop.json")
	main._load_headers("SHOP")

	for c in data["palette"]:
		colours.append(Color8(c[0], c[1], c[2]))

	for i in 2:
		pages.append(hd.target(Image.create(320, 200, false, Image.FORMAT_RGBA8)))

	black = Image.create(320, 200, false, Image.FORMAT_RGBA8)
	black.fill(Color.BLACK)
	hd.target(black)
	texture = ImageTexture.create_from_image(black)
	view = Sprite2D.new()
	var shown: Dictionary = hd.view(black, texture)
	large_texture = shown["large"]
	view.texture = shown["texture"]
	view.centered = false
	add_child(view)
	visible = false

	for i in 60:
		glyphs.append(_picture("res://assets/gr/font_tiny/%02d.png" % i))

	for i in 20:
		digits.append(_picture("res://assets/gr/hud_digits_shop/%02d.png" % i))

	strip = _picture("res://assets/gr/shopkeeper_strip.png")
	side = _picture("res://assets/gr/shop_side_panel.png")
	bottom = _picture("res://assets/gr/shop_bottom_panel.png")

	for i in 5:
		pipes.append(_picture("res://assets/gr/pipes/%d.png" % i))

	for i in 20:
		var at: Array = data["slots"][i]
		slots.append({"counter": 0, "x": int(at[0]), "y": int(at[1]), "item": 0, "frames": [], "loop": 0, "pos": 0, "launcher": null})

	for entry in data["background"]:
		background.append({"x": int(entry["x"]), "y": int(entry["y"]), "frames": entry["anim"]["frames"], "loop": int(entry["anim"]["loop"]), "pos": 0})


func tick() -> void:

	# code 0x600b : every third timer interrupt counts ds:0x3046 and ds:0x3048

	ticks += 1
	ticks_total += 1
	ticked.emit()


# ---------------------------------------------------------------- the shop, 0x4a69

func open(level_number: int, is_final: bool, price_cap: int) -> void:
	running = true
	visible = true
	level = level_number
	final = is_final
	max_price = price_cap
	ticks = 0
	_run()


func _run() -> void:
	clip = BOTTOM_CLIP

	# 0xd5f blanks the display, 0xc0b draws the background

	blank = true
	_present()
	_background()
	selling = true
	eyes_shut = true
	wink = 0
	page_start = 0

	for s in slots:
		s["counter"] = -9

	door = 0x30
	door2 = 0x44
	talking = false
	col = 0
	row = 4
	_cursor_off()
	col = 1
	row = 4
	_cursor_off()
	_credits()
	_update_all()
	await _frame()
	_update_all()

	# 0xe09 sets the shop palette, 0xd81 shows the display

	blank = false
	_present()
	main.sound_request = 0

	# Amiga shop $54f32 : $8 when the shop shows, $16 for the doors ($54f3c)

	main.amiga_2 = 8
	await _wait_ticks(9)
	main.sound_request = 7
	main.amiga_2 = 0x16
	await _open_doors()

	if final:
		_all_out_of_stock()
	else:
		_fill_sell()

	await _open_boxes()
	await _hand()
	_clear_text()

	if final:

		# code 0x4bd4 : the end of the game, nothing to buy or sell. Three lines (the second
		# after the first, no clear), each held while the keeper and the boxes move (0x4c48,
		# no hand), then the boxes close.

		await _say(data["messages"]["end_1"])
		await _hold_still(0x1e)
		await _say(data["messages"]["end_2"])
		await _hold_still(0x1e)
		_clear_text()
		await _say(data["messages"]["end_3"])
		await _hold_still(0x11)
		await _close_boxes()
	else:
		var message: String = data["messages"]["sell"]

		if level == 5:
			await _say(data["messages"]["welcome"])
			await _hold(0x11)
			_clear_text()
			await _say(data["messages"]["everything"])
			await _hold(0x11)
			_clear_text()
			message = data["messages"]["last_chance"]

		await _say(message)
		await _sell_loop()
		await _close_boxes()
		selling = false
		col = 1
		row = 4
		_cursor_off()
		_fill_buy()
		await _open_boxes()
		_clear_text()
		await _say(data["messages"]["buy"])
		await _buy_loop()
		await _close_boxes()

	main.sound_request = 7

	# Amiga shop $54fea and $55092 : $16 for the doors, $8 after them

	main.amiga_2 = 0x16
	await _close_doors()
	main.sound_request = 0
	main.amiga_2 = 8
	await _frame()
	await _wait_ticks(9)
	_update_all()
	await _frame()
	_update_all()

	if final:
		await _switched_off()

	blank = true
	_present()

	# 0xbe9 puts the status bar back, ss:0x10 goes back to 0xbf, 0x3319 and 0x35f2 make
	# sure of a front gun and save the weapons

	main._shop_weapons()

	if not main.level_done:

		# 0x4ba8 : the next tick, the map and the stars, the flip, the level palette

		var start := ticks_total

		while ticks_total == start:
			await ticked

		ticks = 0

	main.advice_step = 0xc
	running = false
	visible = main.level_done
	main._shop_closed()


func _frame() -> void:

	# code f29:131e (stub 0xa51) : waits for a tick unless one is already counted, then
	# shows the page just drawn and draws on the other one

	while ticks == 0:
		await ticked

	if amiga_pay > 0:
		amiga_pay -= 1
		main.amiga_2 = 0xd

	ticks = 0
	shown = draw_page
	draw_page ^= 1
	_present()


func _wait_ticks(count: int) -> void:

	# code 0x4bc7 : waits until ds:0x3046 has gone up by the count

	var target := ticks + count

	while ticks != target:
		await ticked


func _present() -> void:
	texture.update(black if blank else pages[shown])
	hd.show(large_texture, black if blank else pages[shown])


# ---------------------------------------------------------------- doors and boxes

func _open_doors() -> void:

	# code 0x4c59 : both doors go up by 4 a frame, then the text box is cleared

	while true:
		await _frame()

		if door != 0:
			door -= 4

			if door <= 0:

				# code 0x4c6c : the sound stops and the shop tune starts

				main._shop_tune()
				door = 0

		if door2 != 0:
			door2 -= 4

			if door2 < 0:
				door2 = 0

		_update_all()
		_lamps(door, 4)
		_lamps(door2, 0x6d)

		if door == 0 and door2 == 0:
			break

	_clear_box()


func _close_doors() -> void:

	# code 0x4cad

	_clear_box()

	while true:
		await _frame()

		if door2 != 0x44:
			door2 = mini(door2 + 4, 0x44)

		if door != 0x30:
			door = mini(door + 4, 0x30)

		_update_all()
		_lamps(door2, 0x6d)
		_lamps(door, 4)

		if door2 == 0x44:
			break

	# code 0x4cf5 : the sound stops

	main._stop_sound()


func _lamps(position: int, y: int) -> void:

	# code 0x4cfa, 0x4d0d : three lamps, the frame by bit 2 of the door position

	var key: String = data["sprites"]["b1ae" if position & 4 else "b144"]

	for x in [0xe2, 0x102, 0x122]:
		_sprite_both(key, x, y)


func _open_boxes() -> void:

	# code 0x558e : the shutters open, then every box shows noise for 5 frames

	while true:
		await _frame()

		for s in slots:
			s["counter"] += 1

		if slots[0]["counter"] == 0:
			break

		_draw_boxes()
		_keeper()

	for s in slots:
		s["counter"] = 1

	for i in 5:
		if i > 0:
			await _frame()

		_draw_boxes()
		_keeper()


func _close_boxes() -> void:

	# code 0x55d0

	for s in slots:
		s["counter"] = 0

	while true:
		await _frame()

		for s in slots:
			s["counter"] -= 1

		if slots[0]["counter"] == -9:
			break

		_draw_boxes()
		_keeper()

	for i in 11:
		if i > 0:
			await _frame()

		_draw_boxes()
		_keeper()


func _animate_boxes() -> void:

	# code 0x5691 : a box with an item counts down, at 0 it starts again from a random
	# 20 to 275. While the count is 1 or 2 the box shows noise.

	for s in slots:
		if s["item"] == 0:
			s["counter"] = 0
		else:
			s["counter"] -= 1

			if s["counter"] <= 0:
				s["counter"] = (main._random() & 0xff) + 0x14


func _draw_boxes() -> void:

	# code 0x56b8 : counts -9 to -1 are the shutter frames (all but -8 over noise), 0 to 2
	# noise only, above 2 the background and the next frame of the item, centred at
	# (x + 16, y + 14)

	for i in 20:
		var s: Dictionary = slots[i]
		var c: int = s["counter"]

		if c <= 0:
			if c != -8:
				_noise(s["x"], s["y"])

			if c != 0:
				_sprite(data["box_frames"][c + 9], s["x"], s["y"])
		elif c <= 2:
			_noise(s["x"], s["y"])

			# Amiga shop $56a08 : $b on $418 as the noise starts, when $414 has none

			if c == 2 and main.amiga_2 < 0:
				main.amiga_1 = 0xb
		else:
			_sprite(data["box_back"][(20 - i) & 1], s["x"], s["y"])
			var key := _next_frame(s)
			var h: Array = main.headers[key]
			_sprite(key, s["x"] + h[4] - ((h[6] >> 1) - 16), s["y"] + h[5] - ((h[7] >> 1) - 14))


func _next_frame(entry: Dictionary) -> String:

	# code 0x571b : the animation pointer moves on each draw, a zero word sends it back

	if entry["pos"] >= entry["frames"].size():
		entry["pos"] = entry["loop"]

	var key: String = entry["frames"][entry["pos"]]
	entry["pos"] += 1
	return key


func _set_item(s: Dictionary, item: int) -> void:
	s["item"] = item

	if item == 0:
		return

	var anim: Dictionary = data["items"][str(item)]["anim"]
	s["frames"] = anim["frames"]
	s["loop"] = int(anim["loop"])
	s["pos"] = 0


# ---------------------------------------------------------------- shopkeeper

func _update_all() -> void:

	# code 0x5612

	_draw_boxes()
	_keeper()
	_door2()


func _keeper() -> void:

	# code f29:1afa (stub 0xc93) : the strip rows 0 to 51 at y 9 and 52 to 61 at y 95, the
	# face (34 rows) at y 61. While talking the face is one of four, by the lowest set bit
	# of a random number.

	_strip(strip, 0, 52, 9)
	_strip(strip, 52, 10, 95)
	var face := 62

	if talking:
		var r: int = main._random()
		var v := 0

		while v < 3 and r & 1 == 0:
			r >>= 1
			v += 1

		face += v * 34

	_strip(strip, face, 34, 61)
	_background_animations()
	_face()

	if door == 0:
		return

	if door > 8:

		# the side panel, rows 0 to 39 as the upper door and 40 to 79 as the lower one

		_strip(side, 0x30 - door, door - 8, 9)
		_strip(side, 40, door - 8, 113 - door)

	_sprite(data["sprites"]["abe4"], 0xd7, door + 1)
	_sprite(data["sprites"]["ace4"], 0xf7, door + 1)
	_sprite(data["sprites"]["ad94"], 0x117, door + 1)
	_sprite(data["sprites"]["ae94"], 0xd7, 0x70 - door)
	_sprite(data["sprites"]["af94"], 0xf7, 0x70 - door)
	_sprite(data["sprites"]["b044"], 0x117, 0x70 - door)

	if door < 8:

		# the pipe rows above and below, from the third and fourth pipe pieces without
		# their first 16 pixels

		hd.blit_rect(pages[draw_page], pipes[2], Rect2i(16, 0, 112, 9), Vector2i(STRIP_X, 0))
		hd.blit_rect(pages[draw_page], pipes[3], Rect2i(16, 0, 112, 9), Vector2i(STRIP_X, 105))


func _door2() -> void:

	# code f29:1cc4 (stub 0xcb5) : the text box door, side panel rows 80 on, below a part
	# cleared in colour 0

	if door2 == 0:
		return

	var cleared := BOX_ROWS - door2
	hd.fill_rect(pages[draw_page], Rect2i(BOX_X, BOX_Y, BOX_WIDTH, cleared), colours[0])
	_strip(side, 80, door2, BOX_Y + cleared)


func _background_animations() -> void:

	# code 0x5835

	for entry in background:
		_sprite(_next_frame(entry), entry["x"], entry["y"])


func _face() -> void:

	# code 0x561c : eyes shut (ds:0x3adf), a wink (ds:0x3ae0) or a random blink, then the
	# eyebrows (ds:0x3ae1, a signed byte : below 0 one is held, above 0 both are raised)

	if eyes_shut:
		_sprite(data["sprites"]["ea9e"], 0x107, 0x29)
		_sprite(data["sprites"]["e9f8"], 0xf7, 0x29)

		if wink != 0:
			wink -= 1
	elif wink != 0:
		_sprite(data["sprites"]["e9f8"], 0xf7, 0x29)
		wink -= 1
	elif main._random() & 0x2654 == 0:
		_sprite(data["sprites"]["ea9e"], 0x107, 0x29)
		_sprite(data["sprites"]["e9f8"], 0xf7, 0x29)

	if eyes_shut:
		return

	if brow < 0:
		_sprite(data["sprites"]["eb44"], 0xf5, 0x23)
		return

	if brow == 0:
		if main._random() & 0x2654 != 0:
			return

		brow = 8
	else:
		brow -= 1

	_sprite(data["sprites"]["ebea"], 0x107, 0x23)
	_sprite(data["sprites"]["eb44"], 0xf5, 0x23)


func _draw_hand() -> void:

	# code 0x54db : drawn with the bottom clip at 0x68

	clip = HAND_CLIP
	_sprite(data["sprites"][hand_key], hand_x, hand_y)
	clip = BOTTOM_CLIP


func _hold_still(count: int) -> void:

	# code 0x4c48 : the keeper, the boxes, a frame, no hand

	for i in count:
		_keeper()
		_animate_boxes()
		_draw_boxes()
		await _frame()


func _switched_off() -> void:

	# code 0x4c1c : 150 ticks of a black screen with a dot in the middle, in colour 7 of the
	# level 5 palette (63, 54, 63 of 63), silent ; then 80 ticks blank

	main.sound_request = 0

	# Amiga shop $550bc : $12 as the set goes off

	main.amiga_2 = 0x12
	blank = false
	var dot := Color8(255, 218, 255)

	for i in 0x96:
		var page: Image = pages[draw_page]
		hd.fill(page, Color.BLACK)

		for p in [[165, 100], [166, 100], [164, 101], [165, 101], [166, 101], [167, 101], [165, 102], [166, 102]]:
			hd.set_pixel(page, p[0], p[1], dot)

		await _frame()

	blank = true
	_present()

	for i in 0x50:
		await _frame()


func _hold(count: int) -> void:

	# code 0x54fc

	for i in count:
		await _frame()
		_animate_boxes()
		_draw_boxes()
		_keeper()
		_draw_hand()


func _hand() -> void:

	# code 0x5510 : the hand comes up, then the eyes open

	hand_x = 0x106
	hand_y = 0x88
	hand_key = "f700"

	while true:
		await _frame()
		_animate_boxes()
		_draw_boxes()
		_keeper()
		_draw_hand()

		if hand_x == 0x11c:
			break

		hand_x += 2
		hand_y -= 2

	hand_key = "f990"
	await _hold(6)

	# code 0x5551 : the sound stops (the shop tune too) and effect 8

	main._stop_sound()
	main.sound_request = 8
	eyes_shut = false
	hand_key = "f700"
	await _hold(6)

	while true:
		await _frame()
		_animate_boxes()
		_draw_boxes()
		_keeper()
		_draw_hand()
		hand_x -= 2
		hand_y += 2

		if hand_x <= 0x106:
			break


# ---------------------------------------------------------------- text

func _clear_box() -> void:

	# code f29:1a88 (stub 0xc71) : on both pages

	for p in pages:
		hd.fill_rect(p, Rect2i(BOX_X, BOX_Y, BOX_WIDTH, BOX_ROWS), colours[0])


func _clear_text() -> void:

	# code 0x576d

	_clear_box()
	text_x = TEXT_X
	text_y = TEXT_Y


func _newline() -> void:

	# code 0x5829

	text_x = TEXT_X
	text_y += LINE_STEP


func _glyph(code: int) -> void:

	# code f29:1ea2 (stub 0xcf9) : a 4 by 8 glyph of the tiny font on both pages

	for p in pages:
		hd.blit_rect(p, glyphs[code - 0x20], Rect2i(0, 0, 4, 8), Vector2i(text_x * 4, text_y))

	text_x += 1


func _say(text: String) -> void:

	# code 0x5787 : one frame for each word (the shopkeeper talks), a word that does not
	# fit goes to the next line, a carriage return starts a line

	# Amiga shop $56cc0 : the keeper's voice, one of the three first samples at random on
	# channel 0, called at once. unconfirmed : the Amiga generator ($1f50) is not the PC's,
	# the remake uses one of its own.

	if main.use_amiga:
		main.amiga_sound.effect_now(0x80 + voice_random.randi_range(0, 2))

	var i := 0

	while true:
		talking = true
		_animate_boxes()
		_draw_boxes()
		_keeper()
		await _frame()

		# the result of these random numbers is not used

		while main._random() & 3 == 0:
			pass

		var length := 0
		var j := i

		while j < text.length() and text[j] != " " and text[j] != "\r":
			length += 1
			j += 1

		if length + text_x > TEXT_RIGHT:
			_newline()

		while true:
			if i >= text.length():
				talking = false
				return

			var ch := text.unicode_at(i)
			i += 1

			if ch == 0x20:
				text_x += 1

				while true:
					if i >= text.length():
						talking = false
						return

					if text.unicode_at(i) == 0x20:
						text_x += 1
						i += 1
					else:
						break

				break

			if ch == 0x0d:
				_newline()
				break

			_glyph(ch)


func _say_number(value: int) -> void:

	# code 0x57fa

	talking = true
	await _frame()
	_animate_boxes()
	_draw_boxes()
	_keeper()

	for ch in str(value):
		_glyph(ch.unicode_at(0))

	talking = false


func _credits() -> void:

	# code 0x577d, f29:1716 : 7 digits on both pages

	var rest: int = main.credits

	for k in POWERS.size():
		var digit := 0

		while rest >= POWERS[k]:
			rest -= POWERS[k]
			digit += 1

		for p in pages:
			hd.blit_rect(p, digits[mini(digit, 19)], Rect2i(0, 0, 8, 8), Vector2i(CREDITS_X + k * 8, CREDITS_Y))


# ---------------------------------------------------------------- cursor and input

func _cursor_on() -> void:

	# code 0x5435

	if row == 4:
		if col == 0:
			_sprite_both(data["sprites"]["dde0"], 4, 0xa8)
		else:
			_sprite_both(data["sprites"]["e1e8" if selling else "dfe4"], 0x2d, 0xa8)

		return

	var s: Dictionary = slots[row * 5 + col]
	_sprite_both(data["sprites"]["b282"], s["x"] + 10, s["y"] + 0x1f)


func _cursor_off() -> void:

	# code 0x5488

	if row == 4:
		if col == 0:
			_sprite_both(data["sprites"]["e3ec"], 4, 0xa8)
		else:
			_sprite_both(data["sprites"]["e7f4" if selling else "e5f0"], 0x2d, 0xa8)

		return

	var s: Dictionary = slots[row * 5 + col]
	_sprite_both(data["sprites"]["b218"], s["x"] + 10, s["y"] + 0x1f)


func _choose() -> void:

	# code 0x5369 : waits for a fire press. A direction moves the cursor, then 4 frames
	# pass before the next move. On the bottom row left and right switch the two buttons.

	while true:
		if repeat != 0:
			repeat -= 1
		else:
			if main.fire_event:

				# code 0x5429 : effect 9

				main.fire_event = false
				main.sound_request = 9

				# Amiga shop $56038 : $d

				main.amiga_2 = 0xd
				return

			var dirs := 0

			if main.held_up:
				dirs |= 1

			if main.held_down:
				dirs |= 2

			if main.held_left:
				dirs |= 4

			if main.held_right:
				dirs |= 8

			if dirs != 0:

				# code 0x538b : effect 8

				main.sound_request = 8

				# Amiga shop $55f82 : $c

				main.amiga_2 = 0xc
				repeat = 4
				_cursor_off()

				if dirs & 4:
					if row == 4:
						col = 1 if col == 0 else 0
					else:
						col -= 1

						if col < 0:
							col = 4
				elif dirs & 8:
					if row == 4:
						col = 1 if col == 0 else 0
					else:
						col += 1

						if col > 4:
							col = 0
				elif dirs & 1:
					row -= 1

					if row < 0:
						row = 4
				elif dirs & 2:
					row += 1

					if row > 4:
						row = 0

				_cursor_on()

		_keeper()
		_animate_boxes()
		_draw_boxes()
		await _frame()
		main.frame_count += 1


# ---------------------------------------------------------------- selling

func _fill_sell() -> void:

	# code 0x5119 : the launchers in list order, the base gun left out

	var i := 0

	for launcher in main.launchers:
		if launcher["kind"] == "gun":
			continue

		var s: Dictionary = slots[i]
		_set_item(s, main._launcher_item(launcher))
		s["launcher"] = launcher
		i += 1

	while i < 20:
		slots[i]["item"] = 0
		i += 1


func _all_out_of_stock() -> void:

	# code 0x4e12 : slots 0 to 18 ; the last keeps what it had

	for i in 19:
		_set_item(slots[i], OUT_OF_STOCK)


func _sell_loop() -> void:

	# code 0x5154 : choosing a box tells its price, choosing it again (or the right hand
	# button) sells it. The left hand button leaves.

	col = 0
	row = 0
	last_col = -1
	_cursor_on()
	price = -1

	while true:
		main.fire_event = false
		await _choose()
		var confirm := false

		if row == 4:
			if col == 0:
				_cursor_off()
				return

			confirm = true
		elif col == last_col and row == last_row:
			confirm = true

		if not confirm:
			var s: Dictionary = slots[row * 5 + col]

			if s["item"] == 0:
				continue

			last_col = col
			last_row = row
			brow = -1
			await _describe(s["item"], main._launcher_power(s["launcher"]))
			await _quote_sell(s)
			brow = 0
			continue

		last_col = -1

		if price < 0:
			continue

		main.credits += price
		price = -1
		_credits()
		chosen["item"] = 0
		main._remove_launcher(chosen["launcher"])
		_clear_text()
		await _say(data["messages"]["here_cash"])


func _quote_sell(s: Dictionary) -> void:

	# code 0x5240 : the hand comes down, waves and goes back, then the offer is half of
	# 2000 per power level plus the price

	chosen = s
	hand_x = 0xf7
	hand_y = 0x78
	hand_key = "f700"

	while true:
		await _frame()
		_keeper()
		_animate_boxes()
		_draw_boxes()
		_draw_hand()
		hand_y -= 2

		if hand_y <= 0x68:
			break

	await _hold(3)

	for key in ["f470", "f700", "f990", "f700", "f470", "f700", "f990", "f700"]:
		hand_key = key
		await _hold(3)

	while true:
		await _frame()
		_keeper()
		_animate_boxes()
		_draw_boxes()
		_draw_hand()
		hand_y += 2

		if hand_y >= 0x80:
			break

	await _say(data["messages"]["will_pay"])
	var power: int = main._launcher_power(s["launcher"])
	price = ((0x7d0 * power + _price(s["item"], false)) & 0xffff) >> 1
	await _say_number(price)


# ---------------------------------------------------------------- buying

func _price(item: int, halve: bool) -> int:

	# ds:0x38ce, halved in level 5 where the code halves it

	var value: int = data["items"][str(item)]["price"]

	if halve and level == 5:
		value >>= 1

	return value


func _fill_buy() -> void:

	# code 0x4d38 : from item page_start + 2 on, 19 to a page. An item above the price cap
	# of the shop or above the credits shows as out of stock. The last box is the arrow to
	# the next page, or out of stock when the next item could not be bought either.

	if _price(page_start + 1, true) > main.credits:
		page_start = 0

	var item := page_start + 2
	var i := 0

	while true:
		var s: Dictionary = slots[i]
		var value := _price(item, true)

		if value > max_price or value > main.credits:
			_set_item(s, OUT_OF_STOCK)
		else:
			_set_item(s, item)

		item += 1
		i += 1

		if item == 0x1a:
			while i != 19:
				slots[i]["item"] = 0
				i += 1

			if page_start != 0:
				_set_item(slots[19], MORE)
			else:
				slots[19]["item"] = 0

			return

		if i < 19:
			continue

		if page_start == 0:
			var next := _price(item, true)

			if next > max_price or next > main.credits:
				_set_item(slots[19], OUT_OF_STOCK)
				return

		_set_item(slots[19], MORE)
		return


func _refresh_stock() -> void:

	# code 0x4e29 : after a purchase an item the credits no longer cover goes out of stock,
	# and the arrow does too when the box before it is out of stock

	for i in 20:
		var s: Dictionary = slots[i]
		var item: int = s["item"]

		if item == 0:
			continue

		if item == MORE:
			if i > 0 and slots[i - 1]["item"] == OUT_OF_STOCK:
				_set_item(s, OUT_OF_STOCK)

			continue

		if item >= OUT_OF_STOCK:
			continue

		if _price(item, true) > main.credits:
			_set_item(s, OUT_OF_STOCK)


func _buy_loop() -> void:

	# code 0x4e78

	col = 0
	row = 0
	last_col = -1
	_cursor_on()
	price = -1

	while true:
		main.fire_event = false
		await _choose()
		var confirm := false

		if row == 4:
			if col == 0:
				_cursor_off()
				return

			confirm = true
		elif col == last_col and row == last_row:
			confirm = true

		if not confirm:
			var s: Dictionary = slots[row * 5 + col]
			var item: int = s["item"]

			if item == 0:
				continue

			if item == OUT_OF_STOCK:
				_clear_text()
				await _say(data["messages"]["out_of_stock"])
				price = -1
				continue

			if item == MORE:
				page_start += 0x13

				if page_start >= 0x19:
					page_start = 0

				_fill_buy()
				price = -1
				continue

			last_col = col
			last_row = row
			await _describe(item, 0)
			await _quote_buy(s)
			continue

		last_col = -1

		if price < 0:
			continue

		if not _has_room(chosen["item"]):
			_clear_text()
			await _say(data["messages"]["no_room"])
			price = -1
			continue

		_clear_text()
		await _say(data["messages"]["give_cash"])
		main.credits -= price

		# Amiga shop $55698 : the credits go down by 100 a frame, each with $d.
		# unconfirmed : here the sound only, the PC takes the price at once.

		amiga_pay = price / 100
		await _purchase(chosen["item"])
		price = -1
		_credits()
		_refresh_stock()

		if chosen["item"] == 2:
			continue

		await _say(data["messages"]["what_else"])


func _describe(item: int, power: int) -> void:

	# code 0x5319

	_clear_text()
	await _say(data["items"][str(item)]["text"])

	if selling and item in POWER_ITEMS:
		await _say(data["messages"]["power"])
		await _say_number(power + 1)


func _quote_buy(s: Dictionary) -> void:

	# code 0x521a

	chosen = s
	await _say(data["messages"]["will_cost"])
	price = _price(s["item"], true)
	await _say_number(price)


func _has_room(item: int) -> bool:

	# code 0x4fe3 : whether the ship can take the item

	match item:
		3:
			return main.speed_level != 2
		4, 7:
			return main.energy != 0x27
		5:
			return main.autofire_rate != 3
		6:
			return main.nashwan == 0
		0xc:

			# The loop steps 6 bytes through slots of 4 (ds:0x9134), so it reads as meant
			# only the front slot, side slot 3 and the outer slot. The other reads use a
			# slot type, the score or the credits as a pointer into the low data segment,
			# which is all zero in XENON2.EXE, so they never count : a rear weapon below
			# its maximum is not seen. unconfirmed : that the low data segment stays zero,
			# and the last read (pointer = credits, only while the shown score is 65536 or
			# more).

			for slot in [0, 3, 6]:
				var launcher: Variant = main.weapon_slots[slot]

				if launcher != null and launcher["level"] != launcher["max"]:
					return true

			return false
		0x10:
			return main.dive == 0
		0x16:
			return main.lives != 9
		0x18:
			return not main.protection
		0x19:
			return main.shades == 0

	var flags: int = data["items"][str(item)]["flags"]

	if flags & 1:

		# the front slot : the same weapon below its maximum, or room when the slot is empty
		# or holds the base gun. unconfirmed : an empty front slot (sold in this shop) is
		# read through its old launcher pointer, taken as room here.

		var front: Variant = main.weapon_slots[0]

		if front == null:
			return true

		if front["item"] == item:
			return front["level"] != front["max"]

		return front["type"] == 0x94

	if flags & 2:

		# a free side slot (0x100e)

		return main._free_cannon_slot() != 0

	if flags & 4:

		# the rear slot (ds:0x9148) : empty, or the same weapon below its maximum

		return _slot_room(main.weapon_slots[5], item)

	if flags & 0x10:

		# room when the outer or the rear slot is empty

		return main.weapon_slots[6] == null or main.weapon_slots[5] == null

	if flags & 8:

		# the outer slot (ds:0x914c) : empty, or the same weapon below its maximum

		return _slot_room(main.weapon_slots[6], item)

	return true


func _slot_room(launcher: Variant, item: int) -> bool:
	if launcher == null:
		return true

	return launcher["item"] == item and launcher["level"] != launcher["max"]


func _purchase(item: int) -> void:

	# the purchase routines of ds:0x381a

	match item:
		2:

			# code 0x4f9d : the advice of this level, one more each time up to the third

			wink = 0xc
			_clear_text()
			var index: int = ((level - 1) * 0x18 + main.advice_step) >> 2

			if main.advice_step != 8 and main.advice_step != 0x14:
				main.advice_step += 4

			await _say(data["advice"][index])
			wink = 0
		_:
			main._buy_item(item)


# ---------------------------------------------------------------- drawing

func _picture(path: String) -> Image:
	var image: Image = load(path).get_image()
	image.convert(Image.FORMAT_RGBA8)
	return hd.source(image, path)


func _image(key: String) -> Image:

	# the common sprites are saved with their own palette : the shop draws them with its
	# palette (ds:0x427d), so each colour is mapped by its index

	if images.has(key):
		return images[key]

	var path := "res://assets/sprites/%s.png" % key
	var image: Image = load(path).get_image()
	image.convert(Image.FORMAT_RGBA8)
	var set_name := key.get_slice("/", 0)

	if set_name == "SHOP" or not data["sprite_palettes"].has(set_name):
		hd.source(image, path)
	else:
		var source: Array = data["sprite_palettes"][set_name]
		var map := {}
		var from: Array = []
		var to: Array = []

		for i in 16:
			var c: Array = source[i]
			var rgb := (int(c[0]) << 16) | (int(c[1]) << 8) | int(c[2])
			from.append(Color8(int(c[0]), int(c[1]), int(c[2])))
			to.append(colours[i])

			if not map.has(rgb):
				map[rgb] = colours[i]

		hd.recoloured(image, path, from, to)

		for y in image.get_height():
			for x in image.get_width():
				var p := image.get_pixel(x, y)

				if p.a < 0.5:
					continue

				var rgb := (p.r8 << 16) | (p.g8 << 8) | p.b8

				if map.has(rgb):
					image.set_pixel(x, y, map[rgb])

	images[key] = image
	return image


func _sprite(key: String, x: int, y: int, page: int = -1) -> void:

	# code f29:02f5 (stub 0x875) : at the position minus the hot spot, left out when it
	# starts at x 320 or at the bottom clip line or below, rows below the clip line cut

	var h: Array = main.headers[key]
	var left: int = x - h[4]
	var top: int = y - h[5]
	var width: int = h[6]
	var height: int = h[7]

	if left >= 320 or top >= clip or left + width <= 0 or top + height - 1 < 0:
		return

	var last := mini(top + height - 1, clip)
	var sx := 0
	var sy := 0

	if top < 0:
		sy = -top
		top = 0

	if left < 0:
		sx = -left
		left = 0

	var w := mini(width - sx, 320 - left)
	var rows := last - top + 1

	if w <= 0 or rows <= 0:
		return

	var target: Image = pages[draw_page if page < 0 else page]
	hd.blend_rect(target, _image(key), Rect2i(sx, sy, w, rows), Vector2i(left, top))


func _sprite_both(key: String, x: int, y: int) -> void:

	# code f29:19ce (stub 0xc2d) : on the page being drawn and on the one shown

	_sprite(key, x, y, draw_page)
	_sprite(key, x, y, draw_page ^ 1)


func _strip(source: Image, first_row: int, rows: int, y: int) -> void:

	# code f29:1d01 : 112 pixel rows from x 208, the first 7 and the last 8 left out

	if rows <= 0:
		return

	hd.blit_rect(pages[draw_page], source, Rect2i(STRIP_LEFT, first_row, STRIP_WIDTH, rows), Vector2i(STRIP_X + STRIP_LEFT, y))


func _noise(x: int, y: int) -> void:

	# code f29:1e00 (stub 0xcd7) : 28 rows of 32 pixels, each row the 8 bits of the high
	# byte of a random number repeated, 1 in colour 7 and 0 in colour 0

	var target: Image = pages[draw_page]

	for r in 28:
		var bits: int = (main._random() >> 8) & 0xff

		for j in 32:
			hd.set_pixel(target, x + j, y + r, colours[7] if (bits >> (7 - (j & 7))) & 1 else colours[0])


func _background() -> void:

	# code f29:1955 (stub 0xc0b) : the page cleared, the pipes and the bottom panel copied
	# (table at cs:0x1f4c), the empty box frames in a 5 by 4 grid, 41 pixels apart, then
	# the page copied to the other one

	var target: Image = pages[draw_page]
	hd.fill(target, colours[0])
	var places := [Vector2i(192, 9), Vector2i(304, 9), Vector2i(192, 0), Vector2i(192, 105), Vector2i(224, 182)]

	for i in 5:
		hd.blit_rect(target, pipes[i], Rect2i(Vector2i.ZERO, pipes[i].get_size()), places[i])

	hd.blit_rect(target, bottom, Rect2i(Vector2i.ZERO, bottom.get_size()), Vector2i(0, 164))

	for y in range(0, 0xa4, 0x29):
		for x in range(0, 0xcd, 0x29):
			_sprite(data["sprites"]["ec90"], x, y)
			_sprite(data["sprites"]["efc0"], x, y)

	hd.copy_from(pages[draw_page ^ 1], target)
