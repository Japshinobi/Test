// Draws the farm: the ground, water, beds, everything standing on it (sorted by depth),
// shadows that follow the sun, and the colour of the light. Mirrors render() in game/index.html.
// World units: one tile = 1 unit = 16 draft pixels; tile (x, y) has its top-left corner at (x, -y).
using System.Collections.Generic;
using Ogorod.Core;
using UnityEngine;

namespace Ogorod.Game
{
    public class WorldView
    {
        const int T = Atlas.PPU;
        readonly Atlas atlas;
        readonly Transform root;
        Transform dyn;
        SpriteRenderer ground;
        Texture2D groundTex, bareTex;
        readonly List<(SpriteRenderer r, int x, int y)> waters = new List<(SpriteRenderer, int, int)>();
        public SpriteRenderer Player;
        readonly Dictionary<string, (SpriteRenderer soil, SpriteRenderer crop)> plots = new Dictionary<string, (SpriteRenderer, SpriteRenderer)>();
        readonly List<SpriteRenderer> drops = new List<SpriteRenderer>();
        readonly List<Shadowed> shadowed = new List<Shadowed>();
        readonly Mesh shadowMesh;
        readonly Material shadowMat, lightMat, glowMat;
        readonly Transform lightQuad, glowQuad;
        public Camera Cam;

        /// <summary>Something that casts a shadow: its sprite, where it touches the ground (draft px), optional shadow boxes.</summary>
        class Shadowed { public string sprite; public float px, py; public ShadowBox[] boxes; public SpriteRenderer r; }

        public WorldView(Atlas atlas, Transform parent)
        {
            this.atlas = atlas;
            root = new GameObject("World").transform; root.SetParent(parent, false);
            var camGo = new GameObject("Ogorod Camera");
            camGo.transform.SetParent(parent, false);
            Cam = camGo.AddComponent<Camera>();
            Cam.orthographic = true; Cam.clearFlags = CameraClearFlags.SolidColor;
            Cam.backgroundColor = new Color32(15, 22, 56, 255);
            Cam.nearClipPlane = -100; Cam.farClipPlane = 100;
            Cam.transparencySortMode = TransparencySortMode.Orthographic;
            camGo.AddComponent<AudioListener>();

            shadowMat = new Material(Resources.Load<Shader>("Ogorod/OgorodShadow")) { mainTexture = atlas.Texture };
            shadowMesh = new Mesh { name = "Shadows" };
            shadowMesh.MarkDynamic();
            var sh = new GameObject("Shadows");
            sh.transform.SetParent(root, false);
            sh.AddComponent<MeshFilter>().sharedMesh = shadowMesh;
            var shr = sh.AddComponent<MeshRenderer>(); shr.sharedMaterial = shadowMat; shr.sortingOrder = -20000;

            lightMat = new Material(Resources.Load<Shader>("Ogorod/OgorodLight"));
            glowMat = new Material(Resources.Load<Shader>("Ogorod/OgorodGlow"));
            lightQuad = Quad("Daylight", lightMat, 30000);
            glowQuad = Quad("Glow", glowMat, 30001);
        }

        Transform Quad(string name, Material m, int order)
        {
            var go = new GameObject(name);
            go.transform.SetParent(Cam.transform, false);
            go.transform.localPosition = new Vector3(0, 0, 1);
            var mesh = new Mesh();
            mesh.vertices = new[] { new Vector3(-.5f, -.5f), new Vector3(.5f, -.5f), new Vector3(.5f, .5f), new Vector3(-.5f, .5f) };
            mesh.triangles = new[] { 0, 2, 1, 0, 3, 2 };
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>(); r.sharedMaterial = m; r.sortingOrder = order;
            return go.transform;
        }

        static Vector3 W(float xPx, float yPx) => new Vector3(xPx / T, -yPx / T, 0);
        static int Order(float yPx) => Mathf.RoundToInt(yPx) * 2;

        SpriteRenderer Sprite(string name, float px, float py, int order, Transform parent = null)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent ?? dyn, false);
            go.transform.localPosition = W(px, py);
            var r = go.AddComponent<SpriteRenderer>();
            r.sprite = atlas.Get(name);
            r.sortingOrder = order;
            return r;
        }

        /// <summary>Rebuild the whole map for the day: ground, water, objects. Called on start and every morning.</summary>
        public void Build(GameState s, FarmMap map)
        {
            if (dyn != null) Object.Destroy(dyn.gameObject);
            dyn = new GameObject("Map").transform; dyn.SetParent(root, false);
            plots.Clear(); shadowed.Clear(); waters.Clear(); drops.Clear();
            string look = Seasons.LookName(s.day, s.snowCover);
            bool snow = s.snowCover, winter = s.Season.Id == "winter";

            groundTex = Ground(map, look, snow);
            bareTex = snow ? Ground(map, look.Replace("snow", ""), false) : null;
            ground = new GameObject("Ground").AddComponent<SpriteRenderer>();
            ground.transform.SetParent(dyn, false);
            ground.sprite = UnityEngine.Sprite.Create(groundTex, new Rect(0, 0, groundTex.width, groundTex.height), new Vector2(0, 1), T, 0, SpriteMeshType.FullRect);
            ground.sortingOrder = -30000;

            string sfx = snow ? "_snow" : "";
            string flowers = s.Season.Id == "spring" ? "bloom" : s.Season.Id == "summer" ? "some" : "wither";
            for (int y = 0; y < FarmMap.H; y++) for (int x = 0; x < FarmMap.W; x++)
            {
                char c = map[x, y];
                float px = x * T + T / 2f, py = y * T + T;
                switch (c)
                {
                    case '~':
                        var w = Sprite(winter ? "ice_" + (x + y) % 4 : "water_" + (x + y) % 4 + "_0", x * T, y * T, -29500);
                        if (!winter) waters.Add((w, x, y));
                        break;
                    case 'T': Obj("tree" + (Hash.H(x, y, 11) < 0.35 ? 1 : 0) + "_" + look, px, py, "tree"); break;
                    case 'B': Obj("bush_" + look, px, py, "bush"); break;
                    case 'W': Obj("well" + sfx, px, py, "well"); break;
                    case 'S': Obj("bin" + sfx, px, py, "bin"); break;
                    case 'X': Obj("mailbox" + sfx, px, py, null); break;
                    case 'I': Obj("sign" + sfx, px, py, null); break;
                    case 'R': Obj("rock" + sfx, px, py, "rock"); break;
                    case 'K': Obj("twigs" + sfx, px, py, "twigs"); break;
                    case 'U': Obj("stump" + sfx, px, py, "stump"); break;
                    case ',':
                        if (!snow && !winter && s.PlotAt(x, y) == null) Obj($"flower_{flowers}_{(int)(Hash.H(x, y, 31) * 8)}", px, py, null);
                        break;
                }
            }
            Obj("bigtree_" + look, 69 * T + T / 2f, 26 * T, null);
            Obj("house" + (s.house ? 1 : 0) + sfx, 12 * T, 8 * T, "house");
            foreach (var t in FarmMap.Sites)
                foreach (var (sx, sy) in new[] { (t.x0, t.y0), (t.x1, t.y0), (t.x0, t.y1), (t.x1, t.y1) })
                    Obj("stake" + sfx, sx * T + T / 2f, sy * T + T - 1, null);

            // trodden snow shows the ground beneath
            if (snow) foreach (var key in s.snowTrod) { var p = key.Split(','); Trodden(int.Parse(p[0]), int.Parse(p[1])); }
            foreach (var p in s.plots) SyncPlot(s, p, look);
        }

        static void SetTopLeft(SpriteRenderer r)
        {
            // water and ice sprites have their pivot at the top-left corner
            var b = r.sprite.bounds; r.transform.localPosition += new Vector3(-b.min.x, -b.max.y, 0);
        }

        void Obj(string sprite, float px, float py, string boxKind)
        {
            if (!atlas.Has(sprite)) { Debug.LogWarning("Ogorod: no sprite " + sprite); return; }
            var r = Sprite(sprite, px, py, Order(py));
            shadowed.Add(new Shadowed { sprite = sprite, px = px, py = py, r = r, boxes = boxKind != null ? atlas.Boxes(boxKind) : null });
        }

        Texture2D Ground(FarmMap map, string look, bool snow)
        {
            var tex = new Texture2D(FarmMap.W * T, FarmMap.H * T, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            for (int y = 0; y < FarmMap.H; y++) for (int x = 0; x < FarmMap.W; x++)
            {
                char c = map[x, y];
                int v = (int)(Hash.H(x, y, 3) * 4);
                string name = c == '~' ? "path_0" : snow ? "snow_" + v : c == '=' ? "path_" + v : c == 'P' ? "site_" + v : $"grass_{look}_{v}";
                tex.SetPixels32(x * T, (FarmMap.H - 1 - y) * T, T, T, atlas.Pixels(name));
            }
            tex.Apply(false);
            return tex;
        }

        void Trodden(int x, int y)
        {
            if (bareTex == null) return;
            var bare = new GameObject("Trodden").AddComponent<SpriteRenderer>();
            bare.transform.SetParent(dyn, false);
            bare.sprite = UnityEngine.Sprite.Create(bareTex, new Rect(x * T, (FarmMap.H - 1 - y) * T, T, T), new Vector2(0, 1), T, 0, SpriteMeshType.FullRect);
            bare.transform.localPosition = W(x * T, y * T);
            bare.sortingOrder = -29800;
            var o = Sprite("trodden_" + (x + y) % 4, x * T, y * T, -29799); SetTopLeft(o);
        }
        public void AddTrodden(int x, int y) => Trodden(x, y);

        /// <summary>Show a bed and what grows on it.</summary>
        public void SyncPlot(GameState s, Plot p, string look = null)
        {
            look = look ?? Seasons.LookName(s.day, s.snowCover);
            string key = p.x + "," + p.y;
            if (!plots.TryGetValue(key, out var v))
            {
                var soil = Sprite("soil", p.x * T, p.y * T, -29000); SetTopLeft(soil);
                v = (soil, null);
            }
            bool trod = s.snowTrod.Contains(key);
            v.soil.enabled = p.tilled && (!s.snowCover || trod);
            v.soil.sprite = atlas.Get(p.watered ? "soilwet" : "soil"); SetTopLeftKeep(v.soil, p.x, p.y);
            string name = !p.HasCrop ? null : p.dead ? "dead" + (s.snowCover ? "_snow" : "") : p.crop == "apple" ? $"crop_apple_{Crops.Stage(p)}_{look}" : $"crop_{p.crop}_{Crops.Stage(p)}";
            if (name == null) { if (v.crop) { RemoveShadowed(v.crop); Object.Destroy(v.crop.gameObject); v.crop = null; } }
            else if (v.crop == null) { v.crop = Sprite(name, p.x * T + T / 2f, p.y * T + T, Order(p.y * T + T)); shadowed.Add(new Shadowed { sprite = name, px = p.x * T + T / 2f, py = p.y * T + T, r = v.crop }); }
            else if (v.crop.sprite.name != name) { v.crop.sprite = atlas.Get(name); foreach (var sh in shadowed) if (sh.r == v.crop) sh.sprite = name; }
            plots[key] = v;
        }
        void SetTopLeftKeep(SpriteRenderer r, int x, int y) { r.transform.localPosition = W(x * T, y * T); SetTopLeft(r); }
        void RemoveShadowed(SpriteRenderer r) => shadowed.RemoveAll(sh => sh.r == r);

        public void RemoveObjectAt(int x, int y)
        {
            float px = x * T + T / 2f, py = y * T + T;
            foreach (var sh in shadowed.ToArray())
                if (Mathf.Approximately(sh.px, px) && Mathf.Approximately(sh.py, py) && !sh.sprite.StartsWith("crop") && sh.sprite != "dead")
                { Object.Destroy(sh.r.gameObject); shadowed.Remove(sh); }
        }

        public void ShowDrops(List<Drop> list)
        {
            while (drops.Count < list.Count) { var r = Sprite("icon_wood", 0, 0, 0); r.transform.localScale = Vector3.one * .5f; drops.Add(r); }
            for (int i = 0; i < drops.Count; i++)
            {
                bool on = i < list.Count; drops[i].enabled = on; if (!on) continue;
                var d = list[i];
                drops[i].sprite = atlas.Get(d.Icon);
                drops[i].transform.localPosition = W(Mathf.Round(d.DrawX) - 4, Mathf.Round(d.DrawY - d.Z) - 5);
                drops[i].sortingOrder = Order(d.DrawY);
            }
        }

        /// <summary>Per-frame: camera, player, water ripples, shadows and light.</summary>
        public void Frame(GameState s, float rxPx, float ryPx, string face, int frame, float time, int pxPerDraft)
        {
            // camera: one draft pixel = pxPerDraft screen pixels, snapped to whole pixels
            Cam.orthographicSize = Screen.height / (2f * T * pxPerDraft);
            float halfW = Cam.orthographicSize * Cam.aspect, halfH = Cam.orthographicSize;
            float cx = (rxPx + T / 2f) / T, cy = (ryPx + T / 2f) / T;
            cx = FarmMap.W <= halfW * 2 ? FarmMap.W / 2f : Mathf.Clamp(cx, halfW, FarmMap.W - halfW);
            cy = FarmMap.H <= halfH * 2 ? FarmMap.H / 2f : Mathf.Clamp(cy, halfH, FarmMap.H - halfH);
            float snap = T * pxPerDraft;
            Cam.transform.position = new Vector3(Mathf.Round(cx * snap) / snap, -Mathf.Round(cy * snap) / snap, -10);
            lightQuad.localScale = glowQuad.localScale = new Vector3(halfW * 2 + 1, halfH * 2 + 1, 1);

            // player
            string pname = $"player_{face}_{frame}";
            if (Player == null) Player = Sprite(pname, 0, 0, 0, root);
            Player.sprite = atlas.Get(pname);
            Player.transform.localPosition = W(Mathf.Round(rxPx) + T / 2f, Mathf.Round(ryPx) + T);
            Player.sortingOrder = Order(Mathf.Round(ryPx) + T) + 1;

            int wf = (int)(time * 2) % 4;
            foreach (var (r, x, y) in waters) r.sprite = atlas.Get($"water_{(x + y) % 4}_{wf}");

            Shadows(s, rxPx, ryPx, pname);
            var tint = Sky.TintAt(s.min);
            lightMat.color = new Color((float)tint.r / 255f, (float)tint.g / 255f, (float)tint.b / 255f, 1);
            float gl = (float)Sky.GlowAt(s.min);
            glowMat.color = new Color(gl, gl * .63f, gl * .31f, 1);
        }

        readonly List<Vector3> sv = new List<Vector3>();
        readonly List<Vector2> su = new List<Vector2>();
        readonly List<int> st = new List<int>();

        void Shadows(GameState s, float rxPx, float ryPx, string playerSprite)
        {
            sv.Clear(); su.Clear(); st.Clear();
            var sun = Sky.SunAt(s.min);
            if (sun != null)
            {
                var sn = sun.Value;
                shadowMat.color = new Color(0.024f, 0.063f, 0.165f, (float)sn.Alpha);
                var view = new Rect(Cam.transform.position.x - Cam.orthographicSize * Cam.aspect - 4, -Cam.transform.position.y - Cam.orthographicSize - 4,
                                    Cam.orthographicSize * Cam.aspect * 2 + 8, Cam.orthographicSize * 2 + 8);
                foreach (var o in shadowed)
                    if (view.Contains(new Vector2(o.px / T, o.py / T))) Cast(o.sprite, o.px, o.py, o.boxes, sn);
                Cast(playerSprite, Mathf.Round(rxPx) + T / 2f, Mathf.Round(ryPx) + T, null, sn);
            }
            shadowMesh.Clear();
            shadowMesh.SetVertices(sv); shadowMesh.SetUVs(0, su); shadowMesh.SetTriangles(st, 0);
        }

        void Cast(string sprite, float px, float py, ShadowBox[] boxes, Sky.Sun sun)
        {
            var a = atlas.Info(sprite);
            if (a == null) return;
            float X = px - a.ax, Y = py - a.ay, sh = (float)sun.Shear, ln = (float)sun.Len;
            if (boxes != null)
            {
                // objects with depth: every horizontal slice of each box is laid on the ground away from the sun
                var opaque = atlas.UV(atlas.Info("soil").x + 8, atlas.Info("soil").y + 8);
                foreach (var b in boxes)
                {
                    float cx = (b.x0 + b.x1) / 2f, cy = (b.y0 + b.y1) / 2f, hw = (b.x1 - b.x0) / 2f, hd = (b.y1 - b.y0) / 2f;
                    for (int h = b.h0; h <= b.h1; h++)
                    {
                        float k = string.IsNullOrEmpty(b.top) ? 1 : 1 - (float)(h - b.h0) / Mathf.Max(1, b.h1 - b.h0);
                        float w = b.top == "point" ? hw * k : hw, d = hd * k;
                        float x0 = Mathf.Round(X + cx - w + sh * h), y0 = Mathf.Round(Y + cy - d + ln * h);
                        QuadPx(x0, y0, Mathf.Max(1, Mathf.Round(w * 2)), Mathf.Max(1, Mathf.Round(d * 2)), opaque);
                    }
                }
                return;
            }
            // everything else: the sprite's silhouette above the ground line, sheared away from the sun
            float foot = py - a.ay + a.fy;
            Vector3 P(float u, float v) => W(px - a.ax + u + sh * (a.fy - v), foot + ln * (a.fy - v));
            int i = sv.Count;
            sv.Add(P(0, 0)); sv.Add(P(a.w, 0)); sv.Add(P(a.w, a.fy)); sv.Add(P(0, a.fy));
            su.Add(atlas.UV(a.x, a.y)); su.Add(atlas.UV(a.x + a.w, a.y)); su.Add(atlas.UV(a.x + a.w, a.y + a.fy)); su.Add(atlas.UV(a.x, a.y + a.fy));
            st.Add(i); st.Add(i + 1); st.Add(i + 2); st.Add(i); st.Add(i + 2); st.Add(i + 3);
        }

        void QuadPx(float x, float y, float w, float h, Vector2 uv)
        {
            int i = sv.Count;
            sv.Add(W(x, y)); sv.Add(W(x + w, y)); sv.Add(W(x + w, y + h)); sv.Add(W(x, y + h));
            su.Add(uv); su.Add(uv); su.Add(uv); su.Add(uv);
            st.Add(i); st.Add(i + 1); st.Add(i + 2); st.Add(i); st.Add(i + 2); st.Add(i + 3);
        }

        /// <summary>Screen point to tile.</summary>
        public Vector2Int TileAt(Vector3 screen)
        {
            var w = Cam.ScreenToWorldPoint(screen);
            return new Vector2Int(Mathf.FloorToInt(w.x), Mathf.FloorToInt(-w.y));
        }
    }

    /// <summary>An item lying on the ground (draft px). Z is its height while it flies out.</summary>
    public class Drop { public string Kind, Key, Icon; public float X, Y, Z, X0, Y0, T, Dur, DrawX, DrawY; }
}
