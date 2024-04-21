using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

internal class HealGroup : Behavior
{
    //State storage: cooldown timer

    private double range;
    private string group;
    private Cooldown coolDown;
    private int? amount;

    public HealGroup(XElement e)
    {
        range = e.ParseFloat("@range");
        group = e.ParseString("@group");
        amount = e.ParseNInt("@amount");            
        coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
    }
        
    public HealGroup(double range, string group, Cooldown coolDown = new Cooldown(), int? healAmount = null)
    {
        this.range = (float)range;
        this.group = group;
        this.coolDown = coolDown.Normalize();
        this.amount = healAmount;
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
            foreach (var entity in host.GetNearestEntitiesByGroup(range, group).OfType<Enemy>())
            {
                var newHp = entity.ObjectDesc.MaxHP;
                if (amount != null)
                {
                    var newHealth = (int) amount + entity.HP;
                    if (newHp > newHealth)
                        newHp = newHealth;
                }
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
            cool = coolDown.Next(Random);
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}