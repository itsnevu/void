class_name AuthenticationManager
extends Node


## Emitted when a brand-new account is registered (NOT on a returning login). The
## master listens for this to re-broadcast the live "new players this month" count to
## the gateways, so the title-screen stat updates the moment someone joins.
signal account_created

var account_collection: AccountResourceCollection
## Production path (writable). In an exported build res:// is read-only, so
## ResourceSaver.save() against res:// silently fails and accounts can't
## persist. Mirrors the world-db split: editor reads/writes res://, exports
## live under user://. NO seed fallback - production starts blank by design,
## dev/debug accounts never leak into the live environment.
var account_collection_path: String:
	get:
		if OS.has_feature("editor"):
			return "res://source/server/master/account_collection.tres"
		return "user://master/account_collection.tres"
var active_accounts: Dictionary[StringName, AccountResource]


func _ready() -> void:
	tree_exiting.connect(save_account_collection)
	load_account_collection()


# Cryptographically-secure random token (256 bits, hex-encoded -> 64 chars). Used
# for world-handoff auth tokens and guest passwords; both need to be unguessable.
func generate_random_token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()


func create_account(username: String, password: String, is_guest: bool) -> AccountResource:
	# Account names are case-insensitive (like Discord) so "John" and "john"
	# can't both exist. Normalize to lowercase before any lookup / storage.
	if not is_guest:
		username = username.strip_edges().to_lower()
	if not is_guest and username_exists(username):
		return null
	var account_id: int = account_collection.get_new_account_id()
	if is_guest:
		username = "guest%d" % account_id
		password = generate_random_token()
	# Store only a salted, key-stretched hash - never the plaintext password.
	var new_account: AccountResource = AccountResource.new()
	new_account.init(account_id, username, PasswordHasher.hash_password(password))
	new_account.created_at_unix = int(Time.get_unix_time_from_system())
	account_collection.collection[username] = new_account
	# Save on disk should only occur at specific times.
	# Temporary work around for debug purpose.
	save_account_collection()
	account_created.emit()
	return new_account


func load_account_collection() -> void:
	if ResourceLoader.exists(account_collection_path):
		account_collection = ResourceLoader.load(account_collection_path)
	else:
		account_collection = AccountResourceCollection.new()


func save_account_collection() -> void:
	# Ensure user://master/ exists before the first save in an export build.
	if not OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute("user://master")
	ResourceSaver.save(account_collection, account_collection_path)


func username_exists(username: String) -> bool:
	return account_collection.collection.has(username.strip_edges().to_lower())


func validate_credentials(username: String, password: String) -> AccountResource:
	# Case-insensitive lookup to match create_account's lowercase normalization.
	username = username.strip_edges().to_lower()
	var account: AccountResource = null
	if account_collection.collection.has(username):
		account = account_collection.collection[username]
		if PasswordHasher.verify(password, account.password):
			return account
	return null


# --- Solana wallet auth ----------------------------------------------------
## How long a challenge nonce stays valid before the client must request a new one.
const NONCE_TTL_SECONDS: int = 300


## A Solana address is a base58-encoded 32-byte ed25519 public key - 32-44 chars,
## base58 alphabet (no 0 O I l). Cheap sanity gate before we touch the account store.
static func is_plausible_wallet_address(address: String) -> bool:
	if address.length() < 32 or address.length() > 44:
		return false
	const ALPHABET := "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
	for c: String in address:
		if not ALPHABET.contains(c):
			return false
	return true


## The wallet pubkey IS the account identity (stored as `username`, exact case - base58
## is case-sensitive, so never lowercase it). Auto-creates on first sign-in.
func get_or_create_wallet_account(wallet_address: String) -> AccountResource:
	if account_collection.collection.has(wallet_address):
		return account_collection.collection[wallet_address]
	var account_id: int = account_collection.get_new_account_id()
	var account: AccountResource = AccountResource.new()
	account.init(account_id, wallet_address, "")  # no password - wallet-only
	account.wallet_address = wallet_address
	account.created_at_unix = int(Time.get_unix_time_from_system())
	account_collection.collection[wallet_address] = account
	save_account_collection()
	account_created.emit()
	return account


## How many accounts registered since the 1st of the current calendar month (UTC).
## Drives the title screen's "new players this month" stat. Accounts predating the
## created_at_unix field (value 0) are skipped, so the count is honest, not inflated.
func count_accounts_joined_this_month() -> int:
	var now: Dictionary = Time.get_datetime_dict_from_system(true)
	var month_start: int = int(Time.get_unix_time_from_datetime_dict({
		"year": now.year, "month": now.month, "day": 1,
		"hour": 0, "minute": 0, "second": 0,
	}))
	var count: int = 0
	for account: AccountResource in account_collection.collection.values():
		if account != null and account.created_at_unix >= month_start:
			count += 1
	return count


## Step 1: mint a fresh single-use nonce for the client to sign with their wallet.
func issue_wallet_nonce(wallet_address: String) -> String:
	var account: AccountResource = get_or_create_wallet_account(wallet_address)
	account.login_nonce = generate_random_token()
	account.login_nonce_at = int(Time.get_unix_time_from_system())
	return account.login_nonce


## Step 2: verify the signed challenge. Returns the account on success, else null.
## The nonce is consumed (one-shot) regardless of outcome to block replay.
func verify_wallet_login(wallet_address: String, message: String, signature: String, nonce: String) -> AccountResource:
	var account: AccountResource = account_collection.collection.get(wallet_address)
	if not account:
		return null
	var expected: String = account.login_nonce
	account.login_nonce = ""  # one-shot: never reusable, success or fail
	if expected.is_empty() or expected != nonce:
		return null
	if int(Time.get_unix_time_from_system()) - account.login_nonce_at > NONCE_TTL_SECONDS:
		return null
	# The signed message must embed the nonce, so a signature can't be lifted from
	# another context and replayed here.
	if not message.contains(nonce):
		return null
	if not _verify_wallet_signature(wallet_address, message, signature):
		return null
	return account


## ed25519 verification of the wallet signature over the signed message bytes.
## DEV BYPASS: when the master runs from the editor (local multi-instance testing,
## where there is no Phantom extension in-process), cryptographic verification is
## skipped. Exported production servers have no "editor" feature, so real ed25519
## verification is always enforced live.
func _verify_wallet_signature(wallet_address: String, message: String, signature: String) -> bool:
	if OS.has_feature("editor"):
		return true
	var pubkey_bytes: PackedByteArray = Base58.decode(wallet_address)
	if pubkey_bytes.size() != 32:
		return false
	var sig_bytes: PackedByteArray = Base58.decode(signature)
	if sig_bytes.size() != 64:
		return false
	return Ed25519.verify(message.to_utf8_buffer(), sig_bytes, pubkey_bytes)
