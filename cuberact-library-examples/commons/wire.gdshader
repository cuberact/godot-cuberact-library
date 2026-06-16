shader_type canvas_item;

uniform vec4 wire_color : source_color = vec4(0.8, 0.2, 0.2, 1.0);
uniform vec4 pulse_color : source_color = vec4(1.0, 1.0, 0.7, 1.0);
uniform float outline_width : hint_range(0.0, 0.5) = 0.14;
uniform float powered : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed = 2.0;
uniform float pulse_density = 0.15;

void fragment() {
	vec4 base = (UV.y < outline_width || UV.y > 1.0 - outline_width)
			? vec4(0.05, 0.05, 0.06, 1.0) : wire_color;
	float p = fract(UV.x * pulse_density - TIME * pulse_speed);
	float pulse = smoothstep(0.0, 0.2, p) * (1.0 - smoothstep(0.2, 0.45, p));
	COLOR = mix(base, pulse_color, pulse * powered);
}
