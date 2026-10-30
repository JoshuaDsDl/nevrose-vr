class_name SpatialAudio
extends RefCounted
## Réglages de son spatial communs aux sources qu'il faut pouvoir LOCALISER à l'oreille
## (voix, coups dans les murs).
##
## Godot 4 n'a pas de HRTF intégré : AudioStreamPlayer3D ne fait que panoramiquer entre les deux
## oreilles (gauche/droite) avec un filtre de distance. Il manque le devant/derrière et le haut/bas.
## On compense ce qu'on peut sans plugin natif :
##   - panoramique renforcé (panning_strength 2) : la gauche/droite devient très nette ;
##   - atténuation en inverse de la distance, avec une portée courte : on sent la distance ;
##   - « ombre » de la tête et du pavillon : un son situé DERRIÈRE soi (ou très au-dessus / en
##     dessous) devient plus sourd, un son devant reste clair. C'est le repère naturel
##     devant/derrière que l'oreille utilise.
## Un vrai HRTF (Steam Audio, Meta XR Audio) demanderait un plugin natif pour Android : voir CLAUDE.md.

const CLEAR_HZ := 12000.0
const MUFFLED_HZ := 2200.0


static func configure(p: AudioStreamPlayer3D, unit_size := 3.0, max_distance := 30.0) -> void:
	p.panning_strength = 2.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.attenuation_filter_cutoff_hz = CLEAR_HZ
	p.attenuation_filter_db = -12.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED


## À rappeler à chaque image sur une source qui joue : règle la netteté d'après sa position
## par rapport à la tête (0 = devant, 1 = pile derrière).
static func tune(p: AudioStreamPlayer3D, listener: Node3D) -> void:
	if listener == null or not is_instance_valid(listener) or not p.is_inside_tree():
		return
	var to := p.global_position - listener.global_position
	if to.length_squared() < 0.0001:
		return
	var dir := to.normalized()
	var forward := -listener.global_transform.basis.z
	var behind := clampf(-dir.dot(forward), 0.0, 1.0)
	var vertical := clampf(absf(dir.y) - 0.5, 0.0, 0.5) * 2.0 # très haut ou très bas : sourd aussi
	var shadow := maxf(behind, vertical * 0.6)
	p.attenuation_filter_cutoff_hz = lerpf(CLEAR_HZ, MUFFLED_HZ, shadow)
