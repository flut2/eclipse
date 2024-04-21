using System.Collections.Concurrent;
using Shared;
using Shared.resources;
using Shared.terrain;
using DungeonGenerator;
using DungeonGenerator.Templates;
using GameServer.realm.entities;
using GameServer.realm.entities.player;
using GameServer.realm.entities.vendors;
using GameServer.realm.worlds.logic;
using NLog;

namespace GameServer.realm.worlds;

public class World {
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    public const int Retrieve = -2;

    private RealmManager _manager;

    public RealmManager Manager {
        get => _manager;
        internal set {
            _manager = value;
            if (_manager != null)
                Init();
        }
    }

    public int Id { get; internal set; }
    public string Name { get; set; }
    public string SBName { get; set; }
    public int BgLightColor;
    public float BgLightIntensity;
    public float DayLightIntensity;
    public float NightLightIntensity;
    public bool IsLimbo { get; protected set; }
    public bool AllowTeleport { get; protected set; }
    public bool ShowDisplays { get; protected set; }
    public bool Persist { get; protected set; }
    public int Blocking { get; protected set; }
    public string Realm { get; protected set; }

    public string Music { get; set; }
    public bool PlayerDungeon { get; set; }
    public string Opener { get; set; }
    public HashSet<string> Invites { get; set; }
    public Dictionary<string, Player> InviteDict { get; set; }
    public Realm RealmLogic { get; set; }

    public Map Map { get; private set; }
    public bool Deleted { get; protected set; }

    private long _elapsedTime;
    private int _totalConnects;

    public int TotalConnects => _totalConnects;

    private KeyValuePair<IntPoint, TileRegion>[] _spawnPoints;

    public bool Closed { get; set; }

    public ConcurrentDictionary<int, Player> Players { get; private set; }
    public ConcurrentDictionary<int, Enemy> Enemies { get; private set; }
    public ConcurrentDictionary<int, Enemy> Quests { get; private set; }
    public ConcurrentDictionary<Tuple<int, byte>, Projectile> Projectiles { get; private set; }
    public ConcurrentDictionary<int, StaticObject> StaticObjects { get; private set; }

    public CollisionMap<Entity> EnemiesCollision { get; private set; }
    public CollisionMap<Entity> PlayersCollision { get; private set; }

    public List<WorldTimer> Timers { get; private set; }

    private static int _entityInc;

    private readonly object _deleteLock = new();
    public readonly ProtoWorld Proto;

    public World(ProtoWorld proto) {
        Proto = proto;
        Setup();
        Id = proto.id;
        Name = proto.name;
        SBName = proto.sbName;
        BgLightColor = proto.bgLightColor;
        BgLightIntensity = proto.bgLightIntensity;
        DayLightIntensity = proto.dayLightIntensity;
        NightLightIntensity = proto.nightLightIntensity;
        IsLimbo = proto.isLimbo;
        Persist = proto.persist;
        AllowTeleport = !proto.restrictTp;
        ShowDisplays = proto.showDisplays;
        Blocking = proto.blocking;
        Realm = proto.realm;
        Opener = "";

        var rnd = new Random();
        Music = proto.music != null ? proto.music[rnd.Next(0, proto.music.Length)] : "Test";
    }

    private void Setup() {
        Players = new ConcurrentDictionary<int, Player>();
        Enemies = new ConcurrentDictionary<int, Enemy>();
        Quests = new ConcurrentDictionary<int, Enemy>();
        Projectiles = new ConcurrentDictionary<Tuple<int, byte>, Projectile>();
        StaticObjects = new ConcurrentDictionary<int, StaticObject>();
        Timers = new List<WorldTimer>();
        AllowTeleport = true;
        ShowDisplays = true;
        Persist = false; // if false, attempts to delete world with 0 players
        Blocking = 0; // toggles sight block (0 disables sight block)
    }

    public string GetDisplayName() {
        if (SBName != null && SBName.Length > 0) {
            return SBName[0] == '{' ? Name : SBName;
        }
        else {
            return Name;
        }
    }

    public virtual bool AllowedAccess(Client client) {
        return !Closed || client.Account.Admin;
    }

    public virtual KeyValuePair<IntPoint, TileRegion>[] GetSpawnPoints() {
        if (_spawnPoints is null) {
            _spawnPoints = Map.Regions.Where(t => t.Value == TileRegion.Spawn).ToArray();
        }

        return _spawnPoints;
    }

    public virtual World GetInstance() {
        return Manager.AddWorld(new World(_manager.Resources.Worlds[Name]) {
            IsLimbo = false
        });
    }

    public long GetAge() {
        return _elapsedTime;
    }

    protected virtual void Init() {
        if (IsLimbo) return;

        var proto = Proto;

        /*if (proto.maps != null && proto.maps.Length <= 0)
        {
            var template = DungeonTemplates.GetTemplate(Name);
            if (template == null)
                throw new KeyNotFoundException($"Template for {Name} not found.");
            FromDungeonGen(Rand.Next(), template);
            return;
        }*/

        FromWorldMap(new MemoryStream(proto.mapData));

        InitShops();

        if (Realm != null)
            RealmLogic = new Realm(this);
    }

    protected void InitShops() {
        foreach (var shop in Manager.Resources.GameData.MerchantLists) {
            var items = new List<ISellableItem>(shop.Items);
            var mLocations = Map.Regions
                .Where(r => shop.Region == r.Value)
                .Select(r => r.Key)
                .ToArray();

            if (items.Count <= 0 || items.All(i => i.ItemId == ushort.MaxValue))
                continue;

            var rotate = items.Count > mLocations.Length;
            var reloadOffset = 0;
            foreach (var loc in mLocations) {
                var item = items[0];
                items.RemoveAt(0);
                while (item.ItemId == ushort.MaxValue) {
                    if (items.Count <= 0)
                        items.AddRange(shop.Items);

                    item = items[0];
                    items.RemoveAt(0);
                }

                reloadOffset += 500;
                var m = new WorldMerchant(Manager, 0x0400) {
                    ShopItem = item,
                    Item = item.ItemId,
                    Price = item.Price,
                    Count = item.Count,
                    Currency = shop.Currency,
                    ItemList = shop.Items,
                    ReloadOffset = reloadOffset,
                    Rotate = rotate
                };

                m.Move(loc.X + .5f, loc.Y + .5f);
                EnterWorld(m);

                if (items.Count <= 0)
                    items.AddRange(shop.Items);
            }
        }
    }

    public bool Delete() {
        lock (_deleteLock) {
            if (Players.Count > 0)
                return false;

            Deleted = true;
            Manager.RemoveWorld(this);
            Id = 0;

            DisposeEntities(Players);
            DisposeEntities(Enemies);
            DisposeEntities(Projectiles);
            DisposeEntities(StaticObjects);

            Players = null;
            Enemies = null;
            Projectiles = null;
            StaticObjects = null;
            _spawnPoints = null;

            return true;
        }
    }

    private void DisposeEntities<T, TU>(ConcurrentDictionary<T, TU> dictionary) {
        foreach (var entity in dictionary)
            (entity.Value as Entity).Dispose();
    }

    protected void FromDungeonGen(int seed, DungeonTemplate template) {
        Log.Info("Loading template for world {0}({1})...", Id, Name);

        var gen = new Generator(seed, template);
        gen.Generate();
        var ras = new Rasterizer(seed, gen.ExportGraph());
        ras.Rasterize();
        var dTiles = ras.ExportMap();

        if (Map == null) {
            Map = new Map(Manager.Resources.GameData);
            Interlocked.Add(ref _entityInc, Map.Load(dTiles, _entityInc));
            if (Blocking == 3)
                Sight.CalcRegionBlocks(Map);
        }
        else
            Map.ResetTiles();

        InitMap();
    }

    protected void FromWorldMap(Stream dat) {
        Log.Info("Loading map for world {0}({1})...", Id, Name);

        if (Map == null) {
            Map = new Map(Manager.Resources.GameData);
            Interlocked.Add(ref _entityInc, Map.Load(dat, _entityInc));
            if (Blocking == 3)
                Sight.CalcRegionBlocks(Map);
        }
        else
            Map.ResetTiles();

        InitMap();
    }

    private void InitMap() {
        int w = Map.Width, h = Map.Height;
        EnemiesCollision = new CollisionMap<Entity>(0, w, h);
        PlayersCollision = new CollisionMap<Entity>(1, w, h);

        Projectiles.Clear();
        StaticObjects.Clear();
        Enemies.Clear();
        Players.Clear();
        Quests.Clear();
        Timers.Clear();

        foreach (var i in Map.InstantiateEntities(Manager))
            EnterWorld(i);
    }

    public void WorldAnnouncement(string msg) {
        foreach (var player in Players.Values)
            player.SendInfo(msg);
    }

    public int EnterWorld(Entity entity, bool noIdChange = false) {
        switch (entity) {
            case Player p:
                if (!noIdChange)
                    p.Id = GetNextEntityId();
                p.Init(this);
                Players.TryAdd(p.Id, p);
                PlayersCollision.Insert(p);
                Interlocked.Increment(ref _totalConnects);
                return p.Id;
            case Enemy e: {
                e.Id = GetNextEntityId();
                e.Init(this);
                Enemies.TryAdd(e.Id, e);
                EnemiesCollision.Insert(e);
                if (e.ObjectDesc.Quest)
                    Quests.TryAdd(e.Id, e);
                return e.Id;
            }
            case Projectile projectile: {
                projectile.Init(this);
                Projectiles[new Tuple<int, byte>(projectile.ProjectileOwner.Self.Id, projectile.BulletId)] = projectile;
                return projectile.Id;
            }
            case StaticObject staticObject:
                staticObject.Id = GetNextEntityId();
                staticObject.Init(this);
                StaticObjects.TryAdd(staticObject.Id, staticObject);
                EnemiesCollision.Insert(staticObject);
                return staticObject.Id;
            default:
                return entity.Id;
        }
    }

    public virtual void LeaveWorld(Entity entity) {
        switch (entity) {
            case Player player: {
                Players.TryRemove(player.Id, out _);
                PlayersCollision.Remove(player);

                // if in trade, cancel it...
                if (player?.tradeTarget != null)
                    player.CancelTrade();
                player.Dispose();
                break;
            }
            case Enemy enemy: {
                var foundEnigma = false;
                foreach (var p in Players.Values)
                    if (p.ObjectType == 0x0321 && MathUtils.DistSqr(p.X, p.Y, enemy.X, enemy.Y) < 16 * 16) {
                        foundEnigma = true;
                        break;
                    }

                if (foundEnigma) {
                    var soul = Entity.Resolve(Manager, 0x100a); // soul fragment id
                    soul.Move(enemy.X, enemy.Y);
                    EnterWorld(soul);
                }
                
                Enemies.TryRemove(enemy.Id, out _);
                EnemiesCollision.Remove(enemy);
                if (enemy.ObjectDesc.Quest)
                    Quests.TryRemove(enemy.Id, out _);
                enemy.Dispose();
                
                
                break;
            }
            case Projectile projectile: {
                Projectiles.TryRemove(new Tuple<int, byte>(projectile.ProjectileOwner.Self.Id, projectile.BulletId), out _);
                projectile.Dispose();
                break;
            }
            case StaticObject so: {
                StaticObjects.TryRemove(so.Id, out _);

                if (so.ObjectDesc?.BlocksSight == true) {
                    if (Blocking == 3)
                        Sight.UpdateRegion(Map, (int) so.X, (int) so.Y);

                    foreach (var plr in Players.Where(p => MathsUtils.DistSqr(p.Value.X, p.Value.Y, so.X, so.Y) < Player.VISIBILITY_RADIUS_SQR))
                        plr.Value.Sight.UpdateCount++;
                }

                EnemiesCollision.Remove(so);
                so.Dispose();
                break;
            }
            default:
                entity.Dispose();
                break;
        }
    }

    public int GetNextEntityId() {
        return Interlocked.Increment(ref _entityInc);
    }

    public Entity GetEntity(int id) {
        return Players.TryGetValue(id, out var plr) ? plr :
            Enemies.TryGetValue(id, out var en) ? en :
            StaticObjects.TryGetValue(id, out var so) ? so : null;
    }

    public Player GetUniqueNamedPlayer(string name) {
        foreach (var i in Players) {
            if (i.Value.Name.Equals(name, StringComparison.InvariantCultureIgnoreCase)) {
                return i.Value;
            }
        }

        return null;
    }

    public bool IsPassable(double x, double y, bool spawning = false) {
        var x_ = (int) x;
        var y_ = (int) y;

        if (!Map.Contains(x_, y_))
            return false;

        var tile = Map[x_, y_];

        if (tile.TileDesc.NoWalk)
            return false;

        if (tile.ObjType != 0 && tile.ObjDesc != null) {
            if (tile.ObjDesc.FullOccupy || tile.ObjDesc.EnemyOccupySquare ||
                (spawning && tile.ObjDesc.OccupySquare))
                return false;
        }

        return true;
    }

    public void QuakeToWorld(World newWorld) {
        if (!Persist)
            Closed = true;

        foreach (var p in Players)
            p.Value.Client.SendShowEffect(EffectType.Earthquake, 0, 0, 0, 0, 0, 0);

        Timers.Add(new WorldTimer(8000, (w, t) => {
            foreach (var plr in w.Players.Values)
                plr.Client.Reconnect(newWorld.SBName, newWorld.Id);
        }));

        if (!Persist)
            Timers.Add(new WorldTimer(20000, (w2, t2) => {
                // to ensure people get kicked out of world
                foreach (var plr in w2.Players)
                    plr.Value.Client.Disconnect();
            }));
    }

    public void ChatReceived(Player player, string text) {
        foreach (var en in Enemies)
            en.Value.OnChatTextReceived(player, text);
        foreach (var en in StaticObjects)
            en.Value.OnChatTextReceived(player, text);
    }

    public virtual void Tick(RealmTime time) {
        // if Tick is overrided and you make a call to this function
        // make sure not to do anything after the call (or at least check)
        // as it is possible for the world to have been removed at that point.

        try {
            _elapsedTime += time.ElapsedUsDelta;

            if (IsLimbo) return;

            if (!Persist && (this is Stash ? _elapsedTime > 5 * 1000 * 1000 : _elapsedTime > 60 * 1000 * 1000) && Players.Count <= 0) {
                Delete();
                return;
            }

            lock (_deleteLock) {
                RealmLogic?.Tick(time);

                if (Deleted)
                    return;

                if (EnemiesCollision != null) {
                    foreach (var i in EnemiesCollision.GetActiveChunks(PlayersCollision))
                        i.Tick(time);
                }
                else {
                    foreach (var i in Enemies)
                        i.Value.Tick(time);

                    foreach (var i in StaticObjects)
                        i.Value.Tick(time);
                }

                foreach (var i in Players)
                    i.Value.Tick(time);

                foreach (var i in Projectiles)
                    i.Value.Tick(time);
            }

            for (var i = Timers.Count - 1; i >= 0; i--)
                try {
                    if (Timers[i].Tick(this, time))
                        Timers.RemoveAt(i);
                }
                catch (Exception e) {
                    var msg = e.Message + "\n" + e.StackTrace;
                    Log.Error(msg);
                    Timers.RemoveAt(i);
                }
        }
        catch (Exception e) {
            var msg = e.Message + "\n" + e.StackTrace;
            Log.Error(msg);
        }
    }

    public Projectile GetProjectile(int objectId, int bulletId) {
        return GetEntity(objectId) is IProjectileOwner entity
            ? entity.Projectiles[bulletId]
            : Projectiles.SingleOrDefault(p =>
                p.Value.ProjectileOwner.Self.Id == objectId &&
                p.Value.BulletId == bulletId).Value;
    }
}