using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

internal class Decay : Behavior
{
    //State storage: timer

    private int time;
        
    public Decay(XElement e)
    {
        time = e.ParseInt("@time", 10000) * 1000;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = this.time;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var cool = (long)state;

        if (cool <= 0)
            if (host is not Enemy enemy)
                host.Owner.LeaveWorld(host);
            else
                enemy.Death(time);
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}