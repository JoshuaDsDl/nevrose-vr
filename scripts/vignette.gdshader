shader_type canvas_item;

// Vignette de folie : assombrit les bords selon la jauge de schizo.
// Coût négligeable (quelques instructions) — idéal Quest 2.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 1.4142; // 0 au centre, 1 dans les coins
	float edge = smoothstep(0.55, 1.05, dist);
	float pulse = 1.0 + 0.06 * sin(TIME * 2.2); // les murs "respirent"
	float alpha = edge * intensity * pulse;
	// Légère teinte rouge/noir quand ça devient critique
	vec4 crit_tint = vec4(0.12, 0.0, 0.02, 1.0);
	vec4 col = mix(tint, crit_tint, smoothstep(0.75, 1.0, intensity));
	COLOR = vec4(col.rgb, alpha);
}
