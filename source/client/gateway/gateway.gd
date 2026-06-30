extends Control


const CredentialsUtils: GDScript = preload("res://source/common/utils/credentials_utils.gd")

var account_id: int
var account_name: String
var session_id: String
var local_id: String

# True once the boot handshake confirms the gateway is reachable - drives the
# Connected / Offline half of the ConnectionInfo status line.
var _server_online: bool = false

var current_world_id: int
var current_character_id: int
var selected_skin_id: int = 1

var menu_stack: Array[Control]

# Guards the empty-world-list auto-retry so only one poll loop runs at a time.
var _world_poll_active: bool = false

# "Focus navigation" mode: the player is driving the menu by keyboard or gamepad
# (not mouse/touch). We only force focus + show the focus highlight in this mode,
# so pointer users never get a stray focus ring or a popped virtual keyboard.
var _focus_nav: bool = false
# Device-aware focus ring (the theme's Button focus style is intentionally empty,
# which hides focus from mouse users - we draw our own only in _focus_nav mode).
var _focus_highlight: Panel
# Boot intro ("the menu assembles") - a one-shot Tween, editor-disabled + skippable.
var _intro_tween: Tween
# Boot "Connecting..." - a centered, pulsing label (no panel), code-built like
# Toaster/Transition. Shown during the handshake, dropped on reveal.
var _connecting_label: Label
var _connecting_pulse: Tween
# Elements the current intro is fading in - for the skip-snap.
var _intro_elements: Array[CanvasItem] = []
# The subtle backdrop zoom is a one-time boot flourish, not a per-transition tic.
var _booted: bool = false

# --- Gateway palettes -------------------------------------------------------
# Palettes live in ThemePalettes (the shared registry: slug list + styling theme + login backdrop +
# accent). We pick one (saved pref / default / random) and assign its styling Theme to `theme` -
# inheritance styles the whole subtree. The per-node looks (panel / button / divider variations) are set
# in gateway.tscn, not here. Palette preference lives in the shared client settings under [gateway].
const _SETTINGS_SECTION: StringName = &"gateway"
const _SETTING_PALETTE: StringName = &"palette"
const _SETTING_RANDOMIZE: StringName = &"randomize"
var current_theme: StringName = ThemePalettes.DEFAULT

# Community / support links opened by the global "More" menu. Empty = not provided
# yet -> that button is disabled rather than opening a dead link.
const LINK_WEBSITE: String = "https://mythreach.gg"
const LINK_DISCORD: String = "https://discord.gg/QE5JwpFzgK"
## Social: the "X" (Twitter) button on the title screen opens this. Placeholder for
## now - swap in the real Mythreach handle URL when it's live. Empty -> button hidden.
const LINK_X: String = "https://x.com/playmythreach"

## Brand logo on the main login screen (replaces the text title). Static PNG fallback
## + an optional animated version played from extracted video frames (logo_frames/).
const LOGO_PATH: String = "res://assets/sprites/gui/branding/mythreach_logo.png"
const LOGO_FRAMES_DIR: String = "res://assets/sprites/gui/branding/logo_frames/"
var _logo_rect: TextureRect
var _logo_frames: Array[Texture2D] = []
var _logo_frame_index: int = 0

# --- Title-screen footer (version + live stats + social) -------------------
# A code-built bottom strip shown only on the clean title screen (its visibility
# tracks the MainPanel). Left: live "players online" + "new this month" chips fed
# by GatewayAPI.stats(); right: the X/social button + the build version. Stats poll
# on their OWN HTTPRequest so they never collide with the shared one the auth flow
# uses (do_request bails while that node is busy).
var _title_footer: Control
var _stat_online_label: Label
var _stat_online_dot: Panel
var _stat_month_label: Label
var _stats_http: HTTPRequest
const _STATS_POLL_SECONDS: float = 20.0

# Soft, organic foley placeholders, routed through the shared AudioManager's
# polyphonic UI player (Sound bus, volume-bound to settings). Swap the files in
# assets/audio/sfx/ui/ to retune the feel without touching code.
const SFX_CLICK: String = "res://assets/audio/sfx/ui/ui_click.wav"
const SFX_BACK: String = "res://assets/audio/sfx/ui/ui_back.wav"
const SFX_HOVER: String = "res://assets/audio/sfx/ui/ui_hover.wav"
const SFX_REVEAL: String = "res://assets/audio/sfx/ui/ui_reveal.wav"
const MUSIC_GATEWAY: String = "res://assets/audio/music/angevin.ogg"

# Release-stage tag shown after the build number in the ConnectionInfo line
# ("Connected - Mythreach 0.2.0 - Alpha"). The version itself comes live from
# project.godot via GatewayAPI.game_version(), so it never drifts from the build.
const BUILD_STAGE: String = "Alpha"

# The persistent top-right "More" menu. Its nodes live in the scene (root-level,
# unique-named); only the dynamic wiring is in code. See _wire_more_menu.
@onready var _more_menu: PanelContainer = %MoreMenu
@onready var _more_backdrop: ColorRect = %MoreBackdrop
@onready var _more_logout: Button = %LogoutButton


# Character-creation skin picker - Prev/Next cycle through the whole roster (the big centre
# preview shows the current one). Sourced from PlayerSkins (every `sprites` entry), so new
# art appears here automatically - no list to maintain. Populated in prepare_character_creation_menu.
var _skin_ids: Array[int] = []
var _skin_index: int = 0
var _skin_preview: AnimatedSprite2D
var _skin_name_label: Label

@onready var main_panel: PanelContainer = $MainPanel
@onready var login_panel: PanelContainer = $LoginPanel
@onready var popup_panel: PanelContainer = $PopupPanel

@onready var back_button: Button = $BackButton

@onready var http_request: HTTPRequest = $HTTPRequest


func _ready() -> void:
	# During boot, show only a centered "Connecting..." over the backdrop - the menu and
	# the corner chrome (More / ConnectionInfo) stay hidden until the handshake passes,
	# so nothing flashes before we know the gateway's reachable + our build matches.
	main_panel.hide()
	%MoreButton.hide()
	$ConnectionInfo.hide()
	_show_connecting()
	menu_stack.append(main_panel)
	back_button.hide()

	prepare_character_creation_menu()

	# Wire the world-list refresh button (disabled in the scene until there's a
	# live endpoint to hit - now there is: GatewayAPI.worlds()).
	var update_button: Button = $WorldSelection/VBoxContainer/Button
	update_button.disabled = false
	update_button.pressed.connect(_on_world_update_button_pressed)

	_setup_focus_highlight()
	_setup_password_fields()
	_wire_more_menu()
	_wire_button_sounds()  # static + character-creation buttons exist by now
	_start_gateway_music()
	_apply_gateway_theme(_pick_startup_palette())
	ClientState.spectator = false  # reset on every return to the title screen
	_install_login_logo()
	_add_spectate_button()
	_add_whitepaper_button()
	_build_title_footer()
	# Live-apply a palette picked in the Settings menu (the gateway's own $Settings
	# overlay shows the same dropdown) - no relaunch needed.
	ClientState.settings.setting_changed.connect(_on_settings_changed)

	local_id = CmdlineUtils.get_parsed_args().get("id", "")

	await get_tree().create_timer(1.5).timeout

	# Boot gate: confirm the gateway is reachable + our build matches before any menu
	# shows. Blocks (update) or retries on failure; else resumes or reveals the menu.
	if not await _boot_handshake():
		return
	# Keep "Connecting..." up through sign-in; the reveal (menu or resume) ends boot.
	if not await try_auto_login():
		_reveal_main_menu()


## Confirm the gateway is reachable + this build matches the server before showing
## any menu. Loops on "can't reach" (Retry); on a version mismatch it shows a hard
## "update required" block and returns false. Returns true once the gateway's good.
func _boot_handshake() -> bool:
	while true:
		_show_connecting()
		var response: Dictionary = await _request_handshake()
		# Editor "Run Multiple Instances": gateway/master may still be booting, so ride
		# out pure connection / not-ready errors. Exported clients skip this.
		var attempts: int = 0
		while OS.has_feature("editor") and GatewayError.is_connection_error(response) and attempts < 20:
			attempts += 1
			await get_tree().create_timer(0.25).timeout
			response = await _request_handshake()

		if response.get("ok") == true:
			_server_online = true  # gateway reachable + build OK
			_refresh_connection_info()
			return true
		_hide_connecting()  # an error popup takes over from here
		var error: Variant = response.get("error")
		if (error is int or error is float) and int(error) == GatewayAPI.ERR_OUTDATED_VERSION:
			_block_outdated(str(response.get("msg", "")))
			return false
		# Gateway / master unreachable -> message + Retry; the press loops us around.
		await popup_panel.confirm_message(tr("ERR_CANT_REACH"), &"CANT_REACH_TITLE", &"RETRY")
	return false  # unreachable - the loop only exits via the returns above


func _request_handshake() -> Dictionary:
	return await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.handshake(),
		{GatewayAPI.KEY_CLIENT_VERSION: GatewayAPI.game_version()}
	)


## Centered "Connecting..." over the backdrop during boot - a plain pulsing label (no
## panel), up from the first frame so the player sees we're connecting immediately.
func _show_connecting() -> void:
	if _connecting_label == null:
		_connecting_label = Label.new()
		_connecting_label.text = tr("CONNECTING")
		# Fill the whole screen and center the text inside it, so the label stays
		# dead-center no matter how long the string is (PRESET_CENTER sizes to the
		# text at preset time, drifting off-center when the text changes).
		_connecting_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_connecting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_connecting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_connecting_label.add_theme_font_size_override(&"font_size", 22)
		_connecting_label.add_theme_color_override(&"font_color", Color(0.929, 0.894, 0.820))
		_connecting_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_connecting_label)
	_connecting_label.show()
	_connecting_label.modulate.a = 1.0
	if _connecting_pulse == null or not _connecting_pulse.is_valid():
		_connecting_pulse = create_tween().set_loops()
		_connecting_pulse.tween_property(_connecting_label, "modulate:a", 0.55, 0.8).set_trans(Tween.TRANS_SINE)
		_connecting_pulse.tween_property(_connecting_label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


## Drop the connecting label (kills its pulse).
func _hide_connecting() -> void:
	if _connecting_pulse and _connecting_pulse.is_valid():
		_connecting_pulse.kill()
	if _connecting_label:
		_connecting_label.hide()


# --- UI sound --------------------------------------------------------------

## Play a UI cue through the shared AudioManager. No-op when audio isn't up (a
## headless/test client frees it), so callers never have to null-check.
func _play_ui(path: String, pitch: float = 1.0) -> void:
	if is_instance_valid(Client) and Client.audio_manager:
		Client.audio_manager.play_ui_sound(path, pitch)


func _play_click() -> void:
	_play_ui(SFX_CLICK)


func _play_back() -> void:
	_play_ui(SFX_BACK)


func _play_hover() -> void:
	_play_ui(SFX_HOVER)


## Start the looping main theme from the gateway (the menu owns the boot music, not
## the networking root). Muted in the editor so it doesn't replay every iteration -
## exports hear it; for multi-client testing silence extras with --mute / --no-sfx.
func _start_gateway_music() -> void:
	if not (is_instance_valid(Client) and Client.audio_manager):
		return
	Client.audio_manager.play_music.call_deferred(MUSIC_GATEWAY, 0.0, 0.0, 5.0)


## Hover on keyboard/gamepad focus, but only while actually driving by focus - a
## mouse click also grabs focus, and we don't want that to double the click cue.
func _on_focus_hover() -> void:
	if _focus_nav:
		_play_hover()


## Give every button a soft click on press (Back gets the distinct "back" cue) and
## a quiet hover. Runtime-built cards wire themselves in their factories
## (add_world_card / the character-card loop), since those buttons don't exist yet
## at boot. Idempotent - safe to call repeatedly on the same button.
func _wire_button_sounds() -> void:
	for node: Node in find_children("*", "Button", true, false):
		_wire_button_audio(node as Button, node == back_button)


func _wire_button_audio(button: Button, is_back: bool = false) -> void:
	if button == null:
		return
	var press: Callable = _play_back if is_back else _play_click
	if not button.pressed.is_connected(press):
		button.pressed.connect(press)
	if not button.mouse_entered.is_connected(_play_hover):  # pointer hover
		button.mouse_entered.connect(_play_hover)
	if not button.focus_entered.is_connected(_on_focus_hover):  # keyboard/gamepad
		button.focus_entered.connect(_on_focus_hover)


## Hard block for an outdated client: nothing's playable on a mismatched build, so
## loop a non-dismissable "please update" (each press opens the download page).
func _block_outdated(detail: String) -> void:
	var message: String = detail if not detail.is_empty() else tr("ERR_OUTDATED")
	while true:
		await popup_panel.confirm_message(message, &"UPDATE_TITLE", &"UPDATE")
		OS.shell_open(LINK_WEBSITE)


## Reveal the main menu (no saved session): show it, focus the first action, then
## play the cosmetic intro.
func _reveal_main_menu() -> void:
	_end_boot()
	$MainPanel.show()
	$MainPanel/VBoxContainer/VBoxContainer/LoginButton.grab_focus()
	# show() + _play_intro() run in the same frame, so the welcome elements never
	# render at full alpha first - the staggered fade-in IS the reveal.
	_play_intro(_screen_elements(main_panel))


## Boot's done (menu or resume about to show): drop the connecting label and bring
## back the corner chrome (More / ConnectionInfo) that stayed hidden during connect.
func _end_boot() -> void:
	_hide_connecting()
	# The --- More menu + the bottom-left status line stay hidden on the clean title
	# screen - the More menu is shown once you're past login (see handle_success_login).


func handle_success_login(d: Dictionary) -> void:
	var worlds: Dictionary = d.get("w", {})

	session_id = d.get("session_id", 0)

	account_name = d.get("name", "")
	account_id = d.get("id", 0)
	current_character_id = d.get("character_id", 0)

	var last_world_name: String = d.get("world_name", "")
	var is_last_world_online: bool = false

	for world_id: String in worlds:
		if worlds[world_id].get("info", {}).get("name", "-1") == last_world_name:
			current_world_id = world_id.to_int()
			is_last_world_online = true

	populate_worlds(worlds)

	_end_boot()
	(%MoreButton as Button).show()  # past login -> expose the More menu (settings / logout)
	fill_connection_info(account_name, account_id)
	if is_last_world_online:
		$AlreadyConnectedPanel/ContinueButton.text = tr("CONTINUE_WORLD_ACC") % [last_world_name, account_name]
		_show($AlreadyConnectedPanel, false)
	else:
		_show($WorldSelection, false)


func do_request(
	method: HTTPClient.Method,
	path: String,
	payload: Dictionary,
) -> Dictionary:
	if http_request.get_http_client_status() == HTTPClient.Status.STATUS_CONNECTED:
		return {"error": "request_error"}

	var custom_headers: PackedStringArray
	custom_headers.append("Content-Type: application/json")
	
	var error: Error = http_request.request(
		path,
		custom_headers,
		method,
		JSON.stringify(payload)
	)

	if error != OK:
		push_error("An error occurred in the HTTP request.")
		return {ok=false, error="request_error", code=error}

	var args: Array = await http_request.request_completed
	var result: int = args[0]
	if result != OK:
		return {"error": "connection_failed", "code": result}

	var response_code: int = args[1]
	var headers: PackedStringArray = args[2]
	var body: PackedByteArray = args[3]

	var data: Variant = JSON.parse_string(body.get_string_from_ascii())
	if data is Dictionary:
		return data
	return {"error": "bad_response"}


func _show(next: Control, can_back: bool = true) -> void:
	_hide_connecting()  # a real screen is appearing -> connecting is done
	if menu_stack.size():
		menu_stack.back().hide()
	if not can_back:
		menu_stack.clear()
	next.show()
	menu_stack.append(next)
	back_button.visible = can_back
	# Land the keyboard/gamepad cursor on the new panel's first control so a
	# non-mouse player always has somewhere to navigate from.
	if _focus_nav:
		_focus_first_in(next)
	_play_intro(_screen_elements(next))  # staggered fade-in on every forward transition


# --- Boot intro ------------------------------------------------------------

## Cosmetic "assembles into place" reveal for ANY screen: a staggered fade-in of the
## given elements (+ a one-time backdrop zoom on the first boot reveal). Cut short by
## any input. Never gates interactivity - pure decoration over already-shown nodes.
func _play_intro(elements: Array[CanvasItem]) -> void:
	_finish_intro()  # snap any in-flight intro to done first (fast navigation)
	_intro_elements = elements
	for element: CanvasItem in elements:
		element.modulate.a = 0.0

	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if not _booted:  # the subtle backdrop zoom is a one-time boot flourish
		_booted = true
		_play_ui(SFX_REVEAL)  # soft "menu assembles" cue, once per session
		var background: Sprite2D = $Background
		var cover: Vector2 = background.scale
		background.scale = cover * 1.06
		_intro_tween.tween_property(background, "scale", cover, 1.2)
	var delay: float = 0.0
	for element: CanvasItem in elements:
		_intro_tween.tween_property(element, "modulate:a", 1.0, 0.4).set_delay(delay)
		delay += 0.08


## Generic: the visual elements to stagger-fade for a screen - its title, divider,
## and buttons / cards. Uses the panel's content column (its first VBoxContainer if
## it has one, else the panel itself) and flattens one level of button/card rows so
## they stagger individually. Replaces the old per-screen hardcoded lists, so every
## screen (world / character select, character creation, ...) animates for free.
func _screen_elements(panel: Control) -> Array[CanvasItem]:
	var column: Node = panel
	for child: Node in panel.get_children():
		if child is VBoxContainer:
			column = child
			break
	var elements: Array[CanvasItem] = []
	for child: Node in column.get_children():
		if child is BoxContainer:  # a row/column of buttons or cards -> stagger its items
			for item: Node in child.get_children():
				if item is CanvasItem and (item as CanvasItem).visible:
					elements.append(item as CanvasItem)
		elif child is CanvasItem and (child as CanvasItem).visible:
			elements.append(child as CanvasItem)
	return elements


## Snap the intro to its finished state (on any input, or if it never ran).
func _finish_intro() -> void:
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = null
	for element: CanvasItem in _intro_elements:
		if is_instance_valid(element):
			element.modulate.a = 1.0
	_apply_theme_background(ThemePalettes.backdrop(current_theme))


# _input (not _unhandled_input): when a control has focus the GUI consumes
# navigation events, so they'd never reach _unhandled_input. We only observe the
# device here - we don't swallow navigation.
func _input(event: InputEvent) -> void:
	# Any press cuts the cosmetic intro short (without consuming the event).
	if _intro_tween and _intro_tween.is_valid() and event.is_pressed():
		_finish_intro()

	# Keyboard or gamepad -> focus-nav mode; mouse/touch -> pointer mode. Guarded on
	# transitions so this stays cheap despite per-frame mouse-motion / stick events.
	if (event is InputEventKey and (event as InputEventKey).pressed) \
			or event is InputEventJoypadButton \
			or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		if not _focus_nav:
			_focus_nav = true
			set_process(true)  # only track the ring while actually focus-navigating
			_refresh_focus_highlight()
	elif event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch:
		if _focus_nav:
			_focus_nav = false
			_focus_highlight.hide()
			set_process(false)

	# B / Escape steps back, mirroring the on-screen Back button - but not while a
	# popup is up (it owns the screen).
	if event.is_action_pressed(&"ui_cancel") and back_button.visible and not popup_panel.visible:
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()

	# Debug: cycle the gateway palette (gold -> horizon -> forest -> fireforge).
	if event is InputEventKey and (event as InputEventKey).pressed \
			and ((event as InputEventKey).keycode == KEY_F3 \
			or (event as InputEventKey).physical_keycode == KEY_F3):
		_cycle_theme()


## Grab focus on the first visible, focusable Control under `node` (depth-first).
## Returns true once it lands focus somewhere.
func _focus_first_in(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is Control:
			var control: Control = child
			if not control.visible:
				continue
			if control.focus_mode != Control.FOCUS_NONE:
				control.grab_focus()
				return true
		if _focus_first_in(child):
			return true
	return false


# --- Wallet sign-in (Solana / Phantom) ------------------------------------
# Mythreach is wallet-only. On WEB we drive the Phantom browser extension via
# JavaScriptBridge (connect + signMessage). On DESKTOP (no in-process wallet) we
# use a persisted local "dev wallet" so the game stays testable locally - the
# master skips signature verification only when it runs from the editor.

## The human-readable line the player signs. The server-issued nonce is appended so
## each signature is single-use and bound to this login.
const WALLET_MESSAGE_PREFIX: String = "Sign in to Mythreach\n\nnonce: "

## Phantom bridge, eval'd once on web. Exposes window.MythreachWallet.{connect,signMessage}
## which stash their async results on window.__aeth so GDScript can poll them.
const WALLET_SHIM_JS: String = """
window.__aeth = window.__aeth || {status:'', pubkey:'', signature:'', error:''};
window.MythreachWallet = {
  _provider: function(){
    if (window.phantom && window.phantom.solana && window.phantom.solana.isPhantom) return window.phantom.solana;
    if (window.solana && window.solana.isPhantom) return window.solana;
    return null;
  },
  _b58: function(bytes){
    var A='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var d=[],s='',i,j,c;
    for(i=0;i<bytes.length;i++){ c=bytes[i];
      for(j=0;j<d.length;j++){ c+=d[j]<<8; d[j]=c%58; c=(c/58)|0; }
      while(c>0){ d.push(c%58); c=(c/58)|0; } }
    for(i=0;i<bytes.length&&bytes[i]===0;i++) s+=A[0];
    for(i=d.length-1;i>=0;i--) s+=A[d[i]];
    return s;
  },
  connect: async function(){
    window.__aeth.status='pending'; window.__aeth.error=''; window.__aeth.pubkey='';
    try { var p=this._provider(); if(!p){ window.__aeth.status='nowallet'; return; }
      var res=await p.connect(); window.__aeth.pubkey=res.publicKey.toString(); window.__aeth.status='ok';
    } catch(e){ window.__aeth.error=String(e); window.__aeth.status='error'; }
  },
  signMessage: async function(msg){
    window.__aeth.status='pending'; window.__aeth.error=''; window.__aeth.signature='';
    try { var p=this._provider(); if(!p){ window.__aeth.status='nowallet'; return; }
      var enc=new TextEncoder().encode(msg); var signed=await p.signMessage(enc,'utf8');
      window.__aeth.signature=this._b58(signed.signature); window.__aeth.status='ok';
    } catch(e){ window.__aeth.error=String(e); window.__aeth.status='error'; }
  }
};
"""

var _wallet_shim_ready: bool = false


## Entry point from the single "Connect Wallet" main-menu button.
func _on_login_button_pressed() -> void:
	var login_button: Button = $MainPanel/VBoxContainer/VBoxContainer/LoginButton
	login_button.disabled = true
	var pubkey: String = await _wallet_get_pubkey()
	if pubkey.is_empty():
		login_button.disabled = false
		await popup_panel.confirm_message(tr("ERR_NO_WALLET"))
		return
	main_panel.hide()
	_show_connecting()
	var ok: bool = await _do_wallet_login(pubkey, false)
	if not ok:
		_hide_connecting()
		main_panel.show()
		login_button.disabled = false


## Run the full challenge -> sign -> verify handshake for a pubkey. Returns true on a
## successful login (worlds populated, selection shown). `silent` suppresses error popups
## (used by auto-login). On success calls handle_success_login(), reusing the old path.
func _do_wallet_login(pubkey: String, silent: bool, dev_sign: bool = false) -> bool:
	# 1. Ask the server for a fresh nonce to sign.
	var challenge: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.wallet_challenge(),
		{GatewayAPI.KEY_WALLET_PUBKEY: pubkey}
	)
	if challenge.has("error"):
		if not silent:
			_hide_connecting()  # drop "Connecting..." so it doesn't overlap the error popup
			await popup_panel.confirm_message(GatewayError.humanize(challenge))
		return false
	var nonce: String = str(challenge.get(GatewayAPI.KEY_WALLET_NONCE, ""))
	if nonce.is_empty():
		return false

	# 2. Sign the nonce-bound message with the wallet. Spectators sign with the local
	# dev key (no Phantom popup) even on web - they don't need a real wallet to watch.
	var message: String = WALLET_MESSAGE_PREFIX + nonce
	var signature: String
	if dev_sign:
		signature = _dev_wallet_sign(message)  # spectator: real ed25519 sig, no Phantom popup
	else:
		signature = await _wallet_sign(message)
	if signature.is_empty():
		if not silent:
			_hide_connecting()  # drop "Connecting..." so it doesn't overlap the error popup
			await popup_panel.confirm_message(tr("ERR_WALLET_REJECTED"))
		return false

	# 3. Submit for verification + login.
	var response: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.wallet_login(),
		{
			GatewayAPI.KEY_WALLET_PUBKEY: pubkey,
			GatewayAPI.KEY_WALLET_SIGNATURE: signature,
			GatewayAPI.KEY_WALLET_NONCE: nonce,
			GatewayAPI.KEY_WALLET_MESSAGE: message,
			GatewayAPI.KEY_CLIENT_VERSION: GatewayAPI.game_version(),
		}
	)
	if response.has("error"):
		if not silent:
			_hide_connecting()  # drop "Connecting..." so it doesn't overlap the error popup
			await popup_panel.confirm_message(GatewayError.humanize(response))
		return false

	session_id = response.get("session_id", "")
	_save_wallet_pubkey(pubkey)
	handle_success_login(response)
	return true


## Get the wallet public key (base58): Phantom on web, the persisted dev wallet on desktop.
func _wallet_get_pubkey() -> String:
	if OS.has_feature("web"):
		_ensure_wallet_shim()
		JavaScriptBridge.eval("window.MythreachWallet.connect();", true)
		if await _poll_wallet_status() != "ok":
			return ""
		return str(JavaScriptBridge.eval("window.__aeth.pubkey || '';", true))
	return _dev_wallet_pubkey()


## Sign a message and return the base58 signature ("" on rejection/failure).
func _wallet_sign(message: String) -> String:
	if OS.has_feature("web"):
		_ensure_wallet_shim()
		JavaScriptBridge.eval("window.MythreachWallet.signMessage(%s);" % JSON.stringify(message), true)
		if await _poll_wallet_status() != "ok":
			return ""
		return str(JavaScriptBridge.eval("window.__aeth.signature || '';", true))
	# Desktop dev: sign the nonce with the local dev-wallet seed - a real ed25519
	# signature the master verifies even when exported (no editor bypass needed).
	return _dev_wallet_sign(message)


func _ensure_wallet_shim() -> void:
	if _wallet_shim_ready:
		return
	JavaScriptBridge.eval(WALLET_SHIM_JS, true)
	_wallet_shim_ready = true


## Poll window.__aeth.status until the async wallet call settles. Returns the final
## status ("ok" / "error" / "nowallet" / "timeout").
func _poll_wallet_status() -> String:
	var elapsed: float = 0.0
	while elapsed < 120.0:
		await get_tree().create_timer(0.15).timeout
		var status: String = str(JavaScriptBridge.eval("window.__aeth.status || '';", true))
		if status != "pending":
			return status
		elapsed += 0.15
	return "timeout"


## A stable local "dev wallet" address for desktop testing - 32 random bytes, base58,
## persisted per local id so the same dev account is reused across launches.
## The local "dev wallet" is a REAL ed25519 keypair. It used to be 32 random bytes
## passed off as a pubkey, signed with a random signature - which only ever passed the
## master's editor-only verification bypass. On an exported server (the live VPS) the
## fake signature is rejected, so Spectate failed with "Incorrect account name or
## password." We now persist the 32-byte private SEED and derive the pubkey + sign the
## login nonce for real, so spectators / desktop-dev produce a signature the live
## server actually verifies - no Phantom extension needed. base58 throughout (Phantom).
var _dev_pubkey_cache: String = ""


func _dev_wallet_seed() -> PackedByteArray:
	var path: String = "user://%swallet_seed.dat" % local_id
	if FileAccess.file_exists(path):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f:
			var saved: String = f.get_as_text().strip_edges()
			f.close()
			var bytes: PackedByteArray = Base58.decode(saved)
			if bytes.size() == 32:
				return bytes
	var seed: PackedByteArray = Crypto.new().generate_random_bytes(32)
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out:
		out.store_string(Base58.encode(seed))
		out.close()
	return seed


## The dev wallet's public key (base58) - the account identity the master sees.
## Cached: deriving it is a scalar multiply we don't want to repeat each login.
func _dev_wallet_pubkey() -> String:
	if _dev_pubkey_cache.is_empty():
		_dev_pubkey_cache = Base58.encode(Ed25519.derive_public_key(_dev_wallet_seed()))
	return _dev_pubkey_cache


## Sign `message` with the dev-wallet seed, returning a base58 ed25519 signature the
## master verifies like any Phantom signature. Reuses the cached pubkey to skip a
## scalar multiply.
func _dev_wallet_sign(message: String) -> String:
	return Base58.encode(Ed25519.sign(
		message.to_utf8_buffer(),
		_dev_wallet_seed(),
		Base58.decode(_dev_wallet_pubkey())
	))


func _save_wallet_pubkey(pubkey: String) -> void:
	save_refresh_token(pubkey, "user://%ssession.dat" % local_id)


func _on_login_login_button_pressed() -> void:
	var account_name_edit: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer/LineEdit
	var password_edit: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit

	var username: String = account_name_edit.text
	var password: String = password_edit.text

	var login_button: Button = $LoginPanel/VBoxContainer/VBoxContainer/LoginButton
	login_button.disabled = true
	if (
		CredentialsUtils.validate_username(username).code != CredentialsUtils.UsernameError.OK
		or CredentialsUtils.validate_password(password).code != CredentialsUtils.UsernameError.OK
	):
		#await popup_panel.confirm_message(str(response))
		login_button.disabled = false
		return

	login_panel.hide()  # hide the form so the label sits over the backdrop, not the menu
	_show_connecting()
	var response: Dictionary = await request_login(username, password)
	if response.has("error"):
		_hide_connecting()
		await popup_panel.confirm_message(GatewayError.humanize(response))
		login_panel.show()
		login_button.disabled = false
		return

	session_id = response.get("session_id")

	save_refresh_token("%s\n%s" % [username, password], "user://%ssession.dat" % local_id)

	
	populate_worlds(response.get("w", {}))
	fill_connection_info(response["name"], response["id"])

	_show($WorldSelection, false)


func _on_guest_button_pressed() -> void:
	main_panel.hide()  # hide the menu so the label sits over the backdrop, not the menu
	_show_connecting()

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.guest(),
		{}
	)
	if d.has("error"):
		_hide_connecting()
		await popup_panel.confirm_message(GatewayError.humanize(d))
		main_panel.show()
		return

	session_id = d.get("session_id", 0)

	fill_connection_info(d.get("name", ""), d.get("id", 0))
	populate_worlds(d.get("w", {}))

	_show($WorldSelection, false)


func _on_world_selected(world_id: int) -> void:
	$WorldSelection.hide()
	_show_connecting()
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_characters(),
		{
			GatewayAPI.KEY_WORLD_ID: world_id,
			GatewayAPI.KEY_ACCOUNT_ID: account_id,
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_TOKEN_ID: session_id
		}
	)
	if d.has("error"):
		_hide_connecting()
		await popup_panel.confirm_message(GatewayError.humanize(d))
		$WorldSelection.show()
		return

	var container: HBoxContainer = $CharacterSelection/VBoxContainer/HBoxContainer
	var character_ids: Array = d.keys()
	var slots: Array[Node] = container.get_children()
	for slot_index: int in slots.size():
		var button: Button = slots[slot_index]
		# Wrap so the long "Create New Character" card stays the same width as the
		# others instead of stretching wider.
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Clear prior card content (portrait + label from a previously-shown world).
		for content: Node in button.get_children():
			content.queue_free()
		# Connections are bound callables, so is_connected(unbound) never matched -
		# clear every prior connection so re-entering doesn't stack duplicates.
		for conn: Dictionary in button.pressed.get_connections():
			button.pressed.disconnect(conn["callable"])
		_wire_button_audio(button)  # re-add click+hover: the clear above dropped pressed
		# Slot index tracks the button position directly (the old manual counter
		# skipped its increment on `continue`, desyncing every later slot).
		if slot_index < character_ids.size():
			var cid: String = str(character_ids[slot_index])
			var entry: Dictionary = d.get(cid, {})
			if entry.has_all(["name", "level"]):  # "class" dropped - no classes anymore
				_fill_character_card(button, entry)
				button.pressed.connect(_on_character_selected.bind(world_id, cid.to_int()))
				continue
		button.text = tr("CREATE_NEW_CHAR")
		button.pressed.connect(_on_character_selected.bind(world_id, -1))
	popup_panel.hide()
	_show($CharacterSelection)


func _on_character_selected(world_id: int, character_id: int) -> void:
	current_world_id = world_id
	if character_id == -1:
		_show($CharacterCreation)
		return

	$CharacterSelection.hide()
	$BackButton.hide()
	_show_connecting()  # plain label, not a panel - the Transition cover takes over

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_enter(),
		{
			GatewayAPI.KEY_TOKEN_ID: session_id,
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_WORLD_ID: world_id,
			GatewayAPI.KEY_CHAR_ID: character_id
		}
	)
	if d.has("error"):
		_hide_connecting()
		await popup_panel.confirm_message(GatewayError.humanize(d))
		$CharacterSelection.show()
		$BackButton.show()
		return

	Transition.start_world_load(d["address"], d["port"], d["auth-token"], $Background.texture)
	queue_free.call_deferred()


## Dress an existing-character card: the character's actual sprite (idle pose) up
## top, name + level pinned to the bottom. Children use MOUSE_FILTER_IGNORE so the
## card button still receives the click.
func _fill_character_card(button: Button, entry: Dictionary) -> void:
	button.text = ""
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", int(entry.get("skin", 1))) as SpriteFrames
	if frames:
		var portrait: AnimatedSprite2D = AnimatedSprite2D.new()
		portrait.sprite_frames = frames
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel sprite
		portrait.scale = Vector2(2.4, 2.4)
		portrait.position = Vector2(75.0, 100.0)  # upper-centre of the 150x250 card
		var anim: StringName = _card_anim(frames)
		if not anim.is_empty():
			portrait.play(anim)
		button.add_child(portrait)
	var info: Label = Label.new()
	info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_top = -54.0
	info.offset_bottom = -12.0
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.text = tr("NAME_LEVEL") % [entry["name"], entry["level"]]
	button.add_child(info)


## Prefer an idle pose for the card, fall back to run, then the first animation.
func _card_anim(frames: SpriteFrames) -> StringName:
	for candidate: StringName in [&"idle", &"run"]:
		if frames.has_animation(candidate):
			return candidate
	var names: PackedStringArray = frames.get_animation_names()
	if not names.is_empty():
		return StringName(names[0])
	return &""


func _on_create_character_button_pressed() -> void:
	var username_edit: LineEdit = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer2/LineEdit

	var create_button: Button = $CharacterCreation/VBoxContainer/VBoxContainer/CreateButton
	create_button.disabled = true
	$BackButton.hide()
	$CharacterCreation.hide()

	var result: Dictionary
	result = CredentialsUtils.validate_username(username_edit.text)
	if result.code != CredentialsUtils.UsernameError.OK:
		await popup_panel.confirm_message(tr("USERNAME") + result.message)
		create_button.disabled = false
		$BackButton.show()
		$CharacterCreation.show()
		return

	_show_connecting()  # plain label, not a panel - the Transition cover takes over
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_create_char(),
		{
			GatewayAPI.KEY_TOKEN_ID: session_id,
			"data": {
				"name": username_edit.text,
				"skin": selected_skin_id,
			},
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_WORLD_ID: current_world_id
		}
	)
	if d.has("error"):
		_hide_connecting()
		await popup_panel.confirm_message(GatewayError.humanize(d))
		create_button.disabled = false
		$CharacterCreation.show()
		return

	Transition.start_world_load(d["address"], d["port"], d["auth-token"], $Background.texture)
	queue_free.call_deferred()


func create_account() -> void:
	var name_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer/LineEdit
	var password_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	var password_repeat_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer3/LineEdit

	if password_edit.text != password_repeat_edit.text:
		await popup_panel.confirm_message(tr("PASSWORDS_DONT_MATCH"))
		return
	
	var result: Dictionary
	result = CredentialsUtils.validate_username(name_edit.text)
	if result.code != CredentialsUtils.UsernameError.OK:
		await popup_panel.confirm_message(tr("USERNAME") + result.message)
		return
	result = CredentialsUtils.validate_password(password_edit.text)
	if result.code != CredentialsUtils.UsernameError.OK:
		await popup_panel.confirm_message(tr("PASSWORD") + ":\n" + result.message)
		return
	
	$CreateAccountPanel.hide()
	_show_connecting()

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.account_create(),
		{
			GatewayAPI.KEY_ACCOUNT_USERNAME: name_edit.text,
			GatewayAPI.KEY_ACCOUNT_PASSWORD: password_edit.text,
		}
	)
	if d.has("error"):
		_hide_connecting()
		await popup_panel.confirm_message(GatewayError.humanize(d))
		$CreateAccountPanel.show()
		return
	
	save_refresh_token(name_edit.text + "\n" + password_edit.text, "user://%ssession.dat" % local_id)


	fill_connection_info(d["name"], d["id"])
	populate_worlds(d.get("w", {}))
	
	_show($WorldSelection, false)


func _on_create_account_button_pressed() -> void:
	_show($CreateAccountPanel)


func populate_worlds(world_info: Dictionary) -> void:
	var container: HBoxContainer = $WorldSelection/VBoxContainer/HBoxContainer
	for child: Node in container.get_children():
		child.queue_free()

	if world_info.is_empty():
		# No world online: show a clear in-place message (not a dead-end countdown
		# popup) and quietly auto-retry while the player stays on this screen. They
		# can also hit Update to refresh manually.
		var empty_label: Label = Label.new()
		empty_label.text = tr("NO_WORLDS_ONLINE")
		empty_label.custom_minimum_size = Vector2(360.0, 250.0)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		container.add_child(empty_label)
		_poll_worlds_while_empty()
		return

	for world_id: String in world_info:
		add_world_card(world_info.get(world_id, {}).get("info", {}), world_id.to_int())

	# A fresh list just arrived - lock Update briefly so it can't be spammed (the
	# boot-time list counts too, since this runs on every populate).
	_start_update_cooldown()


func _on_world_update_button_pressed() -> void:
	await refresh_worlds()


## Re-fetch the live world list from the gateway without re-logging-in. Cheap -
## the gateway serves it from its cached roster (GatewayAPI.worlds()).
func refresh_worlds() -> void:
	var update_button: Button = $WorldSelection/VBoxContainer/Button
	update_button.disabled = true
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.worlds(),
		{}
	)
	if d.has("error"):
		update_button.disabled = false  # request failed - allow an immediate retry
		return
	populate_worlds(d.get("w", {}))  # success -> populate starts the cooldown


## Lock the Update button for 5s after a refresh so it can't be hammered.
func _start_update_cooldown() -> void:
	var update_button: Button = $WorldSelection/VBoxContainer/Button
	update_button.disabled = true
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(update_button):
		update_button.disabled = false


## While the list is empty and the player is still on the selection screen,
## quietly re-poll so a world coming online appears without a manual refresh.
## Guarded by _world_poll_active so only one loop ever runs.
func _poll_worlds_while_empty() -> void:
	if _world_poll_active:
		return
	_world_poll_active = true
	# populate_worlds() runs just before the caller shows WorldSelection, so let
	# that happen before we gate the loop on the panel's visibility.
	await get_tree().process_frame
	while $WorldSelection.visible:
		await get_tree().create_timer(5.0).timeout
		if not $WorldSelection.visible:
			break
		var d: Dictionary = await do_request(
			HTTPClient.Method.METHOD_POST,
			GatewayAPI.worlds(),
			{}
		)
		if d.has("error"):
			continue
		var w: Dictionary = d.get("w", {})
		if not w.is_empty():
			_world_poll_active = false
			populate_worlds(w)
			return
	_world_poll_active = false


func fill_connection_info(_account_name: String, _account_id: int) -> void:
	account_name = _account_name
	account_id = _account_id
	_refresh_connection_info()


## The bottom-left status line, two rows: "<Connected/Offline> - <account / not logged
## in>" then "Mythreach <version> <stage>". Built in one place so the build version is
## ALWAYS shown - logged in or not. Version is live from project.godot (never drifts
## from the handshake gate); the account-ID (old dev-only debug) is intentionally gone.
func _refresh_connection_info() -> void:
	var status: String = tr("STATUS_ONLINE") if _server_online else tr("STATUS_OFFLINE")
	var who: String = _short_wallet(account_name) if not account_name.is_empty() else tr("NOT_LOGGED_IN")
	var game: String = str(ProjectSettings.get_setting("application/config/name", "Mythreach"))
	$ConnectionInfo.text = "%s - %s\n%s %s %s" % [
		status, who, game, GatewayAPI.game_version(), BUILD_STAGE
	]


## Swap the text title for the brand logo (animated video frames if available, else
## the static PNG) on the login screen. The art has an opaque black background, so we
## (a) deepen the backdrop and (b) put a soft RADIAL BLACK HALO directly behind it -
## the square's hard edge dissolves into black instead of showing a visible cut.
func _install_login_logo() -> void:
	var frames: Array[Texture2D] = _load_logo_frames()
	var static_tex: Texture2D = load(LOGO_PATH) as Texture2D if ResourceLoader.exists(LOGO_PATH) else null
	if frames.is_empty() and static_tex == null:
		return  # nothing to show - keep the text title

	# The logo is the title now - hide the text title + its divider.
	($MainPanel/VBoxContainer/Label as Control).hide()
	($MainPanel/VBoxContainer/HSeparator as Control).hide()

	# Hero box holding the halo (behind) + the logo (front).
	var hero: Control = Control.new()
	hero.custom_minimum_size = Vector2(300.0, 165.0)
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# A seamless CIRCLE of black behind the logo only (centered, overflowing the
	# hero box - Controls don't clip): solid black across the logo's square, fading
	# to fully transparent so the background stays visible everywhere else. The
	# logo's opaque-black art sits entirely inside the solid core, so no square cut.
	var halo: TextureRect = TextureRect.new()
	halo.texture = _make_radial_black()
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.set_anchors_preset(Control.PRESET_CENTER)
	halo.offset_left = -175.0
	halo.offset_top = -255.0
	halo.offset_right = 175.0
	halo.offset_bottom = 255.0
	hero.add_child(halo)

	_logo_rect = TextureRect.new()
	_logo_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_rect.texture = frames[0] if not frames.is_empty() else static_tex
	hero.add_child(_logo_rect)

	var column: VBoxContainer = $MainPanel/VBoxContainer
	column.add_child(hero)
	column.move_child(hero, 0)  # above the Connect Wallet button

	# Loop the frames (extracted at 10 fps) if we have them.
	if not frames.is_empty():
		_logo_frames = frames
		var timer: Timer = Timer.new()
		timer.wait_time = 0.1
		timer.autostart = true
		timer.timeout.connect(_advance_logo_frame)
		add_child(timer)

	# Darken the backdrop SPRITE directly (modulate is foolproof - no layering/overlay
	# z-order surprises): the map dims to a moody ~35% brightness so the logo's radial
	# halo melts into it seamlessly, while the map stays faintly visible.
	$Background.modulate = Color(0.35, 0.35, 0.4, 1.0)
	$BackgroundRect.color = Color(0.02, 0.025, 0.04, 0.45)
	# Drop the bottom-left status line on the title screen.
	$ConnectionInfo.hide()


func _advance_logo_frame() -> void:
	if _logo_frames.is_empty() or not is_instance_valid(_logo_rect):
		return
	_logo_frame_index = (_logo_frame_index + 1) % _logo_frames.size()
	_logo_rect.texture = _logo_frames[_logo_frame_index]


## Load the extracted logo video frames (f_001.png, f_002.png, ...) by index until a
## gap. ResourceLoader.exists + load resolve imported textures in editor AND export,
## so we avoid fragile DirAccess enumeration of res://.
func _load_logo_frames() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i: int in range(1, 500):
		var path: String = "%sf_%03d.png" % [LOGO_FRAMES_DIR, i]
		if not ResourceLoader.exists(path):
			break
		var t: Texture2D = load(path) as Texture2D
		if t != null:
			out.append(t)
	return out


## A radial gradient: solid black core fading to transparent at the edge - the soft
## black backing that hides the logo art's square cut.
func _make_radial_black() -> Texture2D:
	var grad: Gradient = Gradient.new()
	# Solid black across the logo's footprint, then a soft fade to transparent so it
	# melts into the visible backdrop (no hard ring, no square cut).
	grad.offsets = PackedFloat32Array([0.0, 0.80, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 1.0), Color(0, 0, 0, 1.0), Color(0, 0, 0, 0.0)])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


## Add a "Spectate" button under Connect Wallet - drop into the world as a
## non-combatant fireball (local dev identity, no real wallet needed: just watch).
func _add_spectate_button() -> void:
	var column: VBoxContainer = $MainPanel/VBoxContainer/VBoxContainer
	var btn: Button = Button.new()
	btn.name = "SpectateButton"
	btn.text = "Spectate"
	btn.custom_minimum_size = Vector2(420.0, 48.0)
	btn.theme_type_variation = &"FrameButton"
	btn.add_theme_font_size_override(&"font_size", 16)
	btn.pressed.connect(_on_spectate_pressed)
	_wire_button_audio(btn)
	column.add_child(btn)


func _on_spectate_pressed() -> void:
	var btn: Button = $MainPanel/VBoxContainer/VBoxContainer.get_node_or_null(^"SpectateButton") as Button
	if btn:
		btn.disabled = true
	ClientState.spectator = true
	var pubkey: String = _dev_wallet_pubkey()
	if pubkey.is_empty():
		ClientState.spectator = false
		if btn: btn.disabled = false
		return
	main_panel.hide()
	_show_connecting()
	# dev_sign = true -> no Phantom popup; spectators just watch.
	if not await _do_wallet_login(pubkey, false, true) or not await _auto_enter_world():
		ClientState.spectator = false
		_hide_connecting()
		main_panel.show()
		if btn: btn.disabled = false


## A small "Whitepaper" button under Spectate - opens the in-app whitepaper panel.
func _add_whitepaper_button() -> void:
	var column: VBoxContainer = $MainPanel/VBoxContainer/VBoxContainer
	var btn: Button = Button.new()
	btn.text = "Whitepaper"
	btn.custom_minimum_size = Vector2(420.0, 38.0)
	btn.theme_type_variation = &"FrameButton"
	btn.add_theme_font_size_override(&"font_size", 14)
	btn.pressed.connect(_show_whitepaper)
	_wire_button_audio(btn)
	column.add_child(btn)


# --- Title-screen footer (version + live stats + social) -------------------

## Build the bottom strip: live "players online" + "new this month" chips on the
## left, the X/social button + build version on the right. It lives on the Gateway
## root (not in MainPanel) so it sits flush to the screen bottom, and its visibility
## tracks MainPanel - it's a title-screen-only flourish.
func _build_title_footer() -> void:
	# Dedicated request node so polling stats never trips the shared $HTTPRequest the
	# auth flow uses (do_request returns "request_error" while that one is mid-call).
	_stats_http = HTTPRequest.new()
	_stats_http.timeout = 7.0
	add_child(_stats_http)

	var footer: Control = Control.new()
	footer.name = "TitleFooter"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -58.0
	footer.offset_bottom = 0.0
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.z_index = 5
	_title_footer = footer

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 26)
	margin.add_theme_constant_override(&"margin_right", 26)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	footer.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	# Left: the two live-stat chips.
	var stats_row: HBoxContainer = HBoxContainer.new()
	stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_row.add_theme_constant_override(&"separation", 10)
	stats_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stats_row)

	# "Players online" chip: a status dot + count.
	var online_box: HBoxContainer = HBoxContainer.new()
	online_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_box.add_theme_constant_override(&"separation", 8)
	online_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_stat_online_dot = Panel.new()
	_stat_online_dot.custom_minimum_size = Vector2(10.0, 10.0)
	_stat_online_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stat_online_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_style: StyleBoxFlat = StyleBoxFlat.new()
	dot_style.bg_color = Color(0.5, 0.5, 0.55)  # gray until the first count lands
	dot_style.set_corner_radius_all(5)
	_stat_online_dot.add_theme_stylebox_override(&"panel", dot_style)
	online_box.add_child(_stat_online_dot)
	_stat_online_label = _make_footer_label("0 Online", 14, Color(0.92, 0.89, 0.82))
	online_box.add_child(_stat_online_label)
	stats_row.add_child(_make_stat_chip(online_box))

	# "New this month" chip.
	_stat_month_label = _make_footer_label("+0 this month", 14, Color(0.92, 0.89, 0.82))
	stats_row.add_child(_make_stat_chip(_stat_month_label))

	# Middle spacer pushes social + version to the right edge.
	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# Right: the X/social button then the build version.
	var right: HBoxContainer = HBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override(&"separation", 14)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)

	if not LINK_X.is_empty():
		var x_button: Button = Button.new()
		x_button.name = "XButton"
		x_button.text = "X"
		x_button.tooltip_text = "Follow us on X"
		x_button.custom_minimum_size = Vector2(44.0, 40.0)
		x_button.theme_type_variation = &"FrameButton"
		x_button.add_theme_font_size_override(&"font_size", 18)
		x_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		x_button.pressed.connect(func() -> void: OS.shell_open(LINK_X))
		_wire_button_audio(x_button)
		right.add_child(x_button)

	var version: Label = _make_footer_label(
		"v%s - %s" % [GatewayAPI.game_version(), BUILD_STAGE], 13, Color(0.85, 0.83, 0.78)
	)
	version.modulate.a = 0.6
	version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(version)

	add_child(footer)

	# Visibility follows the title screen: shown with MainPanel, hidden once the
	# player moves on (login / world select / spectate). Refresh on every reveal.
	footer.visible = main_panel.visible
	main_panel.visibility_changed.connect(_on_main_panel_visibility_changed)

	# Poll the live stats on the footer's own cadence (only while it's on screen).
	var poll: Timer = Timer.new()
	poll.wait_time = _STATS_POLL_SECONDS
	poll.autostart = true
	poll.timeout.connect(func() -> void:
		if is_instance_valid(_title_footer) and _title_footer.visible:
			_fetch_stats())
	footer.add_child(poll)


## A plain footer Label: themed font family (inherited), given size + color. Text
## stays ASCII - the Cinzel/Atkinson faces have no glyphs for bullets/dashes/emoji.
func _make_footer_label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


## Wrap content in a subtle rounded "chip" (dark translucent fill, thin accent
## border) matching the title screen's panel styling.
func _make_stat_chip(content: Control) -> PanelContainer:
	var chip: PanelContainer = PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	var accent: Color = ThemePalettes.accent(current_theme)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	chip.add_theme_stylebox_override(&"panel", style)
	chip.add_child(content)
	return chip


## Keep the footer glued to the title screen and refresh stats each time it appears.
func _on_main_panel_visibility_changed() -> void:
	if not is_instance_valid(_title_footer):
		return
	_title_footer.visible = main_panel.visible
	if main_panel.visible:
		_title_footer.modulate.a = 0.0
		create_tween().tween_property(_title_footer, "modulate:a", 1.0, 0.5)
		_fetch_stats()


## Poll GatewayAPI.stats() on the dedicated request node and apply the numbers. On
## any error we keep the last-known values rather than flicker to zero.
func _fetch_stats() -> void:
	if _stats_http == null or not is_inside_tree():
		return
	var data: Dictionary = await _request_stats()
	if not data.has("error"):
		_apply_stats(data)


func _request_stats() -> Dictionary:
	# ERR_BUSY if a prior poll is still in flight - treat as a soft skip.
	var error: Error = _stats_http.request(
		GatewayAPI.stats(),
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.Method.METHOD_POST,
		"{}"
	)
	if error != OK:
		return {"error": "request_error"}
	var args: Array = await _stats_http.request_completed
	if int(args[0]) != OK:
		return {"error": "connection_failed"}
	var parsed: Variant = JSON.parse_string((args[3] as PackedByteArray).get_string_from_ascii())
	if parsed is Dictionary:
		return parsed
	return {"error": "bad_response"}


func _apply_stats(data: Dictionary) -> void:
	var online: int = int(data.get("online", 0))
	var monthly: int = int(data.get("monthly", 0))
	if is_instance_valid(_stat_online_label):
		_stat_online_label.text = "%d Online" % online
	if is_instance_valid(_stat_online_dot):
		var sb: StyleBoxFlat = _stat_online_dot.get_theme_stylebox(&"panel") as StyleBoxFlat
		if sb:
			sb.bg_color = Color(0.45, 0.85, 0.5) if online > 0 else Color(0.5, 0.5, 0.55)
	if is_instance_valid(_stat_month_label):
		_stat_month_label.text = "+%d this month" % monthly


var _whitepaper_overlay: Control


## Full-screen overlay with the scrollable whitepaper (WhitepaperContent). Click the
## dim backdrop or Close to dismiss.
func _show_whitepaper() -> void:
	if is_instance_valid(_whitepaper_overlay):
		return
	var overlay: Control = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200
	_whitepaper_overlay = overlay

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.8)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_close_whitepaper())
	overlay.add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -370.0
	panel.offset_top = -275.0
	panel.offset_right = 370.0
	panel.offset_bottom = 275.0
	overlay.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 8)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = WhitepaperContent.TITLE
	title.add_theme_font_size_override(&"font_size", 26)
	title.add_theme_color_override(&"font_color", Color(0.906, 0.698, 0.416))
	vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = WhitepaperContent.SUBTITLE
	subtitle.add_theme_font_size_override(&"font_size", 13)
	subtitle.add_theme_color_override(&"font_color", Color(0.72, 0.70, 0.66))
	vbox.add_child(subtitle)

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override(&"normal_font_size", 14)
	body.text = WhitepaperContent.BBCODE
	scroll.add_child(body)

	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0.0, 40.0)
	close_button.pressed.connect(_close_whitepaper)
	_wire_button_audio(close_button)
	vbox.add_child(close_button)

	add_child(overlay)


func _close_whitepaper() -> void:
	if is_instance_valid(_whitepaper_overlay):
		_whitepaper_overlay.queue_free()
	_whitepaper_overlay = null


## Shorten a base58 wallet address for display ("9xQe...4kT2"). Leaves shorter names as-is.
func _short_wallet(name: String) -> String:
	if name.length() <= 12:
		return name
	return "%s...%s" % [name.substr(0, 4), name.substr(name.length() - 4)]


func add_world_card(world_info: Dictionary, world_id: int) -> Button:
	var container: HBoxContainer = $WorldSelection/VBoxContainer/HBoxContainer

	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(150.0, 250.0)
	button.pressed.connect(_on_world_selected.bind(world_id))
	_wire_button_audio(button)
	# Styled by the gateway theme's default Button (inherited) - no per-card call.

	var text_label: RichTextLabel = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_label.mouse_filter = Control.MOUSE_FILTER_PASS

	text_label.append_text(
		"[font_size=20][b]%s[/b][/font_size]\n" % world_info.get("name", "Unknown World")
	)
	text_label.append_text(
		"\n[i][font_size=12]\"%s\"[/font_size][/i]\n" % tr(world_info.get("motd", ""))
	)
	text_label.append_text(
		"\n[font_size=13][b]%s[/b][/font_size]\n" % "PvP" if world_info.get("pvp", true) else "No PvP"
	)

	button.add_child(text_label)

	container.add_child(button)
	return button


func _on_continue_button_pressed() -> void:
	$AlreadyConnectedPanel.hide()
	_show_connecting()  # plain label, not a panel - the Transition cover takes over
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_enter(),
		{
			GatewayAPI.KEY_TOKEN_ID: session_id,
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_WORLD_ID: current_world_id,
			GatewayAPI.KEY_CHAR_ID: current_character_id
		}
	)
	if d.has("error"):
		_hide_connecting()
		await popup_panel.confirm_message(GatewayError.humanize(d))
		$AlreadyConnectedPanel.show()
		return

	Transition.start_world_load(d["address"], d["port"], d["auth-token"], $Background.texture)
	queue_free.call_deferred()


func _on_change_button_pressed() -> void:
	# Keep the stack so Back returns to the resume (AlreadyConnected) screen.
	_show($WorldSelection, true)


## Wire the persistent top-right "More" menu. Its nodes (root-level, unique-named:
## %MoreButton, %MoreMenu, %MoreBackdrop + the named entries) and their look live in
## the scene; only the dynamics are here: signal connections, the context-aware
## Logout, and the version text.
func _wire_more_menu() -> void:
	(%MoreButton as Button).pressed.connect(func() -> void: _set_more_open(not _more_menu.visible))
	_more_backdrop.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				_set_more_open(false)
	)

	# Settings entry opens the full Settings overlay (and closes the menu).
	(%SettingsEntry as Button).pressed.connect(
		func() -> void:
			_set_more_open(false)
			$Settings.visible = true
	)

	# Community links -> browser (disabled when no URL is set, see _wire_link).
	_wire_link(%DiscordButton as Button, LINK_DISCORD)
	_wire_link(%WebsiteButton as Button, LINK_WEBSITE)

	# Session: Logout (shown only with an active session, see _set_more_open) + Quit
	# (desktop/console only). On web there's no app to close - get_tree().quit() just
	# tears down the wasm canvas and reads as a crash - and phones use the OS app
	# switcher, so hide the button on both and only wire it on a real desktop build.
	_more_logout.pressed.connect(_logout)
	if OS.has_feature("web") or OS.has_feature("mobile"):
		(%QuitButton as Button).hide()
	else:
		(%QuitButton as Button).pressed.connect(get_tree().quit)

	(%MoreBackButton as Button).pressed.connect(func() -> void: _set_more_open(false))
	(%VersionLabel as Label).text = "v" + GatewayAPI.game_version()


## Open/close the global More menu (flyout + modal backdrop). On open it refreshes
## the context-sensitive entries - Logout only makes sense with an active session.
func _set_more_open(open: bool) -> void:
	if open:
		_more_logout.visible = not session_id.is_empty()
	_more_menu.visible = open
	_more_backdrop.visible = open


## Wire a flyout link button to open `url` in the browser. Empty url -> disable the
## button (reads as "not available yet" instead of a dead click).
func _wire_link(button: Button, url: String) -> void:
	if url.is_empty():
		button.disabled = true
		return
	button.pressed.connect(func() -> void: OS.shell_open(url))


## Forget the saved session and return to the main menu so another account can log
## in. The auto-login token lives in session.dat (see save_refresh_token).
func _logout() -> void:
	var file_path: String = "user://%ssession.dat" % local_id
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	session_id = ""  # clears the active session -> More's Logout hides again
	account_name = ""  # back to "not logged in" in the status line
	_refresh_connection_info()
	_set_more_open(false)
	# Logout can be triggered from any screen (world/character select, character
	# creation, ...), so hide them all - not just the resume panel - before returning
	# to the main menu, or the old screen stays visible and clickable on top.
	for panel: Control in [
		login_panel, $CreateAccountPanel, $WorldSelection,
		$CharacterSelection, $CharacterCreation, $AlreadyConnectedPanel, popup_panel,
	]:
		panel.hide()
	menu_stack.clear()
	menu_stack.append(main_panel)
	main_panel.show()
	(%MoreButton as Button).hide()  # back on the clean title - hide the More menu again
	back_button.hide()
	if _focus_nav:
		_focus_first_in(main_panel)


func _on_back_button_pressed() -> void:
	if menu_stack.size():
		menu_stack.pop_back().hide()
		if menu_stack.size():
			menu_stack.back().show()
			# Going back must re-home focus on the revealed panel for non-mouse
			# players (back doesn't route through _show, so do it here).
			if _focus_nav:
				_focus_first_in(menu_stack.back())
		if menu_stack.size() < 2:
			back_button.hide()


# --- Focus highlight (device-aware) ---------------------------------------

## Build the overlay ring once and start listening for focus changes.
func _setup_focus_highlight() -> void:
	_focus_highlight = Panel.new()
	_focus_highlight.name = &"FocusHighlight"
	_focus_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_highlight.top_level = true
	_focus_highlight.z_index = 100
	_focus_highlight.visible = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(2)
	style.border_color = Color(0.906, 0.698, 0.416, 0.9)  # brand gold #e7b26a
	style.set_corner_radius_all(8)
	_focus_highlight.add_theme_stylebox_override(&"panel", style)
	add_child(_focus_highlight)
	set_process(false)  # _process only runs while focus-navigating (see _input)


## Re-grab focus when the player first switches to keyboard/gamepad with nothing
## focused. The ring itself is positioned every frame in _process.
func _refresh_focus_highlight() -> void:
	if get_viewport().gui_get_focus_owner() == null and menu_stack.size():
		_focus_first_in(menu_stack.back())


## Glue the ring to the focused control every frame. Polling (rather than reacting
## once to gui_focus_changed) avoids reading a control's rect before its container
## has laid it out on a panel transition - which left the ring mispositioned until
## the next input event.
func _process(_delta: float) -> void:
	if _focus_highlight == null:
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if not _focus_nav or focus_owner == null or not is_ancestor_of(focus_owner):
		_focus_highlight.visible = false
		return
	var pad: float = 8.0  # gap between the control and the ring
	var rect: Rect2 = focus_owner.get_global_rect()
	_focus_highlight.global_position = rect.position - Vector2(pad, pad)
	_focus_highlight.size = rect.size + Vector2(pad * 2.0, pad * 2.0)
	_focus_highlight.visible = true


# --- Gateway theming -------------------------------------------------------
# Palettes come from ThemePalettes (slug -> styling theme + login backdrop + accent). Assigning the
# styling Theme to `theme` styles the whole subtree by inheritance; per-node looks (panel / button /
# divider variations) are tagged in gateway.tscn. Swapping palette = reassign `theme` + backdrop + ring.


## Assign a palette: swap to its SHARED styling theme (the same one the in-game UI uses, so a theme fix
## lands in both contexts), update the backdrop, retint the focus ring. Falls back to the default.
func _apply_gateway_theme(palette: StringName) -> void:
	if not ThemePalettes.has(palette):
		palette = ThemePalettes.DEFAULT
	current_theme = palette
	theme = ThemePalettes.theme(palette)
	_apply_theme_background(ThemePalettes.backdrop(palette))
	if _focus_highlight:
		var ring: StyleBoxFlat = _focus_highlight.get_theme_stylebox(&"panel") as StyleBoxFlat
		if ring:
			var accent: Color = ThemePalettes.accent(palette)
			ring.border_color = Color(accent.r, accent.g, accent.b, 0.9)


## Scale the backdrop sprite to cover 960x540, centred.
func _apply_theme_background(tex: Texture2D) -> void:
	if tex == null:
		return
	$Background.texture = tex
	$Background.centered = true
	$Background.position = Vector2(480.0, 270.0)
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		var cover: float = maxf(960.0 / tex_size.x, 540.0 / tex_size.y)
		$Background.scale = Vector2(cover, cover)


## Pick the startup palette from the shared client settings: an explicit saved
## choice, a random one each launch (opt-in), or the default.
func _pick_startup_palette() -> StringName:
	var palettes: Array[StringName] = ThemePalettes.list()
	if ClientState.settings.get_value(_SETTINGS_SECTION, _SETTING_RANDOMIZE) == true \
			and not palettes.is_empty():
		return palettes[randi() % palettes.size()]
	var saved: Variant = ClientState.settings.get_value(_SETTINGS_SECTION, _SETTING_PALETTE)
	if (saved is String or saved is StringName) and ThemePalettes.has(StringName(saved)):
		return StringName(saved)
	return ThemePalettes.DEFAULT


## Live-apply a palette change made in the Settings menu so the gateway re-themes
## without a relaunch. (Persistence is handled by the setting widget itself.)
func _on_settings_changed(section: StringName, property: StringName, value: Variant) -> void:
	if section == _SETTINGS_SECTION and property == _SETTING_PALETTE and value is String:
		_apply_gateway_theme(StringName(value))


## Cycle palette - a debug / for-fun key only. Deliberately does NOT persist: the
## saved preference is owned by the Settings menu. The real palette choice for
## players is the [gateway] setting (default: randomize a new one each launch).
func _cycle_theme() -> void:
	var palettes: Array[StringName] = ThemePalettes.list()
	if palettes.is_empty():
		return
	var i: int = palettes.find(current_theme)
	_apply_gateway_theme(palettes[(i + 1) % palettes.size()])


# --- Password fields ------------------------------------------------------

## Mask the password fields (they shipped unmasked) and give each panel a
## "Show password" toggle - important on mobile, where typing a password blind
## on a touch keyboard is a known drop-off point.
func _setup_password_fields() -> void:
	var login_pw: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	login_pw.secret = true
	_add_password_toggle($LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer2, [login_pw])

	var create_pw: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	var create_pw_confirm: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer3/LineEdit
	create_pw.secret = true
	create_pw_confirm.secret = true
	_add_password_toggle(
		$CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer3,
		[create_pw, create_pw_confirm]
	)


func _add_password_toggle(into: Node, fields: Array[LineEdit]) -> void:
	var toggle: CheckBox = CheckBox.new()
	toggle.text = tr("SHOW_PASSWORD")
	toggle.toggled.connect(
		func(pressed: bool) -> void:
			for field: LineEdit in fields:
				field.secret = not pressed
	)
	into.add_child(toggle)


## A throwaway display name (character names aren't unique - Discord-style), for
## the "Random" dice next to the name field. Letters only, 2-3 syllables, so it
## always passes username validation.
func _random_character_name() -> String:
	var syllables: PackedStringArray = [
		"ar", "en", "th", "or", "el", "an", "ka", "ri", "mo", "lu", "ne", "sa",
		"to", "zi", "fae", "dra", "gor", "lyn", "mir", "nax", "veh", "sol", "kai",
	]
	var generated: String = ""
	for _n: int in randi_range(2, 3):
		generated += syllables[randi() % syllables.size()]
	return generated.capitalize()


# Helpers
func request_login(username: String, password: String) -> Dictionary:
	return await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.login(),
		{
			GatewayAPI.KEY_ACCOUNT_USERNAME: username,
			GatewayAPI.KEY_ACCOUNT_PASSWORD: password,
			GatewayAPI.KEY_CLIENT_VERSION: GatewayAPI.game_version(),
		}
	)

func request_enter_world() -> Dictionary:
	return await do_request(
			HTTPClient.Method.METHOD_POST,
			GatewayAPI.world_enter(),
			{
				GatewayAPI.KEY_TOKEN_ID: session_id,
				GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
				GatewayAPI.KEY_WORLD_ID: current_world_id,
				GatewayAPI.KEY_CHAR_ID: current_character_id
			}
		)


func prepare_character_creation_menu() -> void:
	_skin_ids = PlayerSkins.ids()
	_skin_preview = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer2/CenterContainer/Control/AnimatedSprite2D
	_skin_preview.play(&"run")

	# Replace the tiny-icon grid with a Prev / name / Next cycler. The big centre
	# preview is the visual, so the chosen character shows LARGE instead of as 8
	# small icons.
	var grid: GridContainer = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/VBoxContainer
	for child: Node in grid.get_children():
		child.queue_free()
	grid.columns = 3

	var prev: Button = Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(44.0, 44.0)
	prev.add_theme_font_size_override(&"font_size", 22)
	prev.pressed.connect(_cycle_skin.bind(-1))

	_skin_name_label = Label.new()
	_skin_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skin_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skin_name_label.custom_minimum_size = Vector2(110.0, 44.0)

	var next: Button = Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(44.0, 44.0)
	next.add_theme_font_size_override(&"font_size", 22)
	next.pressed.connect(_cycle_skin.bind(1))

	grid.add_child(prev)
	grid.add_child(_skin_name_label)
	grid.add_child(next)

	_apply_skin(0)  # show the first skin in the preview

	# Enable the (scene-hidden) "Random" dice next to the name field.
	var name_edit: LineEdit = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer2/LineEdit
	var random_button: Button = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer2/Button
	random_button.visible = true
	random_button.pressed.connect(
		func() -> void:
			name_edit.text = _random_character_name()
	)


## Cycle the starter skin by +1 / -1 (wraps around the roster).
func _cycle_skin(delta: int) -> void:
	if _skin_ids.is_empty():
		return
	_apply_skin(wrapi(_skin_index + delta, 0, _skin_ids.size()))


## Apply a skin by index - set selected_skin_id, update the preview + name label.
func _apply_skin(index: int) -> void:
	if index < 0 or index >= _skin_ids.size():
		return
	var skin_id: int = _skin_ids[index]
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", skin_id) as SpriteFrames
	if not frames:
		return
	_skin_index = index
	selected_skin_id = skin_id
	if _skin_preview:
		_skin_preview.sprite_frames = frames
		_skin_preview.play(&"run")
	if _skin_name_label:
		_skin_name_label.text = PlayerSkins.display_name(skin_id)


# Ideally we must not save credentials locally even if crypted,
# saving a temporary token given by the server is the way. 
func try_auto_login() -> bool:
	# Default: show the login screen first (logo + Connect Wallet) - the branded
	# "press start" moment, on web AND desktop.
	# Opt-in: pass `--auto` (desktop only) to silently sign in with the local dev
	# wallet - used by the editor's "Run Multiple Instances" and the multiplayer
	# smoke test so extra clients join hands-free. Never on web (Phantom needs a
	# real click) and never without the flag.
	if OS.has_feature("web") or not CmdlineUtils.get_parsed_args().has("auto"):
		return false
	var pubkey: String = _dev_wallet_pubkey()
	if pubkey.is_empty():
		return false
	if not await _do_wallet_login(pubkey, true):
		return false
	# --auto goes all the way into the world (first world, first character, creating
	# one if needed) so multi-instance / multiplayer testing is fully hands-free.
	return await _auto_enter_world()


## Test helper (--auto only): jump straight into the first online world with the
## first character (auto-creating one if the account has none). Mirrors the manual
## world-select -> character-select -> enter flow. Returns false (-> show menu) on any snag.
func _auto_enter_world() -> bool:
	var worlds_resp: Dictionary = await do_request(HTTPClient.Method.METHOD_POST, GatewayAPI.worlds(), {})
	var worlds: Dictionary = worlds_resp.get("w", {})
	if worlds.is_empty():
		return false
	var world_id: int = int(worlds.keys()[0])
	current_world_id = world_id

	var chars: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_characters(),
		{
			GatewayAPI.KEY_WORLD_ID: world_id,
			GatewayAPI.KEY_ACCOUNT_ID: account_id,
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_TOKEN_ID: session_id,
		}
	)
	if chars.has("error"):
		return false

	var char_id: int = -1
	for key: String in chars.keys():
		var entry: Variant = chars[key]
		if entry is Dictionary and (entry as Dictionary).has("name"):
			char_id = key.to_int()
			break

	var enter: Dictionary
	if char_id == -1:
		enter = await do_request(
			HTTPClient.Method.METHOD_POST,
			GatewayAPI.world_create_char(),
			{
				GatewayAPI.KEY_TOKEN_ID: session_id,
				"data": {"name": _random_character_name(), "skin": selected_skin_id},
				GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
				GatewayAPI.KEY_WORLD_ID: world_id,
			}
		)
	else:
		enter = await do_request(
			HTTPClient.Method.METHOD_POST,
			GatewayAPI.world_enter(),
			{
				GatewayAPI.KEY_TOKEN_ID: session_id,
				GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
				GatewayAPI.KEY_WORLD_ID: world_id,
				GatewayAPI.KEY_CHAR_ID: char_id,
			}
		)
	if enter.has("error") or not enter.has("address"):
		return false
	Transition.start_world_load(enter["address"], enter["port"], enter["auth-token"], $Background.texture)
	queue_free.call_deferred()
	return true


# Can be changed / randomized each build
const LOCAL_PASS: String = "LOCAL_PASSWORD"
func save_refresh_token(token: String, file_path: String) -> void:
	var file: FileAccess = FileAccess.open_encrypted_with_pass(file_path, FileAccess.WRITE, LOCAL_PASS)
	if file:
		file.store_string(token)
		file.close()
	else:
		printerr(error_string(FileAccess.get_open_error()))


func load_refresh_token(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var file: FileAccess = FileAccess.open_encrypted_with_pass(file_path, FileAccess.READ, LOCAL_PASS)
	if not file:
		printerr(error_string(FileAccess.get_open_error()))
		return ""
	var token: String = file.get_as_text()
	file.close()
	return token
