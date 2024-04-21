using System.Collections.Concurrent;
using Shared.terrain;
using GameServer.realm.worlds;

namespace GameServer.realm.entities.player;

public class UpdatedSet : HashSet<Entity> {
    private readonly Player _player;
    private readonly object _changeLock = new();

    public UpdatedSet(Player player) {
        _player = player;
    }

    public new bool Add(Entity e) {
        lock (_changeLock) {
            var added = base.Add(e);
            if (added)
                e.StatChanged += _player.HandleStatChanges;
            return added;
        }
    }

    public new bool Remove(Entity e) {
        lock (_changeLock) {
            e.StatChanged -= _player.HandleStatChanges;
            return base.Remove(e);
        }
    }

    public new void RemoveWhere(Predicate<Entity> match) {
        lock (_changeLock) {
            foreach (var e in this.Where(match.Invoke))
                e.StatChanged -= _player.HandleStatChanges;
            base.RemoveWhere(match);
        }
    }

    public void Dispose() {
        RemoveWhere(e => true);
    }
}

public partial class Player {
    public HashSet<Entity> clientEntities => _clientEntities;

    public readonly ConcurrentQueue<Entity> ClientKilledEntity = new();

    private const int StaticBoundingBox = VISIBILITY_RADIUS * 2;
    private const int AppoxAreaOfSight = (int) (Math.PI * VISIBILITY_RADIUS * VISIBILITY_RADIUS + 1);

    private readonly HashSet<IntPoint> _clientStatic = new();
    private readonly UpdatedSet _clientEntities;
    private ObjectStats[] _updateStatuses;
    private TileData[] _tiles;
    private ObjectDef[] _newObjects;
    private int[] _removedObjects;

    private readonly object _statUpdateLock = new();

    private readonly Dictionary<Entity, Dictionary<StatsType, object>> _statUpdates =
        new();

    public Sight Sight { get; private set; }

    public int TickId;

    public void DisposeUpdate() {
        _clientEntities.Dispose();
        _clientStatic.Clear();
        _newObjects = null;
        _newStatics.Clear();
        _removedObjects = null;
        _statUpdates.Clear();
        _tiles = null;
        _updateStatuses = null;
    }

    public void HandleStatChanges(object entity, StatChangedEventArgs statChange) {
        var e = entity as Entity;
        if (e == null || e != this && statChange.UpdateSelfOnly)
            return;

        lock (_statUpdateLock) {
            if (e == this && statChange.Stat == StatsType.None)
                return;

            if (!_statUpdates.ContainsKey(e))
                _statUpdates[e] = new Dictionary<StatsType, object>();

            if (statChange.Stat != StatsType.None)
                _statUpdates[e][statChange.Stat] = statChange.Value;

            //Log.Info($"{entity} {statChange.Stat} {statChange.Value}");
        }
    }
    
    private void SendNewTick(RealmTime time) {
        lock (_statUpdateLock) {
            _updateStatuses = _statUpdates.Select(e => new ObjectStats {
                Id = e.Key.Id,
                X = e.Key.RealX,
                Y = e.Key.RealY,
                StatTypes = e.Value.ToArray()
            }).ToArray();
            _statUpdates.Clear();
        }

        _client.SendNewTick((byte) (++TickId % 256), (byte) Manager.TPS, _updateStatuses);
        AwaitMove(TickId);
    }

    private void SendUpdate(RealmTime time) {
        // init sight circle
        var sCircle = DetermineSight(); // Sight.GetSightCircle(Owner.Blocking); // old code

        // get list of tiles for update
        var tilesUpdate = new List<TileData>(AppoxAreaOfSight);

        // hacky fix until i rewrite the entire Player.Update - Slendergo
        // this hack is for the way i caceh full sight compared to how i determine sight for blocking

        foreach (var point in sCircle) {
            var x = point.X;
            var y = point.Y;
            var tile = Owner?.Map[x, y] ?? new MapTile();

            if (tile.TileType == 255 || tiles[x, y] >= tile.UpdateCount)
                continue;

            tilesUpdate.Add(new TileData {
                X = (ushort) x,
                Y = (ushort) y,
                Tile = tile.TileType
            });
            tiles[x, y] = tile.UpdateCount;
        }

        // get list of new static objects to add
        var staticsUpdate = GetNewStatics(sCircle).ToArray();

        // get dropped entities list
        var entitiesRemove = new HashSet<int>(GetRemovedEntities(sCircle));

        // removed stale entities
        _clientEntities.RemoveWhere(e => entitiesRemove.Contains(e.Id));

        // get list of added entities
        var entitiesAdd = GetNewEntities(sCircle).ToArray();

        // get dropped statics list
        var staticsRemove = new HashSet<IntPoint>(GetRemovedStatics());
        _clientStatic.ExceptWith(staticsRemove);

        if (tilesUpdate.Count > 0 || entitiesRemove.Count > 0 || staticsRemove.Count > 0 ||
            entitiesAdd.Length > 0 || staticsUpdate.Length > 0) {
            entitiesRemove.UnionWith(
                staticsRemove.Select(s => Owner.Map[s.X, s.Y].ObjId));

            _tiles = tilesUpdate.ToArray();
            _newObjects = entitiesAdd.Select(_ => _.ToDefinition()).Concat(staticsUpdate).ToArray();
            _removedObjects = entitiesRemove.ToArray();
            foreach (var en in _statUpdates.Keys.Where(en => _removedObjects.Contains(en.Id))) {
                _statUpdates.Remove(en);
            }
            AwaitUpdateAck(time.TotalElapsedUs);
            _client.SendUpdate(_tiles, _newObjects, _removedObjects);
        }
    }

    private IEnumerable<int> GetRemovedEntities(HashSet<IntPoint> visibleTiles) {
        foreach (var e in ClientKilledEntity)
            yield return e.Id;

        foreach (var i in _clientEntities) {
            if (i.Owner == null)
                yield return i.Id;
            
            if (i is Player) {
                if (i.Owner == null || i.Owner.Id != Owner.Id) // this is a hacky fix to check for a different world
                    yield return i.Id;
            }

            if (i != this && !i.CanBeSeenBy(this))
                yield return i.Id;

            if (i is StaticObject so && so.Static) {
                if (Math.Abs(StaticBoundingBox - ((int) X - i.X)) > 0 &&
                    Math.Abs(StaticBoundingBox - ((int) Y - i.Y)) > 0)
                    continue;
            }

            if (i is Player ||
                i.ObjectDesc.KeepMinimap || /*(i is StaticObject && (i as StaticObject).Static) ||*/
                (i is Enemy enemy && enemy.RealmEvent) ||
                visibleTiles.Contains(new IntPoint((int) i.X, (int) i.Y)))
                continue;

            yield return i.Id;
        }
    }

    private IEnumerable<Entity> GetNewEntities(HashSet<IntPoint> visibleTiles)
    {
        while (ClientKilledEntity.TryDequeue(out var entity))
            _clientEntities.Remove(entity);

        // getting Null owner meaning theres something wrong with threading?
        // or it means we need to rewrite our setting world to null for entities on death lol
        // its stupid
        if (Owner != null)
        {
            foreach (var i in Owner.Players)
                if ((i.Value == this || i.Value.Client.Account != null && i.Value.Client.Player.CanBeSeenBy(this)) &&
                    _clientEntities.Add(i.Value))
                    yield return i.Value;

            var p = new IntPoint(0, 0);
            foreach (var i in Owner.EnemiesCollision.HitTest(X, Y, VISIBILITY_RADIUS))
            {
                if (i is Container)
                {
                    var owners = (i as Container).BagOwners;
                    if (owners.Length > 0 && Array.IndexOf(owners, AccountId) == -1)
                        continue;
                }

                p.X = (int)i.X;
                p.Y = (int)i.Y;
                if (visibleTiles.Contains(p) && _clientEntities.Add(i))
                    yield return i;
            }

            foreach (var en in Owner.Enemies.Values)
            {
                if (en != null && en.RealmEvent && _clientEntities.Add(en))
                    yield return en;
            }
        }
    }

    private IEnumerable<IntPoint> GetRemovedStatics() {
        foreach (var i in _clientStatic) {
            var tile = Owner.Map[i.X, i.Y];

            if (
                StaticBoundingBox - ((int) X - i.X) > 0 &&
                StaticBoundingBox - ((int) Y - i.Y) > 0 &&
                tile.ObjType != 0 &&
                tile.ObjId != 0)
                continue;

            yield return i;
        }
    }

    private List<ObjectDef> _newStatics = new(AppoxAreaOfSight);
    private IEnumerable<ObjectDef> GetNewStatics(HashSet<IntPoint> visibleTiles) 
    {
        _newStatics.Clear();
        foreach (var i in visibleTiles) {
            var tile = Owner?.Map[i.X, i.Y] ?? new MapTile();

            if (tile.ObjId != 0 && tile.ObjType != 0 && _clientStatic.Add(i))
                _newStatics.Add(tile.ToDef(i.X, i.Y));
        }
        return _newStatics;
    }

    // SIGHT FROM TKR - Slendergo
    // Should be good to use

    public const int VISIBILITY_RADIUS = 20;
    public const int VISIBILITY_RADIUS_SQR = VISIBILITY_RADIUS * VISIBILITY_RADIUS;
    public const int VISIBILITY_CIRCUMFERENCE_SQR = (VISIBILITY_RADIUS - 2) * (VISIBILITY_RADIUS - 2);

    // i could cache the results like i do full sight but i cant be arsed atm

    public HashSet<IntPoint> DetermineSight()
    {
        var hashSet = new HashSet<IntPoint>();
        switch (Owner.Blocking)
        {
            case 0:
                CalculateFullSight(hashSet);
                break;
            case 1:
                CalculateLineOfSight(hashSet);
                break;
            case 2:
                CalculatePath(hashSet);
                break;
        }
        return hashSet;
    }

    // not how i like todo it but its a hacky solution atm
    public void CalculateFullSight(HashSet<IntPoint> points)
    {
        var px = (int)X;
        var py = (int)Y;
        foreach (var point in SightPoints)
            points.Add(new IntPoint(point.X + px, point.Y + py));
    }

    public void CalculateLineOfSight(HashSet<IntPoint> points)
    {
        var px = (int)X;
        var py = (int)Y;

        foreach (var point in CircleCircumferenceSightPoints)
            DrawLine(px, py, px + point.X, py + point.Y, (x, y) =>
            {
                if (!Owner.Map.Contains(x, y))
                    return false;
                _ = points.Add(new IntPoint(x, y));
                return IsBlocking(x, y);
            });
    }

    public void CalculatePath(HashSet<IntPoint> points)
    {
        var px = (int)X;
        var py = (int)Y;

        var pathMap = new bool[Owner.Map.Width, Owner.Map.Height];
        StepPath(points, pathMap, px, py, px, py);
    }

    private void StepPath(HashSet<IntPoint> points, bool[,] pathMap, int x, int y, int px, int py)
    {
        if (!Owner.Map.Contains(x, y))
            return;

        if (pathMap[x, y])
            return;
        pathMap[x, y] = true;

        var point = new IntPoint(x - px, y - py);
        if (!SightPoints.Contains(point))
            return;
        point.X += px;
        point.Y += py;
        _ = points.Add(point);

        if (!IsBlocking(x, y))
            foreach (var p in SurroundingPoints)
                StepPath(points, pathMap, x + p.X, y + p.Y, px, py);
    }

    private bool IsBlocking(int x, int y)
    {
        var tile = Owner.Map[x, y];
        return tile.ObjType != 0 && tile.ObjDesc != null && tile.ObjDesc.BlocksSight;
    }

    private static readonly IntPoint[] SurroundingPoints = new IntPoint[5]
    {
        new IntPoint(0, 0),
        new IntPoint(1, 0),
        new IntPoint(0, 1),
        new IntPoint(-1, 0),
        new IntPoint(0, -1)
    };

    private static readonly HashSet<IntPoint> CircleCircumferenceSightPoints = CircleCircumferenceSightPoints ??= Cache(true);
    private static readonly HashSet<IntPoint> SightPoints = SightPoints ??= Cache();

    private static HashSet<IntPoint> Cache(bool circumferenceCheck = false)
    {
        var ret = new HashSet<IntPoint>();
        for (var x = -VISIBILITY_RADIUS; x <= VISIBILITY_RADIUS; x++)
            for (var y = -VISIBILITY_RADIUS; y <= VISIBILITY_RADIUS; y++)
            {
                var flag = x * x + y * y <= VISIBILITY_RADIUS_SQR;
                if (circumferenceCheck)
                    flag &= x * x + y * y > VISIBILITY_CIRCUMFERENCE_SQR;
                if (flag)
                    _ = ret.Add(new IntPoint(x, y));
            }

        return ret;
    }

    public static void DrawLine(int x, int y, int x2, int y2, Func<int, int, bool> func)
    {
        var w = x2 - x;
        var h = y2 - y;
        var dx1 = 0;
        var dy1 = 0;
        var dx2 = 0;
        var dy2 = 0;
        if (w < 0)
            dx1 = -1;
        else if (w > 0)
            dx1 = 1;
        if (h < 0)
            dy1 = -1;
        else if (h > 0)
            dy1 = 1;
        if (w < 0)
            dx2 = -1;
        else if (w > 0)
            dx2 = 1;

        var longest = Math.Abs(w);
        var shortest = Math.Abs(h);
        if (!(longest > shortest))
        {
            longest = Math.Abs(h);
            shortest = Math.Abs(w);
            if (h < 0)
                dy2 = -1;
            else if (h > 0)
                dy2 = 1;
            dx2 = 0;
        }

        var numerator = longest >> 1;
        for (var i = 0; i <= longest; i++)
        {
            if (func(x, y))
                break;

            numerator += shortest;
            if (!(numerator < longest))
            {
                numerator -= longest;
                x += dx1;
                y += dy1;
            }
            else
            {
                x += dx2;
                y += dy2;
            }
        }
    }
}