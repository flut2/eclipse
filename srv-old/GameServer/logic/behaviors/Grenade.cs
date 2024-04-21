using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class Grenade : Behavior
{
    //State storage: cooldown timer

    private double range;
    private float radius;
    private double? fixedAngle;
    private int damage;
    private Cooldown coolDown;
    private ConditionEffectIndex effect;
    private int effectDuration;
    private uint color;
    private bool noDef;

    public Grenade(XElement e)
    {
        radius = e.ParseFloat("@radius");
        damage = e.ParseInt("@damage");
        range = e.ParseInt("@range", 5);
        fixedAngle = (float?)(e.ParseNFloat("@fixedAngle") * Math.PI / 180);
        coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
        effect = e.ParseConditionEffect("@effect");
        effectDuration = e.ParseInt("@effectDuration");
        color = e.ParseUInt("@color", true, 0xff0000);
        noDef = e.ParseBool("@noDef");
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
            var player = host.AttackTarget ?? host.GetNearestEntity(range, true);

            if (host.TauntedPlayerNearby(range))
                player = host.GetNearestTauntedPlayer(range);

            if (player != null || fixedAngle != null)
            {
                Position target;
                if (fixedAngle != null)
                    target = new Position()
                    {
                        X = (float)(range * Math.Cos(fixedAngle.Value)) + host.X,
                        Y = (float)(range * Math.Sin(fixedAngle.Value)) + host.Y,
                    };
                else
                    target = new Position()
                    {
                        X = player.X,
                        Y = player.Y,
                    };
                foreach (var p in host.Owner.Players.Values)
                    if (MathUtils.DistSqr(p.X, p.Y, host.X, host.Y) < 16 * 16)
                        p.Client.SendShowEffect(EffectType.Throw, host.Id, target.X, target.Y, 0, 0, color);
                    
                host.Owner.Timers.Add(new WorldTimer(1500, (world, t) =>
                {
                    foreach (var p in host.Owner.Players.Values)
                        if (MathUtils.DistSqr(p.X, p.Y, host.X, host.Y) < 16 * 16)
                            p.Client.SendAOE(target.X, target.Y, radius, (ushort)damage, 0, 0, host.ObjectType, color);
                    world.AOE(target, radius, true, p =>
                    {
                        if (p == null) return;
                        var tenacity = Constants.NegativeEffsIdx.Contains(effect)
                            ? (1d - (double)((Player)p).Stats[StatsManager.TENACITY_STAT] / 100)
                            : 1d;
                        ((IPlayer)p).Damage(damage, host, noDef);
                        p.ApplyConditionEffect(effect, (int)(Math.Max(1, effectDuration * tenacity)));
                    });
                }));
            }

            cool = coolDown.Next(Random);
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}