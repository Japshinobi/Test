// Дедушкин огород — game rules, ported from game/index.html.
// Plain C# with no UnityEngine dependency, so it can be compiled and tested outside Unity.
// Coordinates: tiles, x to the right, y down (as in the browser version).
using System;
using System.Collections.Generic;

namespace Ogorod.Core
{
    /// <summary>The same deterministic hash as hash() in sprites.js: it picks where trees, stones and flowers grow.</summary>
    public static class Hash
    {
        public static double H(int a, int b, int c = 0)
        {
            unchecked
            {
                int h = (a * 374761393) ^ (b * 668265263) ^ (c * 1274126177);
                h = (h ^ (int)((uint)h >> 13)) * 1274126177;
                h ^= (int)((uint)h >> 16);
                return (uint)h / 4294967296.0;
            }
        }
    }

    public sealed class CropDef
    {
        public string Key, Name, Product, SeedName;
        public int Seed, Sell, Grow, Regrow, Yield = 1;
        public bool Tree;
        public string[] Seasons, Plant, Fruit;
        public string[] PlantSeasons => Plant ?? Seasons;
    }

    /// <summary>Growth in game days; a season is 12 days. Out of its seasons a plant withers.</summary>
    public static class Crops
    {
        public static readonly CropDef[] All =
        {
            new CropDef { Key = "radish", Name = "Редис", Product = "Редис", SeedName = "Семена редиса", Seed = 8, Sell = 22, Grow = 3, Seasons = new[] { "spring", "autumn" } },
            new CropDef { Key = "peas", Name = "Горох", Product = "Горох", SeedName = "Семена гороха", Seed = 20, Sell = 14, Grow = 6, Regrow = 3, Seasons = new[] { "spring" } },
            new CropDef { Key = "potato", Name = "Картофель", Product = "Картофель", SeedName = "Семенной картофель", Seed = 15, Sell = 55, Grow = 8, Seasons = new[] { "spring" } },
            new CropDef { Key = "carrot", Name = "Морковь", Product = "Морковь", SeedName = "Семена моркови", Seed = 20, Sell = 80, Grow = 10, Seasons = new[] { "spring", "autumn" } },
            new CropDef { Key = "strawberry", Name = "Клубника", Product = "Клубника", SeedName = "Рассада клубники", Seed = 40, Sell = 30, Grow = 8, Regrow = 4, Seasons = new[] { "spring", "summer" } },
            new CropDef { Key = "cucumber", Name = "Огурец", Product = "Огурцы", SeedName = "Семена огурцов", Seed = 15, Sell = 12, Grow = 5, Regrow = 2, Seasons = new[] { "summer" } },
            new CropDef { Key = "tomato", Name = "Помидор", Product = "Помидоры", SeedName = "Рассада томатов", Seed = 25, Sell = 24, Grow = 7, Regrow = 3, Seasons = new[] { "summer" } },
            new CropDef { Key = "corn", Name = "Кукуруза", Product = "Кукуруза", SeedName = "Семена кукурузы", Seed = 20, Sell = 75, Grow = 8, Seasons = new[] { "summer" } },
            new CropDef { Key = "pumpkin", Name = "Тыква", Product = "Тыква", SeedName = "Семена тыквы", Seed = 50, Sell = 240, Grow = 11, Seasons = new[] { "summer", "autumn" } },
            new CropDef { Key = "apple", Name = "Яблоня", Product = "Яблоки", SeedName = "Саженец яблони", Seed = 200, Sell = 40, Grow = 12, Regrow = 3, Yield = 3, Tree = true,
                          Seasons = new[] { "spring", "summer", "autumn", "winter" }, Plant = new[] { "spring", "summer", "autumn" }, Fruit = new[] { "autumn" } },
        };
        public static int Index(string key) => Array.FindIndex(All, c => c.Key == key);
        public static CropDef Get(string key) => All[Index(key)];
        public static bool InSeason(string key, string season) => Array.IndexOf(Get(key).Seasons, season) >= 0;
        public static bool CanPlant(string key, string season) => Array.IndexOf(Get(key).PlantSeasons, season) >= 0;

        /// <summary>0 seed, 1 sprout, 2 bush (or grown tree), 3 ripe.</summary>
        public static int Stage(Plot p)
        {
            var d = Get(p.crop);
            if (p.ripe) return 3;
            if (d.Tree && p.grown) return 2;
            double f = p.age / d.Grow;
            return f < 0.3 ? 0 : f < 0.6 ? 1 : 2;
        }
    }

    public struct Season
    {
        public int Index, Day;          // Day: 1..12 inside the season
        public string Id, Name;
    }

    public static class Seasons
    {
        public const int Days = 12;
        static readonly string[] Ids = { "spring", "summer", "autumn", "winter" };
        static readonly string[] Names = { "Весна", "Лето", "Осень", "Зима" };
        public static Season Of(int day)
        {
            int i = ((day - 1) / Days) % 4;
            return new Season { Index = i, Id = Ids[i], Name = Names[i], Day = (day - 1) % Days + 1 };
        }
        public static string RuName(string id) => id switch { "spring" => "весна", "summer" => "лето", "autumn" => "осень", _ => "зима" };
        public static string RuList(string[] ids) => string.Join(", ", Array.ConvertAll(ids, RuName));
        /// <summary>About every other winter day it snows; the snow settles by the next morning.</summary>
        public static bool Snowing(int day) => Of(day).Id == "winter" && Hash.H(day, 5, 77) < 0.5;

        /// <summary>Name of the day's look in the sprite atlas: trees, bushes, grass and flowers change with it.</summary>
        public static string LookName(int day, bool snow)
        {
            var s = Of(day);
            return s.Id switch
            {
                "spring" => "spring" + s.Day.ToString("00"),
                "autumn" => "autumn" + s.Day.ToString("00"),
                "summer" => "summer",
                _ => snow ? "wintersnow" : "winter",
            };
        }
    }

    /// <summary>The sun and the colour of the light over a day (min: minutes since midnight).</summary>
    public static class Sky
    {
        public struct Sun { public double Shear, Len, Alpha; }

        /// <summary>The sun rises at 6:00 in the east and sets at 20:30 in the west; null at night.</summary>
        public static Sun? SunAt(double min)
        {
            double t = (min - 360) / 870;
            if (t <= 0 || t >= 1) return null;
            double a = t * Math.PI, elev = Math.Sin(a);
            return new Sun
            {
                Shear = -Math.Cos(a) * Clamp(0.35 / Math.Max(elev, 0.2), 0.35, 1.4),
                Len = Clamp(0.22 + (1 - elev) * 0.45, 0.22, 0.65),
                Alpha = 0.34 * Math.Min(1, elev * 3.5),
            };
        }

        static readonly (int m, int r, int g, int b)[] Tint =
        {
            (0, 70, 80, 140), (300, 80, 90, 150), (360, 255, 186, 150), (450, 255, 226, 198), (600, 255, 248, 238),
            (720, 255, 255, 255), (900, 255, 252, 244), (1080, 255, 224, 184), (1200, 242, 168, 128), (1260, 150, 128, 188),
            (1320, 96, 100, 166), (1440, 70, 80, 140),
        };
        /// <summary>Colour multiplied over the whole picture, 0..255 per channel.</summary>
        public static (double r, double g, double b) TintAt(double min)
        {
            for (int i = 1; i < Tint.Length; i++)
            {
                var c1 = Tint[i]; var c0 = Tint[i - 1];
                if (min <= c1.m)
                {
                    double f = (min - c0.m) / (c1.m - c0.m);
                    return (c0.r + (c1.r - c0.r) * f, c0.g + (c1.g - c0.g) * f, c0.b + (c1.b - c0.b) * f);
                }
            }
            var l = Tint[Tint.Length - 1]; return (l.r, l.g, l.b);
        }
        /// <summary>Warm glow at sunrise and sunset, 0..0.1.</summary>
        public static double GlowAt(double min) => Math.Max(0, Math.Max(0.1 * (1 - Math.Abs(min - 390) / 90), 0.1 * (1 - Math.Abs(min - 1190) / 90)));
        static double Clamp(double v, double a, double b) => Math.Max(a, Math.Min(b, v));
    }

    [Serializable]
    public class Plot
    {
        public int x, y;
        public bool tilled, watered;
        public string crop = "";   // empty: nothing planted
        public double age;
        public bool ripe, grown, dead;
        public bool HasCrop => !string.IsNullOrEmpty(crop);
    }

    /// <summary>Everything that is saved. Plain fields so that UnityEngine.JsonUtility can store it.</summary>
    [Serializable]
    public class GameState
    {
        public int version = 1;
        public int day = 1;
        public double min = 360;
        public int money = 100, water = 10, cap = 10;
        public bool house;
        public string loc = "farm";
        public int px = 14, py = 9;
        public string face = "down";
        public int tool;
        public bool intro, lateWarned, snowCover;
        public int[] seeds = new int[Crops.All.Length];
        public int[] produce = new int[Crops.All.Length];
        public int[] shipped = new int[Crops.All.Length];
        public List<Plot> plots = new List<Plot>();
        public List<string> snowTrod = new List<string>();

        public static GameState New()
        {
            var s = new GameState();
            s.seeds[Crops.Index("radish")] = 6;
            s.seeds[Crops.Index("potato")] = 3;
            return s;
        }
        public Season Season => Seasons.Of(day);
        public Plot PlotAt(int x, int y) => plots.Find(p => p.x == x && p.y == y);
    }

    /// <summary>What happened overnight, for the morning message.</summary>
    public class Morning
    {
        public Dictionary<string, int> Ripened = new Dictionary<string, int>(), Withered = new Dictionary<string, int>();
        public int Dry, ShippedIncome;
        public bool SeasonChanged, Snowed;
    }

    public static class Rules
    {
        public static double Factor(int day, string key) => 0.8 + 0.45 * Hash.H(day, Crops.Index(key) + 1, 99);
        public static int Price(int day, string key) => Math.Max(1, (int)Math.Round(Crops.Get(key).Sell * Factor(day, key), MidpointRounding.AwayFromZero));
        /// <summary>The shipping bin pays 10% less than the market.</summary>
        public static int BinPrice(int day, string key) => Math.Max(1, (int)Math.Round(Price(day, key) * 0.9, MidpointRounding.AwayFromZero));

        /// <summary>Sleep: plants grow (half as fast unwatered), out-of-season plants wither, the bin pays, snow settles.</summary>
        public static Morning NewDay(GameState s)
        {
            var m = new Morning();
            bool snowed = Seasons.Snowing(s.day);
            string before = s.Season.Id, next = Seasons.Of(s.day + 1).Id;
            m.SeasonChanged = next != before;
            foreach (var p in s.plots)
            {
                if (p.HasCrop && !p.dead)
                {
                    var d = Crops.Get(p.crop);
                    if (d.Tree)
                    {
                        // the apple tree lives through every season; it grows up outside winter and bears fruit only in autumn
                        if (m.SeasonChanged && p.ripe && Array.IndexOf(d.Fruit, next) < 0) { p.ripe = false; p.age = d.Grow - d.Regrow; }
                        if (before != "winter" && !p.ripe)
                        {
                            if (!p.grown || Array.IndexOf(d.Fruit, before) >= 0) { if (!p.watered) m.Dry++; p.age += p.watered ? 1 : 0.5; }
                            if (p.age >= d.Grow)
                            {
                                p.age = d.Grow; p.grown = true;
                                if (Array.IndexOf(d.Fruit, next) >= 0) { p.ripe = true; Add(m.Ripened, p.crop); }
                                else p.age = d.Grow - d.Regrow;
                            }
                        }
                    }
                    else if (!p.ripe)
                    {
                        if (!p.watered) m.Dry++;
                        p.age += p.watered ? 1 : 0.5;
                        if (p.age >= d.Grow) { p.age = d.Grow; p.ripe = true; Add(m.Ripened, p.crop); }
                    }
                    if (m.SeasonChanged && !d.Tree && !Crops.InSeason(p.crop, next))
                    {
                        p.dead = true; p.ripe = false; Add(m.Withered, p.crop); m.Ripened.Remove(p.crop);
                    }
                }
                p.watered = false;
            }
            for (int i = 0; i < Crops.All.Length; i++) { m.ShippedIncome += s.shipped[i] * BinPrice(s.day, Crops.All[i].Key); s.shipped[i] = 0; }
            s.money += m.ShippedIncome;
            s.day++; s.min = 360; s.lateWarned = false;
            if (s.Season.Id == "winter") { if (snowed) { s.snowCover = true; s.snowTrod.Clear(); } }
            else { s.snowCover = false; s.snowTrod.Clear(); }
            m.Snowed = snowed;
            s.loc = "farm"; s.px = 14; s.py = 8; s.face = "down";
            return m;
        }

        /// <summary>Harvest a ripe plant: how many items fall out. A regrowing plant stays and starts over.</summary>
        public static int Harvest(Plot p)
        {
            var d = Crops.Get(p.crop);
            int n = d.Yield;
            if (d.Regrow > 0) { p.ripe = false; p.age = d.Grow - d.Regrow; if (d.Tree) p.grown = true; }
            else { p.crop = ""; p.age = 0; p.ripe = false; }
            return n;
        }

        static void Add(Dictionary<string, int> d, string k) { d.TryGetValue(k, out int v); d[k] = v + 1; }
    }

    /// <summary>The farm map, built exactly like buildMap()/buildFarm() in the browser version.
    /// Tiles: '.' grass, ',' flowers, '=' path, 'P' building site, '~' water, 'T' tree, 'B' bush, 'R' stone, 'K' branches,
    /// 'H' house, 'D' door, 'W' well, 'S' shipping bin, 'X' mailbox, 'I' sign, 'Y' the big oak.</summary>
    public sealed class FarmMap
    {
        public const int W = 72, H = 44;
        public readonly char[,] Tiles = new char[W, H];
        public static readonly (int x0, int y0, int x1, int y1, string kind)[] Sites =
        {
            (3, 12, 9, 17, "greenhouse"), (40, 28, 45, 32, "animals"), (48, 28, 53, 32, "animals"), (56, 28, 61, 32, "animals"),
        };
        public static readonly (int x0, int y0, int x1, int y1) Yard = (10, 3, 17, 9);
        public static readonly (int x0, int x1, int y0, int y1, string to)[] Exits =
        {
            (24, 25, 0, 0, "cross"), (30, 31, 43, 43, "river"),
        };
        public static readonly Dictionary<(int, int), string> Signs = new Dictionary<(int, int), string>
        {
            [(7, 18)] = "Место под теплицу. Здесь можно будет построить теплицу и выращивать культуры круглый год.",
            [(44, 26)] = "Место под постройку: курятник или хлев, на выбор.",
            [(52, 26)] = "Место под постройку: курятник или хлев, на выбор.",
            [(60, 26)] = "Место под постройку: курятник или хлев, на выбор.",
        };

        public char this[int x, int y] => In(x, y) ? Tiles[x, y] : 'T';
        public static bool In(int x, int y) => x >= 0 && y >= 0 && x < W && y < H;

        public FarmMap(GameState state)
        {
            for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) Tiles[x, y] = '.';
            for (int x = 0; x < W; x++) { Set(x, 0, 'T'); Set(x, H - 1, 'T'); }
            for (int y = 0; y < H; y++) { Set(0, y, 'T'); Set(W - 1, y, 'T'); }
            BuildFarm(state);
            foreach (var e in Exits) Rect(e.x0, e.y0, e.x1, e.y1, '=');
            foreach (var k in Signs.Keys) Set(k.Item1, k.Item2, 'I');
            for (int y = 1; y < H - 1; y++) for (int x = 1; x < W - 1; x++)
                if (Tiles[x, y] == '.' && Hash.H(x, y, 7 + W) < 0.09) Tiles[x, y] = ',';
        }

        void Set(int x, int y, char c) { if (In(x, y)) Tiles[x, y] = c; }
        void Rect(int x0, int y0, int x1, int y1, char c) { for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) Set(x, y, c); }

        void BuildFarm(GameState state)
        {
            Rect(12, 5, 15, 7, 'H'); Set(14, 7, 'D');
            Set(19, 6, 'W'); Set(16, 7, 'S'); Set(12, 8, 'X');
            Rect(14, 8, 14, 24, '='); Rect(14, 24, 67, 24, '='); Rect(66, 25, 67, 25, '=');
            Rect(68, 23, 70, 25, 'Y');
            Rect(14, 8, 24, 8, '='); Rect(24, 0, 24, 8, '='); Rect(25, 0, 25, 1, '=');
            Rect(30, 24, 30, 43, '='); Rect(31, 42, 31, 43, '=');
            Rect(6, 18, 6, 23, '='); Rect(6, 24, 13, 24, '=');
            foreach (int x in new[] { 43, 51, 59 }) Rect(x, 25, x, 27, '=');
            foreach (var t in Sites) Rect(t.x0, t.y0, t.x1, t.y1, 'P');
            Rect(3, 31, 10, 37, '~'); Rect(5, 30, 9, 30, '~'); Rect(11, 33, 11, 36, '~'); Rect(4, 38, 8, 38, '~');
            for (int y = 1; y < 43; y++) for (int x = 1; x < 71; x++)
            {
                if (Keep(x, y)) continue;
                bool corner = (x > 58 && y < 14) || (x < 20 && y > 38) || (x > 60 && y > 34) || (x < 8 && y < 10);
                double r = Hash.H(x, y, 501);
                if (r < (corner ? 0.3 : 0.035)) Set(x, y, 'T'); else if (r < (corner ? 0.36 : 0.05)) Set(x, y, 'B');
                else if (r < (corner ? 0.4 : 0.075)) Set(x, y, 'R'); else if (r < (corner ? 0.44 : 0.095)) Set(x, y, 'K');
            }
            for (int y = 10; y <= 22; y++) for (int x = 18; x <= 56; x++)
            {
                if (Tiles[x, y] != '.' || state.PlotAt(x, y) != null) continue;
                double r = Hash.H(x, y, 503);
                if (r < 0.02) Set(x, y, 'R'); else if (r < 0.035) Set(x, y, 'K');
            }
        }

        bool Keep(int x, int y)
        {
            if (Tiles[x, y] != '.') return true;
            if (x >= Yard.x0 - 1 && x <= Yard.x1 + 1 && y >= Yard.y0 - 1 && y <= Yard.y1 + 1) return true;
            foreach (var t in Sites) if (x >= t.x0 - 1 && x <= t.x1 + 1 && y >= t.y0 - 1 && y <= t.y1 + 1) return true;
            if (x >= 18 && x <= 56 && y >= 10 && y <= 22) return true;
            if (y == 8 || y == 24 || x == 14 || x == 24 || x == 30) return true;
            return Path(x - 1, y) || Path(x + 1, y) || Path(x, y - 1) || Path(x, y + 1);
        }
        bool Path(int x, int y) => In(x, y) && Tiles[x, y] == '=';

        public bool Walkable(int x, int y) => In(x, y) && ".,=P".IndexOf(Tiles[x, y]) >= 0;
        /// <summary>Where the hoe works: any grass on the farm, except the yard (the house and two tiles around it).</summary>
        public bool Farmable(int x, int y)
        {
            if (!In(x, y)) return false;
            char c = Tiles[x, y];
            return (c == '.' || c == ',') && !(x >= Yard.x0 && x <= Yard.x1 && y >= Yard.y0 && y <= Yard.y1);
        }
        public string ExitAt(int x, int y)
        {
            foreach (var e in Exits) if (x >= e.x0 && x <= e.x1 && y >= e.y0 && y <= e.y1) return e.to;
            return null;
        }
    }
}
