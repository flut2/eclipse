//using NetTopologySuite.GeometriesGraph;
//using System;
//using System.Collections.Generic;
//using System.Drawing;
//using System.Linq;

//namespace terrain
//{
//    class Terrain
//    {
//        public const int MAP_SIZE = 2048;

//        static void Show(IEnumerable<MapPolygon> polys, IEnumerable<MapNode> plot)
//        {
//            Bitmap map = new Bitmap(MAP_SIZE, MAP_SIZE);
//            using (Graphics g = Graphics.FromImage(map))
//            {
//                foreach (var poly in polys)
//                {
//                    g.FillPolygon(new SolidBrush(Color.FromArgb(poly.DistanceToCoast == 0 ? 128 : (int)(poly.DistanceToCoast * 255), Color.Blue)),
//                        poly.Nodes.Select(_ => new PointF((float)(_.X + 1) / 2 * MAP_SIZE, (float)(_.Y + 1) / 2 * MAP_SIZE)).ToArray());
//                    for (int j = 0; j < poly.Nodes.Length; j++)
//                    {
//                        MapNode curr = poly.Nodes[j];
//                        MapNode prev = j == 0 ? poly.Nodes[poly.Nodes.Length - 1] : poly.Nodes[j - 1];
//                        g.DrawLine(Pens.White,
//                            (float)(prev.X + 1) / 2 * MAP_SIZE, (float)(prev.Y + 1) / 2 * MAP_SIZE,
//                            (float)(curr.X + 1) / 2 * MAP_SIZE, (float)(curr.Y + 1) / 2 * MAP_SIZE);
//                    }
//                }
//                if (plot != null)
//                    foreach (var i in plot)
//                        g.FillRectangle(Brushes.Black, (float)(i.X + 1) / 2 * MAP_SIZE - 2, (float)(i.Y + 1) / 2 * MAP_SIZE - 2, 4, 4);
//            }
//            Program.Show(map);
//        }

//        static int MinDistToMapEdge(PlanarGraph graph, Node n, int limit)
//        {
//            if (n.Coordinate.X == 0 || n.Coordinate.X == MAP_SIZE ||
//                n.Coordinate.Y == 0 || n.Coordinate.Y == MAP_SIZE)
//                return 0;

//            int ret = int.MaxValue;
//            Stack<Tuple<int, Node>> stack = new Stack<Tuple<int, Node>>();
//            HashSet<Node> visited = new HashSet<Node>();
//            stack.Push(new Tuple<int, Node>(0, n));
//            do
//            {
//                var state = stack.Pop();
//                if (state.Item2.Coordinate.X == 0 || state.Item2.Coordinate.X == MAP_SIZE ||
//                    state.Item2.Coordinate.Y == 0 || state.Item2.Coordinate.Y == MAP_SIZE)
//                {
//                    if (state.Item1 < ret)
//                        ret = state.Item1;
//                    if (ret == 0) return 0;

//                    continue;
//                }
//                visited.Add(state.Item2);

//                if (state.Item1 > limit) continue;
//                foreach (var i in state.Item2.Edges)
//                {
//                    Node node = graph.Find(i.DirectedCoordinate);
//                    if (!visited.Contains(node))
//                        stack.Push(new Tuple<int, Node>(state.Item1 + 1, node));
//                }

//            } while (stack.Count > 0);
//            return ret;
//        }

//        static Bitmap RenderColorBmp(TerrainTile[,] tiles)
//        {
//            int w = tiles.GetLength(0);
//            int h = tiles.GetLength(1);
//            Bitmap bmp = new Bitmap(w, h);
//            BitmapBuffer buff = new BitmapBuffer(bmp);
//            buff.Lock();
//            for (int y = 0; y < w; y++)
//                for (int x = 0; x < h; x++)
//                    buff[x, y] = TileTypes.color[tiles[x, y].TileId];
//            buff.Unlock();
//            return bmp;
//        }
//        static Bitmap RenderTerrainBmp(TerrainTile[,] tiles)
//        {
//            int w = tiles.GetLength(0);
//            int h = tiles.GetLength(1);
//            Bitmap bmp = new Bitmap(w, h);
//            BitmapBuffer buff = new BitmapBuffer(bmp);
//            buff.Lock();
//            for (int y = 0; y < w; y++)
//                for (int x = 0; x < h; x++)
//                {
//                    buff[x, y] = TileTypes.terrainColor[tiles[x, y].Terrain];
//                }
//            buff.Unlock();
//            return bmp;
//        }
//        static Bitmap RenderMoistBmp(TerrainTile[,] tiles)
//        {
//            int w = tiles.GetLength(0);
//            int h = tiles.GetLength(1);
//            Bitmap bmp = new Bitmap(w, h);
//            BitmapBuffer buff = new BitmapBuffer(bmp);
//            buff.Lock();
//            for (int y = 0; y < w; y++)
//                for (int x = 0; x < h; x++)
//                {
//                    uint color = 0x00ffffff;
//                    color |= (uint)(tiles[x, y].Moisture * 255) << 24;
//                    buff[x, y] = color;
//                }
//            buff.Unlock();
//            return bmp;
//        }
//        static Bitmap RenderEvalBmp(TerrainTile[,] tiles)
//        {
//            int w = tiles.GetLength(0);
//            int h = tiles.GetLength(1);
//            Bitmap bmp = new Bitmap(w, h);
//            BitmapBuffer buff = new BitmapBuffer(bmp);
//            buff.Lock();
//            for (int y = 0; y < w; y++)
//                for (int x = 0; x < h; x++)
//                {
//                    uint color = 0x00ffffff;
//                    color |= (uint)(tiles[x, y].Elevation * 255) << 24;
//                    buff[x, y] = color;
//                }
//            buff.Unlock();
//            return bmp;
//        }

//        public static void Generate()
//        {
//            //while (true)
//            //    Test.Show(RenderNoiseBmp(500, 500));

//            PolygonMap map = new PolygonMap(1, 1);
//            map.Generate(20000, 2, 1);

//            var dat = CreateTerrain(map);
//            new Biome(map).ComputeBiomes(dat);

//            Program.Show(RenderColorBmp(dat));
//            Program.Show(RenderTerrainBmp(dat));
//            Program.Show(RenderMoistBmp(dat));
//            Program.Show(RenderEvalBmp(dat));
//        }

//        static TerrainTile[,] CreateTerrain(PolygonMap map)
//        {
//            Rasterizer<TerrainTile> rasterizer = new Rasterizer<TerrainTile>(MAP_SIZE, MAP_SIZE);
            
//            //Set all to ocean
//            rasterizer.Clear(new TerrainTile()
//            {
//                PolygonId = -1,
//                Elevation = 0,
//                Moisture = 1,
//                TileId = TileTypes.DeepWater,
//                TileObj = null
//            });

//            //Render lands poly

//            foreach (var poly in map.MapPolygons)
//            {
//                var points = new List<double>();
//                foreach (var polyNode in poly.Nodes)
//                {
//                    points.Add((polyNode.X + 1) / 2 * MAP_SIZE);
//                    points.Add((polyNode.Y + 1) / 2 * MAP_SIZE);
//                }
//                points.Add((poly.Nodes[0].X + 1) / 2 * MAP_SIZE);
//                points.Add((poly.Nodes[0].Y + 1) / 2 * MAP_SIZE);

//                var tile = new TerrainTile()
//                {
//                    PolygonId = poly.Id,
//                    Elevation = (float)poly.DistanceToCoast,
//                    TileId = TileTypes.Water,
//                    TileObj = null
//                };
//                rasterizer.FillPolygon(points.ToArray(), tile);
//            }

//            ////Render roads
//            MapFeatures fea = new MapFeatures(map);
//            var roads = fea.GenerateRoads();
//            foreach (var i in roads)
//            {
//                rasterizer.DrawClosedCurve(i.SelectMany(_ => new[] {
//                    (_.X + 1) / 2 * MAP_SIZE, (_.Y + 1) / 2 * MAP_SIZE }).ToArray(),
//                    1, new TerrainTile()
//                    {
//                        PolygonId = -1,
//                        Elevation = -1,
//                        Moisture = -1,
//                        TileId = TileTypes.Road,
//                        TileObj = null
//                    }, 3);
//            }

//            //Render waters poly
//            foreach (var poly in map.MapPolygons.Where(_ => _.IsWater))
//            {
//                var tile = new TerrainTile()
//                {
//                    PolygonId = poly.Id,
//                    Elevation = (float)poly.DistanceToCoast,
//                    TileObj = null
//                };
//                if (poly.IsOcean && !poly.IsCoast || poly.Neighbours.All(_ => _.IsWater))
//                {
//                    tile.TileId = TileTypes.DeepWater;
//                    tile.Moisture = 1;
//                }
//                else
//                {
//                    tile.TileId = TileTypes.MovingWater;
//                    tile.Moisture = 1;
//                }
//                rasterizer.FillPolygon(
//                    poly.Nodes.SelectMany(_ =>
//                    {
//                        return new[]{ (_.X + 1) / 2 * MAP_SIZE,
//                                      (_.Y + 1) / 2 * MAP_SIZE};
//                    }).Concat(new[]{ (poly.Nodes[0].X + 1) / 2 * MAP_SIZE,
//                                     (poly.Nodes[0].Y + 1) / 2 * MAP_SIZE}).ToArray(), tile);
//            }

//            return rasterizer.Buffer;
//        }
//    }
//}