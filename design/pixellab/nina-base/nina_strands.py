# Малиновые пряди у висков Нины (запуск из scratchpad, исходники — pl/nina/ и pl/nina_eyes.png): прямые пряди в колонках, подобранных для каждого направления по краю лица.
# Красятся только пиксели волос; лицо, кожа, контур и одежда не меняются.
import os
from PIL import Image
H = lambda h: tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
RASP = {H('ca5f2a'): H('b04a72'), H('883e23'): H('92285a'), H('7e312a'): H('7e2250'),
        H('6a2b1b'): H('6c1c46'), H('370b13'): H('4e1232'), H('400d16'): H('4e1232'), H('1f040a'): H('340a22')}
COLS = {   # колонки прядей (ближняя к зрителю — 2 колонки, дальняя вполоборота — 1)
    "south": [25, 26, 37, 38],
    "south-east": [29, 30, 39],
    "east": [32, 33],
    "west": [29, 30],
    "south-west": [23, 32, 33],
}
DIRS = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
os.makedirs('pl/nina_final', exist_ok=True)
for d in DIRS:
    src = 'pl/nina_eyes.png' if d == 'south' else f'pl/nina/{d}.png'
    im = Image.open(src).convert('RGBA'); px = im.load(); n = 0
    for y in range(8, 31):
        for x in COLS.get(d, []):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in RASP:
                px[x, y] = RASP[(r, g, b)] + (a,); n += 1
    im.save(f'pl/nina_final/{d}.png'); print(d, n)
