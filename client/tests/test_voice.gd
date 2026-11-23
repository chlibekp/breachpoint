extends TestCase


func test_ulaw_round_trip_is_close() -> void:
	var src := PackedFloat32Array()
	for i: int in 320:
		src.append(sin(TAU * 440.0 * i / 16000.0) * 0.6)
	var enc := Ulaw.encode(src)
	check_eq(enc.size(), 320, "one byte per sample")
	var worst := 0.0
	for i: int in src.size():
		worst = maxf(worst, absf(Ulaw.decode(enc[i]) - src[i]))
	# G.711 µ-law: ≤ ~3 % error at this level.
	check(worst < 0.03, "max error %f" % worst)


func test_ulaw_silence_and_extremes() -> void:
	var enc := Ulaw.encode(PackedFloat32Array([0.0, 1.0, -1.0]))
	check(absf(Ulaw.decode(enc[0])) < 0.001, "silence")
	check(Ulaw.decode(enc[1]) > 0.95, "full positive")
	check(Ulaw.decode(enc[2]) < -0.95, "full negative")
