shader_type canvas_item;

uniform vec4 rope_color1 : source_color = vec4(0.533, 0.325, 0.122, 1.0);
uniform vec4 rope_color2 : source_color = vec4(0.933, 0.635, 0.357, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width : hint_range(0.0, 0.5) = 0.1;
uniform float stripe_width : hint_range(0.01, 0.5) = 0.3;
uniform float repeat: hint_range(0.1, 1000.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = vec2(UV.x * repeat, UV.y);
	float rot_45 = uv.x + uv.y;
    float stripe = mod(rot_45, stripe_width * 3.0);
    COLOR = (uv.y < outline_width || uv.y > (1.0 - outline_width)) ?
      outline_color :
      mix(rope_color1, rope_color2, step(stripe_width, stripe));
}