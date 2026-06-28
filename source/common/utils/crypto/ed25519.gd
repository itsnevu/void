class_name Ed25519
extends RefCounted

## Pure GDScript Ed25519 signature verification (RFC 8032, edwards25519).
##
## Matches libsodium's crypto_sign_verify_detached semantics:
##   - 64-byte signature R || S, 32-byte public key A, arbitrary message M.
##   - Rejects S >= L (non-canonical scalar).
##   - Rejects non-canonical / invalid encoded points.
##   - Uses the cofactored verification group equation
##         [8][S]B == [8]R + [8][k]A   with  k = SHA512(R || A || M) mod L
##     which accepts exactly the signatures libsodium accepts.
##
## Big integers are represented as little-endian arrays of base-2^28 limbs
## ("digits"). A single-limb product is at most (2^28-1)^2 < 2^56, and during
## multiplication we accumulate column sums that stay well below 2^63, so all
## intermediate values fit in GDScript's signed 64-bit ints.

const _Sha512 = preload("res://source/common/utils/crypto/sha512.gd")

const LIMB_BITS: int = 28
const LIMB_BASE: int = 1 << LIMB_BITS          # 2^28
const LIMB_MASK: int = LIMB_BASE - 1

# ---------------------------------------------------------------------------
# Curve / field constants (initialised lazily as big-int limb arrays).
# ---------------------------------------------------------------------------
static var _P: Array        # field prime 2^255 - 19
static var _L: Array        # group order   2^252 + 27742317777372353535851937790883648493
static var _D: Array        # curve constant d = -121665/121666 mod p
static var _I: Array        # sqrt(-1) mod p = 2^((p-1)/4)
static var _By: Array       # base point y
static var _Bx: Array       # base point x
static var _ONE: Array
static var _ZERO: Array
static var _initialised: bool = false


static func _ensure_init() -> void:
	if _initialised:
		return
	_ZERO = _from_int(0)
	_ONE = _from_int(1)
	# p = 2^255 - 19
	_P = _sub(_shl_pow2(_from_int(1), 255), _from_int(19))
	# L = 2^252 + 27742317777372353535851937790883648493
	_L = _add(_shl_pow2(_from_int(1), 252), _from_dec("27742317777372353535851937790883648493"))
	# d = -121665 * inv(121666) mod p
	var num: Array = _mod(_sub(_P, _from_int(121665)), _P)
	var den_inv: Array = _inv(_from_int(121666))
	_D = _mulmod(num, den_inv)
	# I = 2^((p-1)/4) mod p
	var exp: Array = _div2(_div2(_sub(_P, _from_int(1))))  # (p-1)/4
	_I = _powmod(_from_int(2), exp)
	# Base point: y = 4/5 mod p, x recovered with positive sign convention.
	_By = _mulmod(_from_int(4), _inv(_from_int(5)))
	_Bx = _recover_x(_By, 0)
	_initialised = true


# ===========================================================================
# PUBLIC API
# ===========================================================================
static func verify(message: PackedByteArray, signature: PackedByteArray, public_key: PackedByteArray) -> bool:
	if signature.size() != 64 or public_key.size() != 32:
		return false
	_ensure_init()

	var r_bytes: PackedByteArray = signature.slice(0, 32)
	var s_bytes: PackedByteArray = signature.slice(32, 64)

	# Decode S as a little-endian scalar and reject S >= L (libsodium behaviour).
	var s: Array = _from_le_bytes(s_bytes)
	if _cmp(s, _L) >= 0:
		return false

	# Decode point A (public key).
	var a_point: Array = _decode_point(public_key)
	if a_point.is_empty():
		return false

	# Decode point R from the signature.
	var r_point: Array = _decode_point(r_bytes)
	if r_point.is_empty():
		return false

	# k = SHA512(R || A || M) mod L
	var h_input: PackedByteArray = PackedByteArray()
	h_input.append_array(r_bytes)
	h_input.append_array(public_key)
	h_input.append_array(message)
	var digest: PackedByteArray = _Sha512.hash(h_input)
	var k: Array = _mod(_from_le_bytes(digest), _L)

	# Verify the cofactored group equation: [8][S]B == [8]R + [8][k]A
	var sb: Array = _scalar_mult(s, [_Bx, _By, _ONE.duplicate(), _mulmod(_Bx, _By)])
	var ka: Array = _scalar_mult(k, a_point)
	var rhs: Array = _point_add(r_point, ka)

	# Multiply both sides by the cofactor 8 (= 2^3) to be cofactor-permissive.
	for _i in range(3):
		sb = _point_double(sb)
		rhs = _point_double(rhs)

	return _point_equal(sb, rhs)


# ===========================================================================
# POINT DECODING (extended coordinates X, Y, Z, T with Z = 1)
# ===========================================================================
# A compressed point is 32 little-endian bytes: y in the low 255 bits, with the
# top bit of the last byte holding the sign (parity) of x.
static func _decode_point(data: PackedByteArray) -> Array:
	if data.size() != 32:
		return []
	var bytes: PackedByteArray = data.duplicate()
	var sign: int = (bytes[31] >> 7) & 1
	bytes[31] = bytes[31] & 0x7F
	var y: Array = _from_le_bytes(bytes)
	# Reject non-canonical y >= p.
	if _cmp(y, _P) >= 0:
		return []
	var x: Array = _recover_x(y, sign)
	if x.is_empty():
		return []
	var t: Array = _mulmod(x, y)
	return [x, y, _ONE.duplicate(), t]


# Recover x from y and the desired sign bit, per RFC 8032.
# Returns [] if no square root exists (invalid point).
static func _recover_x(y: Array, sign: int) -> Array:
	# x^2 = (y^2 - 1) / (d*y^2 + 1)
	var y2: Array = _mulmod(y, y)
	var u: Array = _submod(y2, _ONE)
	var v: Array = _addmod(_mulmod(_D, y2), _ONE)

	# Compute candidate x = u * v^3 * (u * v^7)^((p-5)/8)  (RFC 8032 fast sqrt)
	var v3: Array = _mulmod(_mulmod(v, v), v)
	var v7: Array = _mulmod(_mulmod(v3, v3), v)
	var exp: Array = _div8(_sub(_P, _from_int(5)))  # (p-5)/8
	var x: Array = _mulmod(_mulmod(u, v3), _powmod(_mulmod(u, v7), exp))

	# Check v*x^2 == u  (correct) or == -u (multiply by sqrt(-1)).
	var vx2: Array = _mulmod(v, _mulmod(x, x))
	if _cmp(vx2, _mod(u, _P)) != 0:
		var neg_u: Array = _submod(_ZERO, u)
		if _cmp(vx2, neg_u) == 0:
			x = _mulmod(x, _I)
		else:
			return []  # not a square -> invalid point

	# Fix the sign (parity of the low bit).
	var x_parity: int = _is_odd(x)
	if x_parity != sign:
		if _is_zero(x) and sign == 1:
			return []  # x == 0 cannot have odd parity (non-canonical)
		x = _submod(_ZERO, x)
	return x


# ===========================================================================
# POINT ARITHMETIC — twisted Edwards extended homogeneous coordinates.
# Point = [X, Y, Z, T] with x = X/Z, y = Y/Z, T = XY/Z.
# Curve: -x^2 + y^2 = 1 + d x^2 y^2  (a = -1).
# Formulas: RFC 8032, "add-2008-hwcd-3" style.
# ===========================================================================
static func _point_add(p1: Array, p2: Array) -> Array:
	var x1: Array = p1[0]; var y1: Array = p1[1]; var z1: Array = p1[2]; var t1: Array = p1[3]
	var x2: Array = p2[0]; var y2: Array = p2[1]; var z2: Array = p2[2]; var t2: Array = p2[3]

	var a: Array = _mulmod(_submod(y1, x1), _submod(y2, x2))
	var b: Array = _mulmod(_addmod(y1, x1), _addmod(y2, x2))
	# c = T1 * 2*d * T2
	var c: Array = _mulmod(_mulmod(t1, _addmod(_D, _D)), t2)
	var dd: Array = _mulmod(_addmod(z1, z1), z2)  # d = 2 * Z1 * Z2
	var e: Array = _submod(b, a)
	var f: Array = _submod(dd, c)
	var g: Array = _addmod(dd, c)
	var h: Array = _addmod(b, a)
	var x3: Array = _mulmod(e, f)
	var y3: Array = _mulmod(g, h)
	var t3: Array = _mulmod(e, h)
	var z3: Array = _mulmod(f, g)
	return [x3, y3, z3, t3]


static func _point_double(p: Array) -> Array:
	# Dedicated doubling for a = -1: "dbl-2008-hwcd".
	#   A = X1^2 ; B = Y1^2 ; C = 2*Z1^2
	#   D = -A
	#   E = (X1+Y1)^2 - A - B
	#   G = D + B  (= B - A)
	#   F = G - C
	#   H = D - B  (= -A - B)
	#   X3 = E*F ; Y3 = G*H ; T3 = E*H ; Z3 = F*G
	var x1: Array = p[0]; var y1: Array = p[1]; var z1: Array = p[2]
	var a: Array = _mulmod(x1, x1)
	var b: Array = _mulmod(y1, y1)
	var c: Array = _mulmod(_addmod(z1, z1), z1)  # 2*Z1^2
	var d: Array = _submod(_ZERO, a)             # -A
	var xy: Array = _addmod(x1, y1)
	var e: Array = _submod(_submod(_mulmod(xy, xy), a), b)
	var g: Array = _addmod(d, b)
	var f: Array = _submod(g, c)
	var h: Array = _submod(d, b)
	var x3: Array = _mulmod(e, f)
	var y3: Array = _mulmod(g, h)
	var t3: Array = _mulmod(e, h)
	var z3: Array = _mulmod(f, g)
	return [x3, y3, z3, t3]


# Scalar multiplication via double-and-add (MSB first).
static func _scalar_mult(scalar: Array, point: Array) -> Array:
	# Neutral element (identity): (0, 1, 1, 0).
	var result: Array = [_ZERO.duplicate(), _ONE.duplicate(), _ONE.duplicate(), _ZERO.duplicate()]
	var bits: int = _bit_length(scalar)
	for i in range(bits - 1, -1, -1):
		result = _point_double(result)
		if _get_bit(scalar, i) == 1:
			result = _point_add(result, point)
	return result


static func _point_equal(p1: Array, p2: Array) -> bool:
	# (X1/Z1, Y1/Z1) == (X2/Z2, Y2/Z2)  <=>  X1*Z2 == X2*Z1  and  Y1*Z2 == Y2*Z1
	var x1z2: Array = _mod(_mulmod(p1[0], p2[2]), _P)
	var x2z1: Array = _mod(_mulmod(p2[0], p1[2]), _P)
	if _cmp(x1z2, x2z1) != 0:
		return false
	var y1z2: Array = _mod(_mulmod(p1[1], p2[2]), _P)
	var y2z1: Array = _mod(_mulmod(p2[1], p1[2]), _P)
	return _cmp(y1z2, y2z1) == 0


# ===========================================================================
# FIELD ARITHMETIC (mod p) wrappers
# ===========================================================================
static func _addmod(a: Array, b: Array) -> Array:
	return _mod(_add(a, b), _P)

static func _submod(a: Array, b: Array) -> Array:
	# a - b mod p, handling a < b.
	var diff: Array = _sub(_add(a, _P), b)
	return _mod(diff, _P)

static func _mulmod(a: Array, b: Array) -> Array:
	return _mod(_mul(a, b), _P)

static func _powmod(base: Array, exp: Array) -> Array:
	return _powmod_m(base, exp, _P)

static func _inv(a: Array) -> Array:
	# Fermat: a^(p-2) mod p.
	return _powmod_m(a, _sub(_P, _from_int(2)), _P)


# ===========================================================================
# GENERIC BIG-INTEGER CORE (little-endian base-2^28 limb arrays, non-negative)
# ===========================================================================
static func _from_int(v: int) -> Array:
	var out: Array = []
	if v == 0:
		return [0]
	while v > 0:
		out.append(v & LIMB_MASK)
		v = v >> LIMB_BITS
	return out


static func _from_dec(s: String) -> Array:
	var acc: Array = [0]
	var ten: Array = _from_int(10)
	for ch in s:
		var digit: int = ch.unicode_at(0) - 48
		acc = _add(_mul(acc, ten), _from_int(digit))
	return _normalize(acc)


static func _from_le_bytes(bytes: PackedByteArray) -> Array:
	# Interpret bytes as a little-endian integer.
	var out: Array = [0]
	var cur: int = 0
	var cur_bits: int = 0
	# Build limbs by packing bits.
	var limbs: Array = []
	for i in range(bytes.size()):
		cur |= bytes[i] << cur_bits
		cur_bits += 8
		while cur_bits >= LIMB_BITS:
			limbs.append(cur & LIMB_MASK)
			cur = cur >> LIMB_BITS
			cur_bits -= LIMB_BITS
	if cur_bits > 0 or limbs.is_empty():
		limbs.append(cur & LIMB_MASK)
	return _normalize(limbs)


static func _to_le_bytes(a: Array, length: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(length)
	var bit: int = 0
	for i in range(length):
		var byte_val: int = 0
		for b in range(8):
			byte_val |= (_get_bit(a, bit) << b)
			bit += 1
		out[i] = byte_val
	return out


static func _normalize(a: Array) -> Array:
	var n: int = a.size()
	while n > 1 and a[n - 1] == 0:
		a.remove_at(n - 1)
		n -= 1
	return a


static func _add(a: Array, b: Array) -> Array:
	var out: Array = []
	var carry: int = 0
	var n: int = max(a.size(), b.size())
	for i in range(n):
		var av: int = a[i] if i < a.size() else 0
		var bv: int = b[i] if i < b.size() else 0
		var s: int = av + bv + carry
		out.append(s & LIMB_MASK)
		carry = s >> LIMB_BITS
	if carry > 0:
		out.append(carry)
	return out


# Assumes a >= b (non-negative result).
static func _sub(a: Array, b: Array) -> Array:
	var out: Array = []
	var borrow: int = 0
	for i in range(a.size()):
		var av: int = a[i]
		var bv: int = b[i] if i < b.size() else 0
		var s: int = av - bv - borrow
		if s < 0:
			s += LIMB_BASE
			borrow = 1
		else:
			borrow = 0
		out.append(s)
	return _normalize(out)


static func _mul(a: Array, b: Array) -> Array:
	var out: Array = []
	out.resize(a.size() + b.size())
	for i in range(out.size()):
		out[i] = 0
	for i in range(a.size()):
		var carry: int = 0
		var ai: int = a[i]
		for j in range(b.size()):
			var cur: int = out[i + j] + ai * b[j] + carry
			out[i + j] = cur & LIMB_MASK
			carry = cur >> LIMB_BITS
		var k: int = i + b.size()
		while carry > 0:
			var cur2: int = out[k] + carry
			out[k] = cur2 & LIMB_MASK
			carry = cur2 >> LIMB_BITS
			k += 1
	return _normalize(out)


# Compare: returns -1, 0, 1.
static func _cmp(a: Array, b: Array) -> int:
	var an: Array = _normalize(a.duplicate())
	var bn: Array = _normalize(b.duplicate())
	if an.size() != bn.size():
		return 1 if an.size() > bn.size() else -1
	for i in range(an.size() - 1, -1, -1):
		if an[i] != bn[i]:
			return 1 if an[i] > bn[i] else -1
	return 0


static func _is_zero(a: Array) -> bool:
	for limb in a:
		if limb != 0:
			return false
	return true


static func _is_odd(a: Array) -> int:
	return a[0] & 1


static func _div2(a: Array) -> Array:
	# Halve a non-negative big integer (floor).
	var out: Array = []
	out.resize(a.size())
	var carry: int = 0
	for i in range(a.size() - 1, -1, -1):
		var cur: int = (carry << LIMB_BITS) | a[i]
		out[i] = cur >> 1
		carry = cur & 1
	return _normalize(out)


static func _div8(a: Array) -> Array:
	return _div2(_div2(_div2(a)))


static func _shl_pow2(a: Array, bits: int) -> Array:
	# Multiply by 2^bits.
	var limb_shift: int = bits / LIMB_BITS
	var bit_shift: int = bits % LIMB_BITS
	var out: Array = []
	for i in range(limb_shift):
		out.append(0)
	var carry: int = 0
	for i in range(a.size()):
		var cur: int = (a[i] << bit_shift) | carry
		out.append(cur & LIMB_MASK)
		carry = cur >> LIMB_BITS
	if carry > 0:
		out.append(carry)
	return _normalize(out)


static func _bit_length(a: Array) -> int:
	var n: Array = _normalize(a.duplicate())
	var top: int = n.size() - 1
	if top == 0 and n[0] == 0:
		return 0
	var bits: int = top * LIMB_BITS
	var v: int = n[top]
	while v > 0:
		bits += 1
		v = v >> 1
	return bits


static func _get_bit(a: Array, index: int) -> int:
	var limb_index: int = index / LIMB_BITS
	if limb_index >= a.size():
		return 0
	var bit_index: int = index % LIMB_BITS
	return (a[limb_index] >> bit_index) & 1


# Modular reduction a mod m via long division (schoolbook, bit by bit).
static func _mod(a: Array, m: Array) -> Array:
	if _cmp(a, m) < 0:
		return _normalize(a.duplicate())
	# Bitwise long division remainder.
	var rem: Array = [0]
	var bits: int = _bit_length(a)
	for i in range(bits - 1, -1, -1):
		# rem = rem << 1 | bit_i
		rem = _shl_pow2(rem, 1)
		if _get_bit(a, i) == 1:
			rem = _add(rem, [1])
		if _cmp(rem, m) >= 0:
			rem = _sub(rem, m)
	return _normalize(rem)


static func _powmod_m(base: Array, exp: Array, m: Array) -> Array:
	var result: Array = _from_int(1)
	var b: Array = _mod(base, m)
	var bits: int = _bit_length(exp)
	for i in range(bits):
		if _get_bit(exp, i) == 1:
			result = _mod(_mul(result, b), m)
		b = _mod(_mul(b, b), m)
	return result
