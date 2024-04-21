using System.Xml.Linq;
using Shared;
using Shared.resources;
using Shared.terrain;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

internal class TossObject : Behavior
{
    //State storage: cooldown timer

    private readonly double _range;
    private readonly double? _angle;
    private Cooldown _coolDown;
    private readonly int _coolDownOffset;
    private readonly bool _tossInvis;
    private readonly double _probability;
    private ushort[] _children;
    private readonly double? _minRange;
    private readonly double? _maxRange;
    private readonly double? _minAngle;
    private readonly double? _maxAngle;
    private readonly double? _densityRange;
    private readonly int? _maxDensity;
    private readonly string _group;
    private readonly TileRegion _region;
    private readonly double _regionRange;
    private List<IntPoint> _reproduceRegions;

    public TossObject(XElement e)
    {
        _group = e.ParseString("@group");
        if (_group == null)
            _children = new []{GetObjType(e.ParseString("@child"))};
        else
            _children = BehaviorDb.InitGameData.ObjectDescs.Values
                .Where(x => x.Group == _group)
                .Select(x => x.ObjectType).ToArray();

        _range = e.ParseFloat("@range", 5);
        _angle = e.ParseNFloat("@angle") * Math.PI / 180;
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
        _coolDownOffset = e.ParseInt("@coolDownOffset");
        _tossInvis = e.ParseBool("@tossInvis");
        _probability = e.ParseFloat("@probability", 1);
        _minRange = e.ParseNFloat("@minRange");
        _maxRange = e.ParseNFloat("@maxRange");
        _minAngle = e.ParseNFloat("@minAngle") * Math.PI / 180;
        _maxAngle = e.ParseNFloat("@maxAngle") * Math.PI / 180;
        _densityRange = e.ParseNFloat("@densityRange");
        _maxDensity = e.ParseNInt("@maxDensity");
        _region = (TileRegion)Enum.Parse(typeof(TileRegion), e.ParseString("@region", "None"));
        _regionRange = e.ParseFloat("@regionRange", 10);
    }
    
    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = _coolDownOffset;

        if (_region == TileRegion.None)
            return;

        var map = host.Owner.Map;

        var w = map.Width;
        var h = map.Height;

        _reproduceRegions = new List<IntPoint>();

        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        {
            if (map[x, y].Region != _region)
                continue;

            _reproduceRegions.Add(new IntPoint(x, y));
        }
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var cool = (long)state;

        if (cool <= 0)
        {
            if (Random.NextDouble() > _probability)
            {
                state = _coolDown.Next(Random);
                return;
            }

            var player = host.GetNearestEntity(_range, null);
            if (player != null || _angle != null)
            {
                if (_densityRange != null && _maxDensity != null)
                {
                    var cnt = 0;
                    if (_children.Length > 1)
                        cnt = host.CountEntity((double)_densityRange, _group);
                    else
                    {
                        cnt = host.CountEntity((double)_densityRange, _children[0]);
                    }

                    if (cnt >= _maxDensity)
                    {
                        state = _coolDown.Next(Random);
                        return;
                    }
                }

                var r = _range;
                if (_minRange != null && _maxRange != null)
                    r = (double)_minRange + Random.NextDouble() * ((double)_maxRange - (double)_minRange);

                var a = _angle;
                if (_angle == null && _minAngle != null && _maxAngle != null)
                    a = (double)_minAngle + Random.NextDouble() * ((double)_maxAngle - (double)_minAngle);

                Position target;
                if (a != null)
                    target = new Position()
                    {
                        X = host.X + (float)(r * Math.Cos(a.Value)),
                        Y = host.Y + (float)(r * Math.Sin(a.Value)),
                    };
                else
                    target = new Position()
                    {
                        X = player.X,
                        Y = player.Y,
                    };

                if (_reproduceRegions != null && _reproduceRegions.Count > 0)
                {
                    var sx = (int)host.X;
                    var sy = (int)host.Y;
                    var regions = _reproduceRegions
                        .Where(p => Math.Abs(sx - p.X) <= _regionRange &&
                                    Math.Abs(sy - p.Y) <= _regionRange).ToList();
                    var tile = regions[Random.Next(regions.Count)];
                    target = new Position()
                    {
                        X = tile.X,
                        Y = tile.Y
                    };
                }

                if (!_tossInvis)
                    foreach (var p in host.Owner.Players.Values)
                        if (p != host && MathUtils.DistSqr(p.X, p.Y, host.X, host.Y) < 16 * 16)
                            p.Client.SendShowEffect(EffectType.Throw, host.Id, target.X, target.Y, 0, 0, 0xFFBF00);
                host.Owner.Timers.Add(new WorldTimer(_tossInvis ? 0 : 1500, (world, t) =>
                {
                    if (!world.IsPassable(target.X, target.Y, true))
                        return;

                    var entity = Entity.Resolve(host.Manager, _children[Random.Next(_children.Length)]);
                    entity.Move(target.X, target.Y);
                    entity.ParentEntity = host;

                    if (host.Spawned)
                    {
                        entity.Spawned = true;
                    }

                    if (host.DevSpawned)
                    {
                        entity.DevSpawned = true;
                    }

                    var enemyHost = host as Enemy;
                    var enemyEntity = entity as Enemy;
                    if (enemyHost != null && enemyEntity != null)
                    {
                        enemyEntity.Region = enemyHost.Region;

                        if (enemyHost.DevSpawned)
                        {
                            enemyEntity.DevSpawned = true;
                        }
                    }

                    world.EnterWorld(entity);
                }));
                cool = _coolDown.Next(Random);
            }
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}