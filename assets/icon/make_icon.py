"""PlanBook 앱 아이콘 생성 스크립트.

컨셉: Gantt 바(길이가 다른 가로 막대 3개) + 체크마크 배지 = "계획 + 진행률 체크".
앱 테마 색(colorSchemeSeed 0xFF2E5BB6, 파랑)을 그대로 쓴다.

출력:
- icon.png            : 1024x1024, 배경+전경 합쳐진 완전한 아이콘(레거시/윈도우용).
- icon_foreground.png : 1024x1024, 투명 배경 + 전경 글리프만(안드로이드 adaptive icon 용,
                        마스킹에 잘리지 않도록 중앙 약 66% 안전영역 안에 그린다).
"""
from PIL import Image, ImageDraw

SIZE = 1024
BG = (0x2E, 0x5B, 0xB6, 255)  # 앱 테마 파랑
BG_DARK = (0x1F, 0x40, 0x86, 255)  # 그라데이션 하단(살짝 어둡게)
WHITE = (255, 255, 255, 255)
CHECK_GREEN = (0x34, 0xC7, 0x59, 255)


def rounded_rect(draw, box, radius, fill, opacity_img=None):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def make_gradient_bg(size):
    img = Image.new("RGBA", (size, size), BG)
    top = BG
    bottom = BG_DARK
    for y in range(size):
        t = y / (size - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        for x in range(size):
            pass
    # 세로 그라데이션을 픽셀 단위로 그리면 느리니 1px 폭 이미지를 늘려서 만든다.
    grad = Image.new("RGBA", (1, size), BG)
    gd = grad.load()
    for y in range(size):
        t = y / (size - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        gd[0, y] = (r, g, b, 255)
    grad = grad.resize((size, size))
    return grad


def draw_glyph(draw, cx, cy, scale):
    """cx, cy 중심 기준으로 Gantt 바 3개 + 체크 배지를 그린다. scale 은 전체 글리프 폭 기준."""
    bar_h = int(0.11 * scale)
    gap = int(0.075 * scale)
    radius = bar_h // 2

    widths = [0.62, 0.78, 0.50]  # 각 바 길이(스케일 대비 비율) — 짧은/긴/중간으로 리듬감.
    opacities = [255, 235, 200]

    total_h = bar_h * 3 + gap * 2
    start_y = cy - total_h // 2
    start_x = cx - int(scale * 0.5)

    bar_boxes = []
    for i, (w_ratio, op) in enumerate(zip(widths, opacities)):
        w = int(scale * w_ratio)
        y0 = start_y + i * (bar_h + gap)
        y1 = y0 + bar_h
        x0 = start_x
        x1 = start_x + w
        color = (255, 255, 255, op)
        draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=color)
        bar_boxes.append((x0, y0, x1, y1))

    # 첫 번째(맨 위, 가장 짧은) 바 오른쪽 끝에 "완료" 체크 배지.
    x0, y0, x1, y1 = bar_boxes[0]
    badge_r = int(bar_h * 1.15)
    bx = x1
    by = (y0 + y1) // 2
    draw.ellipse(
        [bx - badge_r, by - badge_r, bx + badge_r, by + badge_r],
        fill=CHECK_GREEN,
    )
    # 체크 표시(꺾인 선 두 개를 두꺼운 선으로).
    check_w = int(badge_r * 0.22)
    p1 = (bx - badge_r * 0.5, by + badge_r * 0.05)
    p2 = (bx - badge_r * 0.12, by + badge_r * 0.42)
    p3 = (bx + badge_r * 0.55, by - badge_r * 0.38)
    draw.line([p1, p2], fill=WHITE, width=check_w, joint="curve")
    draw.line([p2, p3], fill=WHITE, width=check_w, joint="curve")
    # 선 끝을 둥글게 보이도록 각 점에 작은 원을 겹쳐 그린다.
    for p in (p1, p2, p3):
        r = check_w / 2
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=WHITE)


def make_full_icon():
    bg = make_gradient_bg(SIZE)
    # 앱스토어형 둥근 사각형 마스크(윈도우/레거시 안드로이드 아이콘용 — 살짝만 둥글게).
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, SIZE - 1, SIZE - 1], radius=int(SIZE * 0.22), fill=255
    )
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(icon)
    draw_glyph(draw, SIZE // 2, SIZE // 2, scale=SIZE * 0.5)
    return icon


def make_foreground_icon():
    """안드로이드 adaptive icon 전경: 투명 배경 + 글리프만, 안전영역(중앙 66%) 안에."""
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)
    # 적응형 아이콘은 원/둥근사각형 등으로 마스킹되므로 중앙 약 60% 안에 그린다.
    draw_glyph(draw, SIZE // 2, SIZE // 2, scale=SIZE * 0.30)
    return icon


if __name__ == "__main__":
    full = make_full_icon()
    full.save("icon.png")
    fg = make_foreground_icon()
    fg.save("icon_foreground.png")
    print("done")
