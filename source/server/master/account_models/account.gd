class_name AccountResource
extends Resource


@export var id: int
@export var username: String
@export var password: String
@export var last_world_name: String
@export var last_character_id: int
## Solana wallet address (base58) that owns this account. For wallet accounts this
## equals `username` (the identity key); empty for legacy username/password accounts.
@export var wallet_address: String

# peer_id = O if not connected
var peer_id: int = 0

# Transient (NOT persisted): the single-use login nonce issued by /v1/wallet/challenge
# and consumed by /v1/wallet/login. login_nonce_at is the unix time it was issued (TTL).
var login_nonce: String = ""
var login_nonce_at: int = 0


func init(_id: int, _username: String, _password: String) -> void:
	id = _id
	username = _username
	password = _password
