class_name AmigaSound
extends Node

# Port of the Amiga sound player of Xenon 2 (David Whittaker, Paula), from the unpacked
# game program on disk 1 (tools/x2amiga.py, data/amiga_sound.bin). Addresses below are
# those of the unpacked image loaded at $30000 (the player's base a3 = $49b9e; the game
# itself runs at $400, where the same player is at $19f9e). The player runs on its own
# memory image : variables, four music voices at $4a196 ($30 bytes each), instruments at
# $4a338 (12 bytes), tunes at $4a428, the period table at $4a256, the effect voices at
# $4b2d0 ($24 bytes), the music voices' copies of the hardware at $4b362 (12 bytes), the
# synthesised effects at $4b392, the sampled effects at $4af52 (16 bytes) and the two sample
# banks from $4b780.
#
# The game's vertical blank interrupt ($20c2, 50 times a second) starts the effects asked
# for at $414 (on channel 2) and $418 (on channel 1), then calls the player ($19fac). Paula
# plays each channel's sample at the channel's period, channels 0 and 3 left, 1 and 2 right.

const BASE := 0x49b00
const A3 := 0x49b9e
const PAULA_HZ := 3546895.0
const VBLANK_HZ := 50.0
const MIX_RATE := 44100.0
const GAIN := 0.25

const VOICES := 0x4a196
const PERIODS := 0x4a256
const SAMPLE_FX := 0x4af52

# the layout of the game's player (data/amiga_sound.bin). The intro music of the original
# release (data/amiga_intro_music.bin, use_intro_music) is the same player built with a
# larger sample bank : 39 instruments, so the tunes, envelopes, shadow registers and effect
# voices sit further on.

var SHADOW := 0x4b362
var EFFECTS := 0x4b2d0
var TUNES := 0x4a428
var ENVELOPES := 0x4b65c
var BANK := 0x4b780
var BANK_COUNT := 20
var SILENT_LINK := 0x1a1c
var PATCHES := [[0x828, 2], [0x7e0, 8], [0x7ec, 8], [0x7f8, 2]]
var music_only := false

# the order list entry a tune starts and loops from (in bytes, 2 a word) : 0 for the game's
# player. The full music skips its first entry, the 14.6 s introduction of the loading
# screen, so it starts with the beat like the game's and loops back there.

var FIRST_ENTRY := 0

var mem := PackedByteArray()
var mem_base := BASE

# the shop's own player (shop_sound) : its memory from $6476e, the game's kept aside

const SHOP_BASE := 0x6476e
const SHOP_VOICES := 0x64d4c
const SHOP_SYNTH := 0x64e0e
const SHOP_SAMPLES := 0x64aae
const SHOP_BANK := 0x650da

var shop_mem := PackedByteArray()
var game_mem := PackedByteArray()
var shop_mode := false
var shop_wave := 0
var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var pending := 0.0
var vblank_debt := 0.0
var recording := PackedFloat32Array()
var record := false

# Paula : registers and the running DMA of each channel

var lc := [0, 0, 0, 0]
var len_words := [0, 0, 0, 0]
var per := [0x7c, 0x7c, 0x7c, 0x7c]
var vol := [0, 0, 0, 0]
var dma := [false, false, false, false]
var ptr := [0, 0, 0, 0]
var left := [0, 0, 0, 0]
var phase := [0.0, 0.0, 0.0, 0.0]

# the game's effect requests ($414 and $418, -1 when none)

var request_2 := -1
var request_1 := -1


func _init() -> void:
	mem = FileAccess.get_file_as_bytes("res://data/amiga_sound.bin")

	if FileAccess.file_exists("res://data/amiga_shop_sound.bin"):
		shop_mem = FileAccess.get_file_as_bytes("res://data/amiga_shop_sound.bin")


func use_intro_music() -> bool:

	# the intro music of the original release (disk 1 of the PNA or QTX dumps : a second
	# copy of the player at disk offset $d772, image base $49b00, tunes at $4a50c, 39
	# instruments from $4b70a). Music only : the effects stay with the game's player.

	if not FileAccess.file_exists("res://data/amiga_intro_music.bin"):
		return false

	mem = FileAccess.get_file_as_bytes("res://data/amiga_intro_music.bin")
	SHADOW = 0x4b2f6
	EFFECTS = 0x4b264
	TUNES = 0x4a50c
	ENVELOPES = 0x4b5e6
	BANK = 0x4b70a
	BANK_COUNT = 39
	SILENT_LINK = 0x19b0
	PATCHES = [[0x7bc, 5], [0x8b8, 2], [0x8c4, 3], [0x828, 8], [0x834, 8], [0x840, 2]]
	FIRST_ENTRY = 2
	music_only = true
	return true


func _ready() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.25
	player = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	playback = player.get_stream_playback()


# ---------------------------------------------------------------- memory (big endian)

func _b(a: int) -> int:
	var i := a - mem_base
	return mem[i] if i >= 0 and i < mem.size() else 0


func _sbyte(a: int) -> int:
	var v := _b(a)
	return v - 0x100 if v & 0x80 else v


func _sb(a: int, v: int) -> void:
	var i := a - mem_base

	if i >= 0 and i < mem.size():
		mem[i] = v & 0xff


func _w(a: int) -> int:
	return (_b(a) << 8) | _b(a + 1)


func _sw16(a: int) -> int:
	var v := _w(a)
	return v - 0x10000 if v & 0x8000 else v


func _sw(a: int, v: int) -> void:
	_sb(a, v >> 8)
	_sb(a + 1, v)


func _l(a: int) -> int:
	return (_w(a) << 16) | _w(a + 2)


func _sl(a: int, v: int) -> void:
	_sw(a, (v >> 16) & 0xffff)
	_sw(a + 2, v & 0xffff)


func _signed32(v: int) -> int:
	v &= 0xffffffff
	return v - 0x100000000 if v & 0x80000000 else v


# ---------------------------------------------------------------- the game side

func start_tune(number: int, volume_byte: int) -> void:

	# $19f9e (game $7894 and the like) : the tune, then the game writes a byte at $1a584,
	# the high byte of the player's master volume word ($4a184 here)

	_init_tune(number)
	_sb(0x4a184, volume_byte)


func music_playing() -> bool:

	# the tune runs ($5f0 set by $49bfc, cleared by $49c9a and $4a0d8)

	return not shop_mode and _b(A3 + 0x5f0) != 0


func channel_busy(ch: int) -> bool:

	# an effect plays on the channel (its +$1a, game $1b732 for channel 2)

	return _b(EFFECTS + 0x24 * ch + 0x1a) != 0


func stop() -> void:

	# $19fba (game) : $49c9a. In the shop $6478a : every voice off, DMA and volumes off.

	if shop_mode:
		_shop_stop_all()
		return

	_stop()


func vblank_ticks(seconds: float) -> void:

	# the time of one game tick, in vertical blanks, each with its sound

	vblank_debt += seconds * VBLANK_HZ

	while vblank_debt >= 1.0:
		vblank_debt -= 1.0
		_vblank()


func _vblank() -> void:

	# game $215e : $414 on channel 2, $418 on channel 1, then the player

	if request_2 >= 0:
		effect_now(request_2 | 0x200)
		request_2 = -1

	if request_1 >= 0:
		effect_now(request_1 | 0x100)
		request_1 = -1

	if shop_mode:
		_shop_tick()
	else:
		_tick()
	_mix(MIX_RATE / VBLANK_HZ)


func effect_now(value: int) -> void:

	# the effect routine of the vector $2094 : the game's ($19fd6) or in the shop the shop's
	# ($647a6), the channel in the high byte

	if music_only:
		return

	if shop_mode:
		_shop_effect(value)
	else:
		_effect(value)


# ---------------------------------------------------------------- the shop's player

func shop_sound(on: bool) -> void:

	# shop $54e0c : the vectors $2090 and $2094 to the shop's player ; $5502a and $55036 at
	# its end : its voices off ($6478a), the game's player back. The game's memory, with its
	# player's state, is kept aside meanwhile.

	if on == shop_mode or shop_mem.is_empty():
		return

	_dma_off(0xf)

	if on:
		game_mem = mem
		mem = shop_mem
		mem_base = SHOP_BASE
		shop_mode = true
		_shop_stop_all()

		# $6492a, once : the first sample of the bank, the waveforms $40 bytes after it
		# ($8c8(a3))

		shop_wave = SHOP_BANK + 6 + _l(SHOP_BANK) + 0x40
		_shop_samples()
	else:
		_shop_stop_all()
		mem = game_mem
		mem_base = BASE
		shop_mode = false


func _shop_samples() -> void:

	# $64972, once : the four sampled effects from the bank + $f42, each {length, rate,
	# data}, into the table $64aae (16 bytes) : pointer, no loop (-1, set in the file),
	# length in words, period 3579545 / rate, frames = length * 50 / rate + 1

	var a0 := SHOP_BANK + 0xf42

	for i in 4:
		var a5 := SHOP_SAMPLES + 0x10 * i
		var length := _l(a0)
		var rate := _w(a0 + 4)
		_sb(a5 + 0xc, (length & 0xffff) * 0x32 / rate + 1)
		_sl(a5, a0 + 6)
		_sw(a5 + 8, length >> 1)
		_sw(a5 + 0xa, 0x369e99 / rate)
		a0 += 6 + length


func _shop_stop_all() -> void:

	# $647ce : the voices off, DMA off, volumes 0

	for ch in 4:
		_sb(SHOP_VOICES + 0x24 * ch + 0x1a, 0)
		vol[ch] = 0

	_dma_off(0xf)


func _shop_effect(value: int) -> void:

	# $649c6 : the channel is the high byte, the effect the low byte. 0 to $7f a synthesised
	# effect ($64a2e, $18 bytes from $64e0e), $80 and above a sample ($64aee).

	value &= 0x3ff
	var ch := value >> 8
	var n := value & 0xff
	var a1 := SHOP_VOICES + 0x24 * ch
	var mask := 1 << ch

	if n >= 0x80:
		_shop_sample(ch, a1, mask, n)
		return

	len_words[ch] = 1
	per[ch] = 0x7c
	_dma_off(mask)
	var a0 := SHOP_SYNTH + n * 0x18

	for i in 0x18:
		_sb(a1 + i, _b(a0 + i))

	len_words[ch] = _w(a1 + 0x16)
	_sb(a1 + 0x18, _b(a1 + 0xe))
	_sb(a1 + 0x19, _b(a1 + 0xf))
	_sb(a1 + 0x1b, 1)

	# the volume curve : a word offset from a3 in the table at a3 + $8cc

	var curve := _sw16(SHOP_BASE + 0x8cc + 2 * _sbyte(a1 + 0x14))
	_sl(a1 + 0x1c, SHOP_BASE + curve)
	_sb(a1 + 0x1a, 0xff)


func _shop_sample(ch: int, a1: int, mask: int, n: int) -> void:

	# $64aee : the sample plays once, its frames counted in +$12, then the channel goes on
	# with the silence at $0 (the long at $6485a), $20 words

	_sb(a1 + 0x15, n)
	_dma_off(mask)
	per[ch] = 0x7c
	len_words[ch] = 1
	var a0 := SHOP_SAMPLES + 0x10 * (n & 0x7f)
	_sb(a1 + 0x12, _b(a0 + 0xc))

	if _b(a0 + 0xd) != 0:
		_sb(a1 + 0x12, 0)

	len_words[ch] = _w(a0 + 8)
	lc[ch] = _l(a0)
	per[ch] = _w(a0 + 0xa)
	_sw(a1 + 0x20, _w(a0 + 0xa))
	_sw(a1 + 0x22, _w(a0 + 0xa))
	vol[ch] = 0x40
	_dma_on(mask)
	_sb(a1 + 0x1a, 0xff)
	var loop := _signed32(_l(a0 + 4))

	if loop < 0:
		lc[ch] = _l(0x6485a)
		len_words[ch] = 0x20
	else:
		lc[ch] = _l(a0) + loop
		len_words[ch] = _w(a0 + 8) - (loop >> 1)


func _shop_tick() -> void:

	# $64bbc : each voice still playing

	for ch in 4:
		var a1 := SHOP_VOICES + 0x24 * ch

		if _b(a1 + 0x1a) != 0:
			_shop_voice(ch, a1, 1 << ch)


func _shop_voice(ch: int, a1: int, mask: int) -> void:

	# $64c1e : the frames left (+$12, 0 for none) end the effect

	if _b(a1 + 0x12) != 0:
		_sb(a1 + 0x12, _b(a1 + 0x12) - 1)

		if _b(a1 + 0x12) == 0:
			_shop_end(a1, mask)
			return

	# $64c72 : a sample only moves its period by +$e of its table entry, below $7c it ends

	if _b(a1 + 0x15) != 0:
		var a2 := SHOP_SAMPLES + 0x10 * (_b(a1 + 0x15) & 0x7f)
		var period := _w(a1 + 0x22)
		var delta := _w(a2 + 0xe)

		if delta == 0:
			per[ch] = period
			return

		period = (period + delta) & 0xffff

		if period < 0x7c:
			_shop_end(a1, mask)
			return

		_sw(a1 + 0x22, period)
		per[ch] = period
		return

	# $64caa : the vibrato, every +$f frames one of the two words of +4 (by the bits of
	# +$10 turning) added to the period

	if _b(a1 + 0xf) != 0:
		_sb(a1 + 0x19, _b(a1 + 0x19) - 1)

		if _b(a1 + 0x19) == 0:
			_sb(a1 + 0x19, _b(a1 + 0xf))
			var turn := _ror(_b(a1 + 0x10))
			_sb(a1 + 0x10, turn[0])
			var add: int = _w(a1 + 6) if turn[1] else _w(a1 + 4)
			_sw(a1 + 8, _w(a1 + 8) + add)

	# the slide (+0) every frame, and back to +2 every +$e frames

	_sw(a1 + 8, _w(a1 + 8) + _w(a1))

	if _b(a1 + 0xe) != 0:
		_sb(a1 + 0x18, _b(a1 + 0x18) - 1)

		if _b(a1 + 0x18) == 0:
			_sb(a1 + 0x18, _b(a1 + 0xe))
			_sw(a1 + 8, _w(a1 + 2))

	# the volume curve every +$13 frames : 0 ends the effect, a negative byte holds

	_sb(a1 + 0x1b, _b(a1 + 0x1b) - 1)

	if _b(a1 + 0x1b) == 0:
		_sb(a1 + 0x1b, _b(a1 + 0x13))
		var at := _l(a1 + 0x1c)
		var level := _sbyte(at)

		if level == 0:
			_shop_end(a1, mask)
			return

		if level > 0:
			_sl(a1 + 0x1c, at + 1)
			vol[ch] = level

	# the period, at least $7c (signed compare), and the waveform : one of the two words of
	# +$a (by the bits of +$11) from the waveforms

	var period := _sw16(a1 + 8)
	per[ch] = maxi(period, 0x7c)
	var turn := _ror(_b(a1 + 0x11))
	_sb(a1 + 0x11, turn[0])
	var offset: int = _sw16(a1 + 0xc) if turn[1] else _sw16(a1 + 0xa)
	lc[ch] = shop_wave + offset
	_dma_on(mask)


func _shop_end(a1: int, mask: int) -> void:

	# $64c2a : the voice off and its DMA

	_sb(a1 + 0x1a, 0)
	_dma_off(mask)


func _ror(value: int) -> Array:

	# ror.b #1 : the new byte and the carry (the bit that went round)

	var carry := value & 1
	return [((value >> 1) | (carry << 7)) & 0xff, carry == 1]


# ---------------------------------------------------------------- Paula

func _dma_on(mask: int) -> void:
	for ch in 4:
		if mask & (1 << ch) and not dma[ch]:
			dma[ch] = true
			ptr[ch] = lc[ch]
			left[ch] = (len_words[ch] if len_words[ch] != 0 else 0x10000) * 2
			phase[ch] = 0.0


func _dma_off(mask: int) -> void:
	for ch in 4:
		if mask & (1 << ch):
			dma[ch] = false


func _mix(frames_float: float) -> void:
	pending += frames_float
	var count := int(pending)
	pending -= count
	var out_l := PackedFloat32Array()
	var out_r := PackedFloat32Array()
	out_l.resize(count)
	out_r.resize(count)
	var size := mem.size()

	for ch in 4:
		if not dma[ch]:
			continue

		# AUDxVOL : 0 to 64, bit 6 alone gives 64

		var level: int = vol[ch] & 0x7f
		level = 64 if level & 0x40 else level
		var scale := GAIN * level / (64.0 * 128.0)
		var p: int = per[ch] if per[ch] >= 0x7c else 0x7c
		var step := PAULA_HZ / p / MIX_RATE
		var f: float = phase[ch]
		var at: int = ptr[ch] - mem_base
		var rest: int = left[ch]
		var to_left := ch == 0 or ch == 3

		for i in count:
			var v := 0

			if at >= 0 and at < size:
				v = mem[at]

				if v >= 0x80:
					v -= 0x100

			if to_left:
				out_l[i] += v * scale
			else:
				out_r[i] += v * scale

			f += step

			while f >= 1.0:
				f -= 1.0
				at += 1
				rest -= 1

				if rest <= 0:
					at = lc[ch] - mem_base
					rest = (len_words[ch] if len_words[ch] != 0 else 0x10000) * 2

		phase[ch] = f
		ptr[ch] = at + mem_base
		left[ch] = rest

	var frames := PackedVector2Array()
	frames.resize(count)

	for i in count:
		frames[i] = Vector2(out_l[i], out_r[i])

		if record:
			recording.append(out_l[i])
			recording.append(out_r[i])

	if playback != null and playback.can_push_buffer(count):
		playback.push_buffer(frames)


func save_wav(path: String, extra := PackedFloat32Array()) -> void:

	# extra : the recording of a second player (the full music of ENHANCED) mixed in

	var data := PackedByteArray()
	data.resize(recording.size() * 2)

	for i in recording.size():
		var v: float = recording[i] + (extra[i] if i < extra.size() else 0.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = true
	wav.data = data
	wav.save_to_wav(path)


# ---------------------------------------------------------------- player : set up

func _instruments() -> void:

	# $4adb6 : once, the 20 music samples (long size, word rate, data) at $4b780 give the
	# instrument table : start, size in words, 3579545 / rate. The end of the bank is the
	# silent sample ($4a192), 64 bytes on the wave base for effects ($4b5ba). Four words of
	# tune data are lowered.

	if _b(A3 + 0x5ef) != 0:
		return

	var a0 := BANK
	var a5 := 0x4a338

	for i in BANK_COUNT:
		var size := _l(a0)
		var rate := _w(a0 + 4)
		a0 += 6
		_sl(a5, a0)
		a0 += size
		_sw(a5 + 8, (size >> 1) & 0xffff)
		_sw(a5 + 0xa, (0x369e99 / rate) & 0xffff)
		a5 += 0xc

	_sl(A3 + 0x5f4, a0)
	_sl(A3 + SILENT_LINK, a0 + 0x40)
	_sb(A3 + 0x5ef, 0xff)

	for patch in PATCHES:
		_sw(A3 + patch[0], _w(A3 + patch[0]) - patch[1])


func _sample_effects() -> void:

	# $4ae16 : once, the 18 effect samples after the music bank : start, size in words,
	# period, and their length in vertical blanks (size * 50 / rate + 1)

	if _b(A3 + 0x12ca) != 0:
		return

	var a0 := 0x4b780 + 0xff1c
	var a5 := SAMPLE_FX

	for i in 18:
		var size := _l(a0)
		var rate := _w(a0 + 4)
		_sb(a5 + 0xc, ((size & 0xffff) * 0x32 / rate) + 1)
		a0 += 6
		_sl(a5, a0)
		a0 += size
		_sw(a5 + 8, (size >> 1) & 0xffff)
		_sw(a5 + 0xa, (0x369e99 / rate) & 0xffff)
		a5 += 0x10

	_sb(A3 + 0x12ca, 0xff)


func _stop() -> void:

	# $49c9a

	_sb(A3 + 0x5f0, 0)

	for ch in 4:
		_sb(EFFECTS + 0x24 * ch + 0x1a, 0)
		_sw(SHADOW + 12 * ch + 0xa, 0)

	_dma_off(0xf)

	for ch in 4:
		vol[ch] = 0


func _init_tune(number: int) -> void:

	# $49bfc : 10 bytes a tune at $4a428 (duration factor, speed, the four voices' order
	# lists as offsets from the base)

	_stop()
	_instruments()
	_sb(A3 + 0x5f1, 0)
	var d0 := number * 10
	_sw(A3 + 0x5e4, _sbyte(TUNES + d0) & 0xffff)
	_sb(A3 + 0x5e8, _b(TUNES + d0 + 1))
	_sb(A3 + 0x5e9, _b(0x4a186))

	for ch in 4:
		var a1 := VOICES + 0x30 * ch
		_sw(a1 + 0x1e, 1)
		_sb(a1, 0)
		_sb(a1 + 1, 0)
		_sb(a1 + 3, 0)
		_sb(a1 + 0x16, 0xff)
		_sl(a1 + 0xc, 0x4a306)
		_sl(a1 + 0x10, 0x4a306)
		var order := _sw16(TUNES + d0 + 2)
		_sw(a1 + 8, order & 0xffff)
		_sw(a1 + 0xa, 2 + FIRST_ENTRY)
		_sl(a1 + 4, A3 + _sw16(A3 + order + FIRST_ENTRY))
		d0 += 2

	_sw(A3 + 0x5e6, 0x40)
	_sb(A3 + 0x5eb, 0)
	_sb(A3 + 0x5f0, 0xff)
	_sb(A3 + 0x5ee, 0xff)


# ---------------------------------------------------------------- player : music

func _tick() -> void:

	# $49d54 : one call a vertical blank

	if _b(A3 + 0x5f0) == 0:
		_effects_tick()
		return

	if _b(A3 + 0x5f3) != 0:
		_sb(A3 + 0x5f2, _b(A3 + 0x5f2) - 1)

		if _b(A3 + 0x5f2) == 0:
			_sb(A3 + 0x5f2, 6)
			return

	var sum := _b(A3 + 0x5ea) + _b(0x4a186)
	_sb(A3 + 0x5ea, sum)

	if sum > 0xff:
		_effects_tick()
		return

	if _b(0x4a189) != 0:
		if _w(A3 + 0x5e6) == 0:
			_end_all()
			return

		_sb(A3 + 0x5ec, _b(A3 + 0x5ec) - 1)

		if _b(A3 + 0x5ec) == 0:
			_sw(A3 + 0x5e6, _w(A3 + 0x5e6) - 1)

			if _w(A3 + 0x5e6) == 0:
				_end_all()
				return

			_sb(A3 + 0x5ec, _b(0x4a189))

	for ch in 4:
		if _voice(ch):
			return

	_effects_tick()


func _period(note: int, a5: int) -> int:

	# the period table times the instrument's factor, over 1024

	return (((_w(PERIODS + 2 * (note & 0xff)) * _w(a5 + 0xa)) >> 10) & 0xffff)


func _set_per(ch: int, a4: int, value: int) -> void:
	_sw(a4 + 6, value)

	if _b(a4 + 0xb) == 0:
		per[ch] = value


func _set_vol(ch: int, a4: int, value: int) -> void:
	_sw(a4 + 8, value)

	if _b(a4 + 0xb) == 0:
		vol[ch] = value


func _set_sample(ch: int, a4: int, start: int, words: int) -> void:
	_sl(a4, start)
	_sw(a4 + 4, words)

	if _b(a4 + 0xb) == 0:
		lc[ch] = start
		len_words[ch] = words


func _voice(ch: int) -> bool:

	# one music voice ; true when the tune ended ($4a0d8 returns from the whole call)

	var a4 := SHADOW + 12 * ch
	_sb(a4 + 0xa, 0xff)
	var a0 := VOICES + 0x30 * ch
	var a1 := _l(a0 + 4)
	var a5 := _l(a0 + 0x18)

	if _b(a0 + 0x16) == 0:

		# the tick after a note : the loop of the sample, or the silent sample

		_sb(a0 + 0x16, 0xff)
		var loop := _signed32(_l(a5 + 4))

		if loop >= 0:
			_set_sample(ch, a4, _l(a5) + loop, (_w(a5 + 8) - (loop >> 1)) & 0xffff)
		else:
			_set_sample(ch, a4, _l(0x4a192), 0x20)

	_sw(a0 + 0x1e, _w(a0 + 0x1e) - 1)

	if _w(a0 + 0x1e) != 0:
		if _w(a0 + 0x1e) == 1:
			if _b(a4 + 0xb) == 0 and _b(a1) != 0x83:
				_dma_off(1 << ch)

			return false

		_sustain(ch, a0, a4, a5)
		return false

	_sb(a0, 0)

	while true:
		var d0 := _b(a1)
		a1 += 1

		if d0 < 0x80:
			_sb(a0 + 2, d0)
			d0 = (d0 + _b(0x4a18f) + _b(a0 + 3)) & 0xff
			var a2 := _l(a0 + 0x22)
			var level := _sbyte(a2) & 0xffff
			_sl(a0 + 0x26, a2 + 1)
			_sb(a0 + 0x2b, _b(a0 + 0x2a))
			_sl(a4, _l(a5))
			_sw(a4 + 4, _w(a5 + 8))
			level = ((level * _w(0x4a184)) & 0xffff) >> 6
			_sw(a4 + 8, level)

			if _b(a4 + 0xb) == 0:
				lc[ch] = _l(a5)
				len_words[ch] = _w(a5 + 8)
				vol[ch] = level

			_set_per(ch, a4, _period(d0, a5))
			_sb(a0 + 0x16, 0)
			break

		if d0 >= 0xe0:

			# a duration

			_sw(a0 + 0x1c, ((d0 - 0xdf) * _w(0x4a182)) & 0xffff)
			continue

		if d0 >= 0xb0:

			# an instrument

			a5 = 0x4a338 + (d0 - 0xb0) * 0xc
			_sl(a0 + 0x18, a5)
			continue

		if d0 >= 0xa0:

			# a volume envelope, its speed in the byte before it

			var env := A3 + _sw16(ENVELOPES + 2 * (d0 - 0xa0))
			_sl(a0 + 0x22, env)
			_sb(a0 + 0x2a, _b(env - 1))
			continue

		if d0 >= 0x90:

			# an arpeggio

			var arp := A3 + _sw16(0x4a2e6 + 2 * (d0 - 0x90))
			_sl(a0 + 0xc, arp)
			_sl(a0 + 0x10, arp)
			continue

		match d0 - 0x80:
			0:

				# $4a06c : the next pattern of the order list, back to its start at a 0

				var index := _w(a0 + 0xa)
				var at := (_sw16(a0 + 8) + index) & 0xffff
				index += 2

				if _w(A3 + _signed16(at)) == 0:
					at = (_w(a0 + 8) + FIRST_ENTRY) & 0xffff
					index = 2 + FIRST_ENTRY

				a1 = A3 + _sw16(A3 + _signed16(at))
				_sw(a0 + 0xa, index)
			1:

				# $4a092 : a slide, step and delay

				_sw(a0 + 0x20, 0)
				_sb(a0 + 0x14, _b(a1))
				_sb(a0 + 0x15, _b(a1 + 1))
				a1 += 2
				_sb(a0, _b(a0) | 2)
			2:

				# $4a0a8 : a rest, the silent sample, no new DMA

				_sw(a0 + 0x1e, _w(a0 + 0x1c))
				_sl(a0 + 4, a1)
				_set_sample(ch, a4, _l(0x4a192), 0x20)
				return false
			3:

				# $4a0d4 : a tie

				break
			4:

				# $4a0d8 : the end

				_end_all()
				return true
			5:
				_sb(0x4a18f, _b(a1))
				a1 += 1
			6:
				_sb(a0 + 1, 0xff)
				_sb(a0 + 0x2c, _b(a1))
				_sb(a0 + 0x2e, _b(a1 + 1))
				_sb(a0 + 0x2d, 0)
				a1 += 2
			7:
				_sb(a0 + 1, 0)
			8:
				_sb(a0 + 3, _b(a1))
				a1 += 1
			9:
				_sb(a0 + 8, _b(a1))
				_sb(a0 + 9, _b(a1 + 1))
				_sw(a0 + 0xa, 0)
				a1 += 2
			10:
				_sw(0x4a182, _sbyte(a1) & 0xffff)
				a1 += 1
			11:
				_sb(0x4a189, _b(a1))
				_sb(A3 + 0x5ec, _b(0x4a189))
				a1 += 1
			_:
				push_error("amiga sound : command %x" % d0)
				break

	# $49ed0

	_sl(a0 + 4, a1)
	_sw(a0 + 0x1e, _w(a0 + 0x1c))
	_dma_on(1 << ch)
	return false


func _signed16(v: int) -> int:
	v &= 0xffff
	return v - 0x10000 if v & 0x8000 else v


func _sustain(ch: int, a0: int, a4: int, a5: int) -> void:

	# $49ef4 : arpeggio, slide, vibrato, volume envelope

	var d0 := (_b(a0 + 2) + _b(0x4a18f) + _b(a0 + 3)) & 0xff
	var a1 := _l(a0 + 0x10)
	var d1 := _b(a1)
	a1 += 1

	if d1 & 0x80:
		d1 &= 0x7f
		a1 = _l(a0 + 0xc)

	_sl(a0 + 0x10, a1)
	d0 = (d0 + d1) & 0xff
	var period := _period(d0, a5)

	if _b(a0) & 2:
		if _b(a0 + 0x15) != 0:
			_sb(a0 + 0x15, _b(a0 + 0x15) - 1)
		else:
			_sw(a0 + 0x20, _w(a0 + 0x20) + _sbyte(a0 + 0x14))
			period = (period - _w(a0 + 0x20)) & 0xffff

	if _b(a0 + 1) != 0:
		var pos := _b(a0 + 0x2d)

		if _b(a0 + 1) & 0x80:
			pos = (pos + _b(a0 + 0x2c)) & 0xff
			_sb(a0 + 0x2d, pos)

			if pos == _b(a0 + 0x2e):
				_sb(a0 + 1, _b(a0 + 1) ^ 0x80)
		else:
			pos = (pos - _b(a0 + 0x2c)) & 0xff
			_sb(a0 + 0x2d, pos)

			if pos == 0:
				_sb(a0 + 1, _b(a0 + 1) ^ 0x80)

		if _b(a0 + 0x2d) == 0:
			_sb(a0 + 1, _b(a0 + 1) ^ 1)

		var delta := pos - 0x100 if pos & 0x80 else pos

		if _b(a0 + 1) & 1:
			period = (period + delta) & 0xffff
		else:
			period = (period - delta) & 0xffff

	_set_per(ch, a4, period)
	var count := _b(a0 + 0x2b)
	_sb(a0 + 0x2b, count - 1)

	if count == 0:
		_sb(a0 + 0x2b, _b(a0 + 0x2a))
		var a2 := _l(a0 + 0x26)
		var level := _b(a2)

		if level < 0x80:
			_sl(a0 + 0x26, a2 + 1)

		level = (((level & 0x7f) * _w(0x4a184)) & 0xffff) >> 6
		_set_vol(ch, a4, level)


func _end_all() -> void:

	# $4a0d8

	_sb(A3 + 0x5ee, 0)
	_sb(A3 + 0x5f0, 0)

	for ch in 4:
		_sb(EFFECTS + 0x24 * ch + 0x1a, 0)
		_sw(SHADOW + 12 * ch + 0xa, 0)

	_dma_off(0xf)


# ---------------------------------------------------------------- player : effects

func _effect(value: int) -> void:

	# $4ae72 : channel in bits 8 and 9, effect in the low byte, from $80 a sample

	value &= 0x3ff
	_sw(0x4b360, value)
	var ch := _b(0x4b360) & 3
	_sb(EFFECTS + 0x24 * ch + 0x1a, 0)
	_instruments()
	var a4 := SHADOW + 12 * ch
	_sb(a4 + 0xb, 0xff)
	var number := value & 0xff

	if number & 0x80:
		_sample_effect(ch, number)
		return

	var a1 := EFFECTS + 0x24 * ch
	var a0 := 0x4b392 + number * 0x18
	len_words[ch] = 1
	per[ch] = 0x7c
	_dma_off(1 << ch)

	for i in 0x18:
		_sb(a1 + i, _b(a0 + i))

	len_words[ch] = _w(a1 + 0x16)
	_sw(a1 + 0x18, _w(a1 + 0xe))
	_sb(a1 + 0x1b, 1)
	var index := _sbyte(a1 + 0x14)
	_sl(a1 + 0x1c, A3 + _sw16(A3 + 0x1a20 + 2 * index))
	_sb(a1 + 0x1a, 0xff)


func _sample_effect(ch: int, number: int) -> void:

	# $4b072

	_sample_effects()
	var a1 := EFFECTS + 0x24 * ch
	_sb(a1 + 0x15, number)
	_dma_off(1 << ch)
	per[ch] = 0x7c
	len_words[ch] = 1
	var a0 := SAMPLE_FX + (number & 0x7f) * 0x10
	_sb(a1 + 0x12, _b(a0 + 0xc))

	if _b(a0 + 0xd) != 0:
		_sb(a1 + 0x12, 0)

	len_words[ch] = _w(a0 + 8)
	lc[ch] = _l(a0)
	per[ch] = _w(a0 + 0xa)
	_sw(a1 + 0x20, _w(a0 + 0xa))
	_sw(a1 + 0x22, _w(a0 + 0xa))
	vol[ch] = 0x40
	_dma_on(1 << ch)
	_sb(a1 + 0x1a, 0xff)
	var loop := _signed32(_l(a0 + 4))

	if loop < 0:
		lc[ch] = _l(0x4a192)
		len_words[ch] = 0x20
	else:
		lc[ch] = _l(a0) + loop
		len_words[ch] = (_w(a0 + 8) - (loop >> 1)) & 0xffff


func _effects_tick() -> void:

	# $4b140 : each active effect channel

	if music_only:
		return

	for ch in 4:
		var a1 := EFFECTS + 0x24 * ch

		if _b(a1 + 0x1a) != 0:
			_effect_channel(ch, a1, SHADOW + 12 * ch)


func _effect_end(ch: int, a1: int, a4: int) -> void:

	# $4b1ae : the effect ends, the music's last sample, period and volume come back

	_sb(a1 + 0x1a, 0)
	_dma_off(1 << ch)
	_sb(a4 + 0xb, 0)

	if _b(a4 + 0xa) == 0:
		return

	per[ch] = 0x7c
	_dma_off(1 << ch)
	lc[ch] = _l(a4)
	len_words[ch] = _w(a4 + 4)
	per[ch] = _w(a4 + 6)
	vol[ch] = _w(a4 + 8)
	_dma_on(1 << ch)


func _effect_channel(ch: int, a1: int, a4: int) -> void:

	# $4b1a2

	if _b(a1 + 0x12) != 0:
		_sb(a1 + 0x12, _b(a1 + 0x12) - 1)

		if _b(a1 + 0x12) == 0:
			_effect_end(ch, a1, a4)
			return

	var number := _b(a1 + 0x15)

	if number != 0:
		var a2 := SAMPLE_FX + (number & 0x7f) * 0x10
		var period := _w(a1 + 0x22)
		var step := _w(a2 + 0xe)

		if step == 0:
			per[ch] = _w(a1 + 0x22)
			return

		period = (period + step) & 0xffff

		if _signed16(period) < 0x7c:
			_effect_end(ch, a1, a4)
			return

		_sw(a1 + 0x22, period)
		per[ch] = period
		return

	if _b(a1 + 0xf) != 0:
		_sb(a1 + 0x19, _b(a1 + 0x19) - 1)

		if _b(a1 + 0x19) == 0:
			_sb(a1 + 0x19, _b(a1 + 0xf))
			var steps := _l(a1 + 4)
			var pattern := _b(a1 + 0x10)
			var carry := pattern & 1
			_sb(a1 + 0x10, (pattern >> 1) | (carry << 7))
			var step := steps & 0xffff if carry else (steps >> 16) & 0xffff
			_sw(a1 + 8, _w(a1 + 8) + step)

	_sw(a1 + 8, _w(a1 + 8) + _w(a1))

	if _b(a1 + 0xe) != 0:
		_sb(a1 + 0x18, _b(a1 + 0x18) - 1)

		if _b(a1 + 0x18) == 0:
			_sb(a1 + 0x18, _b(a1 + 0xe))
			_sw(a1 + 8, _w(a1 + 2))

	_sb(a1 + 0x1b, _b(a1 + 0x1b) - 1)

	if _b(a1 + 0x1b) == 0:
		_sb(a1 + 0x1b, _b(a1 + 0x13))
		var a2 := _l(a1 + 0x1c)
		var level := _b(a2)

		if level == 0:
			_effect_end(ch, a1, a4)
			return

		if level < 0x80:
			_sl(a1 + 0x1c, a2 + 1)
			vol[ch] = level

	var period := _signed16(_w(a1 + 8))
	per[ch] = maxi(period, 0x7c)
	var waves := _l(a1 + 0xa)
	var pattern := _b(a1 + 0x11)
	var carry := pattern & 1
	_sb(a1 + 0x11, (pattern >> 1) | (carry << 7))
	var offset := waves & 0xffff if carry else (waves >> 16) & 0xffff
	lc[ch] = _l(0x4b5ba) + _signed16(offset)
	_dma_on(1 << ch)
