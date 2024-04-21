using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class HealPlayerMP : Behavior
{
    private double _range;
    private Cooldown _coolDown;
    private int _healAmount;
        
    public HealPlayerMP(XElement e)
    {
        _range = e.ParseFloat("@range");
        _healAmount = e.ParseInt("@amount");            
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
    }

    public HealPlayerMP(double range, Cooldown coolDown = new Cooldown(), int healAmount = 100)
    {
        _range = range;
        _coolDown = coolDown.Normalize();
        _healAmount = healAmount;
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
                if ((host.AttackTarget != null && host.AttackTarget != entity))
                    continue;
                var maxMp = entity.Stats[1];
                var newMp = Math.Min(entity.MP + _healAmount, maxMp);

                if (newMp != entity.MP)
                {
                    var n = newMp - entity.MP;
                    entity.MP = newMp;
                    foreach (var p in host.Owner.Players.Values)
                        if (MathUtils.DistSqr(p.X, p.Y, host.X, host.Y) < 16 * 16) {
                            p.Client.SendShowEffect(EffectType.Potion, entity.Id, 0, 0, 0, 0, 0xFFFFFF);
                            p.Client.SendShowEffect(EffectType.Trail, host.Id, entity.X, entity.Y, 0, 0, 0x816ECC);
                            p.Client.SendNotification(entity.Id, "+" + n, 0x816ECC);
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