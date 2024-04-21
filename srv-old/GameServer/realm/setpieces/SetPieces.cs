using Shared.resources;
using GameServer.realm.worlds;
using NLog;

namespace GameServer.realm.setpieces; 

internal class SetPieces
{
    private static Logger Log = LogManager.GetCurrentClassLogger();

    private struct Rect
    {
        public int x;
        public int y;
        public int w;
        public int h;

        public static bool Intersects(Rect r1, Rect r2)
        {
            return !(r2.x > r1.x + r1.w ||
                     r2.x + r2.w < r1.x ||
                     r2.y > r1.y + r1.h ||
                     r2.y + r2.h < r1.y);
        }
    }

    public static int[,] rotateCW(int[,] mat)
    {
        var M = mat.GetLength(0);
        var N = mat.GetLength(1);
        var ret = new int[N, M];
        for (var r = 0; r < M; r++)
        {
            for (var c = 0; c < N; c++)
            {
                ret[c, M - 1 - r] = mat[r, c];
            }
        }

        return ret;
    }

    public static int[,] reflectVert(int[,] mat)
    {
        var M = mat.GetLength(0);
        var N = mat.GetLength(1);
        var ret = new int[M, N];
        for (var x = 0; x < M; x++)
        for (var y = 0; y < N; y++)
            ret[x, N - y - 1] = mat[x, y];
        return ret;
    }

    public static int[,] reflectHori(int[,] mat)
    {
        var M = mat.GetLength(0);
        var N = mat.GetLength(1);
        var ret = new int[M, N];
        for (var x = 0; x < M; x++)
        for (var y = 0; y < N; y++)
            ret[M - x - 1, y] = mat[x, y];
        return ret;
    }

    private static int DistSqr(IntPoint a, IntPoint b)
    {
        return (a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y);
    }

    public static void ApplySetPieces(World world, string worldName)
    {
        world.Manager.Resources.Worlds.BiomeData.TryGetValue(worldName, out var setpieceData);
        if (setpieceData == null)
        {
            Log.Error("Could not find setpiece data for {0}", worldName);
            return;
        }
            
        Log.Info("Applying set pieces to world {0}({1}).", world.Id, world.Name);

        var map = world.Map;
        int w = map.Width, h = map.Height;

        var rand = new Random();
        var rects = new HashSet<Rect>();
        foreach (var dat in setpieceData.SetpieceData)
        {
            int i;
            if (dat.X != null && dat.X.Length > 0 && dat.X.Length == dat.Y.Length)
            {
                for (i = 0; i < dat.X.Length; i++)
                    RenderFromProto(world, new IntPoint(dat.X[i], dat.Y[i]), dat.Setpiece);
                continue;
            }
                
            var count = rand.Next(dat.Min, dat.Max);
            for (i = 0; i < count; i++)
            {
                var pt = new IntPoint();
                Rect rect;

                var max = 50;
                do
                {
                    pt.X = rand.Next(0, w);
                    pt.Y = rand.Next(0, h);
                    rect = new Rect() { x = pt.X, y = pt.Y, w = dat.Size, h = dat.Size };
                    max--;
                } while ((Array.IndexOf(new[] {dat.Region}, map[pt.X, pt.Y].Region) == -1 ||
                          rects.Any(_ => Rect.Intersects(rect, _))) &&
                         max > 0);

                if (max <= 0) continue;
                RenderFromProto(world, pt, dat.Setpiece);
                rects.Add(rect);
            }
        }

        Log.Info("Set pieces applied.");
    }

    public static void RenderFromProto(World world, IntPoint pos, ProtoWorld proto)
    {
        var manager = world.Manager;
        var ms = new MemoryStream(proto.mapData);
        var sp = new Map(manager.Resources.GameData);
        sp.Load(ms, 0);
        sp.ProjectOntoWorld(world, pos);
    }

    public static Map GetWmap(RealmManager manager, ProtoWorld proto)
    {
        var ms = new MemoryStream(proto.mapData);
        var wmap = new Map(manager.Resources.GameData);
        wmap.Load(ms, 0);
        return wmap;
    }
}