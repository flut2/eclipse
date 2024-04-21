using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class HealPlayer : Behavior
{
    private double _range;
    private Cooldown _coolDown;
    private int _healAmount;

    public HealPlayer(XElement e)
    {
        _range = e.ParseFloat("@range");
        _healAmount = e.ParseInt("@amount", 100);            
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
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
            foreach (var entity in host.GetNearestEntities(_range, null, true).OfType<Player>())
            {
                if (entity.Owner == null)
                    continue;

                if ((host.AttackTarget != null && host.AttackTarget != entity) || entity.HasConditionEffect(ConditionEffects.Sick))
                    continue;
                var maxHp = entity.Stats[0];
                var newHp = Math.Min(entity.HP + _healAmount, maxHp);

                if (newHp != entity.HP)
                {
                    var n = newHp - entity.HP;
                    entity.HP = newHp;
                    foreach (var p in host.Owner.Players.Values)
                        if (MathUtils.DistSqr(p.X, p.Y, host.X, host.Y) < 16 * 16) {
                            p.Client.SendShowEffect(EffectType.Potion, entity.Id, 0, 0, 0, 0, 0xFFFFFF);
                            p.Client.SendShowEffect(EffectType.Trail, host.Id, entity.X, entity.Y, 0, 0, 0xFFFFFF);
                            p.Client.SendNotification(entity.Id, "+" + n, 0x00FF00);
                        }
                }
            }
            cool = _coolDown.Next(Random);
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}