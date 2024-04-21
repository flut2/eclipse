using GeoAPI.Geometries;
using Ionic.Zlib;
using Microsoft.Win32;
using NetTopologySuite.Geometries;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace terrain
{
    public partial class GeneratorForm : Form
    {
        public int MAP_SIZE => (int)numericUpDown4.Value;

        public GeneratorForm()
        {
            InitializeComponent();

            pictureBox2.Parent = pictureBox1;
            pictureBox3.Parent = pictureBox2;
        }

        public bool ShowGrid => checkBox1.Checked;
        public bool ShowOcean => checkBox2.Checked;
        public bool RandomizeEdges => checkBox3.Checked;

        private void button1_Click(object sender, EventArgs e)
        {
            Generate();
        }

        public volatile bool Generating;

        public volatile PolygonMap CurrentMap;
        public volatile MapTile[,] MapData;

        public void Generate()
        {
            if (Generating)
                return;
            Generating = true;

            _ = Task.Factory.StartNew(() =>
            {
                var seed = textBox1.Text.GetHashCode();
                var biomeSeed = textBox2.Text.GetHashCode();

                var map = new PolygonMap(seed, biomeSeed);
                map.Generate((int)numericUpDown1.Value, (int)numericUpDown2.Value, (int)numericUpDown3.Value, (double)numericUpDown5.Value);
                CurrentMap = map;

                ////var dat = CreateTerrain(map);
                //new Biome(map).ComputeBiomes(dat);

                RenderMap();
            }).ContinueWith(_ =>
            {
                Generating = false;
            });
        }

        public void RenderMap()
        {
            if (CurrentMap == null)
                return;

            var (bitmap, bitmap2, mapData) = RenderPolygons(CurrentMap);
            pictureBox1.Image = bitmap;
            pictureBox2.Image = bitmap2;
            MapData = mapData;
        }

        (Bitmap, Bitmap, MapTile[,]) RenderPolygons(PolygonMap map)
        {
            var rasterizer = new Rasterizer<MapTile>(MAP_SIZE, MAP_SIZE);
            var overlayRasterizer = new Rasterizer<int>(MAP_SIZE, MAP_SIZE);

            rasterizer.Clear(new MapTile());
            overlayRasterizer.Clear(Color.Transparent.ToArgb());

            var pointThickness = MAP_SIZE < 512 ? 1 : MAP_SIZE < 1024 ? 2 : 3;

            var beaches = new HashSet<MapPolygon>(map.MapPolygons.Where(_ => !_.IsWater && _.Neighbours.Any(__ => __.IsCoast)));

            //Render lands poly
            foreach (var poly in map.MapPolygons)
            {
                if (poly.IsWater || beaches.Contains(poly))
                {
                    if (poly.IsWater)
                        poly.Biome = Biome.None;
                    continue;
                }

                var points = new List<double>();
                foreach (var polyNode in poly.Nodes)
                {
                    points.Add((polyNode.X + 1) / 2 * MAP_SIZE);
                    points.Add((polyNode.Y + 1) / 2 * MAP_SIZE);
                }
                points.Add((poly.Nodes[0].X + 1) / 2 * MAP_SIZE);
                points.Add((poly.Nodes[0].Y + 1) / 2 * MAP_SIZE);

                var color = Color.Magenta;
                var type = GetTileType("Water Dark");
                var region = TileRegion.FM_Empty;
                var r = map.Random.NextDouble();
                var biome = poly.Biome;
                switch (biome)
                {
                    case Biome.Volcanic:
                        color = Color.FromArgb(69, 78, 99);
                        type = GetTileType("Cobblestone");
                        region = r > 0.5 ? TileRegion.Biome_Volcanic_Encounter_Spawn : TileRegion.Biome_Volcanic_Setpiece_Spawn;
                        break;
                    case Biome.Forest:
                        color = Color.FromArgb(65, 109, 93);
                        type = GetTileType("Grass");
                        region = r > 0.5 ? TileRegion.Biome_Forest_Encounter_Spawn : TileRegion.Biome_Forest_Setpiece_Spawn;
                        break;
                    case Biome.Desert:
                        color = Color.FromArgb(226, 178, 126);
                        type = GetTileType("Desert Sand");
                        region = r > 0.5 ? TileRegion.Biome_Desert_Encounter_Spawn : TileRegion.Biome_Desert_Setpiece_Spawn;
                        break;
                }

                // remove some regions

                // no water
                if (region != TileRegion.FM_Empty)
                    if (map.Random.NextDouble() > 0.5)
                        region = TileRegion.FM_Empty;

                var tile = new MapTile();
                tile.Tile = type;
                tile.RenderColor = color;
                tile.Biome = biome;

                rasterizer.FillPolygon(points.ToArray(), tile);

                var cx = (int)((poly.CentroidX + 1) / 2 * MAP_SIZE);
                var cy = (int)((poly.CentroidY + 1) / 2 * MAP_SIZE);

                if (ShowGrid)
                {
                    overlayRasterizer.DrawPolygon(points.ToArray(), Color.Black.ToArgb(), pointThickness);
                    overlayRasterizer.PlotSqr(cx, cy, Color.Black.ToArgb(), pointThickness);
                }

                if (region == TileRegion.FM_Empty)
                    continue;

                var regionColor = Color.Transparent;
                if (region >= TileRegion.Biome_Desert_Encounter_Spawn && region <= TileRegion.Biome_Forest_Encounter_Spawn)
                    regionColor = Color.FromArgb(155, 0, 255);
                else if (region >= TileRegion.Biome_Desert_Setpiece_Spawn && region <= TileRegion.Biome_Forest_Setpiece_Spawn)
                    regionColor = Color.FromArgb(0, 255, 173);

                if (regionColor != Color.Transparent)
                {
                    tile = new MapTile();
                    tile.Tile = type;
                    tile.Region = region;
                    tile.Biome = biome;
                    rasterizer.Plot(cx, cy, tile);
                    overlayRasterizer.PlotSqr(cx, cy, regionColor.ToArgb(), pointThickness);
                }
            }

            foreach (var poly in map.MapPolygons)
            {
                if (!poly.IsWater || !ShowOcean)
                    continue;

                var points = new List<double>();
                foreach (var polyNode in poly.Nodes)
                {
                    points.Add((polyNode.X + 1) / 2 * MAP_SIZE);
                    points.Add((polyNode.Y + 1) / 2 * MAP_SIZE);
                }
                points.Add((poly.Nodes[0].X + 1) / 2 * MAP_SIZE);
                points.Add((poly.Nodes[0].Y + 1) / 2 * MAP_SIZE);

                var tile = new MapTile();

                var color = Color.FromArgb(20, 160, 184);
                var type = GetTileType("Water");
                if (poly.IsOcean && !poly.IsCoast || poly.Neighbours.All(_ => _.IsWater))
                {
                    color = Color.FromArgb(14, 122, 140);
                    type = GetTileType("Water Dark");
                }
                tile.RenderColor = color;
                tile.Tile = type;

                rasterizer.FillPolygon(points.ToArray(), tile);

                var cx = (int)((poly.CentroidX + 1) / 2 * MAP_SIZE);
                var cy = (int)((poly.CentroidY + 1) / 2 * MAP_SIZE);

                if (ShowGrid)
                {
                    overlayRasterizer.DrawPolygon(points.ToArray(), Color.White.ToArgb(), pointThickness);
                    overlayRasterizer.PlotSqr(cx, cy, Color.Black.ToArgb(), pointThickness);
                }
            }

            foreach (var poly in beaches)
            {
                var points = new List<double>();
                foreach (var polyNode in poly.Nodes)
                {
                    points.Add((polyNode.X + 1) / 2 * MAP_SIZE);
                    points.Add((polyNode.Y + 1) / 2 * MAP_SIZE);
                }
                points.Add((poly.Nodes[0].X + 1) / 2 * MAP_SIZE);
                points.Add((poly.Nodes[0].Y + 1) / 2 * MAP_SIZE);

                if (!map.MapPolygons.Any(_ => poly.Neighbours.Contains(_)))
                    continue;

                var color = Color.Magenta;
                var type = GetTileType("Water Dark");
                var biome = poly.Biome;
                switch (biome)
                {
                    case Biome.Volcanic:
                        color = Color.FromArgb(54, 57, 69);
                        type = GetTileType("Cobblestone Dark");
                        break;
                    case Biome.Forest:
                        color = Color.FromArgb(86, 72, 70);
                        type = GetTileType("Dirt");
                        break;
                    case Biome.Desert:
                        color = Color.FromArgb(160, 128, 90);
                        type = GetTileType("Dark Desert Sand");
                        break;
                }

                var tile = new MapTile();
                tile.Tile = type;
                tile.RenderColor = color;
                tile.Biome = biome;
                rasterizer.FillPolygon(points.ToArray(), tile);

                if (ShowGrid)
                {
                    overlayRasterizer.DrawPolygon(points.ToArray(), Color.White.ToArgb(), pointThickness);

                    var cx = (int)((poly.CentroidX + 1) / 2 * MAP_SIZE);
                    var cy = (int)((poly.CentroidY + 1) / 2 * MAP_SIZE);
                    overlayRasterizer.PlotSqr(cx, cy, Color.Black.ToArgb(), pointThickness);
                }
            }

            if (RandomizeEdges)
                Randomize(map, rasterizer.Buffer);

            var roadPolygons = map.MapPolygons.Where(p => p.IsRoad).ToList();
            var connectedRoadEdges = map.ConnectRoadPolygons(roadPolygons);

            var tension = (double)numericUpDown6.Value;

            var i = 0;
            foreach (var (from, to) in connectedRoadEdges)
            {
                var x1 = (from.CentroidX + 1) / 2 * MAP_SIZE;
                var y1 = (from.CentroidY + 1) / 2 * MAP_SIZE;

                var x2 = (to.CentroidX + 1) / 2 * MAP_SIZE;
                var y2 = (to.CentroidY + 1) / 2 * MAP_SIZE;

                // Calculate the midpoint
                double midX = (x1 + x2) / 2;
                double midY = (y1 + y2) / 2;

                // Calculate the vector from start to end point
                double dx = x2 - x1;
                double dy = y2 - y1;

                // Calculate a perpendicular vector
                double perpX = -dy;
                double perpY = dx;

                // Normalize the perpendicular vector
                double perpLength = Math.Sqrt(perpX * perpX + perpY * perpY);
                perpX /= perpLength;
                perpY /= perpLength;

                // Offset the midpoint using the perpendicular vector
                double offsetX = midX + perpX * tension;
                double offsetY = midY + perpY * tension;

                double[] points = { x1, y1, offsetX, offsetY, x2, y2 };

                //overlayRasterizer.DrawLineBresenham(x1, y1, x2, y2, Color.Magenta.ToArgb(), pointThickness);
                rasterizer.DrawCurveFunc(points, 1, (x, y, _) =>
                {
                    i++;

                    var tile = _.Clone();
                    tile.Region = TileRegion.FM_Empty;
                    tile.IsRoad = true;
                    switch (tile.Biome)
                    {
                        case Biome.None:
                            tile.RenderColor = Color.FromArgb(106, 76, 65);
                            tile.Tile = GetTileType("Wood Light");
                            return tile;
                        case Biome.Volcanic:
                            tile.RenderColor = Color.FromArgb(124, 110, 124);
                            tile.Tile = GetTileType("Cobblestone Light");
                            return tile;
                        case Biome.Forest:
                            tile.RenderColor = Color.FromArgb(86, 72, 70);
                            tile.Tile = GetTileType("Dirt");
                            if (/*map.Random.NextDouble() >= 0.99 && */i % 128 == 0)
                            {
                                tile.Region = TileRegion.Spawn;
                                overlayRasterizer.PlotSqr(x, y, Color.Pink.ToArgb(), pointThickness);
                            }
                            return tile;
                        case Biome.Desert:
                            tile.RenderColor = Color.FromArgb(255, 183, 128);
                            tile.Tile = GetTileType("Sandstone Brick");
                            return tile;
                    }
                    return _;
                }, 3);

                rasterizer.DrawCurveFunc(points, 1, (x, y, _) =>
                {
                    i++;
                    switch (_.Biome)
                    {
                        case Biome.None:
                            var tile = _.Clone();
                            tile.Region = TileRegion.FM_Empty;
                            tile.RenderColor = Color.Red;
                            tile.Tile = GetTileType("Wood Light");
                            tile.IsRoad = true;
                            return tile;
                    }
                    return _;
                }, 5);
            }

            // populate the objects

            var staticObjects = new Dictionary<Biome, List<(string, string, double)>>()
            {
                {
                    Biome.Volcanic, new List<(string, string, double)>()
                    {
                        (null, "Bones", 0.98)
                    }
                },

                {
                    Biome.Forest, new List<(string, string, double)>()
                    {
                        ("Grass", "Bush", 0.92),
                        ("Grass", "Grass", 0.92),
                        ("Grass", "Flowers", 0.90),
                        (null, "Tree", 0.98),
                        ("Dirt", "Vase", 0.92),
                        ("Dirt", "Rock", 0.95)
                    }
                },

                {
                    Biome.Desert, new List<(string, string, double)>()
                    {
                        (null, "Cactus", 0.92),
                        (null, "Tumbleweed", 0.96)
                    }
                }
            };

            for (var y = 0; y < MAP_SIZE; y++)
                for (var x = 0; x < MAP_SIZE; x++)
                {
                    var tile = rasterizer.Buffer[x, y];
                    var biome = tile.Biome;

                    if (biome == Biome.None)
                        continue;

                    var objs = staticObjects[biome];
                    var obj = objs[map.Random.Next(objs.Count)];

                    // iterate all tiles and try to place a static
                    if (tile.IsRoad || tile.Region != TileRegion.FM_Empty || map.Random.NextDouble() <= obj.Item3)
                        continue;

                    tile = tile.Clone();
                    if(obj.Item1 != null && tile.Tile != GetTileType(obj.Item1))
                        continue;

                    tile.Object = GetObjectType(obj.Item2);

                    tile.RenderColor = Color.White;

                    rasterizer.Buffer[x, y] = tile;
                }


            var bmp = new Bitmap(MAP_SIZE, MAP_SIZE);
            var buff = new BitmapBuffer(bmp);
            buff.Lock();

            for (var y = 0; y < MAP_SIZE; y++)
                for (var x = 0; x < MAP_SIZE; x++)
                    buff[x, y] = (uint)rasterizer.Buffer[x, y].RenderColor.ToArgb();
            buff.Unlock();

            var bmp2 = new Bitmap(MAP_SIZE, MAP_SIZE);
            var buff2 = new BitmapBuffer(bmp2);
            buff2.Lock();

            for (var y = 0; y < MAP_SIZE; y++)
                for (var x = 0; x < MAP_SIZE; x++)
                    buff2[x, y] = (uint)overlayRasterizer.Buffer[x, y];
            buff2.Unlock();

            var bmp3 = new Bitmap(MAP_SIZE, MAP_SIZE);
            var buff3 = new BitmapBuffer(bmp3);
            buff3.Lock();

            for (var y = 0; y < MAP_SIZE; y++)
                for (var x = 0; x < MAP_SIZE; x++)
                {
                    if (overlayRasterizer.Buffer[x, y] != Color.Transparent.ToArgb())
                        buff3[x, y] = (uint)overlayRasterizer.Buffer[x, y];

                    if (rasterizer.Buffer[x, y].RenderColor != Color.Magenta)
                        buff3[x, y] = (uint)rasterizer.Buffer[x, y].RenderColor.ToArgb();
                }
            buff3.Unlock();

            Image = bmp3;

            return (bmp, bmp2, rasterizer.Buffer);
        }

        public static Bitmap Image;
        
        public static ushort GetObjectType(string idName)
        {
            switch (idName)
            {
                case "Bush":
                    return 0x0103;
                case "Grass":
                    return 0x0101;
                case "Flowers":
                    return 0x0104;
                case "Tree":
                    return 0x0100;
                case "Vase":
                    return 0x010b;

                case "Cactus":
                    return 0x111;
                case "Tumbleweed":
                    return 0x112;

                case "Rock":
                    return 0x0102;
                case "Bones":
                    return 0x010c;
            }
            return ushort.MaxValue;
        }
        
        public static ushort GetTileType(string tile)
        {
            ushort type = 0xFF;
            switch (tile)
            {
                case "Water":
                    type = 0x19;
                    break;
                case "Water Dark":
                    type = 0x20;
                    break;
                case "Cobblestone":
                    type = 0x25;
                    break;
                case "Desert Sand":
                    type = 0x2b;
                    break;
                case "Dark Desert Sand":
                    type = 0x2c;
                    break;
                case "Grass":
                    type = 0x21;
                    break;
                case "Dirt":
                    type = 0x22;
                    break;
                case "Sandstone Brick":
                    type = 0x79;
                    break;
                case "Cobblestone Light":
                    type = 0x78;
                    break;
                case "Cobblestone Dark":
                    type = 0x77;
                    break;
                case "Wood Light":
                    type = 0x00;
                    break;
            }
            return type;
        }

        void Randomize(PolygonMap map, MapTile[,] buff)
        {
            var ocean = GetTileType("Water");
            var water = GetTileType("Water Dark");
            for (var x = 8; x < MAP_SIZE - 8; x++)
                for (var y = 8; y < MAP_SIZE - 8; y++)
                {
                    var tile = buff[x, y].Clone();
                    var tileType = tile.Tile;

                    if (buff[x, y].Region != TileRegion.FM_Empty)
                        continue;

                    if (tileType == ocean || tileType == water)
                        continue;

                    var px = x + map.Random.Next(-2, 3);
                    var py = y + map.Random.Next(-2, 3);

                    var swapTile = buff[px, py].Clone();
                    tileType = swapTile.Tile;
                    if (tileType == ocean || tileType == water)
                        continue;

                    var t = tile.Tile;
                    tile.Tile = swapTile.Tile;
                    swapTile.Tile = t;

                    var t2 = tile.RenderColor;
                    tile.RenderColor = swapTile.RenderColor;
                    swapTile.RenderColor = t2;

                    var t3 = tile.Biome;
                    tile.Biome = swapTile.Biome;
                    swapTile.Biome = t3;

                    buff[x, y] = tile;
                    buff[px, py] = swapTile;
                }
        }

            private void checkBox1_CheckedChanged(object sender, EventArgs e)
        {
            RenderMap();
        }

        private void checkBox2_CheckedChanged(object sender, EventArgs e)
        {
            RenderMap();
        }


        private void pictureBox3_MouseMove(object sender, MouseEventArgs e)
        {
            return;

            if (CurrentMap == null || pictureBox1.Image == null)
                return;

            float panelX = ((float)e.X / pictureBox3.ClientSize.Width) * MAP_SIZE;
            float panelY = ((float)e.Y / pictureBox3.ClientSize.Height) * MAP_SIZE;

            var worldX = panelX;
            var worldY = panelY;
            var nearestVoronis = GetNearestVoroniCell(worldX, worldY);
            if (nearestVoronis == null)
                return;

            // repaint etc

            var bmp = new Bitmap(MAP_SIZE, MAP_SIZE);

            // Get a Graphics object from the Bitmap object
            using (var g = Graphics.FromImage(bmp))
                Update(nearestVoronis, g);

            pictureBox3.Image = bmp;
        }

        private void Update(MapPolygon poly, Graphics g)
        {
            var points = new List<PointF>();
            foreach (var polyNode in poly.Nodes)
            {
                var point = new PointF();
                point.X = (float)((polyNode.X + 1) / 2 * MAP_SIZE);
                point.Y = (float)((polyNode.Y + 1) / 2 * MAP_SIZE);
                points.Add(point);
            }
            var p = new PointF();
            p.X = (float)((poly.Nodes[0].X + 1) / 2 * MAP_SIZE);
            p.Y = (float)((poly.Nodes[0].Y + 1) / 2 * MAP_SIZE);
            points.Add(p);

            g.FillPolygon(new Pen(Color.Red).Brush, points.ToArray());


            foreach (var neighbour in poly.Neighbours)
            {
                if (neighbour.IsWater && !ShowOcean)
                    continue;

                points.Clear();
                foreach (var polyNode in neighbour.Nodes)
                {
                    var point = new PointF();
                    point.X = (float)((polyNode.X + 1) / 2 * MAP_SIZE);
                    point.Y = (float)((polyNode.Y + 1) / 2 * MAP_SIZE);
                    points.Add(point);
                }
                p = new PointF();
                p.X = (float)((neighbour.Nodes[0].X + 1) / 2 * MAP_SIZE);
                p.Y = (float)((neighbour.Nodes[0].Y + 1) / 2 * MAP_SIZE);
                points.Add(p);
                g.FillPolygon(new Pen(Color.Orange).Brush, points.ToArray());
            }
        }

        private MapPolygon GetNearestVoroniCell(double x, double y)
        {
            // Iterate through all the polygons in the map
            foreach (var polygon in CurrentMap.MapPolygons)
            {
                if (polygon.IsWater && !ShowOcean)
                    continue;

                var vertices = polygon.Polygon.ExteriorRing.Coordinates.Select(coord => new PointF(
                                (float)((coord.X + 1) / 2 * MAP_SIZE), 
                                (float)((coord.Y + 1) / 2 * MAP_SIZE))).ToList();

                // Check if the point (x, y) is inside the polygon
                if (PointInPolygon(x, y, vertices))
                {
                    // If the point is inside the polygon, return the polygon
                    return polygon;
                }
            }

            // If the point is not inside any polygon, return null
            return null;
        }

        // Implementation of the PointInPolygon algorithm
        private bool PointInPolygon(double x, double y, List<PointF> polygonVertices)
        { 
            int i, j;
            bool c = false;
            for (i = 0, j = polygonVertices.Count - 1; i < polygonVertices.Count; j = i++)
            {
                if ((((polygonVertices[i].Y <= y) && (y < polygonVertices[j].Y)) || ((polygonVertices[j].Y <= y) && (y < polygonVertices[i].Y))) &&
                    (x < (polygonVertices[j].X - polygonVertices[i].X) * (y - polygonVertices[i].Y) / (polygonVertices[j].Y - polygonVertices[i].Y) + polygonVertices[i].X))
                {
                    c = !c;
                }
            }
            return c;
        }

        private void pictureBox3_Paint(object sender, PaintEventArgs e)
        {
            e.Graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
        }

        public static class ParseMap
        {
            public static byte[] Serialize(MapTile[,] tiles, int version)
            {
                switch (version)
                {
                    case 1:
                        return SerializeV1(tiles);
                    case 2:
                        return SerializeV2(tiles);
                }
                return null;
            }

            private static byte[] SerializeV1(MapTile[,] tiles)
            {
                var w = (ushort)tiles.GetLength(0);
                var h = (ushort)tiles.GetLength(1);

                using (var ms = new MemoryStream())
                {
                    using (var wtr = new BinaryWriter(ms))
                    {
                        wtr.Write((byte)1);
                        wtr.Write((ushort)0); // this will have to be adjusted if client sizes change from 2048 to anything bigger
                        wtr.Write((ushort)0); // this will have to be adjusted if client sizes change from 2048 to anything bigger
                        wtr.Write(w);
                        wtr.Write(h);
                        for (var y = 0; y < h; y++)
                            for (var x = 0; x < w; x++)
                            {
                                wtr.Write(tiles[x, y].Tile);
                                wtr.Write(tiles[x, y].Object);
                                wtr.Write((byte)tiles[x, y].Region);
                            }
                    }
                    return ZlibStream.CompressBuffer(ms.ToArray());
                }
            }

            private static byte[] SerializeV2(MapTile[,] mapTiles)
            {
                var w = (ushort)mapTiles.GetLength(0);
                var h = (ushort)mapTiles.GetLength(1);

                using (var ms = new MemoryStream())
                {
                    using (var wtr = new BinaryWriter(ms))
                    {
                        wtr.Write((byte)2);
                        wtr.Write((ushort)0); // this will have to be adjusted if client sizes change from 2048 to anything bigger
                        wtr.Write((ushort)0); // this will have to be adjusted if client sizes change from 2048 to anything bigger
                        wtr.Write(w);
                        wtr.Write(h);

                        var tiles = new List<MapTile>();
                        for (var y = 0; y < h; y++)
                            for (var x = 0; x < w; x++)
                            {
                                var tile = mapTiles[x, y]; // dont need a null check here cus its a realm it has no whitespace
                                if (!TilesContains(tiles, tile))
                                    tiles.Add(tile);
                            }

                        wtr.Write((ushort)tiles.Count);
                        foreach (var t in tiles)
                        {
                            wtr.Write((ushort)t.Tile);
                            wtr.Write((ushort)t.Object);
                            wtr.Write((byte)t.Region);
                        }

                        var byteWrite = tiles.Count <= 256;
                        for (var y = 0; y < h; y++)
                            for (var x = 0; x < w; x++)
                            {
                                var tile = mapTiles[x, y]; // dont need a null check here cus its a realm it has no whitespace
                                var idx = TilesIndexOf(tiles, tile);
                                if (byteWrite)
                                    wtr.Write((byte)idx);
                                else
                                    wtr.Write((ushort)idx);
                            }

                    }
                    return ZlibStream.CompressBuffer(ms.ToArray());
                }
            }
            private static bool TilesContains(List<MapTile> tiles, MapTile tile)
            {
                foreach (var t in tiles)
                    if (t.Object == tile.Object && t.Tile == tile.Tile && t.Region == tile.Region)
                        return true;
                return false;
            }

            private static short TilesIndexOf(List<MapTile> tiles, MapTile tile)
            {
                for (short i = 0; i < tiles.Count; i++)
                {
                    var t = tiles[i];
                    if (t.Object == tile.Object && t.Tile == tile.Tile && t.Region == tile.Region)
                        return i;
                }
                return 0;
            }
        }

        private void button2_Click(object sender, EventArgs e)
        {
            var version = 1;
            var data = ParseMap.Serialize(MapData, version);
            var name = $"Map_V{version}.fm";
            File.WriteAllBytes(name, data);

            version = 2;
            data = ParseMap.Serialize(MapData, version);
            name = $"Map_V{version}.fm";
            File.WriteAllBytes(name, data);


            Image.Save("Image.png");
        }
    }
}
