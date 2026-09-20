"""纯 PIL 绘制漫域音乐宣传底图：深色渐变背景 + 毛玻璃卡片 + 唱片 + 波形光晕。"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math, random

SIZE = 2048  # 方形底图，之后按平台裁剪
img = Image.new("RGBA", (SIZE, SIZE), (12, 14, 28, 255))
d = ImageDraw.Draw(img)

# 背景对角渐变（深蓝 -> 深紫 -> 近黑）
for y in range(SIZE):
    t = y / SIZE
    r = int(18 * (1 - t) + 28 * t)
    g = int(20 * (1 - t) + 16 * t)
    b = int(48 * (1 - t) + 70 * t)
    d.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

# 大光斑（柔光）
def glow(cx, cy, radius, color, alpha):
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for i in range(radius, 0, -6):
        a = int(alpha * (1 - i / radius) ** 2)
        ld.ellipse((cx - i, cy - i, cx + i, cy + i), fill=(*color, a))
    layer = layer.filter(ImageFilter.GaussianBlur(radius // 4))
    return Image.alpha_composite(img, layer)

img = glow(SIZE * 0.22, SIZE * 0.18, 700, (88, 120, 255), 90)
img = glow(SIZE * 0.82, SIZE * 0.30, 620, (180, 80, 220), 70)
img = glow(SIZE * 0.55, SIZE * 0.92, 760, (60, 200, 230), 55)
d = ImageDraw.Draw(img)

# 毛玻璃主卡片
card_x, card_y = int(SIZE * 0.10), int(SIZE * 0.20)
card_w, card_h = int(SIZE * 0.80), int(SIZE * 0.62)
card_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
cd = ImageDraw.Draw(card_layer)
cd.rounded_rectangle(
    (card_x, card_y, card_x + card_w, card_y + card_h),
    radius=48,
    fill=(255, 255, 255, 28),
    outline=(255, 255, 255, 60),
    width=2,
)
card_layer = card_layer.filter(ImageFilter.GaussianBlur(2))
img = Image.alpha_composite(img, card_layer)
d = ImageDraw.Draw(img)

# 左侧圆形唱片封面
cx, cy, R = card_x + int(card_w * 0.30), card_y + card_h // 2, int(card_h * 0.36)
# 唱片渐变（用多个同心圆环模拟径向渐变）
for i in range(R, 0, -3):
    t = i / R
    r = int(120 * t + 60 * (1 - t))
    g = int(90 * t + 40 * (1 - t))
    b = int(255 * t + 180 * (1 - t))
    d.ellipse((cx - i, cy - i, cx + i, cy + i), fill=(r, g, b, 255))
# 唱片纹路
for i in range(R - 20, 40, -12):
    d.ellipse((cx - i, cy - i, cx + i, cy + i), outline=(0, 0, 0, 40), width=2)
# 中心孔
d.ellipse((cx - 14, cy - 14, cx + 14, cy + 14), fill=(20, 20, 30, 255))
# 高光弧
d.arc((cx - R, cy - R, cx + R, cy + R), 200, 320, fill=(255, 255, 255, 90), width=6)

# 右侧：标题占位 + 波形 + 进度条
tx = card_x + int(card_w * 0.50)
ty = card_y + int(card_h * 0.22)
# 专辑名（色块模拟，不写真实文字）
d.rounded_rectangle((tx, ty, tx + int(card_w * 0.40), ty + 34), 10, fill=(255, 255, 255, 200))
d.rounded_rectangle((tx, ty + 52, tx + int(card_w * 0.28), ty + 84), 8, fill=(255, 255, 255, 110))

# 歌词行（短色块）
ly = ty + 130
for i in range(5):
    ww = int(card_w * (0.32 if i == 1 else 0.22))
    d.rounded_rectangle((tx, ly, tx + ww, ly + 18), 6, fill=(255, 255, 255, 55))
    ly += 32

# 音频波形
wy = card_y + card_h - int(card_h * 0.18)
random.seed(7)
bars = 64
bw = int(card_w * 0.40) // bars
maxh = int(card_h * 0.18)
for i in range(bars):
    h = int(maxh * (0.3 + 0.7 * abs(math.sin(i * 0.7 + random.random()))))
    x = tx + i * (bw + 3)
    d.rounded_rectangle((x, wy - h // 2, x + bw, wy + h // 2), 3,
                        fill=(120, 180, 255, 220))

# 进度条
py = wy + 50
d.rounded_rectangle((tx, py, tx + int(card_w * 0.40), py + 6), 3, fill=(255, 255, 255, 50))
d.rounded_rectangle((tx, py, tx + int(card_w * 0.18), py + 6), 3, fill=(120, 180, 255, 255))
d.ellipse((tx + int(card_w * 0.18) - 6, py - 6, tx + int(card_w * 0.18) + 6, py + 12),
          fill=(255, 255, 255, 255))

# 控制按钮（播放三角）
bx, by = tx + int(card_w * 0.20), py + 60
d.ellipse((bx, by, bx + 56, by + 56), fill=(120, 180, 255, 255))
d.polygon([(bx + 20, by + 14), (bx + 20, by + 42), (bx + 42, by + 28)], fill=(255, 255, 255, 255))

# 背景噪点质感
noise = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
nd = ImageDraw.Draw(noise)
for _ in range(6000):
    x, y = random.randint(0, SIZE), random.randint(0, SIZE)
    a = random.randint(8, 28)
    nd.point((x, y), fill=(255, 255, 255, a))
noise = noise.filter(ImageFilter.GaussianBlur(0.5))
img = Image.alpha_composite(img, noise)

img.convert("RGB").save("dist/promo/base_art.png", "PNG")
print("base art done", img.size)
