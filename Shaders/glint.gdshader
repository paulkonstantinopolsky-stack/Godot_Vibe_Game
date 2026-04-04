shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float width : hint_range(0.0, 1.0) = 0.2;
uniform float angle : hint_range(0.0, 360.0) = 45.0;
uniform vec4 glint_color : source_color = vec4(1.0, 1.0, 1.0, 0.8);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);

	float rad = radians(angle);
	vec2 dir = vec2(cos(rad), sin(rad));

	float p = dot(UV - vec2(0.5), dir) + 0.5;

	float current_pos = mix(-width, 1.0 + width, progress);

	float glint = smoothstep(current_pos - width, current_pos, p) - smoothstep(current_pos, current_pos + width, p);

	COLOR = mix(tex_color, glint_color, glint * tex_color.a * glint_color.a);
}
