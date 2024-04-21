using System.Xml.Linq;
using Shared;
using Shared.resources;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

internal class SpawnGroup : Behavior
{
    //State storage: Spawn state
    private class SpawnState
    {
        public int CurrentNumber;
        public long RemainingTime;
    }

    private int maxChildren;
    private int initialSpawn;
    private Cooldown coolDown;
    private ushort[] children;
    private double radius;
        
    public SpawnGroup(XElement e)
    {
        children = BehaviorDb.InitGameData.ObjectDescs.Values
            .Where(x => x.Group == e.ParseString("@group"))
            .Select(x => x.ObjectType).ToArray();
        maxChildren = e.ParseInt("@maxChildren");
        initialSpawn = (int)(maxChildren * e.ParseFloat("@initialSpawn", 0.5f));
        coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
        radius = e.ParseFloat("@radius");
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = new SpawnState()
        {
            CurrentNumber = initialSpawn,
            RemainingTime = coolDown.Next(Random)
        };
        for (var i = 0; i < initialSpawn; i++)
        {
            var x = host.X + (float)(Random.NextDouble() * radius);
            var y = host.Y + (float)(Random.NextDouble() * radius);

            if (!host.Owner.IsPassable(x, y, true))
                continue;

            var entity = Entity.Resolve(host.Manager, children[Random.Next(children.Length)]);
            entity.Move(x, y);

            var enemyHost = host as Enemy;
            var enemyEntity = entity as Enemy;
            if (enemyHost != null && enemyEntity != null)
            {
                enemyEntity.Region = enemyHost.Region;
                if (enemyHost.Spawned)
                {
                    enemyEntity.Spawned = true;
                }
            }

            host.Owner.EnterWorld(entity);
        }
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var spawn = (SpawnState)state;

        if (spawn.RemainingTime <= 0 && spawn.CurrentNumber < maxChildren)
        {
            var x = host.X + (float)(Random.NextDouble() * radius);
            var y = host.Y + (float)(Random.NextDouble() * radius);

            if (!host.Owner.IsPassable(x, y, true))
            {
                spawn.RemainingTime = coolDown.Next(Random);
                spawn.CurrentNumber++;
                return;
            }

            var entity = Entity.Resolve(host.Manager, children[Random.Next(children.Length)]);
            entity.Move(x, y);

            var enemyHost = host as Enemy;
            var enemyEntity = entity as Enemy;
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
            spawn.RemainingTime = coolDown.Next(Random);
            spawn.CurrentNumber++;
        }
        else
            spawn.RemainingTime -= time.ElapsedUsDelta;
    }
}