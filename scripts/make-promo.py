"""为漫域音乐生成 4 个平台宣传海报：底图 + 渐变蒙版 + 中文文案。"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC = "dist/promo/base_art.png"
HEITI = "/System/Library/Fonts/STHeiti Medium.ttc"
SANS = "/System/Library/Fonts/Hiragino Sans GB.ttc"

# (输出文件名, 宽, 高, 主标题, 副标题, 标签行)
POSTERS = [
    (
        "dist/promo/poster_xiaohongshu.png",
        1350, 1800,
        "终于找到一款\n不占内存的本地播放器",
        "FLAC 无损直读 · 歌词自动匹配 · 纯本地无广告",
        "macOS 原生 · Apple 芯片优化",
    ),
    (
        "dist/promo/poster_douyin.png",
        1080, 1920,
        "你的音乐\n只属于你",
        "无需会员 · 无损播放 · 一键导入本地曲库",
        "漫域音乐 macOS 内测中",
    ),
    (
        "dist/promo/poster_bilibili.png",
        1920, 1080,
        "漫域音乐 3.13",
        "本地音乐播放器内测 · Apple 芯片原生 · 全格式无损解码",
        "macOS 14+ ｜ 无广告 ｜ 无账号 ｜ 数据纯本地",
    ),
    (
        "dist/promo/poster_square.png",
        1800, 1800,
        "漫域音乐",
        "属于你的本地音乐库",
        "macOS 原生 · 无损解码 · 隐私至上",
    ),
]


def cover_resize(img, w, h):
    iw, ih = img.size
    scale = max(w / iw, h / ih)
    nw, nh = int(iw * scale), int(ih * scale)
    r = img.resize((nw, nh), Image.LANCZOS)
    left = (nw - w) // 2
    top = (nh - h) // 2
    return r.crop((left, top, left + w, top + h))


def vgradient(draw, w, h, top_rgba, bottom_rgba):
    for y in range(h):
        t = y / h
        c = tuple(int(top_rgba[i] * (1 - t) + bottom_rgba[i] * t) for i in range(4))
        draw.line([(0, y), (w, y)], fill=c)


def wrap_text(draw, text, font, max_w):
    lines = []
    cur = ""
    for ch in text:
        test = cur + ch
        if draw.textlength(test, font=font) <= max_w:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = ch
    if cur:
        lines.append(cur)
    return lines


for path, w, h, title, subtitle, tag in POSTERS:
    base = Image.open(SRC).convert("RGBA")
    canvas = cover_resize(base, w, h)

    # 底部到顶部的深色渐变蒙版（保证底部标题可读）
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    vgradient(od, w, h, (10, 10, 20, 30), (10, 10, 20, 210))
    canvas = Image.alpha_composite(canvas, overlay)

    draw = ImageDraw.Draw(canvas)

    # 字体大小按图宽自适应
    is_landscape = w > h
    title_size = int(w * 0.062) if not is_landscape else int(h * 0.11)
    sub_size = int(w * 0.026) if not is_landscape else int(h * 0.042)
    tag_size = int(w * 0.018) if not is_landscape else int(h * 0.03)
    brand_size = int(w * 0.022) if not is_landscape else int(h * 0.036)

    f_title = ImageFont.truetype(HEITI, title_size)
    f_sub = ImageFont.truetype(SANS, sub_size)
    f_tag = ImageFont.truetype(SANS, tag_size)
    f_brand = ImageFont.truetype(HEITI, brand_size)

    margin = int(w * 0.07)
    max_text_w = w - margin * 2

    # 顶部品牌
    brand = "漫域音乐  ·  ManyuMusic"
    draw.text((margin, int(h * 0.06)), brand, font=f_brand, fill=(255, 255, 255, 220))

    # 标签胶囊
    tag_text = tag
    tw = draw.textlength(tag_text, font=f_tag)
    th = tag_size * 1.4
    tag_x = margin
    tag_y = int(h * 0.06) + brand_size + int(h * 0.018)
    draw.rounded_rectangle(
        (tag_x, tag_y, tag_x + tw + tag_size * 1.6, tag_y + th),
        radius=th / 2,
        fill=(90, 140, 255, 230),
    )
    draw.text(
        (tag_x + tag_size * 0.8, tag_y + th * 0.18),
        tag_text,
        font=f_tag,
        fill=(255, 255, 255, 255),
    )

    # 主标题（支持 \n 换行 + 自动换行）
    title_lines = []
    for para in title.split("\n"):
        title_lines += wrap_text(draw, para, f_title, max_text_w)

    line_h = int(title_size * 1.22)
    title_total_h = line_h * len(title_lines)

    # 副标题
    sub_lines = wrap_text(draw, subtitle, f_sub, max_text_w)
    sub_line_h = int(sub_size * 1.55)
    sub_total_h = sub_line_h * len(sub_lines)

    block_h = title_total_h + int(h * 0.025) + sub_total_h
    bottom = h - int(h * 0.10)
    top = bottom - block_h

    y = top
    for ln in title_lines:
        draw.text((margin, y), ln, font=f_title, fill=(255, 255, 255, 255))
        y += line_h

    y += int(h * 0.025)
    for ln in sub_lines:
        draw.text((margin, y), ln, font=f_sub, fill=(220, 228, 255, 210))
        y += sub_line_h

    canvas.convert("RGB").save(path, "PNG", optimize=True)
    print("OK", path, canvas.size)
