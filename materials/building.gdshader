// コンクリートのビル（M5の街）。壁は wall_*、屋上は floor_* をワールド座標で貼り、壁には窓の格子を描く。
// 窓は階高 floor_h・柱間 bay_w ごとに並び、lit_ratio の割合で暖色に灯る（窓ごとに乱数で決める）。
shader_type spatial;

uniform sampler2D wall_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wall_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2D roof_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D roof_arm : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.8, 0.8, 0.82);
uniform vec3 roof_tint : source_color = vec3(0.78, 0.76, 0.74);
uniform float uv_scale = 0.2;
uniform float floor_h = 3.5;
uniform float bay_w = 2.6;
uniform vec3 glass_color : source_color = vec3(0.04, 0.05, 0.07);
uniform vec3 lit_color : source_color = vec3(1.0, 0.66, 0.36);
uniform float lit_ratio = 0.28;
uniform float lit_energy = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 n = abs(wnrm);
	if (n.y > 0.5) {
		vec2 uv = wpos.xz * uv_scale;
		vec3 arm = texture(roof_arm, uv).rgb;
		ALBEDO = texture(roof_albedo, uv).rgb * roof_tint;
		AO = arm.r;
		ROUGHNESS = arm.g;
		METALLIC = arm.b;
	} else {
		bool along_z = n.x > n.z;
		float u = along_z ? wpos.z : wpos.x;
		vec2 uv = vec2(u, wpos.y) * uv_scale;
		vec3 arm = texture(wall_arm, uv).rgb;
		vec3 col = texture(wall_albedo, uv).rgb * tint;
		float rough = arm.g;
		float metal = 0.0;
		vec3 emit = vec3(0.0);
		// 窓：階ごと・柱間ごとの区画の中ほど
		float fy = wpos.y / floor_h;
		float fx = u / bay_w;
		vec2 cell = vec2(floor(fx) + (along_z ? 57.0 : 0.0) + sign(wnrm.x + wnrm.z) * 13.0, floor(fy));
		float ly = fract(fy);
		float lx = fract(fx);
		if (ly > 0.3 && ly < 0.82 && lx > 0.16 && lx < 0.84) {
			col = glass_color;
			rough = 0.12;
			metal = 0.5;
			float h = hash(cell);
			if (h < lit_ratio) {
				emit = lit_color * lit_energy * (0.5 + 0.5 * hash(cell.yx + 3.1));
			}
		} else if (ly > 0.24 && ly < 0.3) {
			col *= 0.7; // 窓の下の帯
		}
		ALBEDO = col;
		AO = arm.r;
		ROUGHNESS = rough;
		METALLIC = metal;
		EMISSION = emit;
	}
}
