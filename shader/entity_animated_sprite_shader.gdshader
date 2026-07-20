shader_type canvas_item;

uniform float whitening : hint_range(0.0, 1.0) = 0.0;
uniform vec4 self_modulate = vec4(1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);

	// 【关键修改】使用 max 替代 mix
	// max 会让暗部和亮部同步变白，实现“剪影化填白”，没有过曝感
	// 当 whitening = 1.0 时，纯黑也会变成纯白 (1.0, 1.0, 1.0)
	vec3 final_rgb = max(tex_color.rgb, vec3(whitening));

	vec4 result = vec4(final_rgb, tex_color.a) * self_modulate;

	// 处理 Godot 预乘 Alpha，防止半透明边缘变黑/变暗
	result.rgb *= result.a;

	COLOR = result;
}
