class_name Phone
extends Node3D
## Smartphone interactif avec l'application Messenger dans NÉVROSE.
## Représente un téléphone 3D sortable de la poche (hanche gauche) ou tenu en main gauche.
## Intègre une réplique de Messenger affichant les messages du subconscient et le timer de folie.

# Dimensions réalistes d'un smartphone moderne (~8 x 16 x 0.8 cm)
const PHONE_WIDTH := 0.080
const PHONE_HEIGHT := 0.160
const PHONE_THICKNESS := 0.008

# Dimensions de l'écran (~7.4 x 15 cm)
const SCREEN_WIDTH := 0.074
const SCREEN_HEIGHT := 0.150

# Résolution interne de l'écran Messenger (ratio 9:15)
const VIEWPORT_WIDTH := 384
const VIEWPORT_HEIGHT := 640

# Couleurs de la charte Messenger & Dark Mode VR
const COLOR_MESSENGER_BLUE := Color(0.0, 0.518, 1.0) # #0084FF
const COLOR_BG_DARK := Color(0.09, 0.10, 0.12)       # Fond Messenger sombre
const COLOR_HEADER_TOP := Color(0.06, 0.07, 0.09)    # Barre de statut système
const COLOR_BUBBLE_IN := Color(0.22, 0.23, 0.25)     # Bulle contact gris Messenger
const COLOR_BUBBLE_ALERT := Color(0.65, 0.15, 0.15)  # Bulle rouge alerte critique
const COLOR_ONLINE_GREEN := Color(0.27, 0.72, 0.0)    # Point de statut en ligne

# État de prise en main
@export var is_in_hand: bool = false

# Références VR / caméra
var _left_hand: Node3D = null
var _right_hand: Node3D = null
var _xr_camera: Node3D = null
var _pocket_parent: Node3D = null

# Offsets de positionnement
var _pocket_local_pos := Vector3(-0.25, 0.8, 0.0)
var _pocket_local_rot := Vector3(0.0, 0.0, 0.0)
# Écran avancé à 12 cm de la manette pour éviter une lecture trop près du visage.
var _hand_local_pos := Vector3(0.02, 0.04, -0.12)
var _hand_local_rot := Vector3(-35.0, 15.0, -10.0)
var _desktop_cam_pos := Vector3(-0.16, -0.12, -0.32)
var _desktop_cam_rot := Vector3(-12.0, 12.0, -4.0)

# Composants 3D
var _body_mesh: MeshInstance3D = null
var _screen_mesh: MeshInstance3D = null
var _speaker_mesh: MeshInstance3D = null
var _camera_mesh: MeshInstance3D = null
var _screen_mat: StandardMaterial3D = null
var _body_mat: StandardMaterial3D = null

# Composants 2D / SubViewport
var _sub_viewport: SubViewport = null
var _ui_root: Control = null
var _header_panel: Panel = null
var _header_style: StyleBoxFlat = null
var _status_dot: ColorRect = null
var _contact_status_label: Label = null
var _timer_badge_label: Label = null
var _battery_label: Label = null
var _clock_label: Label = null
var _messages_container: VBoxContainer = null
var _input_label: Label = null

# Historique : 3 messages conservés, mais seulement les 2 derniers affichés.
const MAX_VISIBLE_MESSAGES := 2
var _messages_data: Array[Dictionary] = []
const ALERT_NOTIFICATION_COOLDOWN_MS := 20000
var _last_alert_notification_ms := -1000000

# Tweens d'animation
var _flash_tween: Tween = null
var _transition_tween: Tween = null
var _haptics_ready := false


func _ready() -> void:
	_build_3d_phone()
	_build_2d_messenger_ui()
	_apply_pocket_state(false)


# ---------------------------------------------------------------------------
# Construction du modèle 3D du smartphone
# ---------------------------------------------------------------------------
func _build_3d_phone() -> void:
	# Corps métallique noir/anthracite aux bords biseautés
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "BodyMesh"
	var body_box := BoxMesh.new()
	body_box.size = Vector3(PHONE_WIDTH, PHONE_HEIGHT, PHONE_THICKNESS)
	_body_mesh.mesh = body_box

	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.12, 0.13, 0.15)
	_body_mat.metallic = 0.85
	_body_mat.roughness = 0.25
	_body_mesh.material_override = _body_mat
	add_child(_body_mesh)

	# Fente haut-parleur avant
	_speaker_mesh = MeshInstance3D.new()
	_speaker_mesh.name = "SpeakerMesh"
	var speaker_box := BoxMesh.new()
	speaker_box.size = Vector3(0.018, 0.0018, 0.0006)
	_speaker_mesh.mesh = speaker_box
	_speaker_mesh.position = Vector3(0.0, (PHONE_HEIGHT * 0.5) - 0.0035, (PHONE_THICKNESS * 0.5) + 0.0002)
	var speaker_mat := StandardMaterial3D.new()
	speaker_mat.albedo_color = Color(0.03, 0.03, 0.03)
	speaker_mat.roughness = 0.9
	_speaker_mesh.material_override = speaker_mat
	add_child(_speaker_mesh)

	# Petite caméra selfie avant
	_camera_mesh = MeshInstance3D.new()
	_camera_mesh.name = "CameraMesh"
	var cam_box := BoxMesh.new()
	cam_box.size = Vector3(0.0025, 0.0025, 0.0006)
	_camera_mesh.mesh = cam_box
	_camera_mesh.position = Vector3(0.02, (PHONE_HEIGHT * 0.5) - 0.0035, (PHONE_THICKNESS * 0.5) + 0.0002)
	var cam_mat := StandardMaterial3D.new()
	cam_mat.albedo_color = Color(0.02, 0.05, 0.08)
	cam_mat.metallic = 0.9
	cam_mat.roughness = 0.1
	_camera_mesh.material_override = cam_mat
	add_child(_camera_mesh)

	# Écran plat sur la face avant
	_screen_mesh = MeshInstance3D.new()
	_screen_mesh.name = "ScreenMesh"
	var screen_quad := QuadMesh.new()
	screen_quad.size = Vector2(SCREEN_WIDTH, SCREEN_HEIGHT)
	_screen_mesh.mesh = screen_quad
	# Positionné légèrement en avant de la face pour éviter le Z-fighting
	_screen_mesh.position = Vector3(0.0, 0.0, (PHONE_THICKNESS * 0.5) + 0.0003)

	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mesh.material_override = _screen_mat
	add_child(_screen_mesh)


# ---------------------------------------------------------------------------
# Construction de l'interface 2D Messenger dans le SubViewport
# ---------------------------------------------------------------------------
func _build_2d_messenger_ui() -> void:
	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "ScreenViewport"
	_sub_viewport.size = Vector2i(VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = false
	add_child(_sub_viewport)

	# Branchement de la texture du viewport sur le matériau de l'écran 3D
	_screen_mat.albedo_texture = _sub_viewport.get_texture()

	# Racine de l'interface
	_ui_root = Control.new()
	_ui_root.name = "MessengerApp"
	_ui_root.custom_minimum_size = Vector2(VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	_ui_root.size = Vector2(VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	_sub_viewport.add_child(_ui_root)

	# Fond général sombre Messenger
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = COLOR_BG_DARK
	_ui_root.add_child(bg)

	# 1. Barre d'état système supérieure (heure, batterie, signal)
	var sys_bar := ColorRect.new()
	sys_bar.position = Vector2(0, 0)
	sys_bar.size = Vector2(VIEWPORT_WIDTH, 24)
	sys_bar.color = COLOR_HEADER_TOP
	_ui_root.add_child(sys_bar)

	_clock_label = Label.new()
	_clock_label.position = Vector2(12, 2)
	_clock_label.size = Vector2(80, 20)
	_clock_label.text = "03:42"
	_clock_label.add_theme_font_size_override("font_size", 12)
	_clock_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85))
	sys_bar.add_child(_clock_label)

	_battery_label = Label.new()
	_battery_label.position = Vector2(VIEWPORT_WIDTH - 90, 2)
	_battery_label.size = Vector2(80, 20)
	_battery_label.text = "87% [||||]"
	_battery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_battery_label.add_theme_font_size_override("font_size", 12)
	_battery_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85))
	sys_bar.add_child(_battery_label)

	# 2. En-tête bleu Messenger
	_header_panel = Panel.new()
	_header_panel.position = Vector2(0, 24)
	_header_panel.size = Vector2(VIEWPORT_WIDTH, 76)
	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = COLOR_MESSENGER_BLUE
	_header_panel.add_theme_stylebox_override("panel", _header_style)
	_ui_root.add_child(_header_panel)

	# Flèche retour gauche
	var back_lbl := Label.new()
	back_lbl.position = Vector2(10, 16)
	back_lbl.size = Vector2(24, 40)
	back_lbl.text = "‹"
	back_lbl.add_theme_font_size_override("font_size", 34)
	back_lbl.add_theme_color_override("font_color", Color.WHITE)
	_header_panel.add_child(back_lbl)

	# Avatar rond du contact
	var avatar_panel := Panel.new()
	avatar_panel.position = Vector2(36, 14)
	avatar_panel.size = Vector2(44, 44)
	var av_style := StyleBoxFlat.new()
	av_style.bg_color = Color(0.12, 0.22, 0.38)
	av_style.corner_radius_top_left = 22
	av_style.corner_radius_top_right = 22
	av_style.corner_radius_bottom_left = 22
	av_style.corner_radius_bottom_right = 22
	av_style.border_width_left = 2
	av_style.border_width_top = 2
	av_style.border_width_right = 2
	av_style.border_width_bottom = 2
	av_style.border_color = Color.WHITE
	avatar_panel.add_theme_stylebox_override("panel", av_style)
	_header_panel.add_child(avatar_panel)

	var av_label := Label.new()
	av_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	av_label.text = "S"
	av_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av_label.add_theme_font_size_override("font_size", 20)
	av_label.add_theme_color_override("font_color", Color.WHITE)
	avatar_panel.add_child(av_label)

	# Petit point vert sur l'avatar (en ligne)
	var online_dot := ColorRect.new()
	online_dot.position = Vector2(32, 32)
	online_dot.size = Vector2(10, 10)
	online_dot.color = COLOR_ONLINE_GREEN
	avatar_panel.add_child(online_dot)

	# Nom du contact & titre Messenger
	var contact_vbox := VBoxContainer.new()
	contact_vbox.position = Vector2(88, 12)
	contact_vbox.size = Vector2(160, 52)
	_header_panel.add_child(contact_vbox)

	var title_sub := Label.new()
	title_sub.text = "MESSENGER"
	title_sub.add_theme_font_size_override("font_size", 10)
	title_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	contact_vbox.add_child(title_sub)

	var contact_name := Label.new()
	contact_name.text = "Subconscient"
	contact_name.add_theme_font_size_override("font_size", 16)
	contact_name.add_theme_color_override("font_color", Color.WHITE)
	contact_vbox.add_child(contact_name)

	_contact_status_label = Label.new()
	_contact_status_label.text = "En ligne"
	_contact_status_label.add_theme_font_size_override("font_size", 11)
	_contact_status_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	contact_vbox.add_child(_contact_status_label)

	# Badge compte à rebours / urgence dans l'en-tête (en haut à droite)
	var timer_panel := Panel.new()
	timer_panel.position = Vector2(VIEWPORT_WIDTH - 120, 18)
	timer_panel.size = Vector2(110, 36)
	var tm_style := StyleBoxFlat.new()
	tm_style.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	tm_style.corner_radius_top_left = 18
	tm_style.corner_radius_top_right = 18
	tm_style.corner_radius_bottom_left = 18
	tm_style.corner_radius_bottom_right = 18
	timer_panel.add_theme_stylebox_override("panel", tm_style)
	_header_panel.add_child(timer_panel)

	_timer_badge_label = Label.new()
	_timer_badge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_timer_badge_label.text = "⏱️ --:--"
	_timer_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_badge_label.add_theme_font_size_override("font_size", 13)
	_timer_badge_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	timer_panel.add_child(_timer_badge_label)

	# 3. Zone de conversation Messenger (bulles)
	var chat_scroll := ScrollContainer.new()
	chat_scroll.position = Vector2(12, 108)
	chat_scroll.size = Vector2(VIEWPORT_WIDTH - 24, 468)
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_ui_root.add_child(chat_scroll)

	_messages_container = VBoxContainer.new()
	_messages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages_container.add_theme_constant_override("separation", 10)
	chat_scroll.add_child(_messages_container)

	# 4. Pied de page Messenger (fausse barre de saisie)
	var footer := Panel.new()
	footer.position = Vector2(0, VIEWPORT_HEIGHT - 56)
	footer.size = Vector2(VIEWPORT_WIDTH, 56)
	var ft_style := StyleBoxFlat.new()
	ft_style.bg_color = Color(0.12, 0.13, 0.16)
	footer.add_theme_stylebox_override("panel", ft_style)
	_ui_root.add_child(footer)

	# Bouton + / Médias
	var plus_lbl := Label.new()
	plus_lbl.position = Vector2(10, 10)
	plus_lbl.size = Vector2(28, 34)
	plus_lbl.text = "⊕"
	plus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus_lbl.add_theme_font_size_override("font_size", 22)
	plus_lbl.add_theme_color_override("font_color", COLOR_MESSENGER_BLUE)
	footer.add_child(plus_lbl)

	# Fausse barre de texte arrondie
	var input_panel := Panel.new()
	input_panel.position = Vector2(44, 10)
	input_panel.size = Vector2(VIEWPORT_WIDTH - 128, 36)
	var in_style := StyleBoxFlat.new()
	in_style.bg_color = Color(0.18, 0.20, 0.23)
	in_style.corner_radius_top_left = 18
	in_style.corner_radius_top_right = 18
	in_style.corner_radius_bottom_left = 18
	in_style.corner_radius_bottom_right = 18
	input_panel.add_theme_stylebox_override("panel", in_style)
	footer.add_child(input_panel)

	_input_label = Label.new()
	_input_label.position = Vector2(14, 0)
	_input_label.size = Vector2(input_panel.size.x - 28, 36)
	_input_label.text = "Écrivez un message..."
	_input_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_input_label.add_theme_font_size_override("font_size", 12)
	_input_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
	input_panel.add_child(_input_label)

	# Bouton micro factice
	var mic_lbl := Label.new()
	mic_lbl.position = Vector2(VIEWPORT_WIDTH - 80, 10)
	mic_lbl.size = Vector2(30, 36)
	mic_lbl.text = "🎙️"
	mic_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mic_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mic_lbl.add_theme_font_size_override("font_size", 15)
	footer.add_child(mic_lbl)

	# Bouton pouce levé bleu Messenger
	var thumb_lbl := Label.new()
	thumb_lbl.position = Vector2(VIEWPORT_WIDTH - 44, 10)
	thumb_lbl.size = Vector2(34, 36)
	thumb_lbl.text = "👍"
	thumb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thumb_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thumb_lbl.add_theme_font_size_override("font_size", 16)
	thumb_lbl.add_theme_color_override("font_color", COLOR_MESSENGER_BLUE)
	footer.add_child(thumb_lbl)

	# Message initial de bienvenue du subconscient
	receive_message("Ne reste pas là. Trouve la dose.", false)


# ---------------------------------------------------------------------------
# Configuration de la poche et des mains
# ---------------------------------------------------------------------------
func setup_pocket(left_hand: Node3D, right_hand: Node3D, xr_camera: Node3D) -> void:
	_left_hand = left_hand
	_right_hand = right_hand
	_xr_camera = xr_camera

	if _left_hand:
		_pocket_parent = _left_hand.get_parent()
	elif _xr_camera:
		_pocket_parent = _xr_camera.get_parent()

	_apply_pocket_state(false)
	_haptics_ready = true


# Bascule entre la poche et la main gauche
func toggle_pocket() -> void:
	is_in_hand = not is_in_hand
	_apply_pocket_state(true)


func _apply_pocket_state(animate: bool) -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()

	if is_in_hand:
		# Passage en main gauche
		visible = true
		if animate:
			_trigger_haptic(0.35, 0.15)

		# Détermine si on est en VR avec manette gauche trackée ou en bureau/fallback
		var target_parent: Node3D = _left_hand
		var target_pos: Vector3 = _hand_local_pos
		var target_rot: Vector3 = _hand_local_rot

		# En mode bureau sans contrôleur tracké, attachement devant la caméra pour vue HUD 3D
		if _left_hand == null or (_left_hand is XRController3D and not (_left_hand as XRController3D).get_is_active()):
			if _xr_camera:
				target_parent = _xr_camera
				target_pos = _desktop_cam_pos
				target_rot = _desktop_cam_rot

		if target_parent and get_parent() != target_parent:
			reparent(target_parent)

		if animate:
			_transition_tween = create_tween().set_parallel(true)
			_transition_tween.tween_property(self, "position", target_pos, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_transition_tween.tween_property(self, "rotation_degrees", target_rot, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			scale = Vector3(0.5, 0.5, 0.5)
			_transition_tween.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			position = target_pos
			rotation_degrees = target_rot
			scale = Vector3.ONE
	else:
		# Rangement dans la poche (hanche gauche)
		if animate:
			_trigger_haptic(0.25, 0.12)
		var target_parent: Node3D = _pocket_parent if _pocket_parent else (_xr_camera.get_parent() if _xr_camera else null)

		if target_parent and get_parent() != target_parent:
			reparent(target_parent)

		var target_pos := _pocket_local_pos
		var target_rot := _pocket_local_rot

		if animate:
			_transition_tween = create_tween().set_parallel(true)
			_transition_tween.tween_property(self, "position", target_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_transition_tween.tween_property(self, "rotation_degrees", target_rot, 0.2)
			_transition_tween.tween_property(self, "scale", Vector3(0.3, 0.3, 0.3), 0.2)
			_transition_tween.chain().tween_callback(func() -> void:
				visible = false
			)
		else:
			position = target_pos
			rotation_degrees = target_rot
			scale = Vector3.ONE
			visible = false


# ---------------------------------------------------------------------------
# Réception de messages Messenger
# ---------------------------------------------------------------------------
func receive_message(text: String, is_alert: bool = false) -> void:
	# Stockage avec horodatage
	var time_str := "%02d:%02d" % [Time.get_time_dict_from_system().hour, Time.get_time_dict_from_system().minute]
	_messages_data.append({
		"text": text,
		"time": time_str,
		"alert": is_alert
	})

	# On conserve au maximum les 3 derniers messages
	while _messages_data.size() > 3:
		_messages_data.pop_front()

	_refresh_messages_ui()
	_flash_header(is_alert)

	# Les messages ordinaires restent silencieux. Seules les alertes critiques
	# produisent un retour, espacé pour ne pas masquer les voix ni le jeu.
	if not is_alert:
		return
	var now := Time.get_ticks_msec()
	if now - _last_alert_notification_ms < ALERT_NOTIFICATION_COOLDOWN_MS:
		return
	_last_alert_notification_ms = now
	_trigger_haptic(0.3, 0.2)
	var main_node = get_tree().get_first_node_in_group("main") if get_tree() else null
	if main_node and "creepy_voices" in main_node and main_node.creepy_voices and main_node.creepy_voices.has_method(&"play_notification"):
		main_node.creepy_voices.play_notification()


# Mise à jour graphique des bulles Messenger
func _refresh_messages_ui() -> void:
	if not _messages_container:
		return

	for child in _messages_container.get_children():
		child.queue_free()

	var first_visible := maxi(_messages_data.size() - MAX_VISIBLE_MESSAGES, 0)
	for i in range(first_visible, _messages_data.size()):
		var msg: Dictionary = _messages_data[i]
		var item_vbox := VBoxContainer.new()
		item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Horodatage / En-tête de message
		var meta_lbl := Label.new()
		meta_lbl.text = "Subconscient • " + str(msg.get("time", "Maintenant"))
		meta_lbl.add_theme_font_size_override("font_size", 14)
		meta_lbl.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		item_vbox.add_child(meta_lbl)

		# Bulle de discussion Messenger
		var bubble_panel := PanelContainer.new()
		bubble_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b_style := StyleBoxFlat.new()
		var is_alt: bool = bool(msg.get("alert", false))
		b_style.bg_color = COLOR_BUBBLE_ALERT if is_alt else COLOR_BUBBLE_IN
		b_style.corner_radius_top_left = 14
		b_style.corner_radius_top_right = 14
		b_style.corner_radius_bottom_right = 14
		b_style.corner_radius_bottom_left = 4
		b_style.content_margin_left = 14
		b_style.content_margin_top = 10
		b_style.content_margin_right = 14
		b_style.content_margin_bottom = 10
		bubble_panel.add_theme_stylebox_override("panel", b_style)

		var msg_lbl := Label.new()
		msg_lbl.text = str(msg.get("text", ""))
		msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg_lbl.custom_minimum_size = Vector2.ZERO
		msg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg_lbl.add_theme_font_size_override("font_size", 18)
		msg_lbl.add_theme_color_override("font_color", Color.WHITE)
		bubble_panel.add_child(msg_lbl)

		item_vbox.add_child(bubble_panel)
		_messages_container.add_child(item_vbox)


# Flash lumineux du bandeau lors d'une notification
func _flash_header(is_alert: bool) -> void:
	if not _header_style:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	var flash_color := Color(1.0, 0.25, 0.25) if is_alert else Color(0.4, 0.8, 1.0)
	_header_style.bg_color = flash_color

	_flash_tween = create_tween()
	_flash_tween.tween_property(_header_style, "bg_color", COLOR_MESSENGER_BLUE, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Mise à jour du compte à rebours et de la tension (sanity)
# ---------------------------------------------------------------------------
func update_timer(time_str: String, sanity: float) -> void:
	if _timer_badge_label:
		_timer_badge_label.text = "⏱️ " + time_str

	# Adaptation visuelle selon la folie
	if _contact_status_label:
		if sanity < 40.0:
			_contact_status_label.text = "En ligne"
			_contact_status_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
		elif sanity < 85.0:
			_contact_status_label.text = "Signal perturbé..."
			_contact_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			_contact_status_label.text = "PERTE DE CONNEXION"
			_contact_status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))

	if _timer_badge_label:
		if sanity >= 85.0:
			_timer_badge_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		elif sanity >= 50.0:
			_timer_badge_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		else:
			_timer_badge_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))


# ---------------------------------------------------------------------------
# Vibration haptique sécurisée
# ---------------------------------------------------------------------------
func _trigger_haptic(amplitude: float, duration_sec: float) -> void:
	if not _haptics_ready or not (_left_hand is XRController3D):
		return
	var controller := _left_hand as XRController3D
	if not controller.get_is_active():
		return
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface == null or not xr_interface.is_initialized():
		return
	xr_interface.trigger_haptic_pulse(&"haptic", controller.tracker, 0.0,
		clampf(amplitude, 0.0, 1.0), maxf(duration_sec, 0.01), 0.0)
