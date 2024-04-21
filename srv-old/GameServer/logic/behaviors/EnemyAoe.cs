using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class EnemyAoe : CycleBehavior
{
    //State storage: cooldown timer

    private readonly float _radius;
    private readonly int _minDamage;
    private readonly int _maxDamage;
    private readonly bool _noDef;
    private readonly bool _players;
    private readonly uint _color;
    private readonly ConditionEffectIndex _effect;
    private readonly int _effectDuration;
    private Cooldown _coolDown;
    private int _damage;

    public EnemyAoe(XElement e)
    {
        _radius = e.ParseFloat("@radius");
        _minDamage = e.ParseInt("@minDamage");
        _maxDamage = e.ParseInt("@maxDamage");
        _noDef = e.ParseBool("@noDef");
        _effect = e.ParseConditionEffect("@effect");
        _effectDuration = e.ParseInt("@effectDuration");
        _players = e.ParseBool("@players");
        _color = e.ParseUInt("@color", undefined: 0xffff0000);
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown") * 1000);
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = 0L;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var cool = (long)state;

        if (cool <= 0)
        {
            _damage = Random.Next(_minDamage, _maxDamage);
            var player = host.AttackTarget ?? host.GetNearestEntity(_radius * 2, _players);

            if (host.TauntedPlayerNearby(_radius * 2) && _players)
                player = host.GetNearestTauntedPlayer(_radius * 2);

            if (player != null)
            {
                var target = new Position()
                {
                    X = host.X,
                    Y = host.Y
                };

                var entities = new List<Entity>();
                host.Owner.AOE(target, _radius, _players, en => { entities.Add(en); });

                if (_players)
                        
                    foreach (var p in host.Owner.Players.Values)
                    {
                        if (p != host && MathUtils.DistSqr(p.X, p.Y, host.X, host.Y) < 16 * 16)
                            p.Client.SendAOE(target.X, target.Y, _radius, (ushort)_damage, 0, 0, host.ObjectType, _color);
                    }
                else
                    foreach (var p in host.Owner.Players.Values)
                    {
                        if (p != host && MathUtils.DistSqr(p.X, p.Y, host.X, host.Y) < 16 * 16)
                            p.Client.SendShowEffect(EffectType.AreaBlast, host.Id, _radius, 0, 0, 0, _color);
                    }

                foreach (var entity in entities)
                {
                    if (entity is Player p && _players)
                    {
                        var tenacity = Constants.NegativeEffsIdx.Contains(_effect)
                            ? 1d - (double)p.Stats[StatsManager.TENACITY_STAT] / 100
                            : 1d;
                        ((IPlayer)p).Damage(_damage, host, _noDef);
                        p.ApplyConditionEffect(_effect, (int)(Math.Max(1, _effectDuration * tenacity)));
                    }
                    else if (entity is Enemy e && !_players)
                    {
                        e.Damage(host.GetPlayerOwner(), time, _damage);
                        e.ApplyConditionEffect(_effect, _effectDuration);
                    }
                }

                cool = _coolDown.Next(Random);
            }
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}