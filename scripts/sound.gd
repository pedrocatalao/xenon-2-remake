class_name SpeakerSound
extends Node

# Port of the PC speaker driver of XENON2.EXE (segment 0x14b9, interrupt 0x80, by David
# Whittaker). It runs on a copy of its own segment (data/sound.bin from tools/x2sound.py),
# so every address below is the one the driver uses : variables at cs:0x22 to 0x2f, the
# two music voices at cs:0x100 and cs:0x118 (0x18 bytes each), the sound effect at
# cs:0x40d to 0x41e, effects at cs:0x420 (15 bytes each), the period table at cs:0x54,
# the envelopes at cs:0x5b4, the instruments at cs:0x4e6, the tunes at cs:0x5e2.
#
# The timer interrupt (0x600b) calls the driver every 0x5555 PIT counts (54.6 times a
# second) and every third time, after it, starts the sound effect the game asked for
# (ds:0x8e8a first, else ds:0x8e88). The driver gives one PIT count a call for the speaker
# (channel 2, square wave), 2 being out of hearing.

const PIT_HZ := 1193182.0
const INTERRUPT_COUNTS := 0x5555
const MIX_RATE := 44100.0
const VOLUME := 0.2

# command bytes 0x80 to 0x8c of a voice (jump table at cs:0x30)

const ABORT := -1

var mem := PackedByteArray()
var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var period := 0
var phase := 0.0
var pending := 0.0
var recording := PackedFloat32Array()
var record := false


func _ready() -> void:
	mem = FileAccess.get_file_as_bytes("res://data/sound.bin")

	# code 0x52c : interrupt 0x80, function 0x22, sets cs:0x24 to 0x16

	call_driver(0x22, 0x16)

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.25
	player = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	playback = player.get_stream_playback()


func game_tick(request: int) -> void:

	# one game tick is three timer interrupts (0x600b) : the driver runs on each, the
	# requested effect starts after the third

	for i in 3:
		_interrupt()

		if i == 2 and request != 0:
			call_driver(3, request)


# ---------------------------------------------------------------- memory

func _b(a: int) -> int:
	return mem[a & 0xffff]


func _sb(a: int, v: int) -> void:
	mem[a & 0xffff] = v & 0xff


func _w(a: int) -> int:
	return mem[a & 0xffff] | (mem[(a + 1) & 0xffff] << 8)


func _sw(a: int, v: int) -> void:
	mem[a & 0xffff] = v & 0xff
	mem[(a + 1) & 0xffff] = (v >> 8) & 0xff


# ---------------------------------------------------------------- driver

func call_driver(function: int, value: int) -> int:

	# cs:0x0000 : functions 0 to 4 by the table at cs:0x4a, above 0x1f a variable set
	# (cs:0x22 + function - 0x20), 0x11 to 0x1f a variable read (cs:0x22 + function - 0x10)

	if function > 0x10:
		if function >= 0x20:
			_sb(0x22 + function - 0x20, value)
			return value

		return _b(0x22 + function - 0x10)

	match function:
		0:
			_tick()
		1:
			_stop()
		2:
			_start_tune(value)
		3:
			_start_effect(value)
		4:

			# cs:0x375 : the tune goes on again if one was playing

			if _b(0x29) != 0:
				_sb(0x22, 0xff)

	return 0


func _stop() -> void:

	# cs:0x36c

	_sb(0x23, 0)
	_sb(0x22, 0)


func _start_tune(number: int) -> void:

	# cs:0x145 : 9 bytes a tune at cs:0x5e2 (speed, then for each voice its order list and
	# the list's length and loop point)

	var bx := (_signed8(number) * 9) & 0xffff
	_sb(0x22, 0)
	_sb(0x29, 0)
	_sb(0x28, 0)

	for i in 0x30:
		_sb(0x100 + i, 0)

	_sb(0x25, _b(bx + 0x5e2))
	_sb(0x26, _b(bx + 0x5e2))
	_sb(0x27, 0xff)
	_voice(0x100, bx)
	_voice(0x118, bx + 4)
	_sb(0x22, 0xff)
	_sb(0x29, 0xff)


func _voice(di: int, bx: int) -> void:

	# cs:0x18c

	_sw(di + 4, _w(bx + 0x5e5))
	var order := _w(bx + 0x5e3)
	_sw(di, order)
	_sw(di + 2, _w(order))
	_sb(di + 6, 1)


func _start_effect(number: int) -> void:

	# cs:0x1a3 : 15 bytes copied to cs:0x410, the two counters loaded, the effect on

	var bx := (0x420 + _signed8(number) * 15) & 0xffff
	_sb(0x23, 0)

	for i in 15:
		_sb(0x410 + i, _b(bx + i))

	_sw(0x40d, _w(0x41d))
	_sb(0x23, 0xff)


func _signed8(v: int) -> int:
	return v - 0x100 if v & 0x80 else v


func _tick() -> void:

	# cs:0x1c7 : the tune skips one call in 256 / cs:0x24 (the speaker is silent then
	# unless an effect plays), steps its voices when cs:0x27 overflows, then each voice
	# gives a period. Voice 0 sounds while its count (+0xa) lasts, voice 1 where the bits
	# of its pattern (+0xa) are set. The effect, when on, takes the speaker on the calls
	# its gate bits (cs:0x41b) are clear.

	var cx := 2
	var sum := _b(0x28) + _b(0x24)
	_sb(0x28, sum)

	if sum <= 0xff and _b(0x22) != 0:
		sum = _b(0x27) + _b(0x25)
		_sb(0x27, sum)

		if sum > 0xff:
			if _step(0x100) == ABORT:
				return

			if _step(0x118) == ABORT:
				return

		cx = _pitch(0x100)
		_sw(0x2e, cx)
		cx = _pitch(0x118)
		var ax := 2

		if _b(0x10a) != 0:
			_sb(0x10a, _b(0x10a) - 1)
			ax = _w(0x2e)

		var bit := _b(0x122) & 1
		_sb(0x122, _b(0x122) >> 1)

		if bit == 0:
			cx = ax

	if _b(0x23) != 0:
		var playing := true

		if _b(0x41c) != 0:
			_sb(0x41c, _b(0x41c) - 1)

			if _b(0x41c) == 0:
				_sb(0x23, 0)
				playing = false

		if playing:
			var al := _b(0x41d)
			var ah := _b(0x41e)
			_sb(0x40e, _b(0x40e) - 1)

			if _b(0x40e) == 0:
				_sb(0x40e, ah)
				var carry := _ror(0x41a)
				_sw(0x412, _w(0x412) + (_w(0x416) if carry else _w(0x418)))

			var dx := (_w(0x412) + _w(0x410)) & 0xffff
			_sb(0x40d, _b(0x40d) - 1)

			if _b(0x40d) == 0:
				_sb(0x40d, al)
				dx = _w(0x414)

			_sw(0x412, dx)

			if not _ror(0x41b):
				cx = dx

	# cs:0x270 : the PIT is written only when the count changes, the speaker stays on

	_sw(0x2c, cx)
	period = cx


func _ror(a: int) -> bool:

	# ror byte, 1 : returns the carry (the old bit 0)

	var v := _b(a)
	var carry := v & 1
	_sb(a, (v >> 1) | (carry << 7))
	return carry == 1


func _step(di: int) -> int:

	# cs:0x2fb : a voice's note count runs out, then bytes are read from its pattern :
	# 0xe0 and up a length, 0xa0 to 0xdf an instrument (envelope start), 0x80 to 0x8c a
	# command, below 0x80 a note. While a note lasts, flag 0x40 slides it by a semitone a
	# call (down with 0x80).

	var dl := _b(di + 0x12)
	_sb(di + 6, _b(di + 6) - 1)

	if _b(di + 6) != 0:
		if dl & 0x40:
			if dl & 0x80:
				_sb(di + 0x16, _b(di + 0x16) - 1)
			else:
				_sb(di + 0x16, _b(di + 0x16) + 1)

		return 0

	dl &= 0x30
	var si := _w(di + 2)

	while true:
		var al := _b(si)
		si += 1

		if al >= 0xa0:
			if al >= 0xe0:
				_sb(di + 7, al + 0x20 + 1)
			else:
				_sb(di + 9, _b(0x4e6 + ((al + 0x20) & 0xff)))

			continue

		if al < 0x80:

			# cs:0x346 : a note

			_sw(di + 0xc, 0)
			_sb(di + 0x12, dl)
			_sb(di + 0x16, al)

			if dl & 4 == 0:
				_sw(di + 0xa, _w(di + 8))

			break

		match al - 0x80:
			0:

				# cs:0x341 : a rest (voice 0 count or voice 1 pattern 0)

				_sb(di + 0xa, 0)
				break
			1:

				# cs:0x2ef : flags cleared

				dl = 0
			2:

				# cs:0x2b9 : a slide, step word and delay byte

				_sw(di + 0x14, _w(si))
				si += 2
				dl |= 8
				_sb(di + 0xe, _b(si))
				si += 1
			3:

				# cs:0x2e7 : semitone slide down

				dl |= 0xc0
			4:

				# cs:0x2ea : semitone slide up

				dl |= 0x40
			5:

				# cs:0x28d : the next pattern of the order list, back to the loop point at its
				# end

				var bl := (_b(di + 0x13) + 2) & 0xff

				if _b(di + 4) == bl:
					bl = _b(di + 5)

				si = _w(_w(di) + bl)
				_sb(di + 0x13, bl)
			6:

				# cs:0x2cc : vibrato, speed and depth

				_sb(di + 0x10, _b(si))
				si += 1
				var depth := _b(si)
				si += 1
				_sb(di + 0x11, depth)
				_sb(di + 0xf, depth << 1)
				dl |= 0x10
			7:

				# cs:0x366 : the tune ends. The return address is dropped, so the rest of
				# this call (effect and speaker) is skipped.

				_sb(0x29, 0)
				_sb(0x23, 0)
				_sb(0x22, 0)
				return ABORT
			8:

				# cs:0x2a9 : voice transpose

				_sb(di + 0x17, _b(si))
				si += 1
			9:

				# cs:0x2e2 : every other call silent

				dl |= 2
			10:

				# cs:0x2f3 : count or pattern for the next notes

				_sb(di + 8, _b(si))
				si += 1
			11:

				# cs:0x2a4 : tie, the next note keeps the envelope

				dl |= 4
			12:

				# cs:0x2b1 : transpose of the whole tune

				_sb(0x2a, _b(si))
				si += 1
			_:

				# the jump table has 13 entries, the tunes use no other command

				push_error("sound : command %x at %x" % [al, si - 1])
				break

	# cs:0x35c

	_sb(di + 6, _b(di + 7))
	_sw(di + 2, si)
	return 0


func _pitch(di: int) -> int:

	# cs:0x382 : the envelope byte (cs:0x5b4) plus the note and both transposes gives the
	# period. Envelope bytes from 0x80 go back to the instrument's start (offset by the
	# byte), 0xff holds. Then vibrato (flag 0x10), slide (flag 8), and silence on the
	# calls where flags 1 and 2 are both set.

	var bl := (_b(di + 0xb) + 1) & 0xff
	var al := _b(0x5b4 + bl)

	if al < 0x80:
		_sb(di + 0xb, bl)
	else:
		al = (al + 1) & 0xff

		if al != 0:
			al = (al + 0x7f) & 0xff
			_sb(di + 0xb, _b(di + 9))

	al = (al + _b(di + 0x16) + _b(0x2a) + _b(di + 0x17)) & 0xff
	al = (al << 1) & 0xff
	var cx := _w(0x54 + al)
	var flags := _b(di + 0x12) ^ 1

	if flags & 0x10:
		var step := _b(di + 0x10)

		if step == 0:
			step = 1 & flags

		var ah := _b(di + 0x11)
		var top := _b(di + 0xf)
		var turn := false

		if flags & 0x20:
			ah = (ah + step) & 0xff
			turn = ah == top
		else:
			ah = (ah - step) & 0xff
			turn = ah == 0

		if turn:
			flags ^= 0x20

		_sb(di + 0x11, ah)
		var delta := ah - (top >> 1)
		cx = (cx + (delta & 0xffff)) & 0xffff

	if flags & 8:
		_sb(di + 0xe, _b(di + 0xe) - 1)

		if _b(di + 0xe) == 0:
			_sb(di + 0xe, 1)
			var ax := (_w(di + 0x14) + _w(di + 0xc)) & 0xffff
			_sw(di + 0xc, ax)
			cx = (cx + ax) & 0xffff

	_sb(di + 0x12, flags)

	if (~flags) & 3 == 0:
		cx = 2

	return cx


# ---------------------------------------------------------------- speaker

func _interrupt() -> void:

	# the driver call, then the speaker's square wave for one interrupt period. A period
	# of 0 is 65536 counts. Tones above half the mix rate (period 2 and the like) are
	# silent here, as the speaker cannot follow them.

	_tick()
	pending += MIX_RATE * INTERRUPT_COUNTS / PIT_HZ
	var count := int(pending)
	pending -= count
	var counts := 65536 if period == 0 else period
	var frequency := PIT_HZ / counts
	var audible := frequency < MIX_RATE / 2
	var step := frequency / MIX_RATE
	var frames := PackedVector2Array()
	frames.resize(count)

	for i in count:
		var v := 0.0

		if audible:
			v = VOLUME if phase < 0.5 else -VOLUME
			phase += step
			phase -= floor(phase)

		frames[i] = Vector2(v, v)

		if record:
			recording.append(v)

	if playback != null and playback.can_push_buffer(count):
		playback.push_buffer(frames)


func save_wav(path: String) -> void:

	# test option : the recorded speaker as 16 bit mono

	var data := PackedByteArray()
	data.resize(recording.size() * 2)

	for i in recording.size():
		data.encode_s16(i * 2, int(recording[i] * 32767))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.data = data
	wav.save_to_wav(path)
