shader_type canvas_item;

// 可调整的圆形半径（0.0~0.5，0.5为最大内切圆）
uniform float radius : hint_range(0.0, 0.5) = 0.5;
// 边缘抗锯齿强度（值越大边缘越锐利）
uniform float antialiasing : hint_range(0.0, 0.1) = 0.02;

void fragment() {
    // 将 UV 坐标从 [0,1] 映射到 [-0.5, 0.5]，使图片中心为 (0,0)
    vec2 uv_centered = UV - vec2(0.5);

    // 计算当前像素到中心的距离
    float dist = length(uv_centered);

    // 获取原始颜色
    vec4 color = texture(TEXTURE, UV);

    // 使用 smoothstep 实现平滑裁剪（抗锯齿）
    float alpha = 1.0 - smoothstep(radius - antialiasing, radius + antialiasing, dist);
    color.a *= alpha;

    COLOR = color;
}