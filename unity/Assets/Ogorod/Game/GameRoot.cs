// Дедушкин огород in Unity, step 1: the farm. Ported from game/index.html.
// Starts by itself when you press Play in any scene: no scene setup is needed.
using System.Collections.Generic;
using Ogorod.Core;
using UnityEngine;

namespace Ogorod.Game
{
    public partial class GameRoot : MonoBehaviour
    {
        const int T = Atlas.PPU;
        const string SaveKey = "dedushkin-ogorod-unity-v1";

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (started) return;
            started = true;
            // hide cameras the scene came with: the game makes its own
            foreach (var c in Camera.allCameras) c.gameObject.SetActive(false);
            new GameObject("Дедушкин огород").AddComponent<GameRoot>();
        }
        static bool started;
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics() => started = false;   // when domain reload is turned off in the editor

        Atlas atlas;
        WorldView view;
        GameState state;
        FarmMap map;
        string look;

        // the player moves tile by tile; (tx, ty) is the tile being walked to
        int px, py, tx, ty; float stepT, walk; bool moving; string face = "down";
        readonly List<string> held = new List<string>();
        List<Vector2Int> path = new List<Vector2Int>();
        Vector2Int? pending;
        readonly List<Drop> drops = new List<Drop>();
        bool timeFrozen, sleepNow;
        float autosave;

        static readonly Dictionary<string, Vector2Int> Dirs = new Dictionary<string, Vector2Int>
        { ["up"] = new Vector2Int(0, -1), ["down"] = new Vector2Int(0, 1), ["left"] = new Vector2Int(-1, 0), ["right"] = new Vector2Int(1, 0) };

        void Start()
        {
            atlas = new Atlas();
            view = new WorldView(atlas, transform);
            state = Load() ?? GameState.New();
            BuildWorld();
            px = tx = state.px; py = ty = state.py; face = state.face;
            if (!map.Walkable(px, py)) { px = tx = 14; py = ty = 9; }
            if (!state.intro) OpenIntro(); else Toast("С возвращением! День " + state.day + ".");
        }

        void BuildWorld()
        {
            map = new FarmMap(state);
            look = Seasons.LookName(state.day, state.snowCover);
            view.Build(state, map);
        }

        // ---------- the loop ----------
        void Update()
        {
            float dt = Mathf.Min(Time.deltaTime, .05f);
            try { ReadInput(); }
            catch (System.InvalidOperationException)
            {
                // the project uses only the new Input System: the old keyboard API is switched off
                Toast("Включите Edit → Project Settings → Player → Active Input Handling: Both, и перезапустите Unity.");
            }
            if (sleepNow) { sleepNow = false; NewDay(""); return; }
            UpdateDrops(dt);
            if (panel == null)
            {
                if (!timeFrozen) state.min += dt * 4;
                if (state.min >= 1380 && !state.lateWarned) { state.lateWarned = true; Toast("Уже 23:00. Пора домой спать."); }
                if (state.min >= 1440) { NewDay("Тёма так заработался, что уснул прямо на улице. Соседи проводили его до дома."); return; }
                Move(dt);
                autosave += dt; if (autosave > 15) { autosave = 0; Save(); }
            }
            float rx = Mathf.Lerp(px, tx, stepT) * T, ry = Mathf.Lerp(py, ty, stepT) * T;
            int k = Mathf.Max(1, Mathf.RoundToInt(Mathf.Max(Screen.width, Screen.height) / 900f));
            view.ShowDrops(drops);
            view.Frame(state, rx, ry, face, moving ? (int)(walk * 8) % 2 : 0, Time.time, k * 2);
        }

        void OnApplicationQuit() => Save();

        void Move(float dt)
        {
            if (moving)
            {
                stepT += dt / .15f; walk += dt;
                if (stepT >= 1)
                {
                    px = tx; py = ty; moving = false; stepT = 0;
                    if (state.snowCover) { string key = px + "," + py; if (!state.snowTrod.Contains(key)) { state.snowTrod.Add(key); view.AddTrodden(px, py); } }
                }
            }
            if (moving) return;
            string d = held.Count > 0 ? held[held.Count - 1] : null;
            if (d != null) { path.Clear(); pending = null; Step(d); }
            else if (path.Count > 0) { var n = path[0]; path.RemoveAt(0); if (!Step(DirTo(px, py, n.x, n.y))) { path.Clear(); pending = null; } }
            else if (pending != null) { var p = pending.Value; pending = null; face = DirTo(px, py, p.x, p.y) ?? face; Act(p.x, p.y); }
        }

        bool Step(string d)
        {
            if (d == null) return false;
            face = d;
            var v = Dirs[d]; int nx = px + v.x, ny = py + v.y;
            if (map.ExitAt(nx, ny) != null) { Toast("Эта дорога откроется на следующем шаге переноса в Unity."); return false; }
            if (!map.Walkable(nx, ny)) return false;
            tx = nx; ty = ny; moving = true; stepT = 0; return true;
        }
        static string DirTo(int x, int y, int nx, int ny) => nx > x ? "right" : nx < x ? "left" : ny > y ? "down" : ny < y ? "up" : null;
        Vector2Int Front() => new Vector2Int(px, py) + Dirs[face];

        // ---------- input ----------
        static readonly (KeyCode k, string d)[] MoveKeys =
        {
            (KeyCode.UpArrow, "up"), (KeyCode.W, "up"), (KeyCode.DownArrow, "down"), (KeyCode.S, "down"),
            (KeyCode.LeftArrow, "left"), (KeyCode.A, "left"), (KeyCode.RightArrow, "right"), (KeyCode.D, "right"),
        };
        static readonly KeyCode[] SlotKeys = { KeyCode.Alpha1, KeyCode.Alpha2, KeyCode.Alpha3, KeyCode.Alpha4, KeyCode.Alpha5, KeyCode.Alpha6, KeyCode.Alpha7, KeyCode.Alpha8, KeyCode.Alpha9, KeyCode.Alpha0, KeyCode.Minus, KeyCode.Equals };

        void ReadInput()
        {
            if (Input.GetKeyDown(KeyCode.Escape) && panel != null) { ClosePanel(); return; }
            if (Input.GetKeyDown(KeyCode.I)) { if (panel == "bag") ClosePanel(); else if (panel == null) Open("bag"); return; }
            if (Input.GetKeyDown(KeyCode.H)) { if (panel == "admin") ClosePanel(); else if (panel == null) Open("admin"); return; }
            if (panel != null) { held.Clear(); return; }
            foreach (var (k, d) in MoveKeys)
            {
                if (Input.GetKeyDown(k) && !held.Contains(d)) held.Add(d);
                if (Input.GetKeyUp(k)) held.Remove(d);
            }
            if (Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.E)) { if (!moving) { var f = Front(); Act(f.x, f.y); } }
            var belt = BeltList();
            for (int i = 0; i < SlotKeys.Length && i < belt.Count; i++) if (Input.GetKeyDown(SlotKeys[i])) state.tool = belt[i];
            if (Input.GetMouseButtonDown(0) && !MouseOverUi()) Click(view.TileAt(Input.mousePosition));
        }

        /// <summary>Click a tile: walk next to it and use what is in hand, or just walk there.</summary>
        void Click(Vector2Int t)
        {
            if (!FarmMap.In(t.x, t.y)) return;
            char c = map[t.x, t.y];
            int sx = moving ? tx : px, sy = moving ? ty : py;
            string tool = Tools[state.tool].Id;
            bool target = "DWSX~HITRKUY".IndexOf(c) >= 0 || state.PlotAt(t.x, t.y) != null || (map.Farmable(t.x, t.y) && (tool == "hoe" || tool == "seed"));
            var p = Bfs(sx, sy, target ? (System.Func<int, int, bool>)((x, y) => Mathf.Abs(x - t.x) + Mathf.Abs(y - t.y) == 1) : (x, y) => x == t.x && y == t.y);
            if (p == null) { if (target) Toast("Туда не подойти."); return; }
            held.Clear(); path = p; pending = target ? t : (Vector2Int?)null;
        }

        List<Vector2Int> Bfs(int sx, int sy, System.Func<int, int, bool> goal)
        {
            var prev = new Dictionary<Vector2Int, Vector2Int>();
            var start = new Vector2Int(sx, sy); var q = new Queue<Vector2Int>(); q.Enqueue(start); prev[start] = start;
            while (q.Count > 0)
            {
                var c = q.Dequeue();
                if (goal(c.x, c.y))
                {
                    var res = new List<Vector2Int>();
                    while (c != start) { res.Insert(0, c); c = prev[c]; }
                    return res;
                }
                foreach (var d in Dirs.Values)
                {
                    var n = c + d;
                    if (!map.Walkable(n.x, n.y) || map.ExitAt(n.x, n.y) != null || prev.ContainsKey(n)) continue;
                    prev[n] = c; q.Enqueue(n);
                }
            }
            return null;
        }

        // ---------- tools and actions ----------
        public struct ToolDef { public string Id, Name, Crop; }
        static readonly List<ToolDef> Tools = BuildTools();
        static List<ToolDef> BuildTools()
        {
            var l = new List<ToolDef> { new ToolDef { Id = "hoe", Name = "Мотыга" }, new ToolDef { Id = "can", Name = "Лейка" } };
            foreach (var c in Crops.All) l.Add(new ToolDef { Id = "seed", Name = c.SeedName, Crop = c.Key });
            return l;
        }
        const int NTools = 2;
        /// <summary>The belt: both tools and the seeds you have, up to 12 slots.</summary>
        List<int> BeltList()
        {
            var l = new List<int> { 0, 1 };
            for (int i = NTools; i < Tools.Count && l.Count < 12; i++) if (state.seeds[Crops.Index(Tools[i].Crop)] > 0 || i == state.tool) l.Add(i);
            return l;
        }

        void Act(int x, int y)
        {
            if (!FarmMap.In(x, y)) return;
            char c = map[x, y];
            if (c == 'D') { Open("sleep"); return; }
            if (c == 'S') { Open("ship"); return; }
            if (c == 'X') { Open("mail"); return; }
            if (c == 'I') { FarmMap.Signs.TryGetValue((x, y), out var text); Toast(text ?? "Табличка."); return; }
            if (c == 'Y') { Toast("Огромный старый дуб перегородил дорогу. Что за ним, узнаем позже."); return; }
            if (c == 'W' || c == '~')
            {
                if (state.water >= state.cap) { Toast("Лейка уже полная."); return; }
                state.water = state.cap; Toast("Лейка наполнена: " + state.cap + " л."); return;
            }
            if (c == 'H') { Toast(state.house ? "Дедушкин дом. Теперь в нём тепло и уютно." : "Дедушкин дом. Крыша течёт, доски скрипят. Нужен ремонт."); return; }
            if ("TBRKU".IndexOf(c) >= 0) { Toast("Топор и кирка появятся на следующем шаге переноса в Unity."); return; }
            var tool = Tools[state.tool];
            var pl = state.PlotAt(x, y);
            string sid = state.Season.Id;
            if (pl == null && !map.Farmable(x, y))
            {
                if (tool.Id != "can" && (c == '.' || c == ',' || c == '=' || c == 'P'))
                    Toast(c == '=' ? "На дороге копать нельзя." : c == 'P' ? "Это место под постройку." : "Во дворе у дома копать нельзя: отойдите на пару шагов.");
                return;
            }
            if (pl != null && pl.HasCrop && pl.dead) { pl.crop = ""; pl.dead = false; view.SyncPlot(state, pl); Toast("Увядшее растение убрано. Грядка свободна."); return; }
            if (pl != null && pl.HasCrop && pl.ripe) { HarvestAt(pl); return; }
            if (sid == "winter" && tool.Id != "can") { Toast("Зимой земля промёрзла. Огород отдыхает до весны."); return; }
            if (tool.Id == "hoe")
            {
                if (pl == null || !pl.tilled)
                {
                    pl = pl ?? new Plot { x = x, y = y }; pl.tilled = true;
                    if (!state.plots.Contains(pl)) state.plots.Add(pl);
                    if (c == ',') view.RemoveObjectAt(x, y);
                    view.SyncPlot(state, pl);
                }
                else if (pl.HasCrop) Toast("Тут растёт: " + Crops.Get(pl.crop).Name.ToLower() + ".");
                else Toast("Земля уже вскопана. Выберите семена.");
                return;
            }
            if (tool.Id == "can")
            {
                if (pl == null || !pl.tilled) { Toast("Сначала вскопайте землю мотыгой."); return; }
                if (sid == "winter") { Toast("Зимой поливать не нужно: земля спит под снегом."); return; }
                if (pl.watered) { Toast("Здесь уже полито."); return; }
                if (state.water <= 0) { Toast("Лейка пуста. Наберите воды в колодце или пруду."); return; }
                state.water--; pl.watered = true; view.SyncPlot(state, pl); return;
            }
            var d = Crops.Get(tool.Crop); int ci = Crops.Index(tool.Crop);
            if (pl == null || !pl.tilled) { Toast("Сначала вскопайте землю мотыгой."); return; }
            if (pl.HasCrop) { Toast("Тут уже растёт: " + Crops.Get(pl.crop).Name.ToLower() + "."); return; }
            if (state.seeds[ci] <= 0) { Toast("Закончилось: " + d.SeedName.ToLower() + ". Купите на рынке."); return; }
            if (!Crops.CanPlant(tool.Crop, sid)) { Toast($"{d.Name}: сажают в сезон «{Seasons.RuList(d.PlantSeasons)}». Сейчас {state.Season.Name.ToLower()}."); return; }
            state.seeds[ci]--; pl.crop = tool.Crop; pl.age = 0; pl.ripe = pl.grown = pl.dead = false;
            view.SyncPlot(state, pl);
        }

        void HarvestAt(Plot pl)
        {
            string crop = pl.crop;
            int n = Rules.Harvest(pl);
            Spill(pl.x, pl.y, "prod", crop, n);
            view.SyncPlot(state, pl);
        }

        // ---------- items on the ground ----------
        void Spill(int x, int y, string kind, string key, int n)
        {
            float cx = x * T + T / 2f, cy = y * T + T / 2f;
            for (int i = 0; i < n; i++)
            {
                float a = Random.value * Mathf.PI * 2, r = 3 + Random.value * 13;
                drops.Add(new Drop { Kind = kind, Key = key, Icon = kind == "prod" ? "prod_" + key : "icon_" + key,
                    X = Mathf.Round(cx + Mathf.Cos(a) * r), Y = Mathf.Round(cy + Mathf.Sin(a) * r * .8f), X0 = cx, Y0 = cy - 4, DrawX = cx, DrawY = cy - 4, T = -i * .05f, Dur = .32f + Random.value * .12f });
            }
        }
        /// <summary>Items fly out, lie on the ground, and fly to Тёма when he comes within 1.5 tiles.</summary>
        void UpdateDrops(float dt)
        {
            float ppx = Mathf.Lerp(px, tx, stepT) * T + T / 2f, ppy = Mathf.Lerp(py, ty, stepT) * T + T / 2f;
            for (int i = drops.Count - 1; i >= 0; i--)
            {
                var d = drops[i];
                if (d.T < d.Dur + .2f)
                {
                    d.T += dt; float u = Mathf.Clamp01(d.T / d.Dur);
                    d.DrawX = d.X0 + (d.X - d.X0) * u; d.DrawY = d.Y0 + (d.Y - d.Y0) * u;
                    d.Z = Mathf.Sin(u * Mathf.PI) * 7; continue;
                }
                d.Z = (Mathf.Sin(Time.time * 3.3f + d.X) + 1) * .5f;
                float dx = ppx - d.X, dy = ppy - d.Y, dist = Mathf.Sqrt(dx * dx + dy * dy);
                if (dist > 24 || panel != null) continue;
                if (dist < 4)
                {
                    drops.RemoveAt(i);
                    state.produce[Crops.Index(d.Key)]++;
                    Toast("+1 " + Crops.Get(d.Key).Product.ToLower());
                    continue;
                }
                float sp = (60 + (24 - dist) * 8) * dt;
                d.X += dx / dist * Mathf.Min(sp, dist); d.Y += dy / dist * Mathf.Min(sp, dist);
                d.DrawX = d.X; d.DrawY = d.Y;
            }
        }

        // ---------- days ----------
        void NewDay(string note)
        {
            var m = Rules.NewDay(state);
            px = tx = state.px; py = ty = state.py; face = state.face; moving = false; held.Clear(); path.Clear(); pending = null;
            BuildWorld();
            Save();
            morning = m; morningNote = note;
            Open("morning");
        }

        // ---------- saving ----------
        void Save()
        {
            state.px = px; state.py = py; state.face = face;
            PlayerPrefs.SetString(SaveKey, JsonUtility.ToJson(state));
            PlayerPrefs.Save();
        }
        static GameState Load()
        {
            if (!PlayerPrefs.HasKey(SaveKey)) return null;
            try
            {
                var s = JsonUtility.FromJson<GameState>(PlayerPrefs.GetString(SaveKey));
                if (s == null || s.seeds == null || s.seeds.Length != Crops.All.Length) return null;
                return s;
            }
            catch { return null; }
        }
    }
}
