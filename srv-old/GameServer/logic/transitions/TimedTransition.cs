using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.transitions; 

internal class TimedTransition : Transition
{
    //State storage: cooldown timer

    private int time;
    private bool randomized;
        
    public TimedTransition(XElement e)
        : base(e.ParseString("@targetState", "root"))
    {
        time = e.ParseInt("@time") * 1000;
        randomized = e.ParseBool("@randomizedTime");
    }

    protected override bool TickCore(Entity host, RealmTime time, ref object state)
    {
        long cool;
        if (state == null) cool = randomized ? Random.Next(this.time) : this.time;
        else cool = (long)state;

        var ret = false;
        if (cool <= 0)
        {
            ret = true;
            cool = this.time;
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
        return ret;
    }
}