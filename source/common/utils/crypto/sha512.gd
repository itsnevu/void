class_name Sha512
extends RefCounted

## Pure GDScript implementation of SHA-512 (FIPS 180-4).
##
## GDScript integers are 64-bit signed. Bitwise operators (& | ^ << >>) operate
## on the raw 64-bit two's-complement bit pattern, and integer addition wraps on
## overflow, so unsigned 64-bit modular arithmetic "just works" for + ^ & | <<.
## The ONLY hazard is the right shift `>>`, which is ARITHMETIC for negative
## values (it sign-extends). We therefore use a dedicated helper `_shr` that
## masks off the sign-extended high bits to emulate a logical (unsigned) shift.
##
## Rotations are built from logical shifts so they are also safe.

# Logical right shift (unsigned). Masks sign extension.
static func _shr(value: int, amount: int) -> int:
	if amount == 0:
		return value
	# Shift, then clear the top `amount` bits that arithmetic shift may have set.
	# Mask = (1 << (64 - amount)) - 1, but build it without overflow for amount in 1..63.
	var mask: int = (1 << (64 - amount)) - 1
	return (value >> amount) & mask


# Rotate right by `amount` bits within a 64-bit word.
static func _rotr(value: int, amount: int) -> int:
	return _shr(value, amount) | (value << (64 - amount))


static func hash(data: PackedByteArray) -> PackedByteArray:
	# --- Initial hash values: first 64 bits of fractional parts of square roots
	# of the first 8 primes. Computed at runtime from their unsigned hex strings
	# to avoid signed-literal transcription mistakes.
	var h: Array[int] = [
		_u64("6a09e667f3bcc908"),
		_u64("bb67ae8584caa73b"),
		_u64("3c6ef372fe94f82b"),
		_u64("a54ff53a5f1d36f1"),
		_u64("510e527fade682d1"),
		_u64("9b05688c2b3e6c1f"),
		_u64("1f83d9abfb41bd6b"),
		_u64("5be0cd19137e2179"),
	]

	var k: Array[int] = _build_k()

	# --- Pre-processing (padding) ---
	var msg: PackedByteArray = data.duplicate()
	var bit_len: int = data.size() * 8
	# Append 0x80
	msg.append(0x80)
	# Append 0x00 until length in bytes ≡ 112 (mod 128)
	while msg.size() % 128 != 112:
		msg.append(0x00)
	# Append 128-bit big-endian length. We only support up to 2^64-1 bits, so the
	# high 64 bits are zero.
	for i in range(8):
		msg.append(0x00)
	# Low 64 bits of length, big-endian.
	for i in range(8):
		var shift: int = (7 - i) * 8
		msg.append(_shr(bit_len, shift) & 0xFF)

	# --- Process each 1024-bit (128-byte) chunk ---
	var num_chunks: int = msg.size() / 128
	for chunk_index in range(num_chunks):
		var base: int = chunk_index * 128
		var w: Array[int] = []
		w.resize(80)
		# First 16 words, big-endian 64-bit.
		for t in range(16):
			var off: int = base + t * 8
			var word: int = 0
			for b in range(8):
				word = (word << 8) | msg[off + b]
			w[t] = word
		# Extend to 80 words.
		for t in range(16, 80):
			var s0: int = _rotr(w[t - 15], 1) ^ _rotr(w[t - 15], 8) ^ _shr(w[t - 15], 7)
			var s1: int = _rotr(w[t - 2], 19) ^ _rotr(w[t - 2], 61) ^ _shr(w[t - 2], 6)
			w[t] = w[t - 16] + s0 + w[t - 7] + s1

		# Working variables.
		var a: int = h[0]
		var b: int = h[1]
		var c: int = h[2]
		var d: int = h[3]
		var e: int = h[4]
		var f: int = h[5]
		var g: int = h[6]
		var hh: int = h[7]

		for t in range(80):
			var big_s1: int = _rotr(e, 14) ^ _rotr(e, 18) ^ _rotr(e, 41)
			var ch: int = (e & f) ^ ((~e) & g)
			var temp1: int = hh + big_s1 + ch + k[t] + w[t]
			var big_s0: int = _rotr(a, 28) ^ _rotr(a, 34) ^ _rotr(a, 39)
			var maj: int = (a & b) ^ (a & c) ^ (b & c)
			var temp2: int = big_s0 + maj

			hh = g
			g = f
			f = e
			e = d + temp1
			d = c
			c = b
			b = a
			a = temp1 + temp2

		h[0] = h[0] + a
		h[1] = h[1] + b
		h[2] = h[2] + c
		h[3] = h[3] + d
		h[4] = h[4] + e
		h[5] = h[5] + f
		h[6] = h[6] + g
		h[7] = h[7] + hh

	# --- Produce the final 64-byte digest, big-endian ---
	var out: PackedByteArray = PackedByteArray()
	out.resize(64)
	for i in range(8):
		var word: int = h[i]
		for b in range(8):
			var shift: int = (7 - b) * 8
			out[i * 8 + b] = _shr(word, shift) & 0xFF
	return out


# Parse a 16-char hex string into a signed 64-bit int with the matching bit pattern.
static func _u64(hex: String) -> int:
	var value: int = 0
	for ch in hex:
		value = (value << 4) | ("0123456789abcdef".find(ch.to_lower()))
	return value


# Build the 80 SHA-512 round constants from their canonical hex strings.
static func _build_k() -> Array[int]:
	var hexes: PackedStringArray = [
		"428a2f98d728ae22", "7137449123ef65cd", "b5c0fbcfec4d3b2f", "e9b5dba58189dbbc",
		"3956c25bf348b538", "59f111f1b605d019", "923f82a4af194f9b", "ab1c5ed5da6d8118",
		"d807aa98a3030242", "12835b0145706fbe", "243185be4ee4b28c", "550c7dc3d5ffb4e2",
		"72be5d74f27b896f", "80deb1fe3b1696b1", "9bdc06a725c71235", "c19bf174cf692694",
		"e49b69c19ef14ad2", "efbe4786384f25e3", "0fc19dc68b8cd5b5", "240ca1cc77ac9c65",
		"2de92c6f592b0275", "4a7484aa6ea6e483", "5cb0a9dcbd41fbd4", "76f988da831153b5",
		"983e5152ee66dfab", "a831c66d2db43210", "b00327c898fb213f", "bf597fc7beef0ee4",
		"c6e00bf33da88fc2", "d5a79147930aa725", "06ca6351e003826f", "142929670a0e6e70",
		"27b70a8546d22ffc", "2e1b21385c26c926", "4d2c6dfc5ac42aed", "53380d139d95b3df",
		"650a73548baf63de", "766a0abb3c77b2a8", "81c2c92e47edaee6", "92722c851482353b",
		"a2bfe8a14cf10364", "a81a664bbc423001", "c24b8b70d0f89791", "c76c51a30654be30",
		"d192e819d6ef5218", "d69906245565a910", "f40e35855771202a", "106aa07032bbd1b8",
		"19a4c116b8d2d0c8", "1e376c085141ab53", "2748774cdf8eeb99", "34b0bcb5e19b48a8",
		"391c0cb3c5c95a63", "4ed8aa4ae3418acb", "5b9cca4f7763e373", "682e6ff3d6b2b8a3",
		"748f82ee5defb2fc", "78a5636f43172f60", "84c87814a1f0ab72", "8cc702081a6439ec",
		"90befffa23631e28", "a4506cebde82bde9", "bef9a3f7b2c67915", "c67178f2e372532b",
		"ca273eceea26619c", "d186b8c721c0c207", "eada7dd6cde0eb1e", "f57d4f7fee6ed178",
		"06f067aa72176fba", "0a637dc5a2c898a6", "113f9804bef90dae", "1b710b35131c471b",
		"28db77f523047d84", "32caab7b40c72493", "3c9ebe0a15c9bebc", "431d67c49c100d4c",
		"4cc5d4becb3e42b6", "597f299cfc657e2a", "5fcb6fab3ad6faec", "6c44198c4a475817",
	]
	var arr: Array[int] = []
	arr.resize(80)
	for i in range(80):
		arr[i] = _u64(hexes[i])
	return arr
