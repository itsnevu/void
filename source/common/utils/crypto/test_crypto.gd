extends SceneTree

## Headless test runner for the pure-GDScript crypto stack.
##
## Uses preload() rather than the class_name globals so it runs cleanly with
## `-s` even before Godot's global class cache has been populated.

const Sha512 = preload("res://source/common/utils/crypto/sha512.gd")
const Base58 = preload("res://source/common/utils/crypto/base58.gd")
const Ed25519 = preload("res://source/common/utils/crypto/ed25519.gd")

##
## Run with:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##     --path /Users/navy/Documents/Game/godot-tiny-mmo \
##     -s res://source/common/utils/crypto/test_crypto.gd

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _hex_to_bytes(hex: String) -> PackedByteArray:
	var clean: String = hex.replace(" ", "").replace("\n", "").to_lower()
	var out: PackedByteArray = PackedByteArray()
	var i: int = 0
	while i < clean.length():
		var hi: int = "0123456789abcdef".find(clean[i])
		var lo: int = "0123456789abcdef".find(clean[i + 1])
		out.append((hi << 4) | lo)
		i += 2
	return out


func _bytes_to_hex(bytes: PackedByteArray) -> String:
	var s: String = ""
	for b in bytes:
		s += "0123456789abcdef"[b >> 4]
		s += "0123456789abcdef"[b & 0xF]
	return s


func _init() -> void:
	print("=== CRYPTO TEST SUITE ===")
	_test_sha512()
	_test_base58()
	_test_ed25519()

	print("")
	print("CRYPTO TESTS: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("Failing cases:")
		for f in _failures:
			print("  - ", f)
	quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------------------
# SHA-512
# ---------------------------------------------------------------------------
func _test_sha512() -> void:
	print("[SHA-512]")
	var empty: PackedByteArray = PackedByteArray()
	var d_empty: String = _bytes_to_hex(Sha512.hash(empty))
	_check("SHA512(\"\")",
		d_empty == "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce" +
				   "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")

	var abc: PackedByteArray = "abc".to_utf8_buffer()
	var d_abc: String = _bytes_to_hex(Sha512.hash(abc))
	_check("SHA512(\"abc\")",
		d_abc == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" +
				 "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")

	# Multi-block message (> 128 bytes) to exercise the chunk loop.
	var long_msg: String = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
	var d_long: String = _bytes_to_hex(Sha512.hash(long_msg.to_utf8_buffer()))
	_check("SHA512(NIST 112-byte vector)",
		d_long == "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018" +
				  "501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909")


# ---------------------------------------------------------------------------
# Base58
# ---------------------------------------------------------------------------
func _test_base58() -> void:
	print("[Base58]")
	# Known mapping: "1" -> single zero byte.
	var one: PackedByteArray = Base58.decode("1")
	_check("base58 decode \"1\" == [0x00]", one.size() == 1 and one[0] == 0)

	# Encode of a single zero byte -> "1".
	_check("base58 encode [0x00] == \"1\"", Base58.encode(PackedByteArray([0])) == "1")

	# Known vector (Bitcoin test): "121" -> 0x00 0x00 0x00 (three leading zeros).
	var threezeros: PackedByteArray = Base58.decode("111")
	_check("base58 decode \"111\" == [0,0,0]",
		threezeros.size() == 3 and threezeros[0] == 0 and threezeros[1] == 0 and threezeros[2] == 0)

	# Known mapping: bytes [0x00 0x00 0x00 0x00 0x00] etc not needed; test a real value.
	# 0x61 ("a") encodes to "2g" in Bitcoin base58.
	_check("base58 encode [0x61] == \"2g\"", Base58.encode(PackedByteArray([0x61])) == "2g")
	var dec_2g: PackedByteArray = Base58.decode("2g")
	_check("base58 decode \"2g\" == [0x61]", dec_2g.size() == 1 and dec_2g[0] == 0x61)

	# Round-trips over several byte arrays.
	var samples: Array[PackedByteArray] = [
		PackedByteArray([1, 2, 3, 4, 5]),
		PackedByteArray([255, 254, 253, 0, 0, 12]),
		PackedByteArray([0, 0, 1, 0, 0]),
		_hex_to_bytes("0000287fb4cd"),
	]
	var rt_ok: bool = true
	for s in samples:
		var enc: String = Base58.encode(s)
		var dec: PackedByteArray = Base58.decode(enc)
		if dec != s:
			rt_ok = false
			print("    round-trip mismatch: ", _bytes_to_hex(s), " -> ", enc, " -> ", _bytes_to_hex(dec))
	_check("base58 round-trip samples", rt_ok)

	# A 32-byte Solana-style key round-trip.
	var key: PackedByteArray = _hex_to_bytes("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
	var key_enc: String = Base58.encode(key)
	_check("base58 32-byte round-trip", Base58.decode(key_enc) == key)

	# Invalid input returns empty.
	_check("base58 invalid char -> empty", Base58.decode("0OIl").is_empty())  # 0,O,I,l are not in alphabet


# ---------------------------------------------------------------------------
# Ed25519 - RFC 8032 Section 7.1 test vectors.
# Each tuple: secret seed (unused), public key, message, signature.
# ---------------------------------------------------------------------------
func _test_ed25519() -> void:
	print("[Ed25519]")

	# TEST 1 (empty message)
	var pk1: String = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
	var msg1: String = ""
	var sig1: String = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
	_run_vector("TEST 1", pk1, msg1, sig1)

	# TEST 2 (one-byte message 0x72)
	var pk2: String = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
	var msg2: String = "72"
	var sig2: String = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
	_run_vector("TEST 2", pk2, msg2, sig2)

	# TEST 3 (two-byte message)
	var pk3: String = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"
	var msg3: String = "af82"
	var sig3: String = "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"
	_run_vector("TEST 3", pk3, msg3, sig3)

	# TEST 1024 (1023-byte long message), verbatim from the canonical
	# ed25519.cr.yp.to / RFC 8032 Section 7.1 vector.
	var pk1024: String = "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e"
	var msg1024: String = _RFC_1024_MSG()
	var sig1024: String = "0aab4c900501b3e24d7cdf4663326a3a87df5e4843b2cbdb67cbf6e460fec350aa5371b1508f9f4528ecea23c436d94b5e8fcd4f681e30a6ac00a9704a188a03"
	_run_vector("TEST 1024", pk1024, msg1024, sig1024)

	# --- Cross-vector / malformed-input hardening ---
	# A signature valid for TEST 2 must NOT verify against TEST 3's public key.
	_check("wrong public key rejected",
		not Ed25519.verify(_hex_to_bytes(msg2), _hex_to_bytes(sig2), _hex_to_bytes(pk3)))

	# Wrong-length signature / public key -> false (no crash).
	_check("short signature rejected",
		not Ed25519.verify(_hex_to_bytes(msg2), _hex_to_bytes("dead"), _hex_to_bytes(pk2)))
	_check("short public key rejected",
		not Ed25519.verify(_hex_to_bytes(msg2), _hex_to_bytes(sig2), _hex_to_bytes("dead")))

	# Non-canonical S (S >= L): set S to all 0xFF -> must be rejected.
	var bad_s_sig: PackedByteArray = _hex_to_bytes(sig2)
	for i in range(32, 64):
		bad_s_sig[i] = 0xFF
	_check("non-canonical S (>= L) rejected",
		not Ed25519.verify(_hex_to_bytes(msg2), bad_s_sig, _hex_to_bytes(pk2)))

	# End-to-end Phantom-style flow: base58 public key + raw signature bytes.
	var pk2_b58: String = Base58.encode(_hex_to_bytes(pk2))
	var pk2_decoded: PackedByteArray = Base58.decode(pk2_b58)
	_check("Phantom-style base58 pubkey verifies",
		Ed25519.verify(_hex_to_bytes(msg2), _hex_to_bytes(sig2), pk2_decoded))


func _run_vector(name: String, pk_hex: String, msg_hex: String, sig_hex: String) -> void:
	var pk: PackedByteArray = _hex_to_bytes(pk_hex)
	var msg: PackedByteArray = _hex_to_bytes(msg_hex)
	var sig: PackedByteArray = _hex_to_bytes(sig_hex)

	# Valid signature must verify true.
	_check(name + " verifies", Ed25519.verify(msg, sig, pk))

	# Tamper one byte of the message -> false (skip if empty message).
	if msg.size() > 0:
		var tampered_msg: PackedByteArray = msg.duplicate()
		tampered_msg[0] = tampered_msg[0] ^ 0x01
		_check(name + " rejects tampered message", not Ed25519.verify(tampered_msg, sig, pk))
	else:
		# For empty message, append a byte instead.
		var extended: PackedByteArray = PackedByteArray([0x00])
		_check(name + " rejects altered (empty) message", not Ed25519.verify(extended, sig, pk))

	# Tamper one byte of the signature -> false.
	var tampered_sig: PackedByteArray = sig.duplicate()
	tampered_sig[0] = tampered_sig[0] ^ 0x01
	_check(name + " rejects tampered signature", not Ed25519.verify(msg, tampered_sig, pk))

	# Tamper one byte of the S half of the signature -> false.
	var tampered_sig2: PackedByteArray = sig.duplicate()
	tampered_sig2[40] = tampered_sig2[40] ^ 0x01
	_check(name + " rejects tampered S", not Ed25519.verify(msg, tampered_sig2, pk))


# The RFC 8032 Section 7.1 "TEST 1024" message (1023 bytes), as one hex string.
func _RFC_1024_MSG() -> String:
	return "08b8b2b733424243760fe426a4b54908632110a66c2f6591eabd3345e3e4eb98" + \
		"fa6e264bf09efe12ee50f8f54e9f77b1e355f6c50544e23fb1433ddf73be84d8" + \
		"79de7c0046dc4996d9e773f4bc9efe5738829adb26c81b37c93a1b270b20329d" + \
		"658675fc6ea534e0810a4432826bf58c941efb65d57a338bbd2e26640f89ffbc" + \
		"1a858efcb8550ee3a5e1998bd177e93a7363c344fe6b199ee5d02e82d522c4fe" + \
		"ba15452f80288a821a579116ec6dad2b3b310da903401aa62100ab5d1a36553e" + \
		"06203b33890cc9b832f79ef80560ccb9a39ce767967ed628c6ad573cb116dbef" + \
		"efd75499da96bd68a8a97b928a8bbc103b6621fcde2beca1231d206be6cd9ec7" + \
		"aff6f6c94fcd7204ed3455c68c83f4a41da4af2b74ef5c53f1d8ac70bdcb7ed1" + \
		"85ce81bd84359d44254d95629e9855a94a7c1958d1f8ada5d0532ed8a5aa3fb2" + \
		"d17ba70eb6248e594e1a2297acbbb39d502f1a8c6eb6f1ce22b3de1a1f40cc24" + \
		"554119a831a9aad6079cad88425de6bde1a9187ebb6092cf67bf2b13fd65f270" + \
		"88d78b7e883c8759d2c4f5c65adb7553878ad575f9fad878e80a0c9ba63bcbcc" + \
		"2732e69485bbc9c90bfbd62481d9089beccf80cfe2df16a2cf65bd92dd597b07" + \
		"07e0917af48bbb75fed413d238f5555a7a569d80c3414a8d0859dc65a46128ba" + \
		"b27af87a71314f318c782b23ebfe808b82b0ce26401d2e22f04d83d1255dc51a" + \
		"ddd3b75a2b1ae0784504df543af8969be3ea7082ff7fc9888c144da2af58429e" + \
		"c96031dbcad3dad9af0dcbaaaf268cb8fcffead94f3c7ca495e056a9b47acdb7" + \
		"51fb73e666c6c655ade8297297d07ad1ba5e43f1bca32301651339e22904cc8c" + \
		"42f58c30c04aafdb038dda0847dd988dcda6f3bfd15c4b4c4525004aa06eeff8" + \
		"ca61783aacec57fb3d1f92b0fe2fd1a85f6724517b65e614ad6808d6f6ee34df" + \
		"f7310fdc82aebfd904b01e1dc54b2927094b2db68d6f903b68401adebf5a7e08" + \
		"d78ff4ef5d63653a65040cf9bfd4aca7984a74d37145986780fc0b16ac451649" + \
		"de6188a7dbdf191f64b5fc5e2ab47b57f7f7276cd419c17a3ca8e1b939ae49e4" + \
		"88acba6b965610b5480109c8b17b80e1b7b750dfc7598d5d5011fd2dcc5600a3" + \
		"2ef5b52a1ecc820e308aa342721aac0943bf6686b64b2579376504ccc493d97e" + \
		"6aed3fb0f9cd71a43dd497f01f17c0e2cb3797aa2a2f256656168e6c496afc5f" + \
		"b93246f6b1116398a346f1a641f3b041e989f7914f90cc2c7fff357876e506b5" + \
		"0d334ba77c225bc307ba537152f3f1610e4eafe595f6d9d90d11faa933a15ef1" + \
		"369546868a7f3a45a96768d40fd9d03412c091c6315cf4fde7cb68606937380d" + \
		"b2eaaa707b4c4185c32eddcdd306705e4dc1ffc872eeee475a64dfac86aba41c" + \
		"0618983f8741c5ef68d3a101e8a3b8cac60c905c15fc910840b94c00a0b9d0"
