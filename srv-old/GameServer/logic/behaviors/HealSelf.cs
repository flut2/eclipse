using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

internal class HealSelf : Behavior
{
    //State storage: cooldown timer

    private Cooldown _coolDown;
    private readonly int? _amount;

    public HealSelf(XElement e)
    {
        _amount = e.ParseNInt("@amount");    
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
    }
        
    public HealSelf(Cooldown coolDown = new Cooldown(), int? amount = null)
    {
        _coolDown = coolDown.Normalize();
        _amount = amount;
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
            var entity = host as Character;

            if (entity == null)
                return;

            var newHp = entity.ObjectDesc.MaxHP;
            if (_amount != null)
            {
                var newHealth = (int)_amount + entity.HP;
                if (newHp > newHealth)
                    newHp = newHealth;
            }
            if (newHp != entity.HP)
            {
                var n = newHp - entity.HP;
                entity.HP = newHp;
                foreach (var p in host.Owner.Players.Values)
                    if (MathUtils.DistSqr(p.X, p.Y, host.X, host.Y) < 16 * 16) {
                        p.Client.SendShowEffect(EffectType.Potion, entity.Id, 0, 0, 0, 0, 0xFFFFFFFF);
                        p.Client.SendShowEffect(EffectType.Trail, host.Id, entity.X, entity.Y, 0, 0, 0xFFFFFFFF);
                        p.Client.SendNotification(entity.Id, "+" + n, 0xFF00FF00);
                    }
            }
                
            cool = _coolDown.Next(Random);
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}