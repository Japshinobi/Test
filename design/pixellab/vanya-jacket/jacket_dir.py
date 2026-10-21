# Надеть зелёную куртку на основу Вани в заданных направлениях (своё описание для каждой стороны).
import sys, json, base64, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pl_tool import call, wait, balance
COMMON = ("keep the face, hair, hands, trousers, shoes, pose, size, outline and all other pixels exactly unchanged")
VIEW = {
    "front": "a short open jacket in cool green over his shirt: it covers the shoulders, the arms to the elbows and the torso down to the hips, the light shirt is visible in the middle",
    "side": "a short jacket in cool green over his shirt: it covers the shoulder, the arm to the elbow and the torso down to the hips",
    "back": "a short jacket in cool green seen from behind: the back of the jacket covers the whole back from the shoulders down to the hips and the arms to the elbows, no shirt visible from behind",
}
KIND = {"south": "front", "south-east": "front", "south-west": "front", "east": "side", "west": "side",
        "north": "back", "north-east": "back", "north-west": "back"}
for d in sys.argv[1:]:
    b64 = base64.b64encode(open(f"pl/v5/{d}.png", "rb").read()).decode()
    desc = "put on " + VIEW[KIND[d]] + "; " + COMMON
    for seed in (7, 8, 9):
        code, j = call("POST", "/edit-image-pixen", {"image": {"type": "base64", "base64": b64}, "description": desc,
            "width": 64, "height": 64, "seed": seed, "no_background": True})
        if code not in (200, 202): print(d, code, j); break
        res = wait(j["background_job_id"], every=5)
        print(d, seed, res.get("status"), json.dumps(res.get("usage")), flush=True)
        if res.get("status") == "completed":
            open(f"pl/jacket_{d}.png", "wb").write(base64.b64decode(res["last_response"]["image"]["base64"]))
            break
print(balance()["subscription"])
