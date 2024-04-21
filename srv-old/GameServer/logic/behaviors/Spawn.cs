using System.Xml.Linq;
using GameServer.realm;
using GameServer.realm.entities;
using Shared;

namespace GameServer.logic.behaviors; 

internal class Spawn : Behavior
{
    //State storage: Spawn state
    private class SpawnState
    {
        public int CurrentNumber;
        public long RemainingTime;
    }

    private readonly int _maxChildren;
    private readonly int _initialSpawn;
    private Cooldown _coolDown;
    private readonly ushort _children;
    private readonly bool _givesNoXp;
    private readonly bool _copyHpState;
        
    public Spawn(XElement e)
    {
        _children = GetObjType(e.ParseString("@children"));
        _maxChildren = e.ParseInt("@maxChildren", 5);
        _initialSpawn = (int)(_maxChildren * e.ParseFloat("@initialSpawn", 0.5f));
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
        _givesNoXp = e.ParseBool("@givesNoXp", true);
        _copyHpState = e.ParseBool("@copyHpState");
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = new SpawnState()
        {
            CurrentNumber = _initialSpawn,
            RemainingTime = _coolDown.Next(Random)
        };
        for (var i = 0; i < _initialSpawn; i++)
        {
            var entity = Entity.Resolve(host.Manager, _children);
            entity.Move(host.X, host.Y);

            var enemyHost = host as Enemy;
            var enemyEntity = entity as Enemy;

            entity.GivesNoXp = _givesNoXp;
            if (enemyHost != null && !entity.GivesNoXp)
                entity.GivesNoXp = enemyHost.GivesNoXp;

            entity.ParentEntity = host;
            if (enemyHost != null && enemyEntity != null)
            {
                enemyEntity.ParentEntity = host as Enemy;
                enemyEntity.Region = enemyHost.Region;
                if (enemyHost.Spawned)
                {
                    enemyEntity.Spawned = true;
                }

                if (_copyHpState)
                {
                    enemyEntity.ScaleHpState = enemyHost.ScaleHpState;
                    enemyEntity.HP = enemyHost.HP;
                    enemyEntity.MaximumHP = enemyHost.MaximumHP;
                }
            }

            host.Owner.EnterWorld(entity);
            (state as SpawnState).CurrentNumber++;
        }
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var spawn = state as SpawnState;

        if (spawn == null)
            return;

        if (spawn.RemainingTime <= 0 && spawn.CurrentNumber < _maxChildren)
        {
            var entity = Entity.Resolve(host.Manager, _children);
            entity.Move(host.X, host.Y);

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

                if (_copyHpState)
                {
                    enemyEntity.ScaleHpState = enemyHost.ScaleHpState;
                    enemyEntity.HP = enemyHost.HP;
                    enemyEntity.MaximumHP = enemyHost.MaximumHP;
                }
            }

            host.Owner.EnterWorld(entity);
            spawn.RemainingTime = _coolDown.Next(Random);
            spawn.CurrentNumber++;
        }
        else
            spawn.RemainingTime -= time.ElapsedUsDelta;
    }
}