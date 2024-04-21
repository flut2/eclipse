using System.Drawing;

namespace terrain
{
    public enum Biome
    {
        None,
        Volcanic,
        Forest,
        Desert
    }

    public sealed class MapTile
    {
        public ushort Tile = ushort.MaxValue;
        public ushort Object = ushort.MaxValue;
        public TileRegion Region = TileRegion.FM_Empty;
        public Color RenderColor = Color.Magenta;
        public Biome Biome = Biome.None;
        public bool IsRoad = false;

        public override string ToString() => $"{Tile} {Object} {(byte)Region}";

        public MapTile Clone()
        {
            return new MapTile()
            {
                Tile = Tile,
                Object = Object,
                Region = Region,
                RenderColor = RenderColor,
                Biome = Biome
            };
        }
    }
}
