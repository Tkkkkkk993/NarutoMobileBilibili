shader_type canvas_item;

// 圆形半径（0.0~0.5，0.5 为最大内切圆）
uniform float radius : hint_range(0.0, 0.5) = 0.5;
// 边缘抗锯齿强度（值越大边缘越锐利）
uniform float antialiasing : hint_range(0.0, 0.1) = 0.02;

// 是否启用灰度
uniform bool is_gray = false;
// 是否变暗 30%
uniform bool darken = false;

void fragment() {
    // 1. 获取原始颜色
    vec4 color = texture(TEXTURE, UV);

    // 2. 灰度处理
    if (is_gray) {
        float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        color.rgb = vec3(gray);
    }

    // 3. 变暗处理
    if (darken) {
        color.rgb *= 0.7;
    }

    // 4. 圆形裁剪（计算 alpha）
    vec2 uv_centered = UV - vec2(0.5);
    float dist = length(uv_centered);
    float alpha = 1.0 - smoothstep(radius - antialiasing, radius + antialiasing, dist);
    color.a *= alpha;

    // 5. 输出最终颜色
    COLOR = color;
}