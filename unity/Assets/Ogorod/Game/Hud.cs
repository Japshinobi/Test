// Interface drawn with Unity's immediate-mode GUI (OnGUI): no scene or prefab setup needed.
// Blue panels with gold highlights, as in the browser version. To be replaced with UI Toolkit later.
using System.Collections.Generic;
using System.Linq;
using Ogorod.Core;
using UnityEngine;

namespace Ogorod.Game
{
    public partial class GameRoot
    {
        string panel;                 // which window is open: null when playing
        Morning morning; string morningNote;
        string toast; float toastUntil;
        Rect beltRect, topRect, panelRect;
        GUIStyle box, label, small, gold, title, button, buttonOn, chip, dim;
        float ui = 1;
        Vector2 scroll;
        int adminDay = 1, adminHour = 10, adminMinute, adminItem, adminCount = 10;

        static readonly Color Panel = new Color32(44, 60, 140, 240), Edge = new Color32(21, 27, 74, 255), Panel2 = new Color32(61, 79, 168, 255), Gold = new Color32(255, 210, 74, 255);

        void Toast(string text) { toast = text; toastUntil = Time.time + 2.6f; }
        void Open(string name) { panel = name; scroll = Vector2.zero; held.Clear(); path.Clear(); pending = null; if (name == "admin") { adminDay = state.Season.Day; adminHour = (int)(state.min / 60); adminMinute = (int)(state.min % 60) / 10 * 10; } }
        void ClosePanel() { if (panel == "intro") { state.intro = true; Save(); } panel = null; }
        void OpenIntro() => Open("intro");
        bool MouseOverUi()
        {
            var m = Input.mousePosition; var p = new Vector2(m.x, Screen.height - m.y);
            return panel != null || beltRect.Contains(p) || topRect.Contains(p);
        }

        static Texture2D Solid(Color c) { var t = new Texture2D(1, 1); t.SetPixel(0, 0, c); t.Apply(); return t; }
        void Styles()
        {
            ui = Mathf.Max(1, Screen.height / 720f);
            if (box != null && Mathf.Approximately(box.fontSize, Mathf.Round(15 * ui))) return;
            box = new GUIStyle(GUI.skin.box) { normal = { background = Solid(Panel), textColor = Color.white }, border = new RectOffset(2, 2, 2, 2), padding = new RectOffset(8, 8, 6, 6), fontSize = Mathf.RoundToInt(15 * ui), alignment = TextAnchor.UpperLeft };
            label = new GUIStyle(GUI.skin.label) { fontSize = Mathf.RoundToInt(15 * ui), wordWrap = true, normal = { textColor = Color.white } };
            small = new GUIStyle(label) { fontSize = Mathf.RoundToInt(13 * ui), normal = { textColor = new Color32(195, 203, 242, 255) } };
            gold = new GUIStyle(label) { fontStyle = FontStyle.Bold, normal = { textColor = Gold } };
            title = new GUIStyle(gold) { fontSize = Mathf.RoundToInt(20 * ui) };
            button = new GUIStyle(GUI.skin.button) { fontSize = Mathf.RoundToInt(14 * ui), normal = { background = Solid(Panel2), textColor = Color.white }, hover = { background = Solid(new Color32(80, 100, 200, 255)), textColor = Color.white }, padding = new RectOffset(10, 10, 5, 5) };
            buttonOn = new GUIStyle(button) { normal = { background = Solid(new Color32(47, 158, 58, 255)), textColor = Color.white } };
            chip = new GUIStyle(box) { alignment = TextAnchor.MiddleLeft, padding = new RectOffset(8, 8, 2, 2), fontSize = Mathf.RoundToInt(14 * ui), wordWrap = false };
        }

        void OnGUI()
        {
            if (state == null) return;
            Styles();
            Hud();
            if (panel != null) Window();
        }

        void Hud()
        {
            var s = state.Season; int m = Mathf.FloorToInt((float)state.min / 10) * 10;
            string part = timeFrozen ? "пауза" : state.min < 720 ? "утро" : state.min < 1080 ? "день" : state.min < 1320 ? "вечер" : "ночь";
            string[] chips = { $"{s.Name}, день {s.Day} из {Seasons.Days}", "Дедушкин огород", $"{m / 60}:{m % 60:00} {part}", $"Монеты {state.money}", $"Вода {state.water}/{state.cap}", $"Корзина {state.produce.Sum()}" };
            float x = 8 * ui, h = 26 * ui;
            foreach (var c in chips) { var w = chip.CalcSize(new GUIContent(c)).x; GUI.Box(new Rect(x, 8 * ui, w, h), c, chip); x += w + 5 * ui; }
            topRect = new Rect(0, 0, Screen.width, 40 * ui);
            var bagLabel = "Инвентарь (I)"; var bw = button.CalcSize(new GUIContent(bagLabel)).x;
            if (GUI.Button(new Rect(Screen.width - bw - 8 * ui, 8 * ui, bw, h), bagLabel, button) && panel == null) Open("bag");

            // the belt
            var belt = BeltList(); float cell = 44 * ui, gap = 3 * ui, total = belt.Count * (cell + gap) - gap;
            float bx = (Screen.width - total) / 2, by = Screen.height - cell - 28 * ui;
            beltRect = new Rect(bx, by - 22 * ui, total, cell + 50 * ui);
            for (int i = 0; i < belt.Count; i++)
            {
                var t = Tools[belt[i]]; var r = new Rect(bx + i * (cell + gap), by, cell, cell);
                GUI.Box(r, GUIContent.none, belt[i] == state.tool ? buttonOn : button);
                Icon(new Rect(r.x + 6 * ui, r.y + 6 * ui, cell - 12 * ui, cell - 12 * ui), t.Id == "seed" ? "seed_" + t.Crop : "icon_" + t.Id, t.Id == "seed" && !Crops.CanPlant(t.Crop, s.Id) ? .45f : 1);
                GUI.Label(new Rect(r.x + 3 * ui, r.y, cell, 16 * ui), new[] { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "−", "=" }[i], small);
                string n = t.Id == "can" ? state.water.ToString() : t.Id == "seed" ? state.seeds[Crops.Index(t.Crop)].ToString() : "";
                if (n != "") GUI.Label(new Rect(r.xMax - 22 * ui, r.yMax - 18 * ui, 22 * ui, 18 * ui), n, small);
                if (GUI.Button(r, GUIContent.none, GUIStyle.none)) state.tool = belt[i];
            }
            GUI.Label(new Rect(0, by - 22 * ui, Screen.width, 20 * ui), "В руках: " + Holding(), new GUIStyle(small) { alignment = TextAnchor.MiddleCenter });
            GUI.Label(new Rect(0, Screen.height - 24 * ui, Screen.width, 20 * ui), "Стрелки или WASD — ходить · Пробел или E — действие · 1–0 − = — предмет · I — инвентарь · H — админ-панель · щелчок по клетке — подойти и сделать", new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = Mathf.RoundToInt(12 * ui) });
            if (toast != null && Time.time < toastUntil)
            {
                var c = new GUIContent(toast); var st = new GUIStyle(chip) { alignment = TextAnchor.MiddleCenter, wordWrap = true };
                float w = Mathf.Min(Screen.width - 40 * ui, st.CalcSize(c).x + 20 * ui);
                GUI.Box(new Rect((Screen.width - w) / 2, by - 60 * ui, w, 30 * ui), c, st);
            }
        }

        string Holding()
        {
            var t = Tools[state.tool];
            if (t.Id == "hoe") return "Мотыга — вскопать землю на огороде";
            if (t.Id == "can") return $"Лейка — {state.water}/{state.cap} л. Полить грядку. Воду набирают в колодце или пруду";
            var d = Crops.Get(t.Crop);
            return $"{d.SeedName} — {state.seeds[Crops.Index(t.Crop)]} шт. Сезон: {Seasons.RuList(d.PlantSeasons)}{(Crops.CanPlant(t.Crop, state.Season.Id) ? "" : " (сейчас не сезон)")}, растёт {d.Grow} дн.";
        }

        void Icon(Rect r, string sprite, float alpha = 1)
        {
            var a = atlas.Info(sprite); if (a == null) return;
            var old = GUI.color; GUI.color = new Color(1, 1, 1, alpha);
            GUI.DrawTextureWithTexCoords(r, atlas.Texture, new Rect((float)a.x / atlas.Index.width, 1 - (float)(a.y + a.h) / atlas.Index.height, (float)a.w / atlas.Index.width, (float)a.h / atlas.Index.height));
            GUI.color = old;
        }

        // ---------- windows ----------
        void Window()
        {
            dim = dim ?? new GUIStyle { normal = { background = Solid(new Color(0.02f, 0.03f, 0.1f, 0.6f)) } };
            GUI.Box(new Rect(0, 0, Screen.width, Screen.height), GUIContent.none, dim);
            string current = panel;   // a button may close or switch the window: finish this pass with the same one
            float w = Mathf.Min(Screen.width - 32 * ui, (current == "bag" ? 760 : 520) * ui), h = Mathf.Min(Screen.height - 32 * ui, 620 * ui);
            panelRect = new Rect((Screen.width - w) / 2, (Screen.height - h) / 2, w, h);
            GUILayout.BeginArea(panelRect, box);
            scroll = GUILayout.BeginScrollView(scroll);
            switch (current)
            {
                case "intro": Intro(); break;
                case "sleep": Sleep(); break;
                case "morning": Morning(); break;
                case "bag": Bag(); break;
                case "ship": Ship(); break;
                case "mail": Para("Почтовый ящик", "Писем пока нет. Сюда будут приходить извещения: о смене сезона, о погоде и другие новости."); break;
                case "admin": Admin(); break;
            }
            GUILayout.EndScrollView();
            GUILayout.Space(6 * ui);
            if (current != "sleep" && GUILayout.Button(current == "morning" ? "Доброе утро!" : current == "intro" ? "Начать" : "Закрыть", button, GUILayout.Width(160 * ui)) && panel == current) ClosePanel();
            GUILayout.EndArea();
        }

        void H(string text) => GUILayout.Label(text, title);
        void P(string text) => GUILayout.Label(text, label);
        void Para(string head, string text) { H(head); P(text); }

        void Intro()
        {
            H("Дедушкин огород");
            P("Дедушка Матвей оставил внуку Тёме старый дом и заросший огород на краю деревни. В кармане 100 монет и пара пакетиков семян.");
            P("Это первый шаг переноса игры в Unity: здесь пока только огород. Лес, речка, перекрёсток и рынок, топор, кирка и коса появятся на следующих шагах.");
            GUILayout.Label("Как играть", gold);
            P("1. Мотыгой вскопайте землю на любой траве огорода (кроме двора и дорог).\n2. Выберите семена и посадите.\n3. Полейте из лейки; воду набирают в колодце или пруду.\n4. Ночью растения подрастают, без полива вдвое медленнее.\n5. Год из четырёх сезонов по 12 дней; не по сезону растение увядает.\n6. Урожай кладите в ящик для отгрузки у дома: деньги придут утром.\n7. Спать — у двери дома.");
        }

        void Sleep()
        {
            H("Лечь спать?");
            int m = Mathf.FloorToInt((float)state.min / 10) * 10;
            P($"Сейчас {m / 60}:{m % 60:00}. Наступит утро следующего дня, а растения за ночь подрастут.");
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("Спать", buttonOn, GUILayout.Width(140 * ui))) { panel = null; sleepNow = true; }
            if (GUILayout.Button("Ещё побуду", button, GUILayout.Width(140 * ui))) ClosePanel();
            GUILayout.EndHorizontal();
        }

        static readonly Dictionary<string, string> SeasonText = new Dictionary<string, string>
        {
            ["spring"] = "Наступила весна! Снег сошёл, деревья просыпаются, на лугу зацветают цветы.",
            ["summer"] = "Наступило лето! Тепло, всё зелёное, самое время для огурцов и помидоров.",
            ["autumn"] = "Наступила осень! Листья скоро пожелтеют, а яблони дадут урожай.",
            ["winter"] = "Наступила зима! Земля промёрзла, огород отдыхает до весны. Скоро выпадет снег.",
        };
        void Morning()
        {
            var s = state.Season;
            H($"{s.Name}, день {s.Day} из {Seasons.Days}");
            if (morning == null) return;
            if (morning.SeasonChanged) GUILayout.Label(SeasonText[s.Id], gold);
            if (morning.SeasonChanged && morning.Withered.Count > 0) P("Не пережили смену сезона: " + string.Join(", ", morning.Withered.Select(k => Crops.Get(k.Key).Name + " ×" + k.Value)) + ". Уберите увядшие растения с грядок.");
            if (morning.Snowed && s.Id == "winter") P("За ночь всё засыпало снегом.");
            if (morning.ShippedIncome > 0) P($"За отгрузку из ящика получено {morning.ShippedIncome} монет.");
            if (!string.IsNullOrEmpty(morningNote)) P(morningNote);
            P(morning.Ripened.Count > 0 ? "За ночь созрело: " + string.Join(", ", morning.Ripened.Select(k => Crops.Get(k.Key).Product + " ×" + k.Value)) + "." : "Пока ничего не созрело. Растения тянутся к солнцу.");
            if (morning.Dry > 0) P($"Без полива осталось растений: {morning.Dry}. Они росли вдвое медленнее.");
        }

        void Bag()
        {
            H("Инвентарь");
            GUILayout.BeginHorizontal();
            // equipment: slots for clothes that will give bonuses later
            GUILayout.BeginVertical(GUILayout.Width(170 * ui));
            var r = GUILayoutUtility.GetRect(64 * ui, 96 * ui, GUILayout.Width(150 * ui));
            Icon(new Rect(r.x + (r.width - 64 * ui) / 2, r.y, 64 * ui, 96 * ui), "player_down_0");
            foreach (var slot in new[] { "Голова", "Тело", "Штаны", "Обувь" }) GUILayout.Box(slot + "\nпусто", button, GUILayout.Width(150 * ui));
            GUILayout.Label("Экипировка появится позже: одежда будет давать бонусы и менять внешность Тёмы.", small, GUILayout.Width(150 * ui));
            GUILayout.EndVertical();
            GUILayout.BeginVertical();
            GUILayout.Label("Монеты: " + state.money, gold);
            GUILayout.Label("Инструменты", gold);
            Cells(new[] { (0, "icon_hoe", "Мотыга", ""), (1, "icon_can", "Лейка", state.water + "/" + state.cap) });
            GUILayout.Label("Семена", gold);
            var seeds = Crops.All.Select((c, i) => (i, c)).Where(t => state.seeds[t.i] > 0).Select(t => (NTools + t.i, "seed_" + t.c.Key, t.c.Name, state.seeds[t.i].ToString())).ToArray();
            if (seeds.Length > 0) Cells(seeds); else GUILayout.Label("Семян нет.", small);
            GUILayout.Label("Урожай", gold);
            var prod = Crops.All.Select((c, i) => (i, c)).Where(t => state.produce[t.i] > 0).Select(t => (-1, "prod_" + t.c.Key, t.c.Product, state.produce[t.i].ToString())).ToArray();
            if (prod.Length > 0) Cells(prod); else GUILayout.Label("Урожая пока нет.", small);
            GUILayout.Label("Нажмите на инструмент или семена, чтобы взять их в руки.", small);
            GUILayout.EndVertical();
            GUILayout.EndHorizontal();
        }

        void Cells((int tool, string icon, string name, string count)[] items)
        {
            int perRow = Mathf.Max(1, (int)((panelRect.width - 220 * ui) / (90 * ui)));
            for (int i = 0; i < items.Length; i += perRow)
            {
                GUILayout.BeginHorizontal();
                foreach (var it in items.Skip(i).Take(perRow))
                {
                    var rr = GUILayoutUtility.GetRect(84 * ui, 70 * ui, GUILayout.Width(84 * ui), GUILayout.Height(70 * ui));
                    GUI.Box(rr, GUIContent.none, it.tool >= 0 && it.tool == state.tool ? buttonOn : button);
                    Icon(new Rect(rr.x + (rr.width - 32 * ui) / 2, rr.y + 6 * ui, 32 * ui, 32 * ui), it.icon);
                    GUI.Label(new Rect(rr.x, rr.y + 40 * ui, rr.width, 20 * ui), it.name, new GUIStyle(small) { alignment = TextAnchor.MiddleCenter });
                    if (it.count != "") GUI.Label(new Rect(rr.xMax - 40 * ui, rr.y + 2 * ui, 38 * ui, 18 * ui), it.count, new GUIStyle(gold) { alignment = TextAnchor.UpperRight, fontSize = Mathf.RoundToInt(12 * ui) });
                    if (it.tool >= 0 && GUI.Button(rr, GUIContent.none, GUIStyle.none)) { state.tool = it.tool; ClosePanel(); }
                }
                GUILayout.EndHorizontal();
            }
        }

        void Ship()
        {
            H("Ящик для отгрузки");
            P("Положите урожай в ящик. Утром его заберут, а деньги появятся у вас. Ящик принимает на 10% дешевле, чем рынок.");
            int inBin = 0, total = 0;
            for (int i = 0; i < Crops.All.Length; i++) { inBin += state.shipped[i] * Rules.BinPrice(state.day, Crops.All[i].Key); total += state.produce[i] * Rules.BinPrice(state.day, Crops.All[i].Key); }
            if (inBin > 0) P($"Уже в ящике на {inBin} мон., деньги утром.");
            bool any = false;
            for (int i = 0; i < Crops.All.Length; i++)
            {
                int n = state.produce[i]; if (n == 0) continue; any = true;
                var c = Crops.All[i]; int p = Rules.BinPrice(state.day, c.Key);
                GUILayout.BeginHorizontal();
                var rr = GUILayoutUtility.GetRect(32 * ui, 32 * ui, GUILayout.Width(32 * ui)); Icon(rr, "prod_" + c.Key);
                GUILayout.Label($"{c.Product} ×{n} · {p} мон. за шт.", label);
                if (GUILayout.Button("Положить 1", button, GUILayout.Width(110 * ui))) { state.produce[i]--; state.shipped[i]++; }
                if (GUILayout.Button($"Все за {n * p}", buttonOn, GUILayout.Width(110 * ui))) { state.shipped[i] += n; state.produce[i] = 0; }
                GUILayout.EndHorizontal();
            }
            if (!any) P("В инвентаре нет урожая. Соберите его на огороде.");
            else if (GUILayout.Button($"Положить всё за {total}", buttonOn, GUILayout.Width(220 * ui))) for (int i = 0; i < Crops.All.Length; i++) { state.shipped[i] += state.produce[i]; state.produce[i] = 0; }
        }

        void Admin()
        {
            H("Админ-панель");
            GUILayout.Label("Для тестирования. При переключении сезона и дня растения не растут и не увядают.", small);
            GUILayout.Label("Сезон", gold);
            GUILayout.BeginHorizontal();
            string[] names = { "Весна", "Лето", "Осень", "Зима" };
            for (int i = 0; i < 4; i++)
                if (GUILayout.Button(names[i], state.Season.Index == i ? buttonOn : button))
                    SetDay((state.day - 1) / (Seasons.Days * 4) * Seasons.Days * 4 + i * Seasons.Days + state.Season.Day);
            GUILayout.EndHorizontal();
            GUILayout.Label($"День сезона: {adminDay}", gold);
            GUILayout.BeginHorizontal();
            adminDay = Mathf.RoundToInt(GUILayout.HorizontalSlider(adminDay, 1, Seasons.Days, GUILayout.Width(240 * ui)));
            if (GUILayout.Button("Установить", button)) SetDay(state.day - state.Season.Day + adminDay);
            GUILayout.EndHorizontal();
            GUILayout.Label($"Время: {adminHour}:{adminMinute:00}", gold);
            GUILayout.BeginHorizontal();
            adminHour = Mathf.RoundToInt(GUILayout.HorizontalSlider(adminHour, 6, 23, GUILayout.Width(160 * ui)));
            adminMinute = Mathf.RoundToInt(GUILayout.HorizontalSlider(adminMinute, 0, 50, GUILayout.Width(100 * ui)) / 10) * 10;
            if (GUILayout.Button("Установить", button)) { state.min = adminHour * 60 + adminMinute; state.lateWarned = state.min >= 1380; }
            if (GUILayout.Button(timeFrozen ? "Запустить время" : "Остановить время", timeFrozen ? buttonOn : button)) timeFrozen = !timeFrozen;
            GUILayout.EndHorizontal();
            GUILayout.Label("Добавить в инвентарь", gold);
            var items = Crops.All.Select(c => "Семена: " + c.Name).Concat(Crops.All.Select(c => "Урожай: " + c.Product)).ToArray();
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("◀", button, GUILayout.Width(36 * ui))) adminItem = (adminItem + items.Length - 1) % items.Length;
            GUILayout.Label(items[adminItem], label, GUILayout.Width(220 * ui));
            if (GUILayout.Button("▶", button, GUILayout.Width(36 * ui))) adminItem = (adminItem + 1) % items.Length;
            adminCount = Mathf.Max(1, Mathf.RoundToInt(GUILayout.HorizontalSlider(adminCount, 1, 99, GUILayout.Width(120 * ui))));
            GUILayout.Label(adminCount.ToString(), label, GUILayout.Width(30 * ui));
            if (GUILayout.Button("Добавить", buttonOn))
            {
                int n = Crops.All.Length;
                if (adminItem < n) state.seeds[adminItem] += adminCount; else state.produce[adminItem - n] += adminCount;
                Toast("Добавлено: " + adminCount);
            }
            GUILayout.EndHorizontal();
        }

        void SetDay(int day)
        {
            state.day = Mathf.Max(1, day);
            if (state.Season.Id != "winter") { state.snowCover = false; state.snowTrod.Clear(); }
            adminDay = state.Season.Day;
            BuildWorld();
        }
    }
}
