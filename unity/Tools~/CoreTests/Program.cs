using System;
using System.IO;
using System.Linq;
using Ogorod.Core;

// Compares the C# rules with the browser version: the farm map (char by char) and a few known values.
static class Program
{
    static int failed;
    static void Check(bool ok, string what) { Console.WriteLine((ok ? "ok   " : "FAIL ") + what); if (!ok) failed++; }

    static int Main(string[] args)
    {
        var map = new FarmMap(GameState.New());
        var rows = Enumerable.Range(0, FarmMap.H).Select(y => new string(Enumerable.Range(0, FarmMap.W).Select(x => map.Tiles[x, y]).ToArray())).ToArray();
        if (args.Length > 0)
        {
            var js = File.ReadAllLines(args[0]);
            int diff = 0;
            for (int y = 0; y < FarmMap.H; y++) for (int x = 0; x < FarmMap.W; x++) if (js[y][x] != rows[y][x]) { if (diff++ < 5) Console.WriteLine($"  differs at {x},{y}: js '{js[y][x]}' cs '{rows[y][x]}'"); }
            Check(diff == 0, $"farm map matches the browser version ({diff} different tiles)");
        }
        Check(Math.Abs(Hash.H(3, 4, 5) - double.Parse(args.Length > 1 ? args[1] : "0", System.Globalization.CultureInfo.InvariantCulture)) < 1e-12, "hash(3,4,5) matches");
        Check(Seasons.Of(1).Id == "spring" && Seasons.Of(13).Id == "summer" && Seasons.Of(48).Id == "winter" && Seasons.Of(49).Id == "spring", "seasons follow each other");
        Check(Seasons.LookName(5, false) == "spring05" && Seasons.LookName(40, true) == "wintersnow", "look names");

        // growth: watered radish ripens in 3 nights, a tomato withers when summer ends
        var s = GameState.New();
        s.plots.Add(new Plot { x = 30, y = 15, tilled = true, crop = "radish" });
        for (int i = 0; i < 3; i++) { s.plots[0].watered = true; Rules.NewDay(s); }
        Check(s.plots[0].ripe, "watered radish ripe after 3 nights");
        Check(Rules.Harvest(s.plots[0]) == 1 && !s.plots[0].HasCrop, "radish harvested, bed empty");
        s.day = 24; s.plots.Add(new Plot { x = 31, y = 15, tilled = true, crop = "tomato", age = 2 });
        var m = Rules.NewDay(s);
        Check(m.SeasonChanged && s.plots[1].dead, "tomato withers when summer ends");
        // shipping bin pays 10% less, next morning
        s = GameState.New(); s.shipped[Crops.Index("pumpkin")] = 2; int before = s.money;
        int expected = 2 * Rules.BinPrice(1, "pumpkin");
        Rules.NewDay(s);
        Check(s.money - before == expected && expected < 2 * Rules.Price(1, "pumpkin"), "bin pays next morning, 10% less");
        // the apple tree fruits only in autumn
        s = GameState.New(); s.day = 25; s.plots.Add(new Plot { x = 32, y = 15, tilled = true, crop = "apple", age = 9, grown = true });
        for (int i = 0; i < 3; i++) { s.plots[0].watered = true; Rules.NewDay(s); }
        Check(s.plots[0].ripe, "apple tree bears fruit in autumn");
        Console.WriteLine(failed == 0 ? "all checks passed" : failed + " checks failed");
        return failed == 0 ? 0 : 1;
    }
}
