// The sprite atlas exported from the browser version (unity/Tools~/export-atlas.mjs).
// The PNG is stored as a .bytes TextAsset and decoded at runtime, so Unity's texture import
// (compression, filtering) can never blur the pixel art.
using System;
using System.Collections.Generic;
using UnityEngine;

namespace Ogorod.Game
{
    [Serializable] public class AtlasSprite { public string n; public int x, y, w, h, ax, ay, fy; }
    [Serializable] public class ShadowBox { public int x0, x1, y0, y1, h0, h1; public string top; }
    [Serializable] public class ShadowBoxSet { public string kind, variant; public ShadowBox[] boxes; }
    [Serializable] public class AtlasIndex { public int width, height; public AtlasSprite[] sprites; public ShadowBoxSet[] shadowBoxes; }

    public class Atlas
    {
        /// <summary>Draft pixels per tile; one tile is one Unity unit.</summary>
        public const int PPU = 16;
        public readonly Texture2D Texture;
        public readonly AtlasIndex Index;
        readonly Dictionary<string, AtlasSprite> byName = new Dictionary<string, AtlasSprite>();
        readonly Dictionary<string, Sprite> sprites = new Dictionary<string, Sprite>();
        readonly Dictionary<string, Color32[]> pixels = new Dictionary<string, Color32[]>();
        Color32[] all;

        public Atlas()
        {
            var png = Resources.Load<TextAsset>("Ogorod/atlas");
            Texture = new Texture2D(2, 2, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            Texture.LoadImage(png.bytes, false);
            Texture.filterMode = FilterMode.Point;
            Index = JsonUtility.FromJson<AtlasIndex>(Resources.Load<TextAsset>("Ogorod/atlasindex").text);
            foreach (var s in Index.sprites) byName[s.n] = s;
        }

        public bool Has(string name) => byName.ContainsKey(name);
        public AtlasSprite Info(string name) => byName.TryGetValue(name, out var s) ? s : null;

        /// <summary>A Unity sprite whose pivot is the point that touches the ground.</summary>
        public Sprite Get(string name)
        {
            if (sprites.TryGetValue(name, out var sp)) return sp;
            var s = Info(name);
            if (s == null) { Debug.LogWarning("Ogorod: no sprite " + name); return null; }
            var rect = new Rect(s.x, Index.height - s.y - s.h, s.w, s.h);
            var pivot = new Vector2((float)s.ax / s.w, (float)(s.h - s.ay) / s.h);
            sp = Sprite.Create(Texture, rect, pivot, PPU, 0, SpriteMeshType.FullRect);
            sp.name = name;
            return sprites[name] = sp;
        }

        /// <summary>Pixels of a sprite, rows from the bottom (as Texture2D.SetPixels32 wants them).</summary>
        public Color32[] Pixels(string name)
        {
            if (pixels.TryGetValue(name, out var p)) return p;
            var s = Info(name);
            all = all ?? Texture.GetPixels32();
            p = new Color32[s.w * s.h];
            int by = Index.height - s.y - s.h;
            for (int y = 0; y < s.h; y++) Array.Copy(all, (by + y) * Index.width + s.x, p, y * s.w, s.w);
            return pixels[name] = p;
        }

        /// <summary>Texture coordinates of a pixel given in the exported canvas (origin top-left).</summary>
        public Vector2 UV(float x, float y) => new Vector2(x / Index.width, 1f - y / Index.height);

        public ShadowBox[] Boxes(string kind, string variant = "")
        {
            foreach (var b in Index.shadowBoxes) if (b.kind == kind && (b.variant ?? "") == variant) return b.boxes;
            return null;
        }
    }
}
