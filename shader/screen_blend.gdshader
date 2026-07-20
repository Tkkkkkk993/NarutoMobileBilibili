shader_type canvas_item;

// 提示：这个着色器需要与 "SCREEN_TEXTURE" 配合使用
// 使用时，需要将 "SCREEN_TEXTURE" 设置为你想混合的背景纹理
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_nearest;

// 控制混合强度，范围0-1，1为完全滤色混合
uniform float blend_strength : hint_range(0.0, 1.0) = 1.0;

// 滤色（Screen）混合模式的公式
// 结果 = 1 - (1 - 底色) * (1 - 混合色)
// 这个公式会让结果总是比原来的颜色更亮[reference:3]
vec3 screen_blend(vec3 base, vec3 blend) {
    return 1.0 - (1.0 - base) * (1.0 - blend);
}

void fragment() {
    // 1. 获取当前节点的颜色作为 "混合色"
    vec4 blend_color = texture(TEXTURE, UV);
    
    // 2. 获取屏幕背景的颜色作为 "底色"
    // SCREEN_TEXTURE 和 SCREEN_UV 是Godot内置的，用于获取当前屏幕像素[reference:4]
    vec4 base_color = texture(SCREEN_TEXTURE, SCREEN_UV);
    
    // 3. 对RGB通道执行滤色混合
    vec3 final_rgb = screen_blend(base_color.rgb, blend_color.rgb);
    
    // 4. 根据混合强度，在原始混合色和滤色结果之间进行插值
    final_rgb = mix(blend_color.rgb, final_rgb, blend_strength);
    
    // 5. 输出最终颜色，保留混合色的透明度
    COLOR = vec4(final_rgb, blend_color.a);
}