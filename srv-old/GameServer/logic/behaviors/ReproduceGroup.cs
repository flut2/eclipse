using System.Xml.Linq;
using Shared;
using Shared.resources;
using Shared.terrain;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

internal class ReproduceGroup : Behavior
{
    //State storage: cooldown timer

    private readonly double _densityRadius;
    private readonly int _densityMax;
    private readonly ushort[] _children;
    private readonly string _group;
    private Cooldown _coolDown;
    private readonly TileRegion _region;
    private readonly double _regionRange;
    private List<IntPoint> _reproduceRegions;

    public ReproduceGroup(XElement e)
    {
        _group = e.ParseString("@group");
        _children = BehaviorDb.InitGameData.ObjectDescs.Values
            .Where(x => x.Group == _group)
            .Select(x => x.ObjectType).ToArray();
            
        _densityMax = e.ParseInt("@densityMax", 5);
        _region = (TileRegion)Enum.Parse(typeof(TileRegion), e.ParseString("@region", "None").Replace(' ', '_'));
        _regionRange = e.ParseFloat("@regionRange", 10);
        _densityRadius = e.ParseFloat("@densityRadius", 10);
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        base.OnStateEntry(host, time, ref state);

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
        var cool = (state == null) ? _coolDown.Next(Random) : (long)state;

        if (cool <= 0)
        {
            var count = host.CountEntity(_densityRadius, _group);

            if (count < _densityMax)
            {
                double targetX = host.X;
                double targetY = host.Y;

                if (_reproduceRegions != null && _reproduceRegions.Count > 0)
                {
                    var sx = (int)host.X;
                    var sy = (int)host.Y;
                    var regions = _reproduceRegions
                        .Where(p => Math.Abs(sx - host.X) <= _regionRange &&
                                    Math.Abs(sy - host.Y) <= _regionRange).ToList();
                    var tile = regions[Random.Next(regions.Count)];
                    targetX = tile.X;
                    targetY = tile.Y;
                }

                /*int i = 0;
                do
                {
                    var angle = Random.NextDouble() * 2 * Math.PI;
                    targetX = host.X + densityRadius * 0.5 * Math.Cos(angle);
                    targetY = host.Y + densityRadius * 0.5 * Math.Sin(angle);
                    i++;
                } while (targetX < host.Owner.Map.Width &&
                         targetY < host.Owner.Map.Height &&
                         targetX > 0 && targetY > 0 &&
                         host.Owner.Map[(int)targetX, (int)targetY].Terrain !=
                         host.Owner.Map[(int)host.X, (int)host.Y].Terrain &&
                    i < 10);*/

                if (!host.Owner.IsPassable(targetX, targetY, true))
                {
                    state = _coolDown.Next(Random);
                    return;
                }

                var entity = Entity.Resolve(host.Manager, _children[Random.Next(_children.Length)]);
                entity.GivesNoXp = true;
                entity.Move((float)targetX, (float)targetY);

                var enemyHost = host as Enemy;
                var enemyEntity = entity as Enemy;
                entity.ParentEntity = host;
                if (enemyHost != null && enemyEntity != null)
                {
                    enemyEntity.Region = enemyHost.Region;
                    if (enemyHost.Spawned)
                    {
                        enemyEntity.Spawned = true;
                    }

                    if (enemyHost.DevSpawned)
                    {
                        enemyEntity.DevSpawned = true;
                    }
                }

                host.Owner.EnterWorld(entity);
            }

            cool = _coolDown.Next(Random);
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}