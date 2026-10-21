# Вырезать слой одежды: сильно изменившиеся пиксели «одетого» персонажа относительно основы,
# без одиночных точек и с заполненными дырками внутри вещи. Возвращает слой и сводку.
import math, sys
from PIL import Image, ImageDraw, ImageFont

def dist(a, b):
    if a[3] == 0 and b[3] == 0: return 0
    if (a[3] > 0) != (b[3] > 0): return 999
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))

def extract(base_p, dressed_p, out_p, strong=40, weak=15, min_part=6):
    base = Image.open(base_p).convert('RGBA'); dr = Image.open(dressed_p).convert('RGBA')
    b, d = base.load(), dr.load(); W, H = base.size
    D = {(x, y): dist(b[x, y], d[x, y]) for y in range(H) for x in range(W)}
    mask = {p for p, v in D.items() if v > strong}
    # убрать мелкие кусочки (связные области меньше min_part пикселей)
    seen, keep = set(), set()
    for p in mask:
        if p in seen: continue
        comp, stack = [], [p]; seen.add(p)
        while stack:
            q = stack.pop(); comp.append(q)
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                n = (q[0]+dx, q[1]+dy)
                if n in mask and n not in seen: seen.add(n); stack.append(n)
        if len(comp) >= min_part: keep |= set(comp)
    # дырки внутри вещи: заметно изменившиеся пиксели, окружённые слоем минимум с 3 сторон
    for _ in range(2):
        add = set()
        for (x, y), v in D.items():
            if (x, y) in keep or v <= weak: continue
            n = sum((x+dx, y+dy) in keep for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)))
            if n >= 3: add.add((x, y))
        keep |= add
    layer = Image.new('RGBA', base.size, (0, 0, 0, 0)); l = layer.load()
    for (x, y) in keep:
        l[x, y] = d[x, y]
    layer.save(out_p)
    comp = base.copy(); comp.alpha_composite(layer)
    off = sum(1 for p, v in D.items() if v > strong and p not in keep)
    resid = [dist(comp.load()[p], d[p]) for p in D]
    return layer, comp, {'layer_px': len(keep), 'dropped_strong': off,
                         'diff_after(>40)': sum(1 for v in resid if v > 40)}
if __name__ == '__main__':
    print(extract(*sys.argv[1:4])[2])
