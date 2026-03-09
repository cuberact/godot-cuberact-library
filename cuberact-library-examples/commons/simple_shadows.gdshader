shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform vec3 bg_color : source_color = vec3(0.196, 0.196, 0.196);
uniform vec3 shadow_color : source_color = vec3(0.0,0.0,0.0);
uniform float offset: hint_range(0.0, 1.0, 0.001) = 0.01;
uniform float soft: hint_range(0.0, 10.0, 0.001) = 0.45;
uniform float blur_amount: hint_range(0.0, 5.0) = 2.5;

varying float zoom;

void vertex() {
	mat4 m = CANVAS_MATRIX;
	zoom = m[0][0];
}
void fragment() {
	vec3 p1 = textureLod(SCREEN_TEXTURE, SCREEN_UV, 0.0).rgb;
	vec3 p2 = textureLod(SCREEN_TEXTURE, SCREEN_UV - (offset * zoom), blur_amount).rgb;
	bool p1_tr = length(p1 - bg_color) < 0.01;
	bool p2_tr = length(p2 - bg_color) < 0.01;
	if (p1_tr && !p2_tr) {
		float dist = length(p2 - bg_color);
		float t = clamp(dist / soft, 0.0, 1.0);
		COLOR.rgb = mix(bg_color, shadow_color, t);
	} else {
		COLOR.rgb = p1;
	}
}

