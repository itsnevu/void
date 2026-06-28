class_name Base58
extends RefCounted

## Pure GDScript Base58 codec using the Bitcoin/Solana alphabet.
## decode() returns an empty PackedByteArray on any invalid input.

const ALPHABET: String = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


## Decode a Base58 string to bytes. Returns empty PackedByteArray on invalid input.
static func decode(s: String) -> PackedByteArray:
	if s.is_empty():
		return PackedByteArray()

	# Map characters to their digit values, rejecting unknown characters.
	# We accumulate the big number in base 256 using repeated multiply-add,
	# operating on a byte array (big-endian, most significant first).
	var bytes: PackedByteArray = PackedByteArray()  # big-endian accumulator
	for i in range(s.length()):
		var ch: String = s[i]
		var digit: int = ALPHABET.find(ch)
		if digit == -1:
			return PackedByteArray()  # invalid character

		# bytes = bytes * 58 + digit
		var carry: int = digit
		for j in range(bytes.size() - 1, -1, -1):
			var val: int = bytes[j] * 58 + carry
			bytes[j] = val & 0xFF
			carry = val >> 8
		while carry > 0:
			bytes.insert(0, carry & 0xFF)
			carry = carry >> 8

	# Account for leading '1' characters, each representing a leading zero byte.
	var leading_zeros: int = 0
	for i in range(s.length()):
		if s[i] == "1":
			leading_zeros += 1
		else:
			break

	# Strip any extra leading zero bytes that the accumulator may already hold,
	# then prepend exactly `leading_zeros` zero bytes.
	# (The big-number accumulator never produces spurious leading zeros because
	# we only insert a high byte when carry > 0, so we just prepend the zeros.)
	var result: PackedByteArray = PackedByteArray()
	result.resize(leading_zeros)
	for i in range(leading_zeros):
		result[i] = 0
	result.append_array(bytes)
	return result


## Encode bytes to a Base58 string.
static func encode(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""

	# Count leading zero bytes -> they become leading '1's.
	var leading_zeros: int = 0
	for b in bytes:
		if b == 0:
			leading_zeros += 1
		else:
			break

	# Convert the big-endian byte number to base 58 (digits, least significant first).
	var digits: PackedByteArray = PackedByteArray()
	for i in range(bytes.size()):
		var carry: int = bytes[i]
		for j in range(digits.size()):
			var val: int = digits[j] * 256 + carry
			digits[j] = val % 58
			carry = val / 58
		while carry > 0:
			digits.append(carry % 58)
			carry = carry / 58

	# Build the string: leading '1's, then digits reversed.
	var out: String = ""
	for i in range(leading_zeros):
		out += "1"
	for i in range(digits.size() - 1, -1, -1):
		out += ALPHABET[digits[i]]
	return out
