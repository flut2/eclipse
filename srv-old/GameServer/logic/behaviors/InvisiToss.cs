using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

internal class InvisiToss : Behavior
{
    //State storage: cooldown timer

    private readonly ushort child;
    private readonly int coolDownOffset;
    private readonly double range;
    private double? angle;
    private Cooldown coolDown;

    public InvisiToss(XElement e)
    {
        child = GetObjType(e.ParseString("@child"));
        range = e.ParseFloat("@range");            
        angle = e.ParseNFloat("@angle") * Math.PI / 180;
        coolDownOffset = e.ParseInt("@coolDownOffset");
        coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
    }
    
    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = coolDownOffset;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var cool = (long)state;

        if (cool <= 0)
        {
            var target = new Position
            {
                X = host.X + (float)(range * Math.Cos(angle.Value)),
                Y = host.Y + (float)(range * Math.Sin(angle.Value)),
            };
            host.Owner.Timers.Add(new WorldTimer(0, (world, t) =>
            {
                var entity = Entity.Resolve(world.Manager, child);
                if (host.Spawned)
                {
                    entity.Spawned = true;
                }

                if (host.DevSpawned)
                {
                    entity.DevSpawned = true;
                }

                entity.Move(target.X, target.Y);
                entity.ParentEntity = host;
                (entity as Enemy).Region = (host as Enemy).Region;
                world.EnterWorld(entity);
            }));
            cool = coolDown.Next(Random);
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}