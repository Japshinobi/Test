# Один оттенок куртки во всех сторонах: ИИ красит её то бирюзовой, то серо-зелёной.
# Зелёным пикселям слоя ставим общий тон и насыщенность, яркость (тени и блики) остаётся своя.
import colorsys, statistics as st, sys
from PIL import Image
HUE, SAT = 140 / 360, 0.35

def green(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return s > 0.12 and 0.2 < h < 0.55 and v > 0.15, (h, s, v)

def tone(src, dst):
    im = Image.open(src).convert('RGBA'); px = im.load(); W, H = im.size
    sats = [green(*px[x, y][:3])[1][1] for y in range(H) for x in range(W)
            if px[x, y][3] and green(*px[x, y][:3])[0]]
    k = SAT / st.median(sats)
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            ok, (h, s, v) = green(r, g, b)
            if a and ok:
                r, g, b = colorsys.hsv_to_rgb(HUE, min(1, s * k), v)
                px[x, y] = (round(r * 255), round(g * 255), round(b * 255), a)
    im.save(dst)

if __name__ == '__main__':
    for d in sys.argv[1:]:
        tone(f'pl/layer_jacket_{d}.png', f'pl/layer_jacket_{d}.png')
