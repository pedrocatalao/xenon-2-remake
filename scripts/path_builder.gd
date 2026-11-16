class_name PathBuilder

# Port of the path interpreter of XENON2.EXE (load module offsets 0x4871 to 0x4a66).
# An enemy has a budget of "speed" steps per game frame. The original spends that budget
# command by command, so the whole path can be laid out in advance as one position per
# step : the enemy at step n is at points[n].
#
# pos (10) : only read when the enemy is created, skipped inside a path
# arc (2) : heading, turn, turn change, length
#     heading is 0..255 (0 right, 64 down) with a 16 bit fraction
#     turn is a 16.16 value, set to the argument shifted left by 8
#     turn change is added to turn every step
#     each step adds sine[heading] * 4 / 256 to y and sine[heading + 64] * 4 / 256 to x,
#     both kept with an 8 bit fraction, then advances heading by turn and turn by its change
# wait (4) : spends that many steps without moving
# loop (8) : jumps back to an earlier command. The original loops for ever, here the
#     path is laid out up to MAX_POINTS steps.
# end (0) : the enemy is removed
#
# Opcode 6 (random branch) exists in the code but no level uses it.

const MAX_POINTS := 20000


static func build(commands: Array, sine: Array) -> Dictionary:
	var points: Array[Vector2i] = []

	# angles[n] : the value the interpreter leaves in BX after step n. For an arc step this
	# is the whole heading used by that step (code 0x48de, ds:0xfcee). For a wait step the
	# wait command leaves 4 (code 0x4a36, read by the enemy fire code, unconfirmed).

	var angles: Array[int] = []

	# after[n] : the heading byte the interpreter leaves in the object (+0x1c, 0x4954) after
	# step n, the turn already added (0x490b). A wait step keeps the last one.

	var after: Array[int] = []
	var start := Vector2i.ZERO
	var has_start := false
	var x := 0
	var y := 0
	var x_frac := 0
	var y_frac := 0
	var index := 0

	if not commands.is_empty() and commands[0][0] == "pos":
		start = Vector2i(int(commands[0][1]), int(commands[0][2]))
		has_start = true
		x = start.x
		y = start.y

	# first : the steps of the first command after pos (level 2's snakes hide while in it)

	var first := -1

	while index < commands.size() and points.size() < MAX_POINTS:
		if first < 0 and index > (1 if has_start else 0):
			first = points.size()

		var command: Array = commands[index]
		var name: String = command[0]
		index += 1

		if name == "arc":
			var heading := (int(command[1]) & 0xff) << 16
			var turn := int(command[2]) << 8
			var change := int(command[3])

			for i in int(command[4]):
				var angle := heading >> 16
				var dy := int(sine[angle]) * 4
				var dx := int(sine[angle + 64]) * 4

				y_frac += dy & 0xff
				y += (dy >> 8) + (y_frac >> 8)
				y_frac &= 0xff
				x_frac += dx & 0xff
				x += (dx >> 8) + (x_frac >> 8)
				x_frac &= 0xff

				heading = (heading + turn) & 0xffffff
				turn += change
				points.append(Vector2i(x, y))
				angles.append(angle)
				after.append((heading >> 16) & 0xff)

				if points.size() >= MAX_POINTS:
					break
		elif name == "wait":
			for i in int(command[1]):
				points.append(Vector2i(x, y))
				angles.append(4)
				after.append(after.back() if not after.is_empty() else 0)
		elif name == "loop" and int(command[1]) >= 0:
			index = int(command[1])
		elif name == "pos":
			pass
		else:
			break

	if first < 0:
		first = points.size()

	return {"points": points, "angles": angles, "start": start, "has_start": has_start, "first": first, "after": after}
