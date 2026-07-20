shader_type canvas_item;

// 色相偏移（角度，范围 -180 ~ 180）
uniform float hue_shift : hint_range(-180.0, 180.0) = 0.0;
// 饱和度倍数（0 = 灰度，>1 增强）
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
// 亮度倍数（0 = 全黑，>1 变亮）
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
// 对比度倍数（0 = 全灰，>1 增强）
uniform float contrast : hint_range(0.0, 2.0) = 1.0;

// ---------- RGB ↔ HSV 转换函数 ----------
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    // 采样纹理颜色
    vec4 tex_color = texture(TEXTURE, UV);
    vec3 rgb = tex_color.rgb;

    // 1. 转换为 HSV 并调整
    vec3 hsv = rgb2hsv(rgb);
    hsv.x = fract(hsv.x + hue_shift / 360.0);   // 色相偏移（循环）
    hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
    hsv.z = clamp(hsv.z * brightness, 0.0, 1.0);
    rgb = hsv2rgb(hsv);

    // 2. 调整对比度
    rgb = (rgb - 0.5) * contrast + 0.5;

    // 输出最终颜色（保留原始透明度）
    COLOR = vec4(rgb, tex_color.a);
}